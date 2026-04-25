import Foundation

/// Heuristic parser that extracts (repo, file, branch) hints from a window title.
///
/// Macros for common IDEs:
///   - Cursor / VSCode:  `<file> — <repo>` or `<file> - <repo> - Visual Studio Code`
///   - Xcode:            `<repo> — <file>` or `<repo>` alone
///   - Zed:              `<repo> — <file>`
///   - Terminal/iTerm:   `<user>@<host>: <cwd>` (cwd's last path component is treated as repo)
///   - JetBrains IDEs:   `<repo> – <file>` (en dash)
///
/// Tools fall back to nil when no signal is found — better an empty result than a wrong one.
public struct WindowTitleParser: Sendable {
    public struct Parsed: Hashable, Sendable {
        public var repo: String?
        public var file: String?
        public var branch: String?
    }

    /// Bundle IDs we attempt to parse window titles for. Non-IDE apps return `nil` —
    /// "Slack — #engineering" is not a project signal even if it matches the dash pattern.
    public static let knownIDEBundleIDs: Set<String> = [
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.apple.dt.Xcode",
        "dev.zed.Zed",
        "dev.zed.Zed-Preview",
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.jetbrains.intellij",
        "com.jetbrains.AppCode",
        "com.jetbrains.goland",
        "com.jetbrains.rider",
        "com.jetbrains.PhpStorm",
        "com.jetbrains.WebStorm",
        "com.jetbrains.PyCharm",
        "com.jetbrains.RubyMine",
        "com.sublimetext.4",
    ]

    public static func parse(title: String, bundleID: String?) -> Parsed? {
        guard let bundleID, knownIDEBundleIDs.contains(bundleID) else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Terminal / iTerm: "user@host: ~/path/to/repo"
        if bundleID == "com.apple.Terminal" || bundleID == "com.googlecode.iterm2" {
            return parseTerminal(trimmed)
        }

        // Strip trailing " - Visual Studio Code" / " - Cursor" if present.
        let stripped = stripTrailingAppName(trimmed)

        // Split on em dash, en dash, or " - " (hyphen with surrounding spaces).
        let parts = splitOnDashes(stripped)
        guard !parts.isEmpty else { return nil }

        // Heuristic: in Cursor/VSCode the file is left, repo is right.
        // In Xcode the project is left, file is right.
        // We pick by which segment looks more file-shaped (has a `.` extension).
        if parts.count >= 2 {
            let left = parts.first!.trimmingCharacters(in: .whitespaces)
            let right = parts.last!.trimmingCharacters(in: .whitespaces)
            let leftLooksLikeFile = looksLikeFile(left)
            let rightLooksLikeFile = looksLikeFile(right)
            if leftLooksLikeFile && !rightLooksLikeFile {
                return Parsed(repo: right, file: left, branch: nil)
            } else if rightLooksLikeFile && !leftLooksLikeFile {
                return Parsed(repo: left, file: right, branch: nil)
            } else {
                // Neither or both look file-like — assume left is file, right is repo
                // (Cursor/VSCode/Zed convention).
                return Parsed(repo: right, file: leftLooksLikeFile ? left : nil, branch: nil)
            }
        }

        // Single segment — treat as repo if it doesn't look like a file.
        let only = parts[0].trimmingCharacters(in: .whitespaces)
        if looksLikeFile(only) {
            return Parsed(repo: nil, file: only, branch: nil)
        }
        return Parsed(repo: only, file: nil, branch: nil)
    }

    private static func parseTerminal(_ title: String) -> Parsed? {
        // "user@host: ~/Documents/Projects/repo-name" or "~/path/to/repo"
        let afterColon: String
        if let range = title.range(of: ":") {
            afterColon = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            afterColon = title
        }
        let lastComponent = (afterColon as NSString).lastPathComponent
        let repo = lastComponent.isEmpty ? nil : lastComponent
        return Parsed(repo: repo, file: nil, branch: nil)
    }

    private static let appSuffixes: [String] = [
        " - Visual Studio Code",
        " - Visual Studio Code - Insiders",
        " - Cursor",
        " - Sublime Text",
        " - IntelliJ IDEA",
        " - GoLand",
        " - WebStorm",
        " - PyCharm",
        " - PhpStorm",
        " - RubyMine",
        " - Rider",
    ]

    private static func stripTrailingAppName(_ s: String) -> String {
        for suffix in appSuffixes where s.hasSuffix(suffix) {
            return String(s.dropLast(suffix.count))
        }
        return s
    }

    private static func splitOnDashes(_ s: String) -> [String] {
        // Em dash, en dash, or " - " (hyphen with surrounding spaces).
        let separators: [String] = [" — ", " – ", " - "]
        for sep in separators where s.contains(sep) {
            return s.components(separatedBy: sep)
        }
        return [s]
    }

    private static func looksLikeFile(_ s: String) -> Bool {
        // Has a period and a plausible extension (≤6 alphanum chars after the last dot).
        guard let dotIdx = s.lastIndex(of: ".") else { return false }
        let ext = s[s.index(after: dotIdx)...]
        guard !ext.isEmpty, ext.count <= 6 else { return false }
        return ext.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
