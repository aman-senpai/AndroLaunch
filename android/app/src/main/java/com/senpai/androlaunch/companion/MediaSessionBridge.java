package com.senpai.androlaunch.companion;

import android.content.Context;
import android.graphics.Bitmap;
import android.media.MediaDescription;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.util.Base64;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.util.List;

/**
 * Now-playing state and transport control for whatever is playing on the phone.
 *
 * The companion is an enabled notification listener, which is exactly the access
 * level {@link MediaSessionManager#getActiveSessions} requires — no
 * {@code MEDIA_CONTENT_CONTROL} permission, no extra grant. With several active
 * sessions (e.g. a music app paused behind a podcast) the most recently active
 * one wins, which matches what the user last touched.
 *
 * Artwork is optional: it is scaled down, capped at {@link #MAX_ARTWORK_BYTES}
 * and only sent when the Mac explicitly asks for it. It is never written to disk.
 */
final class MediaSessionBridge {

    private static final String TAG = "AndroLaunchCompanion";

    /** Artwork budget for one response; keeps the line well under the socket limits. */
    private static final int MAX_ARTWORK_BYTES = 96 * 1024;
    private static final int ARTWORK_MAX_EDGE_PX = 256;

    private MediaSessionBridge() {}

    /** Argument passed by the Mac to include artwork in {@code media.state}. */
    static final String ARG_ARTWORK = "artwork";

    private static MediaController activeController(Context context) {
        if (context == null) return null;
        try {
            MediaSessionManager manager =
                    (MediaSessionManager) context.getSystemService(Context.MEDIA_SESSION_SERVICE);
            if (manager == null) return null;
            List<MediaController> sessions =
                    manager.getActiveSessions(NotificationRelay.listenerComponent(context));
            if (sessions == null || sessions.isEmpty()) return null;

            MediaController best = null;
            long bestActivity = Long.MIN_VALUE;
            for (MediaController controller : sessions) {
                if (controller == null) continue;
                PlaybackState state = controller.getPlaybackState();
                if (state == null) continue;
                if (!isTransportable(state.getState())) continue;

                MediaMetadata metadata = controller.getMetadata();
                // A session with no metadata cannot render a now-playing row.
                if (metadata == null) continue;

                long activity = state.getLastPositionUpdateTime();
                // Prefer something playing over a paused session of the same age.
                if (state.getState() == PlaybackState.STATE_PLAYING) {
                    activity += 1_000L;
                }
                if (activity > bestActivity) {
                    bestActivity = activity;
                    best = controller;
                }
            }
            return best;
        } catch (SecurityException e) {
            Log.w(TAG, "media sessions require notification access", e);
            return null;
        } catch (RuntimeException e) {
            Log.w(TAG, "media session lookup failed", e);
            return null;
        }
    }

    private static boolean isTransportable(int state) {
        return state == PlaybackState.STATE_PLAYING
                || state == PlaybackState.STATE_PAUSED
                || state == PlaybackState.STATE_BUFFERING
                || state == PlaybackState.STATE_FAST_FORWARDING
                || state == PlaybackState.STATE_REWINDING;
    }

    /**
     * JSON for {@code media.state}.
     *
     * <pre>
     * {"available":bool,"app":"…","title":"…","artist":"…","album":"…",
     *  "playing":bool,"canNext":bool,"canPrev":bool,
     *  "artwork":{"mime":"image/png","data":"<base64>"}?}
     * </pre>
     *
     * {@code available=false} is a normal answer (nothing is playing), not an error.
     */
    static String stateJson(Context context, boolean includeArtwork) {
        MediaController controller = activeController(context);
        if (controller == null) {
            return "{\"available\":false,\"app\":\"\",\"title\":\"\",\"artist\":\"\",\"album\":\"\","
                    + "\"playing\":false,\"canNext\":false,\"canPrev\":false}";
        }
        try {
            MediaMetadata metadata = controller.getMetadata();
            PlaybackState state = controller.getPlaybackState();
            long actions = state == null ? 0 : state.getActions();

            String app = packageOf(controller);
            String title = text(metadata, MediaMetadata.METADATA_KEY_TITLE);
            String artist = text(metadata, MediaMetadata.METADATA_KEY_ARTIST);
            if (artist.isEmpty()) artist = text(metadata, MediaMetadata.METADATA_KEY_ALBUM_ARTIST);
            if (artist.isEmpty()) artist = text(metadata, MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE);
            String album = text(metadata, MediaMetadata.METADATA_KEY_ALBUM);

            boolean playing = state != null && state.getState() == PlaybackState.STATE_PLAYING;
            boolean canNext = (actions & PlaybackState.ACTION_SKIP_TO_NEXT) != 0;
            boolean canPrev = (actions & PlaybackState.ACTION_SKIP_TO_PREVIOUS) != 0;

            StringBuilder json = new StringBuilder(320);
            json.append('{')
                    .append("\"available\":true,")
                    .append("\"app\":\"").append(Protocol.jsonEscape(app)).append("\",")
                    .append("\"title\":\"").append(Protocol.jsonEscape(title)).append("\",")
                    .append("\"artist\":\"").append(Protocol.jsonEscape(artist)).append("\",")
                    .append("\"album\":\"").append(Protocol.jsonEscape(album)).append("\",")
                    .append("\"playing\":").append(playing).append(',')
                    .append("\"canNext\":").append(canNext).append(',')
                    .append("\"canPrev\":").append(canPrev);

            if (includeArtwork) {
                String artwork = artworkJson(metadata, controller);
                if (artwork != null) {
                    json.append(",\"artwork\":").append(artwork);
                }
            }
            json.append('}');
            return json.toString();
        } catch (RuntimeException e) {
            Log.w(TAG, "media state failed", e);
            return "{\"available\":false,\"app\":\"\",\"title\":\"\",\"artist\":\"\",\"album\":\"\","
                    + "\"playing\":false,\"canNext\":false,\"canPrev\":false}";
        }
    }

    private static String packageOf(MediaController controller) {
        try {
            return controller.getPackageName() == null ? "" : controller.getPackageName();
        } catch (RuntimeException e) {
            return "";
        }
    }

    private static String text(MediaMetadata metadata, String key) {
        if (metadata == null) return "";
        try {
            CharSequence value = metadata.getText(key);
            if (value == null) return "";
            return value.toString().trim();
        } catch (RuntimeException e) {
            return "";
        }
    }

    private static String artworkJson(MediaMetadata metadata, MediaController controller) {
        Bitmap bitmap = null;
        try {
            MediaDescription description = metadata == null ? null : metadata.getDescription();
            if (description != null) bitmap = description.getIconBitmap();
            if (bitmap == null && controller != null) {
                PlaybackState state = controller.getPlaybackState();
                if (state != null) bitmap = state.getExtras() == null
                        ? null : (Bitmap) state.getExtras().get("android.media.session.extra.bitmap");
            }
        } catch (RuntimeException e) {
            return null;
        }
        if (bitmap == null) return null;

        byte[] png = encodeBoundedPng(bitmap);
        if (png == null) return null;
        return "{\"mime\":\"image/png\",\"data\":\"" + Base64.encodeToString(png, Base64.NO_WRAP) + "\"}";
    }

    /** Scales down and re-encodes until the PNG fits the budget. */
    private static byte[] encodeBoundedPng(Bitmap source) {
        try {
            int widest = Math.max(source.getWidth(), source.getHeight());
            float scale = widest > ARTWORK_MAX_EDGE_PX ? ARTWORK_MAX_EDGE_PX / (float) widest : 1f;
            Bitmap bitmap = source;
            if (scale < 1f) {
                bitmap = Bitmap.createScaledBitmap(
                        source,
                        Math.max(1, Math.round(source.getWidth() * scale)),
                        Math.max(1, Math.round(source.getHeight() * scale)),
                        true);
            }
            for (int quality = 0; quality < 3; quality++) {
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
                byte[] bytes = out.toByteArray();
                if (bytes.length <= MAX_ARTWORK_BYTES) return bytes;
                if (bitmap == source && scale == 1f) {
                    bitmap = Bitmap.createScaledBitmap(source, source.getWidth() / 2,
                            source.getHeight() / 2, true);
                } else {
                    bitmap = Bitmap.createScaledBitmap(bitmap,
                            Math.max(1, bitmap.getWidth() / 2),
                            Math.max(1, bitmap.getHeight() / 2), true);
                }
            }
            return null;
        } catch (RuntimeException e) {
            return null;
        }
    }

    // MARK: - Transport

    static String play(Context context) {
        return sendTransport(context, "play");
    }

    static String pause(Context context) {
        return sendTransport(context, "pause");
    }

    static String next(Context context) {
        return sendTransport(context, "next");
    }

    static String previous(Context context) {
        return sendTransport(context, "prev");
    }

    private static String sendTransport(Context context, String label) {
        MediaController controller = activeController(context);
        if (controller == null) return "no_session";
        if (controller.getTransportControls() == null) return "no_session";
        try {
            switch (label) {
                case "play": controller.getTransportControls().play(); break;
                case "pause": controller.getTransportControls().pause(); break;
                case "next": controller.getTransportControls().skipToNext(); break;
                case "prev": controller.getTransportControls().skipToPrevious(); break;
                default: return "unsupported";
            }
            return "ok";
        } catch (SecurityException e) {
            return "permission_required";
        } catch (RuntimeException e) {
            Log.w(TAG, "media transport failed", e);
            return "failed";
        }
    }
}
