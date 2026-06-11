import SwiftUI
import ForgeDesktopCore

@main
struct ForgeApp: App {
    @State private var forgeState = ForgeState()
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
    private let permissionsService: PermissionsService
    private let statusService: StatusService
    private let updateService: UpdateService
    private let personaBuilderService: PersonaBuilderService

    init() {
        let forgePath = UserDefaults.standard.string(forKey: "forgeBinaryPath")
        let resolvedPath = forgePath?.isEmpty == true ? nil : forgePath

        let claudePath = UserDefaults.standard.string(forKey: "claudeBinaryPath")
        let resolvedClaudePath = claudePath?.isEmpty == true ? nil : claudePath

        self.forgeService = ForgeService(forgePath: resolvedPath, cache: DashboardCache())
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
        self.permissionsService = PermissionsService(forgePath: resolvedPath)
        self.statusService = StatusService(forgePath: resolvedPath)
        self.updateService = UpdateService(forgePath: resolvedPath)
        self.personaBuilderService = PersonaBuilderService(forgePath: resolvedPath)
    }

    var body: some Scene {
        MenuBarExtra("Forge", image: "AnvilIcon") {
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
                    NSApp.activate(ignoringOtherApps: true)
                    forgeState.showDoctor = true
                },
                onSelectRepo: { path in
                    forgeState.selectedRepoPath = path
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
            )
            .onAppear {
                if setupComplete, case .idle = forgeState.loadState {
                    hydrateFromCache()
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
                .environment(\.fixService, fixService)
                .environment(\.doctorService, doctorService)
                .environment(\.configService, configService)
                .environment(\.claudeService, claudeService)
                .environment(\.personaService, personaService)
                .environment(\.forgeService, forgeService)
                .environment(\.forgeState, forgeState)
                .environment(\.dismissalService, dismissalService)
                .environment(\.onboardingService, onboardingService)
                .environment(\.permissionsService, permissionsService)
                .environment(\.statusService, statusService)
                .environment(\.updateService, updateService)
                .environment(\.personaBuilderService, personaBuilderService)
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
                .environment(\.permissionsService, permissionsService)
                .environment(\.statusService, statusService)
                .environment(\.updateService, updateService)
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

    private func onDashboardAppear() {
        NSApp.activate(ignoringOtherApps: true)
        forgeState.claudeAvailable = claudeService.isAvailable
        if !setupComplete {
            forgeState.setupPhase = .detectCLI
        } else if case .idle = forgeState.loadState {
            hydrateFromCache()
            refresh()
        }
    }

    /// Render the last successful dashboard immediately; the subsequent refresh
    /// runs behind it (stale-while-revalidate).
    private func hydrateFromCache() {
        guard case .idle = forgeState.loadState,
              let cached = forgeService.cachedDashboard() else { return }
        forgeState.loadState = .loaded(cached)
    }

    private func refresh() {
        Task { await refreshAsync() }
    }

    private func refreshAsync() async {
        guard !forgeState.isBusy else { return }
        let hasVisibleData = forgeState.dashboard != nil
        if hasVisibleData {
            forgeState.isRefreshing = true
        } else {
            forgeState.loadState = .loading
        }

        do {
            let data = try await forgeService.loadDashboard()
            forgeState.loadState = .loaded(data)
            forgeState.refreshError = nil
            // Best-effort: status drives the update-ready affordances only.
            forgeState.forgeStatus = try? await statusService.status()
        } catch {
            let forgeError = (error as? ForgeError) ?? .unexpected(error.localizedDescription)
            if hasVisibleData {
                // Keep the usable dashboard on screen; surface the failure non-destructively.
                forgeState.refreshError = forgeError.localizedDescription
            } else {
                forgeState.loadState = .failed(forgeError)
            }
        }
        forgeState.isRefreshing = false
    }
}
