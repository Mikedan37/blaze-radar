import Foundation
import RadarCore

let socketPath = ProcessInfo.processInfo.environment["BLAZE_RADAR_SOCKET"] ?? "/tmp/blaze_radar.sock"
let server = RadarServer(socketPath: socketPath)
signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }
fputs("blaze-radar-demo-daemon (optional demo — canonical host is AgentDaemon)\n", stderr)
do {
    try server.start()
} catch {
    fputs("Failed to start blaze-radar-demo-daemon: \(error)\n", stderr)
    exit(1)
}
