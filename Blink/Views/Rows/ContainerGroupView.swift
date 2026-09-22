import SwiftUI

// A collapsible Compose project: a header row with the summed stats and a
// "stop all" action, then the member containers indented beneath it.
struct ContainerGroupView: View {
    @Environment(AppState.self) private var appState
    let group: ContainerGroup

    @State private var isHovered = false

    static let childIndent: CGFloat = 14

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .memory
        return formatter
    }()

    private var isCollapsed: Bool {
        appState.collapsedContainerGroups.contains(group.name)
    }

    private var isBusy: Bool {
        group.containers.contains { appState.containerRestartStates[$0.id] == .restarting }
    }

    private var hasFailure: Bool {
        group.containers.contains {
            if case .failed = appState.containerRestartStates[$0.id] { return true }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !isCollapsed {
                ForEach(group.containers) { container in
                    ContainerRowView(container: container)
                        .padding(.leading, Self.childIndent)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            ColorBar(color: hasFailure ? Color.alert : .docker, isWorking: isBusy)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .animation(.snappy(duration: 0.2), value: isCollapsed)

                    Text(group.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered && !isBusy {
                RowAction(symbol: "xmark", help: "Stop all in \(group.name)", tint: .alert) {
                    appState.stopContainerGroup(group)
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .hoverRow { isHovered = $0 }
        .onTapGesture { appState.toggleContainerGroup(group) }
    }

    private var subtitle: String {
        let count = group.containers.count
        var parts = ["\(count) container\(count == 1 ? "" : "s")"]
        if let cpu = group.cpuPercent {
            parts.append(String(format: "%.1f%%", cpu))
        }
        if let memory = group.memoryBytes {
            parts.append(Self.byteFormatter.string(fromByteCount: memory))
        }
        return parts.joined(separator: " · ")
    }
}
