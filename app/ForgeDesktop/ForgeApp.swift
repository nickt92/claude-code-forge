import SwiftUI
import ForgeDesktopCore

@main
struct ForgeApp: App {
    @State private var forgeState = ForgeState()
    @State private var showDoctor = false
    @State private var showNewProject = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage("setupComplete") private var setupComplete = false

    private let forgeService: ForgeService
    private let doctorService: DoctorService
    private let fixService: FixService
    private let configService: ConfigService
    private let claudeService: ClaudeService
    private let personaService: PersonaService
    private let onboardingService: OnboardingService
    private let dismissalService: DismissalService

    init() {
        let forgePath = UserDefaults.standard.string(forKey: "forgeBinaryPath")
        let resolvedPath = forgePath?.isEmpty == true ? nil : forgePath

        let claudePath = UserDefaults.standard.string(forKey: "claudeBinaryPath")
        let resolvedClaudePath = claudePath?.isEmpty == true ? nil : claudePath

        self.forgeService = ForgeService(forgePath: resolvedPath)
        self.doctorService = DoctorService(forgePath: resolvedPath)
        self.claudeService = ClaudeService(claudePath: resolvedClaudePath)

        let initService = InitService(forgePath: resolvedPath)
        self.fixService = FixService(initService: initService, claudeService: claudeService)
        self.configService = ConfigService(forgePath: resolvedPath)
        self.personaService = PersonaService(forgePath: resolvedPath)
        self.onboardingService = OnboardingService(
            claudeService: claudeService,
            forgePath: resolvedPath
        )
        self.dismissalService = DismissalService()
    }

    var body: some Scene {
        MenuBarExtra("Forge", systemImage: menuBarIcon) {
            MenuBarView(
                state: forgeState,
                onRefresh: { refresh() },
                onOpenDashboard: {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                },
                onOpenSettings: {
                    openSettings()
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
                .environment(\.personaService, personaService)
                .environment(\.forgeService, forgeService)
                .environment(\.forgeState, forgeState)
                .environment(\.dismissalService, dismissalService)
                .environment(\.onboardingService, onboardingService)
                .sheet(isPresented: $showNewProject) {
                    if let dashboard = forgeState.dashboard {
                        OnboardingView(
                            mode: .greenfield(projectPath: "", projectName: "", description: ""),
                            persona: dashboard.global.persona,
                            onComplete: { refresh() }
                        )
                    }
                }
        }
        .defaultSize(width: 900, height: 650)

        Settings {
            SettingsView(onRescan: { await refreshAsync() })
                .environment(\.configService, configService)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Project...") {
                    openWindow(id: "dashboard")
                    showNewProject = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    private var menuBarIcon: String {
        if #available(macOS 15.0, *) {
            return "anvil"
        }
        return "hammer.fill"
    }

    private func onDashboardAppear() {
        NSApp.activate(ignoringOtherApps: true)
        forgeState.claudeAvailable = claudeService.isAvailable
        if !setupComplete {
            forgeState.setupPhase = .detectCLI
        } else if case .idle = forgeState.loadState {
            refresh()
        }
    }

    private func refresh() {
        Task { await refreshAsync() }
    }

    private func refreshAsync() async {
        guard !forgeState.isLoading else { return }
        forgeState.loadState = .loading

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
