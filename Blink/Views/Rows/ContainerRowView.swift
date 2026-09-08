import SwiftUI

struct ContainerRowView: View {
    @Environment(AppState.self) private var appState
    let container: DockerContainer

    @State private var isHovered = false

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .memory
        return formatter
    }()

    private var restartState: AppState.RestartState? {
        appState.containerRestartStates[container.id]
    }

    private var isRestarting: Bool { restartState == .restarting }

    private var failureMessage: String? {
        if case .failed(let message) = restartState { return message }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if let failureMessage {
                FailureBox(message: failureMessage)
                    .padding(.leading, HoverRowStyle.horizontalPadding + ColorBar.gutter)
                    .padding(.trailing, HoverRowStyle.horizontalPadding)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: failureMessage)
    }

    private var header: some View {
        HStack(spacing: 0) {
            ColorBar(color: barColor, isWorking: isRestarting)

            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let port = container.primaryPort {
                        Text(verbatim: ":\(port)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    subtitle
                }

                statsText
            }

            Spacer()

            if isHovered && !isRestarting {
                actions
                    .transition(.opacity)
            }
        }
        .opacity(isRestarting ? 0.4 : 1)
        .allowsHitTesting(!isRestarting)
        .animation(.easeOut(duration: 0.2), value: isRestarting)
        .hoverRow { isHovered = $0 }
        .onTapGesture {
            guard failureMessage == nil, container.primaryPort != nil else { return }
            appState.openInBrowser(container)
        }
    }
}

// MARK: - Pieces

private extension ContainerRowView {
    var barColor: Color {
        failureMessage == nil ? .docker : Color.alert
    }

    @ViewBuilder
    var subtitle: some View {
        if isRestarting {
            Text("restarting…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        } else if failureMessage != nil {
            Text("failed to restart")
                .font(.system(size: 10))
                .foregroundStyle(Color.alert)
        } else {
            Text(container.image)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    var statsText: some View {
        if !isRestarting && failureMessage == nil,
           container.cpuPercent != nil || container.memoryBytes != nil {
            Text(statsString)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    var statsString: String {
        var parts: [String] = []
        if let cpuPercent = container.cpuPercent {
            parts.append(String(format: "%.1f%%", cpuPercent))
        }
        if let memoryBytes = container.memoryBytes {
            parts.append(Self.byteFormatter.string(fromByteCount: memoryBytes))
        }
        return parts.joined(separator: " · ")
    }

    var actions: some View {
        HStack(spacing: RowAction.spacing) {
            RowAction(symbol: "arrow.clockwise", help: "Restart container") {
                appState.restartContainer(container)
            }

            RowAction(
                symbol: "xmark",
                help: failureMessage == nil ? "Stop container" : "Dismiss",
                tint: .alert
            ) {
                if failureMessage == nil {
                    appState.stopContainer(container)
                } else {
                    appState.dismissContainerFailure(container)
                }
            }
        }
    }
}
