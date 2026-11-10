package com.senpai.androlaunch.companion;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.CopyOnWriteArraySet;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * The daemon the macOS app talks to.
 *
 * The socket lives in the Linux abstract namespace, which `adb forward
 * localabstract:androlaunch-companion` can reach without any network permission,
 * port, or pairing — traffic stays inside the USB/Wi-Fi ADB tunnel.
 *
 * Protocol: see {@link Protocol}. One request per line, one response per line,
 * multiple requests per connection. Unknown commands return an error rather than
 * closing the socket, so newer Mac builds degrade instead of breaking.
 *
 * The service also owns the foreground notification (brand colour, large
 * icon, live status text) and the opt-in {@link CallStateMonitor} lifecycle.
 */
public class CompanionService extends Service {

    /**
     * Loopback TCP port. `adb forward tcp:<mac> tcp:27777` turns it into a socket
     * on the Mac; loopback keeps it off the network and needs no pairing.
     */
    static final int PORT = 27777;
    /**
     * v3 adds notification actions, media transport, ring, storage and clipboard
     * images; v4 adds app-icons (real launcher icons as 96 px PNGs); v5 adds the
     * storage-permission handshake and generic (non-reply) notification actions.
     */
    static final String VERSION = "5";

    /** Foreground-service extra carrying the per-install loopback token. */
    static final String EXTRA_TOKEN = "token";
    private static final String TOKEN_PREFS = "companion_security";
    private static final String TOKEN_KEY = "auth_token";

    static final String ACTION_STOP = "com.senpai.androlaunch.companion.action.STOP";
    static final String ACTION_ANSWER = "com.senpai.androlaunch.companion.action.ANSWER";
    static final String ACTION_DECLINE = "com.senpai.androlaunch.companion.action.DECLINE";
    /** "End call" in the shade reuses the decline path: Telecom endCall() ends offhook too. */
    static final String ACTION_END_CALL = "com.senpai.androlaunch.companion.action.END_CALL";
    /** Stops a "find my phone" ring started from the Mac. */
    static final String ACTION_STOP_RING = "com.senpai.androlaunch.companion.action.STOP_RING";

    /**
     * Shared secret for the loopback socket. Older Macs omit it and remain
     * compatible; when present, every request id must carry it. Only the adb
     * shell (UID 2000) or this app may set it, so a co-installed app cannot
     * claim the channel by starting the exported service with its own token.
     */
    private volatile String serviceToken = "";

    private static final String CHANNEL_ID = "connection_status";
    /** Old MIN-importance channel from protocol v1; deleted so upgrades are clean. */
    private static final String LEGACY_CHANNEL_ID = "companion";
    private static final int NOTIFICATION_ID = 1;
    private static final int REQUEST_OPEN = 1;
    private static final int REQUEST_STOP = 2;
    private static final int REQUEST_ANSWER = 3;
    private static final int REQUEST_DECLINE = 4;
    private static final int REQUEST_END_CALL = 5;
    private static final int REQUEST_STOP_RING = 6;

    /** Minimum gap between notification updates; keeps the shade from flickering. */
    private static final long NOTIFICATION_MIN_INTERVAL_MS = 2_000L;
    /** "Synced with your Mac just now" only for genuinely recent activity. */
    private static final long RECENT_SYNC_WINDOW_MS = 60_000L;

    private static final String TAG = "AndroLaunchCompanion";

    private static volatile boolean active;
    private static final AtomicInteger CLIENT_COUNT = new AtomicInteger();
    private static volatile long lastClientActivityMillis;
    private static final CopyOnWriteArraySet<Runnable> STATE_LISTENERS =
            new CopyOnWriteArraySet<>();
    private static final Handler MAIN_HANDLER = new Handler(Looper.getMainLooper());

    private volatile boolean running;
    private ServerSocket serverSocket;
    private Thread acceptThread;

    private boolean notificationListenersRegistered;
    private long lastNotificationUpdateAt;
    private boolean notificationUpdateScheduled;
    private final Object notificationLock = new Object();

    private final Runnable notificationRefreshTask = () -> {
        synchronized (notificationLock) {
            notificationUpdateScheduled = false;
            lastNotificationUpdateAt = SystemClock.elapsedRealtime();
        }
        if (!active) return;
        NotificationManager manager =
                (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return;
        try {
            manager.notify(NOTIFICATION_ID, buildNotification());
        } catch (RuntimeException e) {
            Log.w(TAG, "notification update failed", e);
        }
    };

    private final Runnable callStateChanged = this::requestNotificationRefresh;

    public static void start(Context context) {
        Intent intent = new Intent(context, CompanionService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    /** True while the daemon is running, so the UI can show real state. */
    public static boolean isActive() {
        return active;
    }

    /** Number of live Mac connections; normally 0 or 1 (one request per connection). */
    public static int clientCount() {
        return CLIENT_COUNT.get();
    }

    /**
     * Epoch millis of the last request received from the Mac, or 0 if the Mac has
     * not talked to this phone since the service started.
     */
    public static long lastClientActivityMillis() {
        return lastClientActivityMillis;
    }

    /** Registers a main-thread listener for service state changes. */
    public static void addStateListener(Runnable listener) {
        if (listener != null) STATE_LISTENERS.add(listener);
    }

    public static void removeStateListener(Runnable listener) {
        if (listener != null) STATE_LISTENERS.remove(listener);
    }

    public static void stop(Context context) {
        context.stopService(new Intent(context, CompanionService.class));
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : null;

        // Notification "Stop" action: end cleanly instead of being restarted sticky.
        if (ACTION_STOP.equals(action)) {
            stopSelf();
            return START_NOT_STICKY;
        }

        loadOrUpdateToken(intent);

        prepareChannel();
        try {
            startForeground(NOTIFICATION_ID, buildNotification());
        } catch (RuntimeException e) {
            // A missing/failed channel, an OEM notification block, or a background
            // start denial must not crash the daemon; keep serving and log it.
            Log.e(TAG, "could not post foreground notification", e);
        }
        active = true;
        registerNotificationListeners();
        // OEM reinstall quirk: access is granted but the platform listener stays
        // unbound until asked to rebind. Throttled and harmless when already bound.
        NotificationRelay.requestRebindIfNeeded(this);
        if (CallStateMonitor.isEnabled(this)) {
            CallStateMonitor.start(this);
        }
        startServer();
        notifyStateListeners();

        // Notification call actions change the phone's call, not the daemon: keep
        // serving and let the call-state listener refresh the notification.
        if (ACTION_ANSWER.equals(action)) {
            applyCallAction(true);
        } else if (ACTION_DECLINE.equals(action)) {
            applyCallAction(false);
        } else if (ACTION_END_CALL.equals(action)) {
            applyCallAction(false);
        } else if (ACTION_STOP_RING.equals(action)) {
            RingController.stop(this);
        }
        if (intent != null && intent.getAction() != null) {
            requestNotificationRefresh();
        }
        return START_STICKY;
    }

    /**
     * Best-effort call control behind the notification buttons. Defensive by design:
     * the call or the permission may have changed between rendering the action and
     * the tap, so a no-op with a log is the correct outcome.
     */
    private void applyCallAction(boolean answer) {
        if (!CallStateMonitor.hasControlAccess(this)) {
            Log.i(TAG, "call action ignored: ANSWER_PHONE_CALLS not granted");
            return;
        }
        boolean applied = answer
                ? CallStateMonitor.answerCall(this)
                : CallStateMonitor.declineCall(this);
        if (!applied) {
            Log.i(TAG, "call action not applied (call state changed or platform refused)");
        }
    }

    @Override
    public void onDestroy() {
        active = false;
        unregisterNotificationListeners();
        CallStateMonitor.stop();
        RingController.shutdown();
        synchronized (notificationLock) {
            MAIN_HANDLER.removeCallbacks(notificationRefreshTask);
            notificationUpdateScheduled = false;
        }
        stopServer();
        notifyStateListeners();
        super.onDestroy();
    }

    private void registerNotificationListeners() {
        if (notificationListenersRegistered) return;
        notificationListenersRegistered = true;
        NotificationRelay.setCountListener(count -> requestNotificationRefresh());
        CallStateMonitor.addListener(callStateChanged);
        RingController.setStateListener(this::requestNotificationRefresh);
    }

    private void unregisterNotificationListeners() {
        if (!notificationListenersRegistered) return;
        notificationListenersRegistered = false;
        NotificationRelay.setCountListener(null);
        CallStateMonitor.removeListener(callStateChanged);
        RingController.setStateListener(null);
    }

    private static void notifyStateListeners() {
        if (STATE_LISTENERS.isEmpty()) return;
        MAIN_HANDLER.post(() -> {
            for (Runnable listener : STATE_LISTENERS) {
                try {
                    listener.run();
                } catch (RuntimeException e) {
                    Log.w(TAG, "service state listener failed", e);
                }
            }
        });
    }

    // MARK: - Server

    private void startServer() {
        if (running) return;
        running = true;
        acceptThread = new Thread(this::acceptLoop, "companion-accept");
        acceptThread.start();
    }

    private void stopServer() {
        running = false;
        try {
            if (serverSocket != null) serverSocket.close();
        } catch (IOException ignored) {
            // Closing an already-broken socket is not interesting.
        }
        serverSocket = null;
        acceptThread = null;
    }

    private void acceptLoop() {
        // Bind IPv4 explicitly: InetAddress.getLoopbackAddress() resolves to ::1 on
        // Android, and `adb forward ... tcp:27777` dials 127.0.0.1 — an IPv6-only
        // listener is unreachable through the tunnel.
        boolean bound = false;
        for (int attempt = 0; attempt < 20 && running && !bound; attempt++) {
            try {
                ServerSocket socket = new ServerSocket();
                socket.setReuseAddress(true);
                socket.bind(new java.net.InetSocketAddress(InetAddress.getByName("127.0.0.1"), PORT), 4);
                serverSocket = socket;
                bound = true;
            } catch (IOException e) {
                Log.e(TAG, "bind failed (attempt " + attempt + ")", e);
                try {
                    Thread.sleep(500);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        if (!bound) {
            Log.e(TAG, "companion socket unavailable on port " + PORT);
            running = false;
            return;
        }
        Log.i(TAG, "listening on 127.0.0.1:" + PORT);

        while (running) {
            try {
                Socket client = serverSocket.accept();
                Thread handler = new Thread(() -> handleClient(client), "companion-client");
                handler.setDaemon(true);
                handler.start();
            } catch (IOException e) {
                if (running) continue;
                break;
            }
        }
    }

    private void handleClient(Socket client) {
        CLIENT_COUNT.incrementAndGet();
        lastClientActivityMillis = System.currentTimeMillis();
        notifyStateListeners();
        requestNotificationRefresh();

        try (Socket socket = client;
             BufferedReader reader = new BufferedReader(
                     new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
             BufferedWriter writer = new BufferedWriter(
                     new OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8))) {

            String line;
            while ((line = reader.readLine()) != null) {
                lastClientActivityMillis = System.currentTimeMillis();
                requestNotificationRefresh();
                String response = handleRequest(line);
                writer.write(response);
                writer.write("\n");
                writer.flush();
            }
        } catch (IOException ignored) {
            // Client went away; nothing to clean up beyond the try-with-resources.
        } finally {
            CLIENT_COUNT.decrementAndGet();
            notifyStateListeners();
            requestNotificationRefresh();
        }
    }

    private void loadOrUpdateToken(Intent intent) {
        String stored = getSharedPreferences(TOKEN_PREFS, MODE_PRIVATE)
                .getString(TOKEN_KEY, "");
        if (stored != null) serviceToken = stored;

        // Only the adb shell (UID 2000) or this app may install the secret. Any
        // other app can start this exported service but cannot replace the token.
        if (intent == null) return;
        int callingUid = android.os.Binder.getCallingUid();
        boolean fromAdbShell = callingUid == 2000;
        boolean fromSelf = callingUid == android.os.Process.myUid();
        if (!fromAdbShell && !fromSelf) return;

        String extra = intent.getStringExtra(EXTRA_TOKEN);
        if (extra == null || extra.isEmpty()) {
            // A legacy Mac (or a manually started service) explicitly asks for
            // the open channel. Only the adb shell may downgrade; the companion
            // UI starting its own service must not disable authentication.
            if (fromAdbShell) {
                serviceToken = "";
                getSharedPreferences(TOKEN_PREFS, MODE_PRIVATE)
                        .edit().remove(TOKEN_KEY).apply();
            }
            return;
        }
        serviceToken = extra;
        getSharedPreferences(TOKEN_PREFS, MODE_PRIVATE)
                .edit().putString(TOKEN_KEY, extra).apply();
    }

    /** Request ids from authenticated Macs look like `t.<token>.<random>`. */
    private static String tokenFromRequestId(String id) {
        if (id == null || !id.startsWith("t.")) return "";
        int end = id.indexOf('.', 2);
        if (end <= 2) return "";
        return id.substring(2, end);
    }

    private String handleRequest(String line) {
        String[] parts = line.split("\t", 3);
        String id = parts.length > 0 ? parts[0] : "";
        String command = parts.length > 1 ? parts[1] : "";
        String argument = parts.length > 2 ? Protocol.decode(parts[2]) : "";

        if (!serviceToken.isEmpty() && !serviceToken.equals(tokenFromRequestId(id))) {
            Log.w(TAG, "rejected unauthenticated companion request");
            return Protocol.error(id, "unauthorized");
        }

        switch (command) {
            case Protocol.CMD_PING:
                return Protocol.ok(id, "companion/" + VERSION + "/sdk" + Build.VERSION.SDK_INT);
            case Protocol.CMD_CLIPBOARD_SET:
                return setClipboard(id, argument);
            case Protocol.CMD_CLIPBOARD_GET:
                return getClipboard(id);
            case Protocol.CMD_CLIPBOARD_SET_IMAGE:
                return setClipboardImage(id, argument);
            case Protocol.CMD_CLIPBOARD_GET_IMAGE:
                return getClipboardImage(id);
            case Protocol.CMD_NOTIFICATIONS:
                return Protocol.ok(id, notificationsJson());
            case Protocol.CMD_NOTIFICATIONS_CLEAR:
                NotificationRelay.clearBuffer();
                return Protocol.ok(id, "cleared");
            case Protocol.CMD_NOTIFICATIONS_REPLY:
                return replyToNotification(id, argument);
            case Protocol.CMD_NOTIFICATIONS_DISMISS:
                return dismissNotification(id, argument);
            case Protocol.CMD_CALL_STATE:
                return Protocol.ok(id, callStateJson());
            case Protocol.CMD_CALL_ANSWER:
                return answerCall(id);
            case Protocol.CMD_CALL_END:
                return endCall(id);
            case Protocol.CMD_MEDIA_STATE:
                return Protocol.ok(
                        id,
                        MediaSessionBridge.stateJson(
                                this, MediaSessionBridge.ARG_ARTWORK.equals(argument)));
            case Protocol.CMD_MEDIA_PLAY:
                return mediaTransport(id, MediaSessionBridge.play(this));
            case Protocol.CMD_MEDIA_PAUSE:
                return mediaTransport(id, MediaSessionBridge.pause(this));
            case Protocol.CMD_MEDIA_NEXT:
                return mediaTransport(id, MediaSessionBridge.next(this));
            case Protocol.CMD_MEDIA_PREV:
                return mediaTransport(id, MediaSessionBridge.previous(this));
            case Protocol.CMD_PHONE_RING:
                return ringPhone(id, argument);
            case Protocol.CMD_PHONE_RING_STOP:
                return Protocol.ok(id, RingController.stop(this));
            case Protocol.CMD_STORAGE_INFO:
                return Protocol.ok(id, StorageInfo.json(this));
            case Protocol.CMD_APP_ICONS:
                return appIcons(id, argument);
            case Protocol.CMD_STORAGE_ACCESS:
                return storageAccess(id);
            case Protocol.CMD_STORAGE_REQUEST_ACCESS:
                return requestStorageAccess(id);
            case Protocol.CMD_NOTIFICATIONS_ACTION:
                return actionNotification(id, argument);
            default:
                return Protocol.error(id, "unknown_command:" + command);
        }
    }

    private String setClipboard(String id, String text) {
        try {
            ClipboardManager clipboard =
                    (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard == null) return Protocol.error(id, "no_clipboard_service");
            clipboard.setPrimaryClip(ClipData.newPlainText("AndroLaunch", text));
            // Length only: enough to debug delivery, never the content itself.
            Log.i(TAG, "clip.set received (" + text.length() + " chars)");
            return Protocol.ok(id, "clipboard_set");
        } catch (RuntimeException e) {
            return Protocol.error(id, "clipboard_failed:" + e.getClass().getSimpleName());
        }
    }

    private String getClipboard(String id) {
        try {
            ClipboardManager clipboard =
                    (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard == null || !clipboard.hasPrimaryClip()) {
                return Protocol.error(id, "empty");
            }
            ClipData clip = clipboard.getPrimaryClip();
            if (clip == null || clip.getItemCount() == 0) return Protocol.error(id, "empty");
            CharSequence text = clip.getItemAt(0).coerceToText(this);
            if (text == null) return Protocol.error(id, "empty");
            return Protocol.ok(id, text.toString());
        } catch (SecurityException e) {
            // Android 10+: background apps may not read the clipboard. The Mac falls
            // back to the mirrored session for Android -> Mac.
            return Protocol.error(id, "focus_required");
        } catch (RuntimeException e) {
            return Protocol.error(id, "clipboard_failed");
        }
    }

    // MARK: - Storage permission (v5)

    private String storageAccess(String id) {
        return Protocol.ok(id, StorageAccess.json(this));
    }

    private String requestStorageAccess(String id) {
        String result = StorageAccess.requestAccess(this);
        return "opened".equals(result) ? Protocol.ok(id, result) : Protocol.error(id, result);
    }

    // MARK: - Non-reply notification action (v5)

    /**
     * Argument is {@code key \n actionIndex}. Kept as one string so the existing
     * line protocol needs no JSON on the request side.
     */
    private String actionNotification(String id, String argument) {
        if (argument == null) return Protocol.error(id, "no_action");
        int newline = argument.indexOf('\n');
        if (newline <= 0) return Protocol.error(id, "no_action");

        String key = argument.substring(0, newline).trim();
        String indexText = argument.substring(newline + 1).trim();
        if (key.isEmpty() || indexText.isEmpty()) return Protocol.error(id, "no_action");

        int actionIndex;
        try {
            actionIndex = Integer.parseInt(indexText);
        } catch (NumberFormatException e) {
            return Protocol.error(id, "no_action");
        }
        if (actionIndex < 0) return Protocol.error(id, "no_action");

        String result = NotificationRelay.action(key, actionIndex);
        return "ok".equals(result) ? Protocol.ok(id, result) : Protocol.error(id, result);
    }

    // MARK: - App icons (v4)

    private String appIcons(String id, String argument) {
        String json = AppIcons.json(this, argument);
        if (json == null) return Protocol.error(id, "too_many_packages");
        return Protocol.ok(id, json);
    }

    // MARK: - Clipboard images (v3)

    private String setClipboardImage(String id, String argument) {
        byte[] bytes = Protocol.decodeBytes(argument);
        if (bytes == null || bytes.length == 0) return Protocol.error(id, "empty");
        if (bytes.length > ClipboardImages.MAX_IMAGE_BYTES) {
            return Protocol.error(id, "too_large");
        }
        String result = ClipboardImages.set(this, bytes);
        return "image_set".equals(result)
                ? Protocol.ok(id, result)
                : Protocol.error(id, result);
    }

    private String getClipboardImage(String id) {
        ClipboardImages.ReadResult result = ClipboardImages.get(this);
        if (result.error != null) return Protocol.error(id, result.error);
        // Raw base64 bytes; the Mac decodes to an NSImage and never persists it.
        return Protocol.ok(id, Protocol.encodeBytes(result.bytes));
    }

    // MARK: - Notification actions (v3)

    private String replyToNotification(String id, String argument) {
        String key;
        int actionIndex = -1;
        String text;
        try {
            org.json.JSONObject object = new org.json.JSONObject(argument);
            key = object.optString("key", "");
            actionIndex = object.optInt("action", -1);
            text = object.optString("text", "");
        } catch (org.json.JSONException e) {
            return Protocol.error(id, "bad_argument");
        }
        if (key.isEmpty()) return Protocol.error(id, "no_action");
        if (text.length() > 4_000) text = text.substring(0, 4_000);
        String result = NotificationRelay.reply(this, key, actionIndex, text);
        return "replied".equals(result) ? Protocol.ok(id, result) : Protocol.error(id, result);
    }

    private String dismissNotification(String id, String argument) {
        String result = NotificationRelay.dismiss(argument == null ? "" : argument.trim());
        return "dismissed".equals(result) ? Protocol.ok(id, result) : Protocol.error(id, result);
    }

    // MARK: - Media (v3)

    private String mediaTransport(String id, String result) {
        return "ok".equals(result) ? Protocol.ok(id, result) : Protocol.error(id, result);
    }

    // MARK: - Find my phone (v3)

    private String ringPhone(String id, String argument) {
        int duration = RingController.MAX_DURATION_MS;
        if (argument != null && !argument.trim().isEmpty()) {
            try {
                duration = Integer.parseInt(argument.trim());
            } catch (NumberFormatException ignored) {
                // Non-numeric arguments fall back to the maximum bounded ring.
            }
        }
        String result = RingController.ring(this, duration);
        return "ringing".equals(result) ? Protocol.ok(id, result) : Protocol.error(id, result);
    }

    private String notificationsJson() {
        List<NotificationRelay.NotificationItem> entries = NotificationRelay.snapshot();
        StringBuilder json = new StringBuilder(entries.size() * 192 + 2);
        json.append('[');
        for (int i = 0; i < entries.size(); i++) {
            NotificationRelay.NotificationItem entry = entries.get(i);
            if (i > 0) json.append(',');
            json.append('{')
                    .append("\"key\":\"").append(Protocol.jsonEscape(entry.key)).append("\",")
                    .append("\"pkg\":\"").append(Protocol.jsonEscape(entry.packageName)).append("\",")
                    .append("\"title\":\"").append(Protocol.jsonEscape(entry.title)).append("\",")
                    .append("\"text\":\"").append(Protocol.jsonEscape(entry.text)).append("\",")
                    .append("\"time\":").append(entry.postedAt).append(',')
                    .append("\"ongoing\":").append(entry.ongoing).append(',')
                    .append("\"sensitive\":").append(entry.sensitive).append(',')
                    .append("\"replyIndex\":").append(entry.replyActionIndex()).append(',')
                    .append("\"actions\":[");
            for (int a = 0; a < entry.actions.size(); a++) {
                NotificationRelay.ActionInfo action = entry.actions.get(a);
                if (a > 0) json.append(',');
                json.append('{')
                        .append("\"index\":").append(action.index).append(',')
                        .append("\"title\":\"").append(Protocol.jsonEscape(action.title)).append("\",")
                        .append("\"hasReply\":").append(action.hasReply)
                        .append('}');
            }
            json.append("]}");
        }
        json.append(']');
        return json.toString();
    }

    // MARK: - Call protocol

    private String callStateJson() {
        String state;
        if (CallStateMonitor.isRinging()) {
            state = CallStateMonitor.STATE_RINGING;
        } else if (CallStateMonitor.isInCall()) {
            state = CallStateMonitor.STATE_OFFHOOK;
        } else {
            state = CallStateMonitor.STATE_IDLE;
        }
        return new StringBuilder(160)
                .append('{')
                .append("\"supported\":").append(CallStateMonitor.isSupported(this)).append(',')
                .append("\"permission\":").append(CallStateMonitor.hasAccess(this)).append(',')
                .append("\"enabled\":").append(CallStateMonitor.isEnabled(this)).append(',')
                .append("\"control\":").append(CallStateMonitor.hasControlAccess(this)).append(',')
                .append("\"state\":\"").append(state).append("\",")
                .append("\"incoming\":").append(CallStateMonitor.isIncoming()).append(',')
                .append("\"since\":").append(CallStateMonitor.stateSinceMillis())
                .append('}')
                .toString();
    }

    private String answerCall(String id) {
        if (!CallStateMonitor.isSupported(this)) return Protocol.error(id, "unsupported");
        if (!CallStateMonitor.hasAccess(this) || !CallStateMonitor.hasControlAccess(this)) {
            return Protocol.error(id, "permission_required");
        }
        if (!CallStateMonitor.isRinging()) return Protocol.error(id, "not_ringing");
        return CallStateMonitor.answerCall(this)
                ? Protocol.ok(id, "answered")
                : Protocol.error(id, "failed");
    }

    private String endCall(String id) {
        if (!CallStateMonitor.isSupported(this)) return Protocol.error(id, "unsupported");
        if (!CallStateMonitor.hasAccess(this) || !CallStateMonitor.hasControlAccess(this)) {
            return Protocol.error(id, "permission_required");
        }
        if (!CallStateMonitor.isRinging() && !CallStateMonitor.isInCall()) {
            return Protocol.error(id, "not_ringing");
        }
        return CallStateMonitor.declineCall(this)
                ? Protocol.ok(id, "ended")
                : Protocol.error(id, "failed");
    }

    // MARK: - Foreground notification

    /** Creates the brand channel once and removes the legacy v1 channel. */
    private void prepareChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager manager =
                (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return;

        try {
            manager.deleteNotificationChannel(LEGACY_CHANNEL_ID);
        } catch (RuntimeException e) {
            Log.w(TAG, "legacy channel cleanup failed", e);
        }

        try {
            NotificationChannel existing = manager.getNotificationChannel(CHANNEL_ID);
            if (existing != null) {
                // Keep user customisations, but refresh the copy so shortened
                // strings reach installs that already created the channel.
                existing.setDescription(getString(R.string.svc_channel_description));
                manager.createNotificationChannel(existing);
                return;
            }
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.svc_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT);
            channel.setDescription(getString(R.string.svc_channel_description));
            channel.setSound(null, null);
            channel.enableVibration(false);
            channel.setShowBadge(false);
            channel.enableLights(true);
            channel.setLightColor(brandColor());
            manager.createNotificationChannel(channel);
        } catch (RuntimeException e) {
            Log.w(TAG, "could not create notification channel", e);
        }
    }

    private Notification buildNotification() {
        boolean ringing = CallStateMonitor.isRinging();
        boolean inCall = CallStateMonitor.isInCall();
        int mirrored = NotificationRelay.size();
        long lastActivity = lastClientActivityMillis;
        boolean synced = lastActivity > 0
                && System.currentTimeMillis() - lastActivity <= RECENT_SYNC_WINDOW_MS;

        // One short line only: the compact native notification is the design now.
        String text;
        if (ringing) {
            text = getString(R.string.svc_text_ringing);
        } else if (RingController.isRinging()) {
            text = getString(R.string.svc_text_ring_phone);
        } else if (inCall) {
            text = getString(R.string.svc_text_in_call);
        } else if (mirrored > 0) {
            text = getString(R.string.svc_text_mirrored, mirrored);
        } else if (synced) {
            text = getString(R.string.svc_text_synced);
        } else {
            text = getString(R.string.svc_text_ready);
        }

        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);

        builder.setSmallIcon(R.drawable.ic_stat_companion)
                .setColor(brandColor())
                .setLargeIcon(largeIcon())
                .setContentTitle(getString(R.string.svc_title))
                .setContentText(text)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setContentIntent(openPendingIntent());

        addNotificationActions(builder);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE);
        }
        return builder.build();
    }

    /**
     * The real AndroLaunch app icon, decoded from the bundled 192px raster. Adaptive
     * launcher icons cannot be drawn faithfully into a notification bitmap on every
     * OEM (some wrap or crop the foreground), so the notification uses the original
     * raster artwork — identical to the home-screen mark — with the vector as a
     * safety net.
     */
    private Icon largeIcon() {
        try {
            Bitmap bitmap = BitmapFactory.decodeResource(
                    getResources(), R.drawable.ic_notification_large_icon);
            if (bitmap != null) return Icon.createWithBitmap(bitmap);
        } catch (RuntimeException e) {
            Log.w(TAG, "could not load notification large icon", e);
        }
        return Icon.createWithResource(this, R.drawable.ic_notification_large);
    }

    /**
     * Contextual action row: call control while a call is on screen, otherwise the
     * standard Open/Stop pair. The platform renders at most three action buttons,
     * so the most urgent action is added first.
     */
    private void addNotificationActions(Notification.Builder builder) {
        boolean control = CallStateMonitor.hasControlAccess(this);
        if (RingController.isRinging()) {
            // Find-my-phone takes over the action row while it is active; nothing
            // else on this notification matters until the phone stops ringing.
            builder.addAction(action(R.drawable.ic_action_stop,
                    getString(R.string.svc_action_stop_ring),
                    stopRingPendingIntent()));
            builder.addAction(openAction());
            builder.addAction(stopAction());
        } else if (CallStateMonitor.isRinging() && control) {
            // Ringing: answer/decline are the whole point of the notification here.
            builder.addAction(action(R.drawable.ic_action_call_answer,
                    getString(R.string.svc_action_answer),
                    callActionPendingIntent(ACTION_ANSWER, REQUEST_ANSWER)));
            builder.addAction(action(R.drawable.ic_action_call_end,
                    getString(R.string.svc_action_decline),
                    callActionPendingIntent(ACTION_DECLINE, REQUEST_DECLINE)));
            builder.addAction(openAction());
            builder.addAction(stopAction());
        } else if (CallStateMonitor.isInCall() && control) {
            builder.addAction(action(R.drawable.ic_action_call_end,
                    getString(R.string.svc_action_end_call),
                    callActionPendingIntent(ACTION_END_CALL, REQUEST_END_CALL)));
            builder.addAction(openAction());
            builder.addAction(stopAction());
        } else {
            builder.addAction(openAction());
            builder.addAction(stopAction());
        }
    }

    private Notification.Action openAction() {
        return action(R.drawable.ic_stat_companion,
                getString(R.string.svc_action_open), openPendingIntent());
    }

    private Notification.Action stopAction() {
        return action(R.drawable.ic_action_stop,
                getString(R.string.svc_action_stop), stopPendingIntent());
    }

    private PendingIntent callActionPendingIntent(String action, int requestCode) {
        Intent call = new Intent(this, CompanionService.class);
        call.setAction(action);
        return PendingIntent.getService(this, requestCode, call,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private PendingIntent stopRingPendingIntent() {
        Intent ring = new Intent(this, CompanionService.class);
        ring.setAction(ACTION_STOP_RING);
        return PendingIntent.getService(this, REQUEST_STOP_RING, ring,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private Notification.Action action(int iconRes, String title, PendingIntent intent) {
        return new Notification.Action.Builder(
                Icon.createWithResource(this, iconRes), title, intent).build();
    }

    private PendingIntent openPendingIntent() {
        Intent launch = new Intent(this, MainActivity.class);
        launch.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        return PendingIntent.getActivity(this, REQUEST_OPEN, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private PendingIntent stopPendingIntent() {
        Intent stop = new Intent(this, CompanionService.class);
        stop.setAction(ACTION_STOP);
        return PendingIntent.getService(this, REQUEST_STOP, stop,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /** Brand green, with a literal fallback so a resource rename cannot crash. */
    private int brandColor() {
        try {
            return getColor(R.color.al_brand);
        } catch (Resources.NotFoundException e) {
            return 0xFF4CB250;
        }
    }

    /**
     * Coalesces notification updates to at most one per {@link #NOTIFICATION_MIN_INTERVAL_MS}.
     * Callable from any thread; the actual notify happens on the main thread.
     */
    private void requestNotificationRefresh() {
        if (!active) return;
        synchronized (notificationLock) {
            if (notificationUpdateScheduled) return;
            long elapsed = SystemClock.elapsedRealtime() - lastNotificationUpdateAt;
            long delay = NOTIFICATION_MIN_INTERVAL_MS - elapsed;
            if (delay < 0) delay = 0;
            notificationUpdateScheduled = true;
            if (delay == 0) {
                MAIN_HANDLER.post(notificationRefreshTask);
            } else {
                MAIN_HANDLER.postDelayed(notificationRefreshTask, delay);
            }
        }
    }
}
