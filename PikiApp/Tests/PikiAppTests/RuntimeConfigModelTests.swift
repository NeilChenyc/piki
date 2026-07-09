import Foundation
import Testing
@testable import PikiApp

@Suite("Runtime config models")
struct RuntimeConfigModelTests {
    @Test
    func runtimeConfigDTODecodesTingwuStatus() throws {
        let json = """
        {
          "provider": "claude",
          "agent_model": "claude-live",
          "anthropic_base_url": "https://gateway.example",
          "api_key_configured": true,
          "api_key_preview": "sk-a...1234",
          "api_key_source": "persisted",
          "agent_runtime_enabled": true,
          "tingwu_configured": true,
          "tingwu_region_id": "cn-shanghai",
          "aliyun_access_key_id_preview": "LTAI...abcd",
          "aliyun_access_key_secret_configured": true,
          "tingwu_app_key_preview": "appk...wxyz"
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(RuntimeConfigDTO.self, from: json)

        #expect(config.tingwuConfigured == true)
        #expect(config.tingwuRegionId == "cn-shanghai")
        #expect(config.aliyunAccessKeyIdPreview == "LTAI...abcd")
        #expect(config.aliyunAccessKeySecretConfigured == true)
        #expect(config.tingwuAppKeyPreview == "appk...wxyz")
    }

    @Test
    func runtimeConfigUpdateRequestEncodesTingwuCredentials() throws {
        let request = RuntimeConfigUpdateRequest(
            agentModel: nil,
            anthropicBaseURL: nil,
            apiKey: nil,
            clearAPIKey: nil,
            aliyunAccessKeyId: "LTAI-test",
            aliyunAccessKeySecret: "aliyun-secret",
            tingwuAppKey: "tingwu-app",
            tingwuRegionId: "cn-shanghai",
            clearTingwuConfig: nil
        )

        let data = try JSONEncoder().encode(request)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(payload["aliyun_access_key_id"] as? String == "LTAI-test")
        #expect(payload["aliyun_access_key_secret"] as? String == "aliyun-secret")
        #expect(payload["tingwu_app_key"] as? String == "tingwu-app")
        #expect(payload["tingwu_region_id"] as? String == "cn-shanghai")
    }

    @Test
    func runtimeConfigUpdateRequestEncodesTingwuClearFlag() throws {
        let request = RuntimeConfigUpdateRequest(
            agentModel: nil,
            anthropicBaseURL: nil,
            apiKey: nil,
            clearAPIKey: nil,
            aliyunAccessKeyId: nil,
            aliyunAccessKeySecret: nil,
            tingwuAppKey: nil,
            tingwuRegionId: nil,
            clearTingwuConfig: true
        )

        let data = try JSONEncoder().encode(request)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(payload["clear_tingwu_config"] as? Bool == true)
    }

    @MainActor
    @Test
    func runtimeSettingsViewModelSendsTingwuSaveRequest() async throws {
        let runtime = TingwuConfigRuntimeService(
            initialConfig: makeRuntimeConfig(tingwuConfigured: false),
            updateResponse: makeRuntimeConfig(
                tingwuConfigured: true,
                tingwuRegionId: "cn-shanghai",
                aliyunAccessKeyIdPreview: "LTAI...test",
                aliyunAccessKeySecretConfigured: true,
                tingwuAppKeyPreview: "app...test"
            )
        )
        let appState = AppState(runtimeService: runtime)
        let viewModel = RuntimeSettingsViewModel()

        await viewModel.load(appState: appState, force: true)
        viewModel.draftAliyunAccessKeyId = " LTAI-test "
        viewModel.draftAliyunAccessKeySecret = " aliyun-secret "
        viewModel.draftTingwuAppKey = " tingwu-app "
        viewModel.draftTingwuRegionId = " cn-shanghai "

        await viewModel.saveTingwuConfig(appState: appState)

        let request = try #require(runtime.lastUpdateRequest)
        #expect(request.aliyunAccessKeyId == "LTAI-test")
        #expect(request.aliyunAccessKeySecret == "aliyun-secret")
        #expect(request.tingwuAppKey == "tingwu-app")
        #expect(request.tingwuRegionId == "cn-shanghai")
        #expect(request.clearTingwuConfig == nil)
        #expect(viewModel.tingwuConfigured == true)
        #expect(viewModel.draftAliyunAccessKeySecret.isEmpty)
    }

    @MainActor
    @Test
    func runtimeSettingsViewModelSendsTingwuClearRequest() async throws {
        let runtime = TingwuConfigRuntimeService(
            initialConfig: makeRuntimeConfig(
                tingwuConfigured: true,
                tingwuRegionId: "cn-beijing",
                aliyunAccessKeyIdPreview: "LTAI...test",
                aliyunAccessKeySecretConfigured: true,
                tingwuAppKeyPreview: "app...test"
            ),
            updateResponse: makeRuntimeConfig(tingwuConfigured: false)
        )
        let appState = AppState(runtimeService: runtime)
        let viewModel = RuntimeSettingsViewModel()

        await viewModel.load(appState: appState, force: true)
        await viewModel.clearTingwuConfig(appState: appState)

        let request = try #require(runtime.lastUpdateRequest)
        #expect(request.clearTingwuConfig == true)
        #expect(request.aliyunAccessKeyId == nil)
        #expect(request.aliyunAccessKeySecret == nil)
        #expect(request.tingwuAppKey == nil)
        #expect(viewModel.tingwuConfigured == false)
    }
}

private func makeRuntimeConfig(
    tingwuConfigured: Bool,
    tingwuRegionId: String = "cn-beijing",
    aliyunAccessKeyIdPreview: String = "",
    aliyunAccessKeySecretConfigured: Bool = false,
    tingwuAppKeyPreview: String = ""
) -> RuntimeConfigDTO {
    RuntimeConfigDTO(
        provider: "claude",
        agentModel: "claude-test",
        anthropicBaseURL: "https://api.anthropic.com",
        apiKeyConfigured: true,
        apiKeyPreview: "sk-...test",
        apiKeySource: "persisted",
        agentRuntimeEnabled: true,
        tingwuConfigured: tingwuConfigured,
        tingwuRegionId: tingwuRegionId,
        aliyunAccessKeyIdPreview: aliyunAccessKeyIdPreview,
        aliyunAccessKeySecretConfigured: aliyunAccessKeySecretConfigured,
        tingwuAppKeyPreview: tingwuAppKeyPreview
    )
}

private enum RuntimeConfigTestError: Error {
    case unimplemented
}

@MainActor
private final class TingwuConfigRuntimeService: RuntimeServiceProtocol {
    private var config: RuntimeConfigDTO
    private let updateResponse: RuntimeConfigDTO
    private(set) var lastUpdateRequest: RuntimeConfigUpdateRequest?

    init(initialConfig: RuntimeConfigDTO, updateResponse: RuntimeConfigDTO) {
        self.config = initialConfig
        self.updateResponse = updateResponse
    }

    func health() async throws -> ServiceHealth {
        ServiceHealth(
            ok: true,
            runnerAvailable: true,
            runnerDetail: nil,
            provider: "claude",
            anthropicAPIKeyConfigured: true,
            anthropicBaseURL: "https://api.anthropic.com",
            agentModel: "claude-test",
            agentRuntimeEnabled: true,
            agentRuntimeConfigured: true,
            claudeConfigDir: nil
        )
    }

    func getRuntimeConfig() async throws -> RuntimeConfigDTO {
        config
    }

    func updateRuntimeConfig(_ request: RuntimeConfigUpdateRequest) async throws -> RuntimeConfigDTO {
        lastUpdateRequest = request
        config = updateResponse
        return updateResponse
    }

    func smokeTestRuntime() async throws -> RuntimeSmokeTestResponse {
        throw RuntimeConfigTestError.unimplemented
    }

    func createTask(_ request: TaskCreateRequest) async throws -> TaskCreateResponse {
        throw RuntimeConfigTestError.unimplemented
    }

    func taskEvents(taskId: String) -> AsyncThrowingStream<TaskEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func getTask(taskId: String) async throws -> TaskRecordDTO {
        throw RuntimeConfigTestError.unimplemented
    }

    func submitTaskInput(taskId: String, message: String) async throws -> TaskRecordDTO {
        throw RuntimeConfigTestError.unimplemented
    }

    func cancelTask(taskId: String) async throws -> TaskRecordDTO {
        throw RuntimeConfigTestError.unimplemented
    }

    func uploadFile(_ fileURL: URL) async throws -> BufferedUploadResponse {
        throw RuntimeConfigTestError.unimplemented
    }

    func recentJournal(limit: Int, vaultPath: String?) async throws -> [JournalEntry] {
        throw RuntimeConfigTestError.unimplemented
    }

    func runLint(vaultPath: String) async throws -> LintResultDTO {
        throw RuntimeConfigTestError.unimplemented
    }

    func fixLint(vaultPath: String, issueIds: [String]?) async throws {
        throw RuntimeConfigTestError.unimplemented
    }
}
