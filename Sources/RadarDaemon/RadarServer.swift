import Foundation
import RadarCore
import RadarClient

actor RadarHandler {
    let service = AwarenessService()

    func handle(_ data: Data) async -> Data {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = json["method"] as? String,
                  let paramsObj = json["params"] else {
                return try wireError("Invalid request envelope")
            }
            let paramsData = try JSONSerialization.data(withJSONObject: paramsObj)

            switch method {
            case "register":
                struct Params: Decodable {
                    let workspacePath: String; let agentName: String; let task: String
                    let branch: String?; let worktree: String?
                }
                let p = try decoder.decode(Params.self, from: paramsData)
                let reg = try await service.register(
                    workspacePath: p.workspacePath, agentName: p.agentName, task: p.task,
                    branch: p.branch, worktree: p.worktree
                )
                let result = RegisterAgentResponse(
                    registrationId: reg.id.uuidString, branch: reg.branch, worktree: reg.worktree
                )
                return try wireResponse(success: true, result: result, error: nil)

            case "active":
                struct Params: Decodable { let workspacePath: String; let excludeRegistrationId: String? }
                let p = try decoder.decode(Params.self, from: paramsData)
                let exclude = p.excludeRegistrationId.flatMap(UUID.init(uuidString:))
                let snapshot = await service.getActiveWork(workspacePath: p.workspacePath, excludeId: exclude)
                return try wireResponse(success: true, result: snapshot, error: nil)

            case "sync":
                struct Params: Decodable { let workspacePath: String; let registrationId: String? }
                let p = try decoder.decode(Params.self, from: paramsData)
                let regId = p.registrationId.flatMap(UUID.init(uuidString:))
                let snapshot = await service.sync(workspacePath: p.workspacePath, registrationId: regId)
                return try wireResponse(success: true, result: snapshot, error: nil)

            case "update":
                let patch = try decoder.decode(UpdateAgentRequest.self, from: paramsData)
                guard let id = UUID(uuidString: patch.registrationId) else {
                    return try wireError("Invalid registration ID")
                }
                _ = try await service.update(workspacePath: patch.workspacePath, registrationId: id, patch: patch)
                struct Empty: Encodable {}
                return try wireResponse(success: true, result: Empty(), error: nil)

            case "done":
                struct Params: Decodable { let workspacePath: String; let registrationId: String }
                let p = try decoder.decode(Params.self, from: paramsData)
                guard let id = UUID(uuidString: p.registrationId) else {
                    return try wireError("Invalid registration ID")
                }
                _ = try await service.markDone(workspacePath: p.workspacePath, registrationId: id)
                struct Empty: Encodable {}
                return try wireResponse(success: true, result: Empty(), error: nil)

            default:
                return try wireError("Unknown method: \(method)")
            }
        } catch {
            return (try? wireError(error.localizedDescription)) ?? Data()
        }
    }

    private func wireError(_ message: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["success": false, "error": message, "result": NSNull()])
    }

    private func wireResponse<T: Encodable>(success: Bool, result: T?, error: String?) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object: [String: Any] = ["success": success]
        if let error { object["error"] = error }
        if let result {
            let resultData = try encoder.encode(result)
            object["result"] = try JSONSerialization.jsonObject(with: resultData)
        } else {
            object["result"] = NSNull()
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

final class RadarServer: @unchecked Sendable {
    private let socketPath: String
    private let handler = RadarHandler()
    private let poller: AwarenessGitPoller
    private var listenFD: Int32 = -1
    private var running = false

    init(socketPath: String = "/tmp/blaze_radar.sock") {
        self.socketPath = socketPath
        poller = AwarenessGitPoller(service: handler.service)
    }

    func start() throws {
        if FileManager.default.fileExists(atPath: socketPath) {
            try FileManager.default.removeItem(atPath: socketPath)
        }
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POSIXError(.init(rawValue: errno)!) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for (i, b) in pathBytes.enumerated() { raw[i] = b }
        }
        guard withUnsafePointer(to: &addr, { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }) == 0 else { throw POSIXError(.init(rawValue: errno)!) }
        guard listen(listenFD, 32) == 0 else { throw POSIXError(.init(rawValue: errno)!) }

        running = true
        poller.start()
        fputs("blaze-radar-daemon listening on \(socketPath)\n", stderr)

        while running {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else { continue }
            Task { await self.handleClient(clientFD) }
        }
    }

    func stop() {
        running = false
        poller.stop()
        if listenFD >= 0 { close(listenFD) }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func handleClient(_ fd: Int32) async {
        defer { close(fd) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return }
            buffer.append(contentsOf: chunk.prefix(n))
            if chunk.prefix(n).contains(0x0A) { break }
        }
        if let newline = buffer.firstIndex(of: 0x0A) { buffer = Data(buffer[..<newline]) }
        let response = await handler.handle(buffer)
        var payload = response
        payload.append(0x0A)
        _ = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }
}
