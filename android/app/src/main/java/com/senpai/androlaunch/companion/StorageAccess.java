package com.senpai.androlaunch.companion;

import android.Manifest;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.Settings;
import android.util.Log;

/**
 * Storage permission state and the one-tap route to granting it (protocol v5).
 *
 * Why this exists: the Mac storage sheet can show exact capacity from
 * {@link StorageInfo} without any permission, but per-folder totals need to read
 * the shared-storage tree. Since Android 11 the only app-facing way to do that is
 * the "All files access" special grant ({@code MANAGE_EXTERNAL_STORAGE}); on
 * Android 8–9 it is {@code READ_EXTERNAL_STORAGE}. Android 10+ scoped storage and
 * Android 13 media permissions do not expose a folder tree, so those states are
 * reported honestly instead of pretending the scan will work.
 *
 * {@link #requestAccess} opens the right system screen for the device: All-files
 * access on Android 11+, app details → permissions on older versions. Opening a
 * screen can be refused by background-activity-launch rules; the companion never
 * crashes, it reports {@code failed} and the foreground notification keeps a
 * "Allow storage" hint in the UI.
 */
final class StorageAccess {

    private static final String TAG = "AndroLaunchCompanion";

    private StorageAccess() {}

    /**
     * JSON: {@code {"granted":bool,"manager":bool,"read":bool,"media":bool,"detail":"…"}}
     *
     * - {@code manager}: Android 11+ "All files access" is granted.
     * - {@code read}: legacy READ_EXTERNAL_STORAGE is granted (meaningful up to API 32).
     * - {@code media}: READ_MEDIA_IMAGES or READ_MEDIA_VIDEO is granted (API 33+).
     * - {@code granted}: full folder-tree access is available. Media-only access does
     *   not count, because it cannot enumerate folders.
     * - {@code detail}: one sentence the Mac can show unchanged.
     */
    static String json(Context context) {
        boolean manager = false;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                manager = Environment.isExternalStorageManager();
            } catch (RuntimeException e) {
                Log.w(TAG, "storage: isExternalStorageManager failed", e);
            }
        }

        boolean read = hasPermission(context, Manifest.permission.READ_EXTERNAL_STORAGE);
        boolean media = hasPermission(context, Manifest.permission.READ_MEDIA_IMAGES)
                || hasPermission(context, Manifest.permission.READ_MEDIA_VIDEO);

        // READ_EXTERNAL_STORAGE stops granting shared-storage reads on Android 13.
        boolean legacyReadCounts = read && Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2;
        boolean granted = manager || legacyReadCounts;

        String detail;
        if (manager) {
            detail = "All files access is granted, so folder totals are complete.";
        } else if (legacyReadCounts) {
            detail = "Storage access is granted, so folder totals are complete.";
        } else if (media) {
            detail =
                "Media access only. Folder totals need All files access in Android settings.";
        } else {
            detail =
                "Storage access is not granted. Android hides folder totals from apps without it.";
        }

        return new StringBuilder(240)
                .append('{')
                .append("\"granted\":").append(granted).append(',')
                .append("\"manager\":").append(manager).append(',')
                .append("\"read\":").append(read).append(',')
                .append("\"media\":").append(media).append(',')
                .append("\"detail\":\"").append(Protocol.jsonEscape(detail)).append("\"")
                .append('}')
                .toString();
    }

    /**
     * Opens the system screen where the user can grant storage access.
     *
     * @return {@code opened} when the Settings activity was launched, otherwise a
     *         short error code. Never throws.
     */
    static String requestAccess(Context context) {
        if (context == null) return "failed";

        try {
            context.startActivity(allFilesIntent(context));
            return "opened";
        } catch (ActivityNotFoundException e) {
            Log.w(TAG, "storage: all-files settings unavailable", e);
        } catch (RuntimeException e) {
            // Background activity launch restrictions or an OEM-blocked Settings
            // activity: report honestly, the user can still open the app from the
            // shade and grant it there.
            Log.w(TAG, "storage: could not open all-files settings", e);
        }

        try {
            context.startActivity(appDetailsIntent(context));
            return "opened";
        } catch (ActivityNotFoundException e) {
            Log.w(TAG, "storage: app details unavailable", e);
        } catch (RuntimeException e) {
            Log.w(TAG, "storage: could not open app details", e);
        }
        return "failed";
    }

    private static Intent allFilesIntent(Context context) {
        Intent intent;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
        } else {
            // No all-files screen below Android 11; app details is the closest.
            intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        }
        intent.setData(Uri.parse("package:" + context.getPackageName()));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return intent;
    }

    private static Intent appDetailsIntent(Context context) {
        Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        intent.setData(Uri.parse("package:" + context.getPackageName()));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return intent;
    }

    private static boolean hasPermission(Context context, String permission) {
        if (context == null) return false;
        try {
            return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
        } catch (RuntimeException e) {
            return false;
        }
    }
}
