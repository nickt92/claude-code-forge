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
    @State private var hoveredPersona: String?
    @State private var showBuilder = false

    public init(currentPersona: String, onSwitched: @escaping () -> Void) {
        self.currentPersona = currentPersona
        self.onSwitched = onSwitched
    }

    public var body: some View {
        ForgeSheet(
            icon: "person.crop.circle",
            title: "Switch Persona",
            subtitle: "Tailor Claude Code's behavior to how you work",
            content: {
                Group {
                    if isLoading {
                        loadingContent
                    } else if let error {
                        ForgeEmptyState(
                            icon: "exclamationmark.triangle",
                            title: "Couldn't Load Personas",
                            message: error
                        )
                    } else {
                        personaList
                    }
                }
                .frame(minHeight: 400, maxHeight: 560)
            },
            footer: {
                HStack {
                    Button {
                        showBuilder = true
                    } label: {
                        Label("Create Custom Persona…", systemImage: "person.crop.circle.badge.plus")
                            .font(ForgeTheme.Typography.body)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLoading || isSwitching)
                    .accessibilityLabel("Create a custom persona")

                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .keyboardShortcut(.cancelAction)
                }
            }
        )
        .sheet(isPresented: $showBuilder) {
            PersonaBuilderView(
                builtinIds: personas.filter { $0.source == "builtin" }.map(\.persona),
                customIds: personas.filter { $0.source == "custom" }.map(\.persona),
                onCreated: { _ in
                    Task { await loadPersonas() }
                    onSwitched()
                }
            )
        }
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

    private var loadingContent: some View {
        SkeletonGroup {
            VStack(spacing: ForgeTheme.Spacing.sm) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonDetailCard()
                }
                Spacer()
            }
            .padding(ForgeTheme.Spacing.lg)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading personas")
    }

    private var personaList: some View {
        let builtIn = personas.filter { $0.source == "builtin" }
        let custom = personas.filter { $0.source == "custom" }

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: ForgeTheme.Spacing.sm) {
                if !builtIn.isEmpty {
                    sectionHeader("Built-in")
                    ForEach(builtIn) { persona in
                        personaCard(persona)
                    }
                }
                if !custom.isEmpty {
                    sectionHeader("Custom")
                        .padding(.top, ForgeTheme.Spacing.sm)
                    ForEach(custom) { persona in
                        personaCard(persona)
                    }
                }
            }
            .padding(ForgeTheme.Spacing.lg)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(ForgeTheme.Typography.cardTitle)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func personaCard(_ persona: PersonaProfile) -> some View {
        let isCurrent = persona.persona == currentPersona
        let isHovered = hoveredPersona == persona.persona

        return Button {
            if !isCurrent && !isSwitching {
                confirmPersona = persona
            }
        } label: {
            HStack(alignment: .top, spacing: ForgeTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs + 2) {
                    HStack(spacing: ForgeTheme.Spacing.sm) {
                        Text(persona.label)
                            .font(ForgeTheme.Typography.rowTitle)
                        if isCurrent {
                            StatusBadge("Current", icon: "checkmark", tint: ForgeTheme.Colors.success)
                        }
                    }
                    Text(persona.description)
                        .font(ForgeTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: ForgeTheme.Spacing.xs) {
                        axisBadge(persona.axes.communication, label: "comm")
                        axisBadge(persona.axes.autonomy, label: "auto")
                        axisBadge(persona.axes.workflow, label: "flow")
                        axisBadge(persona.axes.depth, label: "depth")
                    }
                }
                Spacer()
            }
            .padding(ForgeTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isCurrent ? ForgeTheme.Colors.forgeAmber.opacity(0.08) :
                    (isHovered ? ForgeTheme.Colors.hoverWash : Color.clear),
                in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
            )
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                        .stroke(ForgeTheme.Gradients.forge, lineWidth: 1.5)
                        .opacity(0.6)
                } else {
                    RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                        .stroke(.quaternary)
                }
            }
            .forgeShadow(isHovered && !isCurrent ? ForgeTheme.Elevation.card : ForgeTheme.Elevation.flat)
        }
        .buttonStyle(.plain)
        .forgeAnimation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            hoveredPersona = hovering ? persona.persona : nil
        }
        .onDisappear {
            if hoveredPersona == persona.persona { hoveredPersona = nil }
        }
        .disabled(isSwitching)
        .opacity(isSwitching && !isCurrent ? 0.5 : 1)
        .accessibilityLabel(
            isCurrent
                ? "\(persona.label), current persona"
                : "Switch to \(persona.label)"
        )
    }

    private func axisBadge(_ value: String, label: String) -> some View {
        StatusBadge("\(label): \(value)", tint: axisColor(value))
    }

    private func axisColor(_ value: String) -> Color {
        switch value {
        case "expert", "full", "high", "engineering", "advanced":
            return ForgeTheme.Colors.success
        case "detailed", "moderate", "guided", "standard", "technical":
            return ForgeTheme.Colors.info
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
