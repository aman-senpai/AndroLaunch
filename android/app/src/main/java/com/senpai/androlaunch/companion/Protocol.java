package com.senpai.androlaunch.companion;

import android.util.Base64;

/**
 * Line protocol shared with the macOS app.
 *
 * <pre>
 * request : &lt;id&gt; \t &lt;command&gt; \t &lt;base64 argument&gt;
 * response: &lt;id&gt; \t ok|error \t &lt;base64 payload&gt;
 * </pre>
 *
 * Base64 keeps arbitrary text (clipboard contents, notification bodies) on one
 * line without escaping rules. Commands are deliberately coarse so new ones can
 * be added on the Mac side without a protocol version bump.
 *
 * Version history
 * ---------------
 * v1  ping / clip.set / clip.get / notif.list / notif.clear.
 * v2  adds call awareness: {@code call.state} reports the coarse call state and
 *     {@code call.answer}/{@code call.end} are best-effort call control.
 * v3  adds notification actions (reply/dismiss), now-playing media transport,
 *     ring-phone, storage info and clipboard images. Every v1/v2 command keeps
 *     its exact request and response shape, and the {@code notif.list} entries
 *     only gain extra JSON fields, so an older Mac build keeps working.
 * v4  adds app-icons: newline-separated package names in, 96 px PNG icons out.
 *     Purely additive — an older Mac never sends it, and an older companion
 *     answers unknown_command so the Mac keeps its SF Symbol fallback.
 * v5  adds storage.access / storage.requestAccess (is the All-files grant in
 *     place, and open the Android screen that grants it) and notif.action for
 *     non-reply notification action buttons such as "Mark as read".
 *
 * Unknown commands always answer {@code error unknown_command:<name>} and keep
 * the socket open, so a newer Mac can probe for capabilities it is not sure the
 * installed companion supports.
 */
final class Protocol {
    // v1
    static final String CMD_PING = "ping";
    static final String CMD_CLIPBOARD_SET = "clip.set";
    static final String CMD_CLIPBOARD_GET = "clip.get";
    static final String CMD_NOTIFICATIONS = "notif.list";
    static final String CMD_NOTIFICATIONS_CLEAR = "notif.clear";

    // v2
    static final String CMD_CALL_STATE = "call.state";
    static final String CMD_CALL_ANSWER = "call.answer";
    static final String CMD_CALL_END = "call.end";

    // v3 — notification actions
    static final String CMD_NOTIFICATIONS_REPLY = "notif.reply";
    static final String CMD_NOTIFICATIONS_DISMISS = "notif.dismiss";

    // v3 — media session
    static final String CMD_MEDIA_STATE = "media.state";
    static final String CMD_MEDIA_PLAY = "media.play";
    static final String CMD_MEDIA_PAUSE = "media.pause";
    static final String CMD_MEDIA_NEXT = "media.next";
    static final String CMD_MEDIA_PREV = "media.prev";

    // v3 — find my phone
    static final String CMD_PHONE_RING = "phone.ring";
    static final String CMD_PHONE_RING_STOP = "phone.ring.stop";

    // v3 — storage
    static final String CMD_STORAGE_INFO = "storage.info";

    // v3 — clipboard images
    static final String CMD_CLIPBOARD_SET_IMAGE = "clip.set.image";
    static final String CMD_CLIPBOARD_GET_IMAGE = "clip.get.image";

    // v4 — real app icons
    static final String CMD_APP_ICONS = "app-icons";

    // v5 — storage permission + non-reply notification actions
    static final String CMD_STORAGE_ACCESS = "storage.access";
    static final String CMD_STORAGE_REQUEST_ACCESS = "storage.requestAccess";
    static final String CMD_NOTIFICATIONS_ACTION = "notif.action";

    static final String STATUS_OK = "ok";
    static final String STATUS_ERROR = "error";

    private Protocol() {}

    static String encode(String value) {
        if (value == null) return "";
        return Base64.encodeToString(value.getBytes(java.nio.charset.StandardCharsets.UTF_8),
                Base64.NO_WRAP);
    }

    static String decode(String value) {
        if (value == null || value.isEmpty()) return "";
        try {
            return new String(Base64.decode(value, Base64.NO_WRAP),
                    java.nio.charset.StandardCharsets.UTF_8);
        } catch (IllegalArgumentException e) {
            return "";
        }
    }

    /** Lenient decode for binary payloads; null when the argument is not valid base64. */
    static byte[] decodeBytes(String value) {
        if (value == null || value.isEmpty()) return null;
        try {
            return Base64.decode(value, Base64.NO_WRAP | Base64.DEFAULT);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    static String encodeBytes(byte[] value) {
        if (value == null || value.length == 0) return "";
        return Base64.encodeToString(value, Base64.NO_WRAP);
    }

    static String ok(String id, String payload) {
        return id + "\t" + STATUS_OK + "\t" + encode(payload);
    }

    static String error(String id, String message) {
        return id + "\t" + STATUS_ERROR + "\t" + encode(message);
    }

    /** Minimal JSON string escaping for notification/media/storage payloads. */
    static String jsonEscape(String value) {
        if (value == null) return "";
        StringBuilder out = new StringBuilder(value.length() + 16);
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"': out.append("\\\""); break;
                case '\\': out.append("\\\\"); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        out.append(String.format("\\u%04x", (int) c));
                    } else {
                        out.append(c);
                    }
            }
        }
        return out.toString();
    }
}
