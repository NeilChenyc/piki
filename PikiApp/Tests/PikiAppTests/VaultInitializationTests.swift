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

    private func temporaryVaultURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "piki-vault-init-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
