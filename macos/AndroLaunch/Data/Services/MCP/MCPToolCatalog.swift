//
//  MCPToolCatalog.swift
//  AndroLaunch
//
//  The Android Use tool set. Tool names, descriptions and JSON schemas are the
//  contract an AI client sees in `tools/list`; they must stay in sync with the
//  planner in `MCPToolPlanner` and the executor in `MCPToolExecutor`.
//

import Foundation

struct MCPToolDefinition: Equatable {
    let name: String
    let title: String
    let description: String
    let properties: [String: [String: Any]]
    let required: [String]

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false,
        ]
    }

    var wireObject: [String: Any] {
        [
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": inputSchema,
        ]
    }

    static func == (lhs: MCPToolDefinition, rhs: MCPToolDefinition) -> Bool {
        lhs.name == rhs.name && lhs.title == rhs.title
            && lhs.description == rhs.description
            && NSDictionary(dictionary: lhs.properties).isEqual(to: rhs.properties)
            && lhs.required == rhs.required
    }
}

enum MCPToolCatalog {
    /// Order is stable and deliberate: discovery first, then input, then apps,
    /// clipboard/notifications, finally shell and UI inspection.
    static let tools: [MCPToolDefinition] = [
        tool(
            "phone_list_devices",
            title: "List Android devices",
            description:
                "List connected Android devices with serial, model, connection state and transport. Call this first.",
            props: [:]),

        tool(
            "phone_device_info",
            title: "Device information",
            description:
                "Read model, Android version, API level, battery level, charging state and serial for one device.",
            props: ["serial": serialProperty]),

        tool(
            "phone_screenshot",
            title: "Screenshot",
            description:
                "Capture the current screen as a PNG image. Returns image content plus a short caption.",
            props: ["serial": serialProperty]),

        tool(
            "phone_tap",
            title: "Tap",
            description: "Tap the screen at pixel coordinates (x, y).",
            props: [
                "x": integerProperty("Horizontal pixel coordinate.", minimum: 0, maximum: 20000),
                "y": integerProperty("Vertical pixel coordinate.", minimum: 0, maximum: 20000),
                "serial": serialProperty,
            ],
            required: ["x", "y"]),

        tool(
            "phone_swipe",
            title: "Swipe",
            description: "Swipe from (x1, y1) to (x2, y2) over an optional duration.",
            props: [
                "x1": integerProperty("Start x pixel coordinate.", minimum: 0, maximum: 20000),
                "y1": integerProperty("Start y pixel coordinate.", minimum: 0, maximum: 20000),
                "x2": integerProperty("End x pixel coordinate.", minimum: 0, maximum: 20000),
                "y2": integerProperty("End y pixel coordinate.", minimum: 0, maximum: 20000),
                "duration_ms": integerProperty(
                    "Swipe duration in milliseconds.", minimum: 1, maximum: 10000),
                "serial": serialProperty,
            ],
            required: ["x1", "y1", "x2", "y2"]),

        tool(
            "phone_input_text",
            title: "Type text",
            description:
                "Type text into the focused field. Single line; spaces are escaped for the Android input command.",
            props: [
                "text": ["type": "string", "minLength": 1, "maxLength": 2000,
                         "description": "Text to type. Newlines are not supported."],
                "serial": serialProperty,
            ],
            required: ["text"]),

        tool(
            "phone_press_key",
            title: "Press key",
            description:
                "Press a hardware or navigation key. Accepts names (home, back, recents, enter, power, volume_up, volume_down, delete, tab, escape, space, wakeup, sleep) or an Android keycode number.",
            props: [
                "key": ["type": "string", "minLength": 1, "maxLength": 32,
                        "description": "Key name or numeric keycode."],
                "serial": serialProperty,
            ],
            required: ["key"]),

        tool(
            "phone_shell",
            title: "Run shell command",
            description:
                "Run a shell command on the device as the shell user. Use deliberately: it can change device state.",
            props: [
                "command": ["type": "string", "minLength": 1, "maxLength": 4096,
                            "description": "Command passed to `adb shell`."],
                "serial": serialProperty,
            ],
            required: ["command"]),

        tool(
            "phone_list_apps",
            title: "List installed apps",
            description:
                "List installed app package names. Third-party apps by default; set include_system to include system packages.",
            props: [
                "include_system": [
                    "type": "boolean",
                    "description": "Include system packages. Defaults to false.",
                ],
                "serial": serialProperty,
            ]),

        tool(
            "phone_launch_app",
            title: "Launch app",
            description: "Launch an installed app by package name.",
            props: [
                "package": [
                    "type": "string", "minLength": 3, "maxLength": 255,
                    "description": "Android package name, for example com.android.settings.",
                ],
                "serial": serialProperty,
            ],
            required: ["package"]),

        tool(
            "phone_clipboard_get",
            title: "Read clipboard",
            description:
                "Read text from the phone clipboard through the AndroLaunch companion. Android only allows this while the companion is focused.",
            props: ["serial": serialProperty]),

        tool(
            "phone_clipboard_set",
            title: "Set clipboard",
            description:
                "Copy text to the phone clipboard through the AndroLaunch companion.",
            props: [
                "text": ["type": "string", "minLength": 1, "maxLength": 32000,
                         "description": "Text to place on the phone clipboard."],
                "serial": serialProperty,
            ],
            required: ["text"]),

        tool(
            "phone_notifications",
            title: "List notifications",
            description:
                "List current Android notifications (package, title, text, post time) through the companion, with a dumpsys fallback.",
            props: ["serial": serialProperty]),

        tool(
            "phone_open_url",
            title: "Open URL",
            description:
                "Open an http(s) URL on the device with the default browser or matching app.",
            props: [
                "url": ["type": "string", "minLength": 8, "maxLength": 2048,
                        "description": "Absolute http or https URL."],
                "serial": serialProperty,
            ],
            required: ["url"]),

        tool(
            "phone_ui_dump",
            title: "Dump UI hierarchy",
            description:
                "Return the current UI hierarchy XML from uiautomator, including bounds, text and resource ids.",
            props: ["serial": serialProperty]),
    ]

    static func tool(named name: String) -> MCPToolDefinition? {
        tools.first { $0.name == name }
    }

    static var toolNames: [String] { tools.map(\.name) }

    // MARK: - Schema helpers

    private static let serialProperty: [String: Any] = [
        "type": "string",
        "minLength": 1,
        "maxLength": 256,
        "description":
            "ADB device serial from phone_list_devices. Omit when exactly one device is connected.",
    ]

    private static func integerProperty(
        _ description: String, minimum: Int, maximum: Int
    ) -> [String: Any] {
        [
            "type": "integer",
            "minimum": minimum,
            "maximum": maximum,
            "description": description,
        ]
    }

    private static func tool(
        _ name: String,
        title: String,
        description: String,
        props: [String: [String: Any]],
        required: [String] = []
    ) -> MCPToolDefinition {
        MCPToolDefinition(
            name: name,
            title: title,
            description: description,
            properties: props,
            required: required)
    }
}
