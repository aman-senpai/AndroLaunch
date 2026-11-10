package com.senpai.androlaunch.companion;

import android.app.Notification;
import android.app.PendingIntent;
import android.app.RemoteInput;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import android.util.Log;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Captures posted notifications into a small in-memory buffer that the socket
 * service can serve, and owns the v3 notification actions (inline reply and
 * dismiss).
 *
 * This replaces `dumpsys notification` parsing on the Mac: the text is already
 * parsed by the platform, media/ongoing/group notifications can be filtered with
 * real flags instead of heuristics, and nothing is scraped from shell output.
 * Access is granted per-user in Settings, and the buffer is memory-only — it is
 * never written to disk.
 *
 * Reply dispatch follows the platform's direct-reply contract: the listener
 * looks the notification up by key in {@link #getActiveNotifications()}, finds
 * the action that exposes a free-form {@link RemoteInput}, fills the results
 * into a mutable Intent copy and sends the action's own {@link PendingIntent}.
 * Apps that implement reply with a custom flow (opening an activity, custom
 * tokens) will not accept the text — that is reported as {@code no_action}
 * rather than pretended success.
 */
public class NotificationRelay extends NotificationListenerService {

    private static final int MAX_ENTRIES = 80;
    private static final int MAX_ACTIONS = 8;
    private static final String TAG = "AndroLaunchCompanion";

    /** One tappable action on a mirrored notification. */
    static final class ActionInfo {
        final int index;
        final String title;
        final boolean hasReply;

        ActionInfo(int index, String title, boolean hasReply) {
            this.index = index;
            this.title = title;
            this.hasReply = hasReply;
        }
    }

    static final class NotificationItem {
        final String key;
        final String packageName;
        final String title;
        final String text;
        final long postedAt;
        final boolean ongoing;
        /** VISIBILITY_SECRET, or a notification whose content the platform hides. */
        final boolean sensitive;
        final List<ActionInfo> actions;

        NotificationItem(String key, String packageName, String title, String text, long postedAt,
                boolean ongoing, boolean sensitive, List<ActionInfo> actions) {
            this.key = key;
            this.packageName = packageName;
            this.title = title;
            this.text = text;
            this.postedAt = postedAt;
            this.ongoing = ongoing;
            this.sensitive = sensitive;
            this.actions = actions;
        }

        boolean hasReplyAction() {
            for (ActionInfo action : actions) {
                if (action.hasReply) return true;
            }
            return false;
        }

        /** Index the Mac should use when it wants to reply, or -1. */
        int replyActionIndex() {
            for (ActionInfo action : actions) {
                if (action.hasReply) return action.index;
            }
            return -1;
        }
    }

    private static final Map<String, NotificationItem> BUFFER =
            new LinkedHashMap<String, NotificationItem>(64, 0.75f, false) {
                @Override
                protected boolean removeEldestEntry(Map.Entry<String, NotificationItem> eldest) {
                    return size() > MAX_ENTRIES;
                }
            };

    /**
     * Observes buffer-size changes (posts, removals, clears) so the foreground
     * notification can show the mirrored count. Invoked on the thread that changed
     * the buffer; the service throttles and hops to the main thread itself.
     */
    public interface CountListener {
        void onNotificationCountChanged(int count);
    }

    private static volatile CountListener countListener;
    private static volatile NotificationRelay instance;
    private static volatile boolean connected;
    private static volatile long lastRebindAttemptAt;

    /** Android throttles listener rebinds; never ask more than once per interval. */
    private static final long REBIND_INTERVAL_MS = 15_000L;

    /** Replaces the single count listener; pass null to stop observing. */
    public static void setCountListener(CountListener listener) {
        countListener = listener;
    }

    /** True once the platform has bound this listener and delivered onListenerConnected. */
    public static boolean isConnected() {
        return connected;
    }

    /**
     * Recovers the listener after an APK update or a reboot on OEM builds that leave
     * an enabled notification listener unbound. Without this, a freshly reinstalled
     * companion can report notification access as granted while capturing nothing
     * until the user toggles access or reboots. Safe to call often: it only asks the
     * platform to rebind, is skipped while connected, and is throttled.
     */
    public static void requestRebindIfNeeded(Context context) {
        if (context == null || connected || !hasAccess(context)) return;
        long now = System.currentTimeMillis();
        if (now - lastRebindAttemptAt < REBIND_INTERVAL_MS) return;
        lastRebindAttemptAt = now;
        try {
            NotificationListenerService.requestRebind(
                    new ComponentName(context, NotificationRelay.class));
            Log.i(TAG, "requested notification listener rebind");
        } catch (RuntimeException e) {
            Log.w(TAG, "notification listener rebind request failed", e);
        }
    }

    /** Component name used for MediaSessionManager.getActiveSessions(…). */
    static ComponentName listenerComponent(Context context) {
        return new ComponentName(context, NotificationRelay.class);
    }

    public static List<NotificationItem> snapshot() {
        synchronized (BUFFER) {
            return new ArrayList<>(BUFFER.values());
        }
    }

    public static void clearBuffer() {
        int previous;
        synchronized (BUFFER) {
            previous = BUFFER.size();
            BUFFER.clear();
        }
        if (previous > 0) notifyCountChanged(0);
    }

    public static int size() {
        synchronized (BUFFER) {
            return BUFFER.size();
        }
    }

    private static void notifyCountChanged(int count) {
        CountListener listener = countListener;
        if (listener == null) return;
        try {
            listener.onNotificationCountChanged(count);
        } catch (RuntimeException e) {
            Log.w(TAG, "notification count listener failed", e);
        }
    }

    // MARK: - v3 actions

    /**
     * Sends {@code text} to the notification's direct-reply action.
     *
     * @return {@code replied}, {@code no_action} (the notification has no
     *         free-form action), {@code gone} (it is no longer posted),
     *         {@code permission_required} or {@code failed}.
     */
    static String reply(Context context, String key, int actionIndex, String text) {
        NotificationRelay relay = instance;
        if (relay == null) return "permission_required";
        if (key == null || key.isEmpty()) return "no_action";

        StatusBarNotification sbn = relay.findActive(key);
        if (sbn == null || sbn.getNotification() == null) return "gone";
        Notification notification = sbn.getNotification();
        Notification.Action[] actions = notification.actions;
        if (actions == null || actions.length == 0) return "no_action";

        Notification.Action target = null;
        if (actionIndex >= 0 && actionIndex < actions.length
                && remoteInputsOf(actions[actionIndex]).length > 0) {
            target = actions[actionIndex];
        } else {
            // The Mac may pass -1 or a stale index; fall back to the first reply action.
            for (Notification.Action action : actions) {
                if (remoteInputsOf(action).length > 0) {
                    target = action;
                    break;
                }
            }
        }
        if (target == null || target.actionIntent == null) return "no_action";

        RemoteInput[] inputs = remoteInputsOf(target);
        if (inputs.length == 0) return "no_action";

        try {
            Intent intent = new Intent();
            Bundle results = new Bundle();
            for (RemoteInput input : inputs) {
                results.putCharSequence(input.getResultKey(), text == null ? "" : text);
            }
            RemoteInput.addResultsToIntent(inputs, intent, results);
            // PendingIntent.send fills the mutable Intent with the extras above; this is
            // exactly the path the platform's own inline-reply UI uses.
            target.actionIntent.send(context, 0, intent);
            Log.i(TAG, "notif.reply sent (" + (text == null ? 0 : text.length()) + " chars)");
            return "replied";
        } catch (PendingIntent.CanceledException e) {
            return "gone";
        } catch (SecurityException e) {
            return "permission_required";
        } catch (RuntimeException e) {
            Log.w(TAG, "notif.reply failed", e);
            return "failed";
        }
    }

    /**
     * Fires a non-reply notification action ("Mark as read", "Archive", …).
     *
     * Same defensive model as {@link #reply}: the notification is looked up by key
     * in the live list, the action's own PendingIntent is sent, and an action that
     * carries a RemoteInput is refused here — those belong to {@code notif.reply}.
     * A stale index, a cancelled PendingIntent or a revoked listener all return a
     * typed result instead of throwing.
     */
    static String action(String key, int actionIndex) {
        NotificationRelay relay = instance;
        if (relay == null) return "permission_required";
        if (key == null || key.isEmpty() || actionIndex < 0) return "no_action";

        StatusBarNotification sbn = relay.findActive(key);
        if (sbn == null || sbn.getNotification() == null) return "gone";
        Notification notification = sbn.getNotification();
        Notification.Action[] actions = notification.actions;
        if (actions == null || actionIndex >= actions.length) return "no_action";

        Notification.Action target = actions[actionIndex];
        if (target == null || target.actionIntent == null) return "no_action";
        if (remoteInputsOf(target).length > 0) return "no_action";

        try {
            // The Intent copy is required for mutable PendingIntents; actions that
            // do not use one simply ignore it.
            target.actionIntent.send(relay, 0, new Intent());
            Log.i(TAG, "notif.action sent (index " + actionIndex + ")");
            return "ok";
        } catch (PendingIntent.CanceledException e) {
            return "gone";
        } catch (SecurityException e) {
            return "permission_required";
        } catch (RuntimeException e) {
            Log.w(TAG, "notif.action failed", e);
            return "action_failed";
        }
    }

    /** Dismisses the phone notification with this key. */
    static String dismiss(String key) {
        NotificationRelay relay = instance;
        if (relay == null) return "permission_required";
        if (key == null || key.isEmpty()) return "failed";
        try {
            relay.cancelNotification(key);
            int count;
            boolean removed;
            synchronized (BUFFER) {
                removed = BUFFER.remove(key) != null;
                count = BUFFER.size();
            }
            if (removed) notifyCountChanged(count);
            return "dismissed";
        } catch (SecurityException e) {
            return "permission_required";
        } catch (RuntimeException e) {
            Log.w(TAG, "notif.dismiss failed", e);
            return "failed";
        }
    }

    private StatusBarNotification findActive(String key) {
        try {
            StatusBarNotification[] active = getActiveNotifications();
            if (active == null) return null;
            for (StatusBarNotification sbn : active) {
                if (sbn != null && key.equals(sbn.getKey())) return sbn;
            }
        } catch (SecurityException e) {
            Log.w(TAG, "active notifications unavailable", e);
        } catch (RuntimeException e) {
            Log.w(TAG, "active notification lookup failed", e);
        }
        return null;
    }

    private static RemoteInput[] remoteInputsOf(Notification.Action action) {
        if (action == null) return new RemoteInput[0];
        try {
            RemoteInput[] inputs = action.getRemoteInputs();
            if (inputs == null) return new RemoteInput[0];
            return inputs;
        } catch (RuntimeException e) {
            return new RemoteInput[0];
        }
    }

    // MARK: - Lifecycle

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
    }

    public void onDestroy() {
        if (instance == this) instance = null;
        super.onDestroy();
    }

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        if (sbn == null || sbn.getNotification() == null) return;

        Notification notification = sbn.getNotification();
        int flags = notification.flags;
        boolean ongoing = (flags & Notification.FLAG_ONGOING_EVENT) != 0
                || (flags & Notification.FLAG_FOREGROUND_SERVICE) != 0;
        boolean groupSummary = (flags & Notification.FLAG_GROUP_SUMMARY) != 0;

        // Ongoing and summary rows add noise without adding information.
        if (groupSummary) return;

        String title = textOf(notification, Notification.EXTRA_TITLE);
        String body = textOf(notification, Notification.EXTRA_TEXT,
                Notification.EXTRA_BIG_TEXT, Notification.EXTRA_SUMMARY_TEXT);
        if (title == null && body == null) return;

        NotificationItem entry = new NotificationItem(
                sbn.getKey(),
                sbn.getPackageName(),
                title == null ? "" : title,
                body == null ? "" : body,
                sbn.getPostTime(),
                ongoing,
                isSensitive(notification),
                actionsOf(notification));

        boolean added;
        int count;
        synchronized (BUFFER) {
            added = BUFFER.put(sbn.getKey(), entry) == null;
            count = BUFFER.size();
        }
        // Re-posts of the same key keep the count stable; only a new row is a size change.
        if (added) notifyCountChanged(count);
    }

    @Override
    public void onNotificationRemoved(StatusBarNotification sbn) {
        if (sbn == null) return;
        boolean removed;
        int count;
        synchronized (BUFFER) {
            removed = BUFFER.remove(sbn.getKey()) != null;
            count = BUFFER.size();
        }
        if (removed) notifyCountChanged(count);
    }

    @Override
    public void onListenerConnected() {
        super.onListenerConnected();
        connected = true;
        instance = this;
        // Re-seed from whatever is already on screen so the Mac is not blank until
        // the next notification arrives.
        try {
            StatusBarNotification[] active = getActiveNotifications();
            if (active != null) {
                for (StatusBarNotification sbn : active) {
                    onNotificationPosted(sbn);
                }
            }
        } catch (SecurityException ignored) {
            // Access revoked between connect and read; the buffer stays empty.
        }
    }

    @Override
    public void onListenerDisconnected() {
        connected = false;
        super.onListenerDisconnected();
    }

    // MARK: - Extraction helpers

    /**
     * A notification is treated as sensitive when the posting app marked it
     * secret (lock screen shows nothing), or when the platform redacted its text.
     * The Mac keeps its own deny-list for apps regardless.
     */
    private static boolean isSensitive(Notification notification) {
        try {
            if (notification.visibility == Notification.VISIBILITY_SECRET) return true;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP
                    && notification.publicVersion == null
                    && notification.visibility == Notification.VISIBILITY_PRIVATE) {
                return true;
            }
        } catch (RuntimeException ignored) {
            // Treat unknown visibility as not sensitive; the Mac's deny-list still applies.
        }
        return false;
    }

    private static List<ActionInfo> actionsOf(Notification notification) {
        Notification.Action[] actions = notification.actions;
        if (actions == null || actions.length == 0) return new ArrayList<>(0);
        List<ActionInfo> out = new ArrayList<>(Math.min(actions.length, MAX_ACTIONS));
        int limit = Math.min(actions.length, MAX_ACTIONS);
        for (int i = 0; i < limit; i++) {
            Notification.Action action = actions[i];
            if (action == null) continue;
            CharSequence title = action.title;
            out.add(new ActionInfo(
                    i,
                    title == null ? "" : title.toString(),
                    remoteInputsOf(action).length > 0));
        }
        return out;
    }

    private static String textOf(Notification notification, String... keys) {
        Bundle extras = notification.extras;
        if (extras == null) return null;
        for (String key : keys) {
            CharSequence value = extras.getCharSequence(key);
            if (value == null) continue;
            String trimmed = value.toString().trim();
            if (!trimmed.isEmpty()) return trimmed;
        }
        return null;
    }

    /** True when the user has granted notification access to this app. */
    public static boolean hasAccess(Context context) {
        String enabled = android.provider.Settings.Secure.getString(
                context.getContentResolver(), "enabled_notification_listeners");
        return enabled != null && enabled.contains(context.getPackageName());
    }
}
