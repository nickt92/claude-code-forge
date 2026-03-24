import SwiftUI

public struct PersonaSwitcherView: View {
    let currentPersona: String
    let onSwitched: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.personaService) private var personaService

    @State private var personas: [PersonaProfile] = []
    @State private var isLoading = true
    @State private var isSwitching = false
    @State private var error: String?
    @State private var confirmPersona: PersonaProfile?

    public init(currentPersona: String, onSwitched: @escaping () -> Void) {
        self.currentPersona = currentPersona
        self.onSwitched = onSwitched
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading personas...")
                Spacer()
            } else if let error {
                Spacer()
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(error)
                }
                Spacer()
            } else {
                personaList
            }
        }
        .frame(minWidth: 500, minHeight: 450)
        .task { await loadPersonas() }
        .alert("Switch Persona?", isPresented: Binding(
            get: { confirmPersona != nil },
            set: { if !$0 { confirmPersona = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmPersona = nil }
            Button("Switch") {
                if let persona = confirmPersona {
                    performSwitch(persona)
                }
            }
        } message: {
            if let persona = confirmPersona {
                Text("Switch to \(persona.label)? This will reassemble your CLAUDE.md.")
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Switch Persona")
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var personaList: some View {
        let builtIn = personas.filter { $0.source == "builtin" }
        let custom = personas.filter { $0.source == "custom" }

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if !builtIn.isEmpty {
                    sectionHeader("Built-in")
                    ForEach(builtIn) { persona in
                        personaCard(persona)
                    }
                }
                if !custom.isEmpty {
                    sectionHeader("Custom")
                        .padding(.top, 8)
                    ForEach(custom) { persona in
                        personaCard(persona)
                    }
                }
            }
            .padding(16)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func personaCard(_ persona: PersonaProfile) -> some View {
        let isCurrent = persona.persona == currentPersona

        return Button {
            if !isCurrent && !isSwitching {
                confirmPersona = persona
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(persona.label)
                            .font(.system(size: 13, weight: .semibold))
                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                        }
                    }
                    Text(persona.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        axisCapsule(persona.axes.communication, label: "comm")
                        axisCapsule(persona.axes.autonomy, label: "auto")
                        axisCapsule(persona.axes.workflow, label: "flow")
                        axisCapsule(persona.axes.depth, label: "depth")
                    }
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? Color.accentColor.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isCurrent ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .disabled(isSwitching)
        .opacity(isSwitching && !isCurrent ? 0.5 : 1)
    }

    private func axisCapsule(_ value: String, label: String) -> some View {
        Text(value)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(axisColor(value).opacity(0.12), in: Capsule())
            .foregroundStyle(axisColor(value))
    }

    private func axisColor(_ value: String) -> Color {
        switch value {
        case "expert", "full", "high", "engineering", "advanced":
            return .green
        case "detailed", "moderate", "guided", "standard", "technical":
            return .blue
        default:
            return .secondary
        }
    }

    private func loadPersonas() async {
        isLoading = true
        defer { isLoading = false }
        do {
            personas = try await personaService.listPersonas()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func performSwitch(_ persona: PersonaProfile) {
        confirmPersona = nil
        isSwitching = true

        Task {
            do {
                try await personaService.switchPersona(name: persona.persona)
                isSwitching = false
                onSwitched()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                isSwitching = false
            }
        }
    }
}
