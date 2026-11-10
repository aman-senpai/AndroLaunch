package com.senpai.androlaunch.companion;

import android.Manifest;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.telecom.TelecomManager;
import android.telephony.PhoneStateListener;
import android.telephony.TelephonyManager;
import android.util.Log;

import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Passive call awareness plus best-effort answer/decline.
 *
 * Calls are strictly opt-in: nothing is observed until the user turns on call
 * awareness in the companion UI (SharedPreferences {@code companion_prefs} /
 * {@code call_awareness}) and grants {@code READ_PHONE_STATE}. Control buttons
 * additionally need {@code ANSWER_PHONE_CALLS}.
 *
 * The monitor is a static facade: the service owns the registration lifecycle
 * ({@link #start(Context)} / {@link #stop()}) while the UI only reads state. It
 * registers with the platform telephony stack — {@code TelephonyCallback} on
 * API 31+, {@code PhoneStateListener} on API 26–30 — and never crashes when a
 * permission or telephony feature is missing; it simply reports idle.
 *
 * Nothing here records numbers, audio, or call history: only the coarse state
 * (idle / ringing / offhook), whether the active call is incoming, and when that
 * state began.
 */
public final class CallStateMonitor {

    /** Preferences file shared with the companion UI. */
    public static final String PREFS_NAME = "companion_prefs";
    /** Opt-in switch; call awareness stays completely off while false. */
    public static final String PREF_CALL_AWARENESS = "call_awareness";

    public static final String STATE_IDLE = "idle";
    public static final String STATE_RINGING = "ringing";
    public static final String STATE_OFFHOOK = "offhook";

    private static final String TAG = "AndroLaunchCompanion";
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static final CopyOnWriteArrayList<Runnable> LISTENERS = new CopyOnWriteArrayList<>();

    /** Application context captured by {@link #start(Context)}; never an Activity. */
    private static volatile Context appContext;
    private static volatile TelephonyManager telephonyManager;
    private static volatile PhoneStateListener legacyListener;
    private static volatile boolean registered;

    private static volatile String state = STATE_IDLE;
    private static volatile boolean incoming;
    private static volatile long stateSince = System.currentTimeMillis();
    private static volatile boolean supportedResolved;
    private static volatile boolean supported;

    private CallStateMonitor() {}

    // MARK: - Permissions and capability

    /** True when this device exposes telephony hardware (calls may be possible). */
    public static boolean isSupported(Context context) {
        if (supportedResolved) return supported;
        boolean resolved = false;
        try {
            PackageManager manager = context.getPackageManager();
            resolved = manager != null
                    && manager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY);
        } catch (RuntimeException e) {
            Log.w(TAG, "telephony capability probe failed", e);
        }
        supported = resolved;
        supportedResolved = true;
        return resolved;
    }

    /** True when {@code READ_PHONE_STATE} is granted, i.e. call state may be read. */
    public static boolean hasAccess(Context context) {
        return permissionGranted(context, Manifest.permission.READ_PHONE_STATE);
    }

    /** True when {@code ANSWER_PHONE_CALLS} is granted, i.e. calls may be controlled. */
    public static boolean hasControlAccess(Context context) {
        return permissionGranted(context, Manifest.permission.ANSWER_PHONE_CALLS);
    }

    /** The user's opt-in preference, independent of the permission state. */
    public static boolean isEnabled(Context context) {
        try {
            return preferences(context).getBoolean(PREF_CALL_AWARENESS, false);
        } catch (RuntimeException e) {
            Log.w(TAG, "call awareness preference unavailable", e);
            return false;
        }
    }

    /**
     * Persists the opt-in switch and immediately starts or stops observation.
     * Enabling without the runtime permission is allowed: the preference is kept
     * so the UI can ask for the permission and {@link #start(Context)} can retry.
     */
    public static void setEnabled(Context context, boolean enabled) {
        try {
            preferences(context).edit().putBoolean(PREF_CALL_AWARENESS, enabled).apply();
        } catch (RuntimeException e) {
            Log.w(TAG, "could not persist call awareness preference", e);
        }
        if (enabled) {
            start(context);
        } else {
            stop();
        }
    }

    private static boolean permissionGranted(Context context, String permission) {
        if (context == null) return false;
        try {
            return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
        } catch (RuntimeException e) {
            return false;
        }
    }

    private static SharedPreferences preferences(Context context) {
        Context app = context.getApplicationContext();
        return (app != null ? app : context).getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    // MARK: - Registration lifecycle

    /**
     * Starts observing call state when the user opted in, the permission is granted
     * and telephony exists. Idempotent and safe to call from any component.
     */
    public static void start(Context context) {
        if (context == null) return;
        Context app = context.getApplicationContext();
        if (app == null) app = context;
        appContext = app;

        if (registered) return;
        if (!isEnabled(app) || !hasAccess(app) || !isSupported(app)) return;

        TelephonyManager manager =
                (TelephonyManager) app.getSystemService(Context.TELEPHONY_SERVICE);
        if (manager == null) return;
        telephonyManager = manager;

        boolean started = false;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                started = Api31.register(app, manager);
            } else {
                started = registerLegacy(manager);
            }
        } catch (SecurityException e) {
            Log.w(TAG, "call state registration denied", e);
        } catch (RuntimeException e) {
            Log.w(TAG, "call state registration failed", e);
        }
        registered = started;
        if (!started) {
            telephonyManager = null;
            legacyListener = null;
            return;
        }

        // Seed from the current state so a call that is already ringing when the
        // service starts is reported immediately instead of at the next transition.
        try {
            applyCallState(manager.getCallState(), false);
        } catch (SecurityException e) {
            Log.w(TAG, "initial call state unavailable", e);
        } catch (RuntimeException e) {
            Log.w(TAG, "initial call state failed", e);
        }
    }

    /** Stops observing call state. Idempotent; resets the reported state to idle. */
    public static void stop() {
        if (registered) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    Api31.unregister(telephonyManager);
                } else if (telephonyManager != null && legacyListener != null) {
                    telephonyManager.listen(legacyListener, PhoneStateListener.LISTEN_NONE);
                }
            } catch (RuntimeException e) {
                Log.w(TAG, "call state unregistration failed", e);
            }
        }
        legacyListener = null;
        telephonyManager = null;
        registered = false;
        resetState();
    }

    private static boolean registerLegacy(TelephonyManager manager) {
        if (manager == null) return false;
        // PhoneStateListener is deprecated on API 31+, but this branch only runs on
        // API 26–30 where it is the supported API. The no-arg constructor delivers
        // callbacks on the calling thread's looper, and start() is always called on
        // the main thread (service onStartCommand or the UI toggle).
        @SuppressWarnings("deprecation")
        PhoneStateListener listener = new PhoneStateListener() {
            @Override
            public void onCallStateChanged(int callState, String phoneNumber) {
                applyCallState(callState, true);
            }
        };
        manager.listen(listener, PhoneStateListener.LISTEN_CALL_STATE);
        legacyListener = listener;
        return true;
    }

    /**
     * API 31+ telephony callback. Kept in a nested holder so the API-31 type is
     * only loaded on devices that actually run it.
     */
    private static final class Api31 {

        private static android.telephony.TelephonyCallback callback;

        static boolean register(Context context, TelephonyManager manager) {
            if (callback != null) return true;
            CallStateCallback listener = new CallStateCallback();
            manager.registerTelephonyCallback(context.getMainExecutor(), listener);
            callback = listener;
            return true;
        }

        static void unregister(TelephonyManager manager) {
            android.telephony.TelephonyCallback listener = callback;
            callback = null;
            if (listener != null && manager != null) {
                manager.unregisterTelephonyCallback(listener);
            }
        }

        private static final class CallStateCallback
                extends android.telephony.TelephonyCallback
                implements android.telephony.TelephonyCallback.CallStateListener {

            @Override
            public void onCallStateChanged(int callState) {
                applyCallState(callState, true);
            }
        }

        private Api31() {}
    }

    // MARK: - State

    private static void applyCallState(int callState, boolean notify) {
        String next;
        switch (callState) {
            case TelephonyManager.CALL_STATE_RINGING:
                next = STATE_RINGING;
                break;
            case TelephonyManager.CALL_STATE_OFFHOOK:
                next = STATE_OFFHOOK;
                break;
            case TelephonyManager.CALL_STATE_IDLE:
            default:
                next = STATE_IDLE;
                break;
        }

        boolean nextIncoming;
        String previous = state;
        if (STATE_RINGING.equals(next)) {
            nextIncoming = true;
        } else if (STATE_OFFHOOK.equals(next)) {
            // An offhook that follows ringing is an answered incoming call; one that
            // starts from idle is an outgoing call.
            nextIncoming = STATE_RINGING.equals(previous)
                    || (STATE_OFFHOOK.equals(previous) && incoming);
        } else {
            nextIncoming = false;
        }

        if (next.equals(previous) && nextIncoming == incoming) return;

        state = next;
        incoming = nextIncoming;
        stateSince = System.currentTimeMillis();
        if (notify) notifyListeners();
    }

    private static void resetState() {
        boolean changed = !STATE_IDLE.equals(state) || incoming;
        state = STATE_IDLE;
        incoming = false;
        stateSince = System.currentTimeMillis();
        if (changed) notifyListeners();
    }

    /** Coarse state name: {@code idle}, {@code ringing} or {@code offhook}. */
    public static String stateName() {
        return state;
    }

    /** Human text for the UI: "Idle", "Ringing" or "In call". */
    public static String stateLabel() {
        switch (state) {
            case STATE_RINGING:
                return "Ringing";
            case STATE_OFFHOOK:
                return "In call";
            default:
                return "Idle";
        }
    }

    public static boolean isRinging() {
        return STATE_RINGING.equals(state);
    }

    public static boolean isInCall() {
        return STATE_OFFHOOK.equals(state);
    }

    /** True when the active (ringing or answered) call is an incoming call. */
    public static boolean isIncoming() {
        return incoming;
    }

    /** Epoch millis when the current state began. */
    public static long stateSinceMillis() {
        return stateSince;
    }

    // MARK: - Call control

    /**
     * Answers the ringing call through Telecom. Best effort only: returns false when
     * the control permission is missing, nothing is ringing, or the platform
     * refuses. Never throws.
     */
    public static boolean answerCall(Context context) {
        Context app = resolveContext(context);
        if (app == null || !hasControlAccess(app)) return false;
        TelecomManager telecom =
                (TelecomManager) app.getSystemService(Context.TELECOM_SERVICE);
        if (telecom == null) return false;
        try {
            telecom.acceptRingingCall();
            return true;
        } catch (SecurityException e) {
            Log.w(TAG, "answer denied", e);
            return false;
        } catch (RuntimeException e) {
            Log.w(TAG, "answer failed", e);
            return false;
        }
    }

    /**
     * Ends the current call through Telecom. Best effort only; returns false when
     * the control permission is missing or the platform refuses. Never throws.
     */
    public static boolean declineCall(Context context) {
        Context app = resolveContext(context);
        if (app == null || !hasControlAccess(app)) return false;
        TelecomManager telecom =
                (TelecomManager) app.getSystemService(Context.TELECOM_SERVICE);
        if (telecom == null) return false;
        try {
            telecom.endCall();
            return true;
        } catch (SecurityException e) {
            Log.w(TAG, "decline denied", e);
            return false;
        } catch (RuntimeException e) {
            Log.w(TAG, "decline failed", e);
            return false;
        }
    }

    private static Context resolveContext(Context context) {
        if (context != null) {
            Context app = context.getApplicationContext();
            return app != null ? app : context;
        }
        return appContext;
    }

    // MARK: - Listeners

    /** Registers a change listener; invoked on the main thread. */
    public static void addListener(Runnable listener) {
        if (listener != null) LISTENERS.addIfAbsent(listener);
    }

    public static void removeListener(Runnable listener) {
        if (listener != null) LISTENERS.remove(listener);
    }

    private static void notifyListeners() {
        if (LISTENERS.isEmpty()) return;
        MAIN.post(() -> {
            for (Runnable listener : LISTENERS) {
                try {
                    listener.run();
                } catch (RuntimeException e) {
                    Log.w(TAG, "call state listener failed", e);
                }
            }
        });
    }
}
