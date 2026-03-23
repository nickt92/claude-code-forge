import SwiftUI
import ForgeDesktopCore

@main
struct ForgeApp: App {
    @State private var forgeState = ForgeState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Forge", systemImage: "hammer.fill") {
            MenuBarView(
                state: forgeState,
                onRefresh: { refresh() },
                onOpenDashboard: { openWindow(id: "dashboard") },
                onOpenSettings: { openWindow(id: "settings") }
            )
        }
        .menuBarExtraStyle(.window)

        Window("Forge Dashboard", id: "dashboard") {
            DashboardView(state: forgeState, onRefresh: { refresh() })
                .frame(minWidth: 700, minHeight: 500)
                .onAppear { refreshIfNeeded() }
        }
        .defaultSize(width: 900, height: 650)

        Settings {
            SettingsView()
        }
    }

    private func refreshIfNeeded() {
        if case .idle = forgeState.loadState {
            refresh()
        }
    }

    private func refresh() {
        guard !forgeState.isLoading else { return }
        forgeState.loadState = .loading

        let forgePath = UserDefaults.standard.string(forKey: "forgeBinaryPath")
        let service = ForgeService(forgePath: forgePath?.isEmpty == true ? nil : forgePath)

        Task { @MainActor in
            do {
                let data = try await service.loadDashboard()
                forgeState.loadState = .loaded(data)
            } catch let error as ForgeError {
                forgeState.loadState = .failed(error)
            } catch {
                forgeState.loadState = .failed(.unexpected(error.localizedDescription))
            }
        }
    }
}
