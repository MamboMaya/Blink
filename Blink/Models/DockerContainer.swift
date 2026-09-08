import Foundation

struct DockerContainer: Identifiable, Equatable {
    let id: String
    let name: String
    let image: String
    let hostPorts: [Int]
    var cpuPercent: Double?
    var memoryBytes: Int64?

    // Ports a browser click is likely to actually want: opening a Postgres
    // or Redis port in Safari isn't useful. Falls back to nil (no click)
    // rather than guessing with the first published port.
    private static let webPortRanges: [ClosedRange<Int>] = [
        80...80, 443...443, 3000...3999, 4200...4200, 4321...4321,
        5173...5174, 8000...8999, 9000...9999
    ]

    var primaryPort: Int? {
        hostPorts.first { port in Self.webPortRanges.contains { $0.contains(port) } }
    }
}

struct ColimaVM: Equatable {
    var isRunning: Bool
    var cpus: Int?
    var memoryGB: Int?
    var arch: String?
}
