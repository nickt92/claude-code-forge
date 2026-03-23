import SwiftUI
import ForgeDesktopCore

@main
struct ForgeApp: App {
    @State private var forgeState = ForgeState()
    @State private var showDoctor = false
    @Environment(\.openWindow) private var openWindow
    @AppStorage("setupComplete") private var setupComplete = false

    private let forgeService: ForgeService
    private let doctorService: DoctorService
    private let fixService: FixService
    private let configService: ConfigService
    private let claudeService: ClaudeService

    init() {
        let forgePath = UserDefaults.standard.string(forKey: "forgeBinaryPath")
        let resolvedPath = forgePath?.isEmpty == true ? nil : forgePath

        self.forgeService = ForgeService(forgePath: resolvedPath)
        self.doctorService = DoctorService(forgePath: resolvedPath)
        self.claudeService = ClaudeService()

        let initService = InitService(forgePath: resolvedPath)
        self.fixService = FixService(initService: initService, claudeService: claudeService)
        self.configService = ConfigService(forgePath: resolvedPath)
    }

    var body: some Scene {
        MenuBarExtra("Forge", systemImage: "hammer.fill") {
            MenuBarView(
                state: forgeState,
                onRefresh: { refresh() },
                onOpenDashboard: { openWindow(id: "dashboard") },
                onOpenSettings: {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                },
                onRunDoctor: {
                    openWindow(id: "dashboard")
                    showDoctor = true
                }
            )
            .onAppear {
                if setupComplete, case .idle = forgeState.loadState {
                    refresh()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Forge Dashboard", id: "dashboard") {
            DashboardView(state: forgeState, onRefresh: { refresh() })
                .frame(minWidth: 700, minHeight: 500)
                .onAppear { onDashboardAppear() }
                .sheet(isPresented: Binding(
                    get: { !setupComplete && forgeState.setupPhase != .complete },
                    set: { if !$0 { setupComplete = true; forgeState.setupPhase = .complete } }
                )) {
                    SetupWizardView(
                        state: forgeState,
                        forgeService: forgeService,
                        onComplete: { setupComplete = true }
                    )
                    .interactiveDismissDisabled()
                }
                .sheet(isPresented: $showDoctor) {
                    DoctorView(state: forgeState)
                }
                .environment(\.fixService, fixService)
                .environment(\.doctorService, doctorService)
                .environment(\.configService, configService)
                .environment(\.claudeService, claudeService)
        }
        .defaultSize(width: 900, height: 650)

        Settings {
            SettingsView()
        }
    }

    private func onDashboardAppear() {
        forgeState.claudeAvailable = claudeService.isAvailable
        if !setupComplete {
            forgeState.setupPhase = .detectCLI
        } else if case .idle = forgeState.loadState {
            refresh()
        }
    }

    private func refresh() {
        guard !forgeState.isLoading else { return }
        forgeState.loadState = .loading

        Task { @MainActor in
            do {
                let data = try await forgeService.loadDashboard()
                forgeState.loadState = .loaded(data)
            } catch let error as ForgeError {
                forgeState.loadState = .failed(error)
            } catch {
                forgeState.loadState = .failed(.unexpected(error.localizedDescription))
            }
        }
    }
}
