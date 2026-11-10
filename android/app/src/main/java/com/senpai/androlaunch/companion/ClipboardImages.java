package com.senpai.androlaunch.companion;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Image clipboard, both directions.
 *
 * Mac → phone: the phone clipboard cannot hold raw bytes, it holds a content URI,
 * so the image is written where the pasting app can read it:
 *  - Android 10+ inserts into {@code MediaStore} (Downloads/AndroLaunch), which
 *    needs no storage permission and produces a normal {@code content://} URI.
 *  - Android 8–9 has no permissionless insertion, so a {@code FileProvider} URI
 *    is used instead; a paste from an app that does not receive the read grant may
 *    be refused by the platform. That limitation is reported, never hidden.
 *
 * Only one image is kept: a new {@code clip.set.image} deletes the previous
 * entry, so the Downloads folder does not accumulate screenshots. Images are
 * capped at {@link #MAX_IMAGE_BYTES} before anything is written.
 *
 * Phone → Mac reading is still restricted by Android 10+ background clipboard
 * access, so {@code focus_required} is the expected, honest answer there.
 */
final class ClipboardImages {

    private static final String TAG = "AndroLaunchCompanion";
    private static final String PREFS = "companion_prefs";
    private static final String PREF_LAST_URI = "clip_image_uri";

    static final int MAX_IMAGE_BYTES = 8 * 1024 * 1024;

    private ClipboardImages() {}

    /** Outcome of a phone → Mac read. */
    static final class ReadResult {
        final byte[] bytes;
        final String error;

        private ReadResult(byte[] bytes, String error) {
            this.bytes = bytes;
            this.error = error;
        }

        static ReadResult ok(byte[] bytes) {
            return new ReadResult(bytes, null);
        }

        static ReadResult error(String code) {
            return new ReadResult(null, code);
        }
    }

    /** JSON-free raw base64 payloads; the Mac decodes them directly. */
    static String set(Context context, byte[] bytes) {
        if (context == null) return "failed";
        if (bytes == null || bytes.length == 0) return "empty";
        if (bytes.length > MAX_IMAGE_BYTES) return "too_large";

        String mime = detectMime(bytes);
        if (mime == null) return "unsupported_type";

        try {
            ClipboardManager clipboard =
                    (ClipboardManager) context.getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard == null) return "no_clipboard_service";

            Uri uri = writeImage(context, bytes, mime);
            if (uri == null) return "failed";

            ClipData clip = ClipData.newUri(context.getContentResolver(), "AndroLaunch image", uri);
            clipboard.setPrimaryClip(clip);
            Log.i(TAG, "clip.set.image wrote " + bytes.length + " bytes as " + mime);
            return "image_set";
        } catch (SecurityException e) {
            return "failed";
        } catch (RuntimeException e) {
            Log.w(TAG, "clip.set.image failed", e);
            return "failed";
        }
    }

    static ReadResult get(Context context) {
        if (context == null) return ReadResult.error("failed");
        ClipData clip;
        try {
            ClipboardManager clipboard =
                    (ClipboardManager) context.getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard == null || !clipboard.hasPrimaryClip()) {
                return ReadResult.error("empty");
            }
            clip = clipboard.getPrimaryClip();
        } catch (SecurityException e) {
            return ReadResult.error("focus_required");
        } catch (RuntimeException e) {
            return ReadResult.error("failed");
        }
        if (clip == null || clip.getItemCount() == 0) return ReadResult.error("empty");

        Uri uri = null;
        try {
            uri = clip.getItemAt(0).getUri();
        } catch (RuntimeException e) {
            return ReadResult.error("failed");
        }
        if (uri == null) {
            // A text clip is not an error the user can act on: there is simply no image.
            return ReadResult.error("empty");
        }

        try (InputStream input =
                context.getContentResolver().openInputStream(uri)) {
            if (input == null) return ReadResult.error("empty");
            byte[] bytes = readBounded(input, MAX_IMAGE_BYTES);
            if (bytes == null) return ReadResult.error("too_large");
            if (bytes.length == 0) return ReadResult.error("empty");
            if (detectMime(bytes) == null) return ReadResult.error("unsupported_type");
            return ReadResult.ok(bytes);
        } catch (SecurityException e) {
            // Android 10+ blocks clipboard reads for apps without focus.
            return ReadResult.error("focus_required");
        } catch (Exception e) {
            return ReadResult.error("failed");
        }
    }

    // MARK: - Writing

    private static Uri writeImage(Context context, byte[] bytes, String mime) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Uri mediaUri = writeToMediaStore(context, bytes, mime);
            if (mediaUri != null) return mediaUri;
        }
        return writeToProvider(context, bytes, mime);
    }

    private static Uri writeToMediaStore(Context context, byte[] bytes, String mime) {
        ContentResolver resolver = context.getContentResolver();
        String name = "androlaunch-clipboard." + (mime.equals("image/png") ? "png" : "jpg");
        try {
            deletePreviousMedia(context);

            ContentValues values = new ContentValues();
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
            values.put(MediaStore.MediaColumns.MIME_TYPE, mime);
            values.put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/AndroLaunch");
            Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) return null;
            try (OutputStream out = resolver.openOutputStream(uri)) {
                if (out == null) return null;
                out.write(bytes);
                out.flush();
            }
            rememberMedia(context, uri);
            return uri;
        } catch (SecurityException e) {
            Log.w(TAG, "MediaStore insert denied", e);
            return null;
        } catch (Exception e) {
            Log.w(TAG, "MediaStore insert failed", e);
            return null;
        }
    }

    private static void deletePreviousMedia(Context context) {
        Uri previous = lastMediaUri(context);
        if (previous == null) return;
        try {
            context.getContentResolver().delete(previous, null, null);
        } catch (Exception ignored) {
            // The item may already be gone; only the current write matters.
        }
        forgetMedia(context);
    }

    private static Uri writeToProvider(Context context, byte[] bytes, String mime) {
        try {
            File dir = new File(context.getCacheDir(), "clipboard");
            if (!dir.exists() && !dir.mkdirs()) return null;
            File file = new File(dir, mime.equals("image/png") ? "clip.png" : "clip.jpg");
            try (FileOutputStream out = new FileOutputStream(file)) {
                out.write(bytes);
            }
            return androidx.core.content.FileProvider.getUriForFile(
                    context,
                    context.getPackageName() + ".fileprovider",
                    file);
        } catch (Exception e) {
            Log.w(TAG, "file provider image write failed", e);
            return null;
        }
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static void rememberMedia(Context context, Uri uri) {
        prefs(context).edit().putString(PREF_LAST_URI, uri.toString()).apply();
    }

    private static void forgetMedia(Context context) {
        prefs(context).edit().remove(PREF_LAST_URI).apply();
    }

    private static Uri lastMediaUri(Context context) {
        String value = prefs(context).getString(PREF_LAST_URI, null);
        if (value == null || value.isEmpty()) return null;
        try {
            return Uri.parse(value);
        } catch (RuntimeException e) {
            return null;
        }
    }

    // MARK: - Helpers

    private static byte[] readBounded(InputStream input, int limit) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream(Math.min(limit, 64 * 1024));
        byte[] buffer = new byte[16 * 1024];
        int total = 0;
        int read;
        while ((read = input.read(buffer)) > 0) {
            total += read;
            if (total > limit) return null;
            out.write(buffer, 0, read);
        }
        return out.toByteArray();
    }

    /** Sniffs PNG/JPEG magic so a mislabeled URI cannot be written as graphics. */
    private static String detectMime(byte[] bytes) {
        if (bytes.length >= 8
                && (bytes[0] & 0xFF) == 0x89 && bytes[1] == 'P' && bytes[2] == 'N'
                && bytes[3] == 'G') {
            return "image/png";
        }
        if (bytes.length >= 3
                && (bytes[0] & 0xFF) == 0xFF && (bytes[1] & 0xFF) == 0xD8
                && (bytes[2] & 0xFF) == 0xFF) {
            return "image/jpeg";
        }
        if (bytes.length >= 12
                && bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F'
                && bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P') {
            return "image/webp";
        }
        return null;
    }
}
