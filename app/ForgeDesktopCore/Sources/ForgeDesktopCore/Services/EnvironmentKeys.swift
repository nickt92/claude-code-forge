import SwiftUI

// MARK: - Fix Service Key

private struct FixServiceKey: EnvironmentKey {
    static let defaultValue: FixService = FixService(
        initService: InitService()
    )
}

// MARK: - Doctor Service Key

private struct DoctorServiceKey: EnvironmentKey {
    static let defaultValue: DoctorService = DoctorService()
}

// MARK: - Claude Service Key

private struct ClaudeServiceKey: EnvironmentKey {
    static let defaultValue: ClaudeService = ClaudeService()
}

// MARK: - Config Service Key

private struct ConfigServiceKey: EnvironmentKey {
    static let defaultValue: ConfigService = ConfigService()
}

// MARK: - Persona Service Key

private struct PersonaServiceKey: EnvironmentKey {
    static let defaultValue: PersonaService = PersonaService()
}

// MARK: - Forge Service Key

private struct ForgeServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue: ForgeService = ForgeService()
}

// MARK: - Dismissal Service Key

private struct DismissalServiceKey: EnvironmentKey {
    static let defaultValue: DismissalService = DismissalService()
}

// MARK: - Onboarding Service Key

private struct OnboardingServiceKey: EnvironmentKey {
    static let defaultValue: OnboardingService = OnboardingService(
        claudeService: ClaudeService()
    )
}

// MARK: - Permissions Service Key

private struct PermissionsServiceKey: EnvironmentKey {
    static let defaultValue: PermissionsService = PermissionsService()
}

// MARK: - Status Service Key

private struct StatusServiceKey: EnvironmentKey {
    static let defaultValue: StatusService = StatusService()
}

// MARK: - Update Service Key

private struct UpdateServiceKey: EnvironmentKey {
    static let defaultValue: UpdateService = UpdateService()
}

// MARK: - Forge State Key

private struct ForgeStateKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: ForgeState = ForgeState()
}

// MARK: - Environment Extensions

extension EnvironmentValues {
    public var fixService: FixService {
        get { self[FixServiceKey.self] }
        set { self[FixServiceKey.self] = newValue }
    }

    public var statusService: StatusService {
        get { self[StatusServiceKey.self] }
        set { self[StatusServiceKey.self] = newValue }
    }

    public var updateService: UpdateService {
        get { self[UpdateServiceKey.self] }
        set { self[UpdateServiceKey.self] = newValue }
    }

    public var doctorService: DoctorService {
        get { self[DoctorServiceKey.self] }
        set { self[DoctorServiceKey.self] = newValue }
    }

    public var claudeService: ClaudeService {
        get { self[ClaudeServiceKey.self] }
        set { self[ClaudeServiceKey.self] = newValue }
    }

    public var configService: ConfigService {
        get { self[ConfigServiceKey.self] }
        set { self[ConfigServiceKey.self] = newValue }
    }

    public var personaService: PersonaService {
        get { self[PersonaServiceKey.self] }
        set { self[PersonaServiceKey.self] = newValue }
    }

    public var forgeService: ForgeService {
        get { self[ForgeServiceEnvironmentKey.self] }
        set { self[ForgeServiceEnvironmentKey.self] = newValue }
    }

    public var onboardingService: OnboardingService {
        get { self[OnboardingServiceKey.self] }
        set { self[OnboardingServiceKey.self] = newValue }
    }

    public var permissionsService: PermissionsService {
        get { self[PermissionsServiceKey.self] }
        set { self[PermissionsServiceKey.self] = newValue }
    }

    public var forgeState: ForgeState {
        get { self[ForgeStateKey.self] }
        set { self[ForgeStateKey.self] = newValue }
    }

    public var dismissalService: DismissalService {
        get { self[DismissalServiceKey.self] }
        set { self[DismissalServiceKey.self] = newValue }
    }
}
