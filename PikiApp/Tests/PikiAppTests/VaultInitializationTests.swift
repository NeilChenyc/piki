import Foundation
import Testing
@testable import PikiApp

@MainActor
@Suite("Vault initialization")
struct VaultInitializationTests {
    @Test
    func createsRequiredRootMarkdownFiles() async throws {
        let root = try temporaryVaultURL()
        let viewModel = RuntimeSettingsViewModel()

        await viewModel.initializeVault(at: root)

        let agents = try String(contentsOf: root.appending(path: "AGENTS.md"), encoding: .utf8)
        #expect(agents.contains("# Piki Agent 协议"))
        #expect(agents.contains("再读 `purpose.md`"))
        #expect(agents.contains("默认使用中文写作"))
        #expect(agents.contains("`wiki/index.md` 和 `wiki/log.md` 始终同步、可信"))
        #expect(try String(contentsOf: root.appending(path: "purpose.md"), encoding: .utf8) == "# Purpose\n\nDescribe this vault's purpose.")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "wiki/index.md").path(percentEncoded: false)))
    }

    @Test
    func preservesExistingProtocolFiles() async throws {
        let root = try temporaryVaultURL()
        let agentsURL = root.appending(path: "AGENTS.md")
        let purposeURL = root.appending(path: "purpose.md")
        try "custom agents".write(to: agentsURL, atomically: true, encoding: .utf8)
        try "custom purpose".write(to: purposeURL, atomically: true, encoding: .utf8)
        let viewModel = RuntimeSettingsViewModel()

        await viewModel.initializeVault(at: root)

        #expect(try String(contentsOf: agentsURL, encoding: .utf8) == "custom agents")
        #expect(try String(contentsOf: purposeURL, encoding: .utf8) == "custom purpose")
    }

    @Test
    func appStateBootstrapCreatesDefaultVaultAtEnvironmentOverride() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "piki-default-vault-\(UUID().uuidString)", directoryHint: .isDirectory)
        setenv("PIKI_DEFAULT_VAULT_PATH", root.path(percentEncoded: false), 1)
        defer { unsetenv("PIKI_DEFAULT_VAULT_PATH") }

        let appState = AppState(runtimeService: VaultBootstrapRuntimeService())

        #expect(appState.vaultPath == root)
        #expect(FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) == false)

        appState.prepareDefaultVaultIfNeeded()

        #expect(FileManager.default.fileExists(atPath: root.appending(path: "raw/inbox").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "raw/inspirations").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "wiki/index.md").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "purpose.md").path(percentEncoded: false)))
    }

    private func temporaryVaultURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "piki-vault-init-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private enum VaultBootstrapError: Error {
    case unimplemented
}

@MainActor
private final class VaultBootstrapRuntimeService: RuntimeServiceProtocol {
    func health() async throws -> ServiceHealth { throw VaultBootstrapError.unimplemented }
    func getRuntimeConfig() async throws -> RuntimeConfigDTO { throw VaultBootstrapError.unimplemented }
    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO { throw VaultBootstrapError.unimplemented }
    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse { throw VaultBootstrapError.unimplemented }
    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse { throw VaultBootstrapError.unimplemented }
    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func getTask(taskId: String) async throws -> TaskRecordDTO { throw VaultBootstrapError.unimplemented }
    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO { throw VaultBootstrapError.unimplemented }
    func cancelTask(taskId: String) async throws -> TaskRecordDTO { throw VaultBootstrapError.unimplemented }
    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse { throw VaultBootstrapError.unimplemented }
    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] { [] }
    func runLint(vaultPath: String) async throws -> LintResultDTO { throw VaultBootstrapError.unimplemented }
    func fixLint(vaultPath: String, issueIds: [String]?) async throws {}
}
