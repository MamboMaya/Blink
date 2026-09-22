import Foundation

// A Compose project and the containers it owns, the same grouping Docker
// Desktop shows. Containers without a project label are listed flat after
// the groups.
struct ContainerGroup: Identifiable, Equatable {
    let name: String
    let containers: [DockerContainer]

    var id: String { name }

    var cpuPercent: Double? {
        let values = containers.compactMap(\.cpuPercent)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var memoryBytes: Int64? {
        let values = containers.compactMap(\.memoryBytes)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    struct Layout: Equatable {
        var groups: [ContainerGroup]
        var ungrouped: [DockerContainer]
    }

    static func layout(_ containers: [DockerContainer]) -> Layout {
        var byProject: [String: [DockerContainer]] = [:]
        var ungrouped: [DockerContainer] = []

        for container in containers {
            if let project = container.project {
                byProject[project, default: []].append(container)
            } else {
                ungrouped.append(container)
            }
        }

        let groups = byProject
            .map { ContainerGroup(name: $0.key, containers: $0.value) }
            .sorted { $0.name < $1.name }

        return Layout(groups: groups, ungrouped: ungrouped)
    }
}
