import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Canonical workspace root for radar storage and lookups.
///
/// `/tmp/foo` and `/private/tmp/foo` must fingerprint identically — BlazeDB lives at
/// the real directory, but row filters use the workspacePath string.
public enum WorkspacePath {
    public static func canonical(_ path: String) -> String {
        var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("~") {
            normalized = (normalized as NSString).expandingTildeInPath
        }
        if !normalized.hasPrefix("/") {
            normalized = (FileManager.default.currentDirectoryPath as NSString)
                .appendingPathComponent(normalized)
        }
        normalized = URL(fileURLWithPath: normalized)
            .standardizedFileURL
            .path

        #if canImport(Darwin)
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(normalized, &buf) != nil {
            return String(cString: buf)
        }
        #endif

        return URL(fileURLWithPath: normalized)
            .resolvingSymlinksInPath()
            .path
    }
}
