import SwiftUI

struct MenuBarView: View {
    static let panelSize = CGSize(width: 320, height: 440)

    @Environment(AppState.self) private var appState

    @State private var page: Page = .main
    @State private var isColimaVMHovered = false

    enum Page {
        case main, settings, about
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainPage
                .panelPage(isActive: page == .main, restingOffset: -24)

            SettingsPage(isVisible: page == .settings) { page = .main }
                .frame(maxHeight: .infinity, alignment: .top)
                .panelPage(isActive: page == .settings, restingOffset: 24)

            AboutPage { page = .main }
                .frame(maxHeight: .infinity, alignment: .top)
                .panelPage(isActive: page == .about, restingOffset: 24)
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        // Material alone takes the wallpaper's colour; the ground pins the
        // panel to something the wallpaper only tints.
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.panelGround.opacity(0.80))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Main page

private extension MenuBarView {

    var mainPage: some View {
        VStack(spacing: 0) {
            header
            PanelDivider()
            content
            PanelDivider()
            footer
        }
    }

    var header: some View {
        HStack {
            Text("Blink")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if appState.totalCount > 0 {
                AnimatedRobotHead(size: 22, event: appState.lastEvent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    var content: some View {
        if appState.isInitialLoad {
            VStack(spacing: 12) {
                AnimatedRobotHead(size: 48, event: .scanning)
                Text("Scanning...")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        } else if appState.servers.isEmpty && appState.simulators.isEmpty && appState.colima == nil {
            EmptyStateView()
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if !appState.servers.isEmpty {
                        serverSection
                    }
                    if !appState.simulators.isEmpty {
                        simulatorSection
                    }
                    if appState.colima != nil {
                        containersSection
                    }
                }
                .padding(12)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.965),
                        .init(color: .black.opacity(0.55), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                "DEV SERVERS",
                icon: "server.rack",
                action: appState.servers.count > 1 ? "Stop All" : nil
            ) {
                appState.stopAllServers()
            }

            ForEach(appState.servers) { server in
                ServerRowView(server: server)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
    }

    var simulatorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                "SIMULATORS",
                icon: "iphone",
                action: appState.simulators.count > 1 ? "Shut Down All" : nil
            ) {
                appState.shutDownAllSimulators()
            }

            ForEach(appState.simulators) { simulator in
                SimulatorRowView(simulator: simulator)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
    }

    var containersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("CONTAINERS", icon: "shippingbox", action: nil) {}

            colimaVMRow

            if appState.colima != nil {
                let layout = appState.containerLayout

                ForEach(layout.groups) { group in
                    ContainerGroupView(group: group)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }

                ForEach(layout.ungrouped) { container in
                    ContainerRowView(container: container)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
        }
    }

    var colimaVMRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            colimaVMHeader

            if let colimaVMFailure = appState.colimaVMFailure {
                FailureBox(message: colimaVMFailure)
                    .padding(.leading, HoverRowStyle.horizontalPadding + ColorBar.gutter)
                    .padding(.trailing, HoverRowStyle.horizontalPadding)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.colimaVMFailure)
    }

    var colimaVMHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Colima")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(colimaStatusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, ColorBar.gutter)

            Spacer()

            if appState.colimaVMBusy {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            } else if isColimaVMHovered {
                RowAction(
                    symbol: appState.colimaVMFailure != nil
                        ? "xmark"
                        : (appState.colima?.vm.isRunning == true ? "stop.fill" : "play.fill"),
                    help: appState.colimaVMFailure != nil
                        ? "Dismiss"
                        : (appState.colima?.vm.isRunning == true ? "Stop Colima" : "Start Colima"),
                    tint: appState.colimaVMFailure != nil || appState.colima?.vm.isRunning == true ? .alert : nil
                ) {
                    if appState.colimaVMFailure != nil {
                        appState.dismissColimaVMFailure()
                    } else if appState.colima?.vm.isRunning == true {
                        appState.stopColimaVM()
                    } else {
                        appState.startColimaVM()
                    }
                }
                .transition(.opacity)
            }
        }
        .opacity(appState.colimaVMBusy ? 0.6 : 1)
        .animation(.easeOut(duration: 0.2), value: appState.colimaVMBusy)
        .hoverRow { isColimaVMHovered = $0 }
    }

    var colimaStatusText: String {
        guard let vm = appState.colima?.vm, vm.isRunning else { return "Stopped" }

        var parts: [String] = []
        if let cpus = vm.cpus { parts.append("\(cpus) CPU") }

        if let totalGB = vm.memoryGB {
            let usedBytes = appState.colima?.containers.reduce(Int64(0)) { $0 + ($1.memoryBytes ?? 0) } ?? 0
            let usedGB = Double(usedBytes) / 1_073_741_824
            parts.append(String(format: "%.1f / %d GB", usedGB, totalGB))
        }

        return parts.joined(separator: " · ")
    }

    func sectionHeader(
        _ title: String,
        icon: String,
        action: String?,
        perform: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .frame(width: 12)
                .foregroundStyle(.secondary.opacity(0.6))

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(.secondary.opacity(0.6))

            Spacer()

            if let action {
                Button(action: perform) {
                    Text(action)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.alert)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
    }

    var footer: some View {
        VStack(spacing: 0) {
            PanelRow("Settings") { page = .settings }
            PanelDivider()
            PanelRow("About") { page = .about }
            PanelDivider()
            PanelRow("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
