package com.senpai.androlaunch.companion;

import android.content.Context;
import android.os.Build;
import android.os.Environment;
import android.os.StatFs;
import android.util.Log;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.TimeUnit;

/**
 * Storage breakdown for the Mac storage sheet.
 *
 * The numbers come from two places, because Android does not offer one API for
 * both facts:
 *  - Total / used / free are exact: {@link StatFs} on {@code /data} is the same
 *    arithmetic `df /data` performs, without spawning a shell.
 *  - Per-folder sizes would need a full storage permission. A regular app cannot
 *    read the shared-storage tree on Android 13 with targetSdk 33 (scoped
 *    storage), so this tries `du -sk` on the top-level public folders as the app
 *    uid and reports only what it could actually measure. {@code complete:false}
 *    is the honest answer there — the Mac then runs the same measurement through
 *    `adb shell`, whose `shell` uid may read the tree, and shows the fuller list.
 *
 * Nothing is cached or written; the scan is bounded to {@link #DU_BUDGET_MS}.
 */
final class StorageInfo {

    private static final String TAG = "AndroLaunchCompanion";
    private static final long DU_BUDGET_MS = 3_500L;
    private static final int MAX_FOLDERS = 14;

    private StorageInfo() {}

    static String json(Context context) {
        long total = 0;
        long free = 0;
        String dataPath = "/data";
        try {
            StatFs stat = new StatFs(Environment.getDataDirectory().getAbsolutePath());
            long blockSize = stat.getBlockSizeLong();
            total = stat.getBlockCountLong() * blockSize;
            free = stat.getAvailableBlocksLong() * blockSize;
        } catch (RuntimeException e) {
            Log.w(TAG, "data StatFs failed", e);
        }
        long used = Math.max(0, total - free);

        long externalTotal = 0;
        long externalFree = 0;
        try {
            File external = Environment.getExternalStorageDirectory();
            if (external != null && external.exists()) {
                StatFs stat = new StatFs(external.getAbsolutePath());
                long blockSize = stat.getBlockSizeLong();
                externalTotal = stat.getBlockCountLong() * blockSize;
                externalFree = stat.getAvailableBlocksLong() * blockSize;
            }
        } catch (RuntimeException e) {
            // No mounted external storage: report zeros rather than a guess.
        }

        FolderScan scan = scanFolders();
        StringBuilder json = new StringBuilder(512);
        json.append('{')
                .append("\"total\":").append(total).append(',')
                .append("\"used\":").append(used).append(',')
                .append("\"free\":").append(free).append(',')
                .append("\"path\":\"").append(Protocol.jsonEscape(dataPath)).append("\",")
                .append("\"externalTotal\":").append(externalTotal).append(',')
                .append("\"externalFree\":").append(externalFree).append(',')
                .append("\"scannedAt\":").append(System.currentTimeMillis()).append(',')
                .append("\"complete\":").append(scan.complete).append(',')
                .append("\"folders\":[");
        for (int i = 0; i < scan.folders.size(); i++) {
            Folder folder = scan.folders.get(i);
            if (i > 0) json.append(',');
            json.append('{')
                    .append("\"name\":\"").append(Protocol.jsonEscape(folder.name)).append("\",")
                    .append("\"bytes\":").append(folder.bytes)
                    .append('}');
        }
        json.append("]}");
        return json.toString();
    }

    private static final class Folder {
        final String name;
        final long bytes;

        Folder(String name, long bytes) {
            this.name = name;
            this.bytes = bytes;
        }
    }

    private static final class FolderScan {
        final List<Folder> folders;
        final boolean complete;

        FolderScan(List<Folder> folders, boolean complete) {
            this.folders = folders;
            this.complete = complete;
        }
    }

    /**
     * Measures the top-level public folders as the app uid. Folders the app cannot
     * read are skipped; {@code complete} only becomes true when every candidate
     * was measured, so the Mac knows when to re-run the scan through ADB.
     */
    private static FolderScan scanFolders() {
        File root;
        try {
            root = Environment.getExternalStorageDirectory();
        } catch (RuntimeException e) {
            return new FolderScan(new ArrayList<>(), false);
        }
        if (root == null || !root.exists()) {
            return new FolderScan(new ArrayList<>(), false);
        }
        File[] children = root.listFiles();
        if (children == null || children.length == 0) {
            return new FolderScan(new ArrayList<>(), false);
        }

        List<File> candidates = new ArrayList<>();
        for (File child : children) {
            if (child == null || !child.isDirectory()) continue;
            String name = child.getName();
            if (name == null || name.startsWith(".") || "Android".equals(name)) continue;
            candidates.add(child);
            if (candidates.size() >= MAX_FOLDERS) break;
        }

        long deadline = System.currentTimeMillis() + DU_BUDGET_MS;
        List<Folder> measured = new ArrayList<>();
        int attempted = 0;
        for (File folder : candidates) {
            if (System.currentTimeMillis() > deadline) break;
            attempted++;
            long bytes = duKilobytes(folder);
            if (bytes > 0) {
                measured.add(new Folder(folder.getName(), bytes * 1024L));
            }
        }
        measured.sort((a, b) -> Long.compare(b.bytes, a.bytes));
        boolean complete = attempted == candidates.size() && measured.size() == candidates.size();
        return new FolderScan(measured, complete);
    }

    /** {@code du -sk}, or -1 when the folder is unreadable. */
    private static long duKilobytes(File folder) {
        Process process = null;
        try {
            process = new ProcessBuilder(Arrays.asList("/system/bin/du", "-sk", folder.getAbsolutePath()))
                    .redirectErrorStream(true)
                    .start();
            boolean finished = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    ? process.waitFor(1_200L, TimeUnit.MILLISECONDS)
                    : waitForCompat(process);
            if (!finished) {
                process.destroyForcibly();
                return -1;
            }
            if (process.exitValue() != 0) return -1;
            java.io.BufferedReader reader = new java.io.BufferedReader(
                    new java.io.InputStreamReader(process.getInputStream()));
            String line;
            while ((line = reader.readLine()) != null) {
                String trimmed = line.trim();
                int tab = trimmed.indexOf('\t');
                if (tab <= 0) tab = trimmed.indexOf(' ');
                if (tab <= 0) continue;
                try {
                    return Long.parseLong(trimmed.substring(0, tab).trim());
                } catch (NumberFormatException ignored) {
                    // `du` can print warnings before the line that matters.
                }
            }
            return -1;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return -1;
        } catch (Exception e) {
            return -1;
        } finally {
            if (process != null) {
                try {
                    process.destroy();
                } catch (RuntimeException ignored) {
                    // Already gone.
                }
            }
        }
    }

    /** API 26 has waitFor(timeout); this exists only as a defensive fallback. */
    private static boolean waitForCompat(Process process) throws InterruptedException {
        return process.waitFor() == 0;
    }
}
