import AppKit

public enum SystemActions {
    public static func openInTerminal(path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    public static func openInEditor(path: String) {
        let editors = [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            "/Applications/Cursor.app/Contents/MacOS/Cursor",
            "/usr/local/bin/cursor",
        ]

        for editor in editors {
            if FileManager.default.isExecutableFile(atPath: editor) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: editor)
                process.arguments = [path]
                try? process.run()
                return
            }
        }

        // Fallback: open directory with default app
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    public static func openInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
