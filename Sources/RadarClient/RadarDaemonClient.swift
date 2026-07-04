import Foundation
import RadarCore

public enum RadarClientError: Error, LocalizedError {
    case daemonUnavailable
    case connectionFailed(Error)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .daemonUnavailable: return "blaze-radar-daemon is not running"
        case .connectionFailed(let e): return "Connection failed: \(e.localizedDescription)"
        case .invalidResponse(let msg): return msg
        }
    }
}

public final class RadarDaemonClient: @unchecked Sendable {
    public static let defaultSocketPath = "/tmp/blaze_radar.sock"

    private let socketPath: String
    private let lock = NSLock()
    private var socketFD: Int32 = -1

    public init(socketPath: String = RadarDaemonClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    public func disconnect() {
        lock.lock()
        if socketFD >= 0 { close(socketFD) }
        socketFD = -1
        lock.unlock()
    }

    public func registerAgent(
        workspacePath: String,
        agentName: String,
        task: String,
        branch: String? = nil,
        worktree: String? = nil
    ) async throws -> RegisterAgentResponse {
        struct Params: Encodable {
            let workspacePath: String
            let agentName: String
            let task: String
            let branch: String?
            let worktree: String?
        }
        return try perform("register", Params(
            workspacePath: workspacePath, agentName: agentName, task: task, branch: branch, worktree: worktree
        ))
    }

    public func getActiveWork(workspacePath: String, excludeRegistrationId: String? = nil) async throws -> ActiveWorkSnapshot {
        struct Params: Encodable {
            let workspacePath: String
            let excludeRegistrationId: String?
        }
        return try perform("active", Params(workspacePath: workspacePath, excludeRegistrationId: excludeRegistrationId))
    }

    public func syncRadar(workspacePath: String, registrationId: String? = nil) async throws -> ActiveWorkSnapshot {
        struct Params: Encodable {
            let workspacePath: String
            let registrationId: String?
        }
        return try perform("sync", Params(workspacePath: workspacePath, registrationId: registrationId))
    }

    public func updateAgent(_ request: UpdateAgentRequest) async throws {
        struct Empty: Decodable {}
        let _: Empty = try perform("update", request)
    }

    public func markDone(workspacePath: String, registrationId: String) async throws {
        struct Params: Encodable {
            let workspacePath: String
            let registrationId: String
        }
        struct Empty: Decodable {}
        let _: Empty = try perform("done", Params(workspacePath: workspacePath, registrationId: registrationId))
    }

    private func perform<T: Decodable, P: Encodable>(_ method: String, _ params: P) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let paramsData = try encoder.encode(params)
        let paramsObject = try JSONSerialization.jsonObject(with: paramsData)
        let requestObject: [String: Any] = ["method": method, "params": paramsObject]
        let requestData = try JSONSerialization.data(withJSONObject: requestObject)
        let responseData = try send(requestData)
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let success = json["success"] as? Bool else {
            throw RadarClientError.invalidResponse("Malformed daemon response")
        }
        guard success else {
            throw RadarClientError.invalidResponse((json["error"] as? String) ?? "Request failed")
        }
        guard let resultObj = json["result"], !(resultObj is NSNull) else {
            throw RadarClientError.invalidResponse("Missing result")
        }
        let resultData = try JSONSerialization.data(withJSONObject: resultObj)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: resultData)
    }

    private func send(_ requestData: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        if socketFD < 0 { socketFD = try connect() }

        var payload = requestData
        payload.append(0x0A)
        let written = payload.withUnsafeBytes { write(socketFD, $0.baseAddress, $0.count) }
        guard written == payload.count else {
            disconnect()
            throw RadarClientError.invalidResponse("Short write to daemon")
        }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(socketFD, &chunk, chunk.count)
            guard n > 0 else {
                disconnect()
                throw RadarClientError.invalidResponse("Daemon closed connection")
            }
            buffer.append(contentsOf: chunk.prefix(n))
            if chunk.prefix(n).contains(0x0A) { break }
        }
        if let newline = buffer.firstIndex(of: 0x0A) {
            buffer = Data(buffer[..<newline])
        }
        return buffer
    }

    private func connect() throws -> Int32 {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw RadarClientError.daemonUnavailable
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw RadarClientError.connectionFailed(NSError(domain: "RadarClient", code: Int(errno)))
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for (i, b) in pathBytes.enumerated() { raw[i] = b }
        }
        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            throw RadarClientError.connectionFailed(NSError(domain: "RadarClient", code: Int(errno)))
        }
        return fd
    }
}
