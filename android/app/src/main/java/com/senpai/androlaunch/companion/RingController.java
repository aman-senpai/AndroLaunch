package com.senpai.androlaunch.companion;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

/**
 * "Find my phone": make the phone ring loudly for a bounded window.
 *
 * Design constraints, all deliberate:
 *  - Alarm usage ({@link AudioAttributes#USAGE_ALARM}) so Do Not Disturb does not
 *    silence it on most OEMs and the media volume is irrelevant.
 *  - The alarm stream volume is raised to maximum only while ringing and is always
 *    restored — on stop, on timeout, on service destruction and on any failure.
 *  - The duration is clamped to {@link #MAX_DURATION_MS}; the Mac cannot start an
 *    endless ring. The foreground notification grows a "Stop ringing" action, and
 *    a static listener lets the service repaint that notification immediately.
 *  - Nothing is recorded here; this only plays a sound.
 */
final class RingController {

    private static final String TAG = "AndroLaunchCompanion";

    static final int MAX_DURATION_MS = 30_000;
    static final int MIN_DURATION_MS = 1_000;

    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private static volatile boolean ringing;
    private static MediaPlayer player;
    private static AudioManager audioManager;
    private static int savedAlarmVolume = -1;
    private static long ringingUntilAt;
    private static Runnable stateListener;

    private RingController() {}

    /** The service repaints its foreground notification through this. */
    static void setStateListener(Runnable listener) {
        stateListener = listener;
    }

    static boolean isRinging() {
        return ringing;
    }

    static long ringingUntilMillis() {
        return ringingUntilAt;
    }

    private static void notifyStateChanged() {
        Runnable listener = stateListener;
        if (listener == null) return;
        MAIN.post(() -> {
            try {
                listener.run();
            } catch (RuntimeException e) {
                Log.w(TAG, "ring state listener failed", e);
            }
        });
    }

    /**
     * Starts (or restarts) the ring.
     *
     * @return {@code ringing} or a short error code.
     */
    static String ring(Context context, int durationMs) {
        if (context == null) return "failed";
        int duration = Math.max(MIN_DURATION_MS, Math.min(MAX_DURATION_MS, durationMs));

        stopInternal(false);
        try {
            audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
            if (audioManager != null) {
                savedAlarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM);
                int max = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM);
                audioManager.setStreamVolume(AudioManager.STREAM_ALARM, max, 0);
            }

            MediaPlayer mediaPlayer = new MediaPlayer();
            mediaPlayer.setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build());
            mediaPlayer.setLooping(true);
            mediaPlayer.setDataSource(context, alarmUri(context));
            mediaPlayer.prepare();
            mediaPlayer.start();

            player = mediaPlayer;
            ringing = true;
            ringingUntilAt = System.currentTimeMillis() + duration;
            MAIN.postDelayed(timeoutTask, duration);
            notifyStateChanged();
            return "ringing";
        } catch (Exception e) {
            Log.w(TAG, "ring failed", e);
            stopInternal(true);
            return "failed";
        }
    }

    /** Stops the ring and restores the alarm volume. Idempotent. */
    static String stop(Context context) {
        boolean wasRinging = ringing;
        stopInternal(true);
        return wasRinging ? "stopped" : "not_ringing";
    }

    /** Full teardown used when the service dies. */
    static void shutdown() {
        stopInternal(false);
    }

    private static final Runnable timeoutTask = () -> {
        if (!ringing) return;
        Log.i(TAG, "ring timed out");
        stopInternal(true);
    };

    private static void stopInternal(boolean notify) {
        MAIN.removeCallbacks(timeoutTask);
        MediaPlayer mediaPlayer = player;
        player = null;
        if (mediaPlayer != null) {
            try {
                if (mediaPlayer.isPlaying()) mediaPlayer.stop();
            } catch (RuntimeException ignored) {
                // The player may already be in an error state; releasing is what matters.
            }
            try {
                mediaPlayer.release();
            } catch (RuntimeException ignored) {
                // Nothing useful to do if release fails.
            }
        }
        if (savedAlarmVolume >= 0 && audioManager != null) {
            try {
                audioManager.setStreamVolume(
                        AudioManager.STREAM_ALARM, savedAlarmVolume, 0);
            } catch (RuntimeException e) {
                Log.w(TAG, "could not restore alarm volume", e);
            }
        }
        savedAlarmVolume = -1;
        ringing = false;
        ringingUntilAt = 0;
        if (notify) notifyStateChanged();
    }

    /**
     * Alarm sound by default; the ringtone is the fallback for devices without a
     * configured alarm and the notification sound is the last resort. A silent or
     * missing sound cannot be faked, so the caller sees {@code failed}.
     */
    private static Uri alarmUri(Context context) {
        Uri alarm = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
        if (alarm != null) return alarm;
        Uri ringtone = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
        if (ringtone != null) return ringtone;
        Uri notification = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        if (notification != null) return notification;
        return android.provider.Settings.System.DEFAULT_ALARM_ALERT_URI;
    }
}
