package com.senpai.androlaunch.companion;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.util.Base64;
import android.util.Log;
import android.util.LruCache;

import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Real launcher icons for the Mac app grid (protocol v4, {@code app-icons}).
 *
 * Request: newline-separated package names (bounded to {@link #MAX_PACKAGES}).
 * Response: {@code {"c":"app-icons","icons":[{"package":"…","label":"…","pngBase64":"…"}]}}
 *
 * Why bitmap rendering instead of shipping app icon files: a launcher icon is a
 * {@link Drawable} — adaptive on Android 8+ — and only the platform can resolve it
 * correctly for every OEM mask, density and themed-icon setting. Each icon is
 * drawn once into a 96×96 ARGB canvas, centre-fit, and PNG-encoded, which is the
 * size the Mac grid actually displays.
 *
 * Privacy/safety: only an icon bitmap and the public app label leave the phone —
 * no app data, no file paths, no user content. One bad package (uninstalled,
 * unreadable, broken drawable) is skipped, never fatal. Results are cached in
 * memory, keyed by package and the app's update time, so an upgraded app gets a
 * fresh icon instead of a stale one.
 */
final class AppIcons {

    private static final String TAG = "AndroLaunchCompanion";

    /** Upper bound on one request; the Mac batches 24 at a time. */
    static final int MAX_PACKAGES = 64;
    /** Guard against a pathological argument before any parsing happens. */
    static final int MAX_ARGUMENT_CHARS = 24 * 1024;
    /** Display size the Mac grid uses, at 1× and 2×. */
    static final int ICON_SIZE_PX = 96;

    /** Base64 text is ~4/3 the PNG size; 4 MB of payload is a few hundred icons. */
    private static final int CACHE_SIZE_KB = 4 * 1024 * 1024;

    private static final class Entry {
        final String label;
        final String base64;

        Entry(String label, String base64) {
            this.label = label;
            this.base64 = base64;
        }
    }

    private static final LruCache<String, Entry> CACHE =
            new LruCache<String, Entry>(CACHE_SIZE_KB) {
                @Override
                protected int sizeOf(String key, Entry value) {
                    return Math.max(1, value.base64.length() / 1024);
                }
            };

    private AppIcons() {}

    /**
     * Builds the JSON response. Returns {@code null} when the request is too large,
     * which the service turns into {@code error too_many_packages} rather than
     * silently truncating what the Mac asked for.
     */
    static String json(Context context, String argument) {
        if (context == null) return "{\"c\":\"app-icons\",\"icons\":[]}";
        if (argument != null && argument.length() > MAX_ARGUMENT_CHARS) return null;

        List<String> packages = parsePackages(argument);
        if (packages.size() > MAX_PACKAGES) return null;
        if (packages.isEmpty()) return "{\"c\":\"app-icons\",\"icons\":[]}";

        PackageManager manager = context.getPackageManager();
        StringBuilder json = new StringBuilder(packages.size() * 8192 + 32);
        json.append("{\"c\":\"app-icons\",\"icons\":[");
        int written = 0;
        for (String packageName : packages) {
            Entry entry = iconEntry(context, manager, packageName);
            if (entry == null || entry.base64.isEmpty()) continue;
            if (written > 0) json.append(',');
            json.append('{')
                    .append("\"package\":\"").append(Protocol.jsonEscape(packageName)).append("\",")
                    .append("\"label\":\"").append(Protocol.jsonEscape(entry.label)).append("\",")
                    .append("\"pngBase64\":\"").append(entry.base64).append("\"")
                    .append('}');
            written++;
        }
        json.append("]}");
        return json.toString();
    }

    // MARK: - Request parsing

    private static List<String> parsePackages(String argument) {
        Set<String> unique = new LinkedHashSet<>();
        if (argument == null) return new ArrayList<>(0);
        for (String raw : argument.split("\n")) {
            String candidate = raw == null ? "" : raw.trim();
            if (candidate.isEmpty()) continue;
            if (!isPlausiblePackage(candidate)) continue;
            unique.add(candidate);
        }
        return new ArrayList<>(unique);
    }

    /** Reverse-DNS package shape only; stops any surprising lookup input. */
    private static boolean isPlausiblePackage(String value) {
        if (value.length() < 3 || value.length() > 200) return false;
        if (value.startsWith(".") || value.endsWith(".") || value.contains("..")) return false;
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            boolean allowed = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                    || (c >= '0' && c <= '9') || c == '.' || c == '_';
            if (!allowed) return false;
        }
        return true;
    }

    // MARK: - Icon loading

    private static Entry iconEntry(
            Context context, PackageManager manager, String packageName) {
        ApplicationInfo info;
        long lastUpdateTime;
        try {
            PackageInfo packageInfo = manager.getPackageInfo(packageName, 0);
            info = packageInfo.applicationInfo;
            lastUpdateTime = packageInfo.lastUpdateTime;
        } catch (PackageManager.NameNotFoundException e) {
            // Uninstalled between the Mac's app list and this request: skip it.
            return null;
        } catch (RuntimeException e) {
            Log.w(TAG, "icon: package info failed for " + packageName, e);
            return null;
        }
        if (info == null) return null;

        // Keyed by update time so an upgraded app never serves a stale icon.
        String cacheKey = packageName + "@" + lastUpdateTime;
        Entry cached = CACHE.get(cacheKey);
        if (cached != null) return cached;

        String label;
        try {
            CharSequence rawLabel = manager.getApplicationLabel(info);
            label = rawLabel == null ? "" : rawLabel.toString();
        } catch (RuntimeException e) {
            label = "";
        }

        String base64 = renderPngBase64(manager, info);
        if (base64 == null) return null;

        Entry entry = new Entry(label, base64);
        CACHE.put(cacheKey, entry);
        return entry;
    }

    private static String renderPngBase64(PackageManager manager, ApplicationInfo info) {
        Drawable drawable = null;
        try {
            drawable = manager.getApplicationIcon(info);
        } catch (RuntimeException e) {
            // A broken/missing icon resource must not fail the whole batch.
            Log.w(TAG, "icon: drawable failed for " + info.packageName, e);
        }
        if (drawable == null) return null;

        Bitmap bitmap = null;
        try {
            bitmap = Bitmap.createBitmap(ICON_SIZE_PX, ICON_SIZE_PX, Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(bitmap);
            int intrinsicWidth = Math.max(1, drawable.getIntrinsicWidth());
            int intrinsicHeight = Math.max(1, drawable.getIntrinsicHeight());
            float scale = Math.min(
                    ICON_SIZE_PX / (float) intrinsicWidth,
                    ICON_SIZE_PX / (float) intrinsicHeight);
            int width = Math.max(1, Math.round(intrinsicWidth * scale));
            int height = Math.max(1, Math.round(intrinsicHeight * scale));
            int left = (ICON_SIZE_PX - width) / 2;
            int top = (ICON_SIZE_PX - height) / 2;
            drawable.setBounds(left, top, left + width, top + height);
            drawable.draw(canvas);

            ByteArrayOutputStream out = new ByteArrayOutputStream(8 * 1024);
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) return null;
            return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP);
        } catch (Throwable e) {
            // OutOfMemoryError included: one oversized icon must not kill the service.
            Log.w(TAG, "icon: render failed for " + info.packageName, e);
            return null;
        } finally {
            if (bitmap != null) bitmap.recycle();
        }
    }
}
