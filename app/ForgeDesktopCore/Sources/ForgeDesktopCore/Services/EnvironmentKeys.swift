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

// MARK: - Environment Extensions

extension EnvironmentValues {
    public var fixService: FixService {
        get { self[FixServiceKey.self] }
        set { self[FixServiceKey.self] = newValue }
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
}
