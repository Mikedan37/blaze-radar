import Foundation
import RadarCore

let socketPath = ProcessInfo.processInfo.environment["BLAZE_RADAR_SOCKET"] ?? "/tmp/blaze_radar.sock"
let server = RadarServer(socketPath: socketPath)
signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }
do {
    try server.start()
} catch {
    fputs("Failed to start blaze-radar-daemon: \(error)\n", stderr)
    exit(1)
}
