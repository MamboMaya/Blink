import Foundation

enum ColimaMonitor {
    static let colimaBinary: String? = firstExisting([
        "/opt/homebrew/bin/colima",
        "/usr/local/bin/colima"
    ])

    static let dockerBinary: String? = firstExisting([
        "/opt/homebrew/bin/docker",
        "/usr/local/bin/docker"
    ])

    struct ColimaState: Equatable {
        var vm: ColimaVM
        var containers: [DockerContainer]
    }

    static func scan() async -> ColimaState? {
        guard let colimaBinary else { return nil }

        guard let output = await Shell.run(colimaBinary, arguments: ["list", "--json"]) else {
            return ColimaState(vm: ColimaVM(isRunning: false, cpus: nil, memoryGB: nil, arch: nil), containers: [])
        }

        let profile = selectProfile(output)
        if let profile { activeProfileName = profile.name }

        let vm = parseVM(profile)
        guard vm.isRunning else {
            return ColimaState(vm: vm, containers: [])
        }

        let containers = await scanContainers()
        return ColimaState(vm: vm, containers: containers)
    }

    static func stopContainer(id: String) async -> String? {
        await runDockerAction(["stop", id])
    }

    static func restartContainer(id: String) async -> String? {
        await runDockerAction(["restart", id])
    }

    static func startVM() async -> String? {
        await runColimaAction(["start"])
    }

    static func stopVM() async -> String? {
        await runColimaAction(["stop"])
    }
}

// MARK: - Binary discovery

private extension ColimaMonitor {
    static func firstExisting(_ paths: [String]) -> String? {
        paths.first { FileManager.default.fileExists(atPath: $0) }
    }
}

// MARK: - VM status

private extension ColimaMonitor {
    struct ColimaProfile: Decodable {
        let name: String
        let status: String
        let runtime: String?
        let arch: String?
        let cpus: Int?
        let memory: Int64?
    }

    // The profile directory (and therefore the docker socket path) is
    // literally the profile's name; "default" was never guaranteed, it's
    // just what most people never rename.
    static var activeProfileName = "default"

    static func selectProfile(_ output: String) -> ColimaProfile? {
        let profiles: [ColimaProfile] = output.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ColimaProfile.self, from: data)
        }

        let dockerProfiles = profiles.filter { $0.runtime == "docker" }
        return dockerProfiles.first { $0.status == "Running" } ?? dockerProfiles.first
    }

    static func parseVM(_ profile: ColimaProfile?) -> ColimaVM {
        guard let profile else { return ColimaVM(isRunning: false, cpus: nil, memoryGB: nil, arch: nil) }

        return ColimaVM(
            isRunning: profile.status == "Running",
            cpus: profile.cpus,
            memoryGB: profile.memory.map { Int((Double($0) / 1_073_741_824).rounded()) },
            arch: profile.arch
        )
    }
}

// MARK: - Containers

private extension ColimaMonitor {
    struct DockerPsEntry: Decodable {
        let id: String
        let names: String
        let image: String
        let ports: String

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case names = "Names"
            case image = "Image"
            case ports = "Ports"
        }
    }

    static func scanContainers() async -> [DockerContainer] {
        guard let dockerBinary else { return [] }

        async let psOutput = Shell.run(
            dockerBinary,
            arguments: dockerArguments(["ps", "--no-trunc", "--format", "{{json .}}"])
        )
        async let statsOutput = Shell.run(
            dockerBinary,
            arguments: dockerArguments(["stats", "--no-stream", "--format", "{{json .}}"])
        )

        guard let output = await psOutput else { return [] }
        let stats = parseStats(await statsOutput ?? "")

        return output.split(separator: "\n").compactMap { line -> DockerContainer? in
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(DockerPsEntry.self, from: data) else {
                return nil
            }

            let stat = stats.first { entry.id.hasPrefix($0.id) }

            return DockerContainer(
                id: entry.id,
                name: entry.names,
                image: entry.image,
                hostPorts: parsePorts(entry.ports),
                cpuPercent: stat?.cpuPercent,
                memoryBytes: stat?.memoryBytes
            )
        }.sorted { $0.name < $1.name }
    }

    struct DockerStatsEntry: Decodable {
        let id: String
        let cpuPerc: String
        let memUsage: String

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case cpuPerc = "CPUPerc"
            case memUsage = "MemUsage"
        }

        var cpuPercent: Double? {
            Double(cpuPerc.trimmingCharacters(in: CharacterSet(charactersIn: "%")))
        }

        var memoryBytes: Int64? {
            guard let leftPart = memUsage.split(separator: "/").first else { return nil }
            return ColimaMonitor.parseByteString(leftPart.trimmingCharacters(in: .whitespaces))
        }
    }

    static func parseStats(_ output: String) -> [DockerStatsEntry] {
        output.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(DockerStatsEntry.self, from: data)
        }
    }

    static func parseByteString(_ raw: String) -> Int64? {
        let units: [(String, Double)] = [
            ("GiB", 1_073_741_824), ("GB", 1_000_000_000),
            ("MiB", 1_048_576), ("MB", 1_000_000),
            ("KiB", 1024), ("KB", 1000),
            ("B", 1)
        ]
        for (suffix, multiplier) in units where raw.hasSuffix(suffix) {
            guard let value = Double(raw.dropLast(suffix.count)) else { return nil }
            return Int64((value * multiplier).rounded())
        }
        return nil
    }

    static func parsePorts(_ raw: String) -> [Int] {
        guard !raw.isEmpty else { return [] }

        // A port range's max expansion, so a pathological "1-65535" mapping
        // can't blow up the row list.
        let maxRangeSize = 32

        var ports = Set<Int>()
        for mapping in raw.split(separator: ",") {
            let trimmed = mapping.trimmingCharacters(in: .whitespaces)
            guard let arrowRange = trimmed.range(of: "->") else { continue }

            let hostPart = trimmed[trimmed.startIndex..<arrowRange.lowerBound]
            guard let portString = hostPart.split(separator: ":").last else { continue }

            if let port = Int(portString) {
                ports.insert(port)
            } else if let dashRange = portString.range(of: "-") {
                let lower = portString[portString.startIndex..<dashRange.lowerBound]
                let upper = portString[dashRange.upperBound...]
                if let lowerPort = Int(lower), let upperPort = Int(upper), lowerPort <= upperPort {
                    let cappedUpper = min(upperPort, lowerPort + maxRangeSize - 1)
                    ports.formUnion(lowerPort...cappedUpper)
                }
            }
        }
        return ports.sorted()
    }
}

// MARK: - Actions

private extension ColimaMonitor {
    static func dockerSocketPath() -> String {
        "\(NSHomeDirectory())/.colima/\(activeProfileName)/docker.sock"
    }

    static func dockerArguments(_ arguments: [String]) -> [String] {
        ["--host", "unix://\(dockerSocketPath())"] + arguments
    }

    static func runDockerAction(_ arguments: [String]) async -> String? {
        guard let dockerBinary else { return "Docker not found." }

        let (status, output) = await Shell.runChecked(
            dockerBinary,
            arguments: dockerArguments(arguments),
            mergingErrors: true
        )

        guard status != 0 else { return nil }
        let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Docker command failed." : trimmed
    }

    static func runColimaAction(_ arguments: [String]) async -> String? {
        guard let colimaBinary else { return "Colima not found." }

        let (status, output) = await Shell.runChecked(
            colimaBinary,
            arguments: arguments,
            mergingErrors: true
        )

        guard status != 0 else { return nil }
        let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Colima command failed." : trimmed
    }
}
