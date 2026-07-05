import Foundation

enum Workspace {
    enum Error: Swift.Error, LocalizedError {
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let path): return "Workspace not found: \(path)"
            }
        }
    }

    static func resolve(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw Error.notFound(url.path)
        }
        return url
    }
}
