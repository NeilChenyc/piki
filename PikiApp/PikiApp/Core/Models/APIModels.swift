import Foundation

// MARK: - Task API

struct TaskCreateRequest: Codable, Sendable {
    let vaultPath: String
    let userInput: String
    let selectedPaths: [String]
    let actionContext: [String: String]
    let conversationId: String?
    let mode: String
    let asyncMode: Bool

    enum CodingKeys: String, CodingKey {
        case vaultPath = "vault_path"
        case userInput = "user_input"
        case selectedPaths = "selected_paths"
        case actionContext = "action_context"
        case conversationId = "conversation_id"
        case mode
        case asyncMode = "async_mode"
    }

    init(
        vaultPath: String,
        userInput: String,
        selectedPaths: [String] = [],
        actionContext: [String: String] = [:],
        conversationId: String? = nil,
        mode: String = "normal",
        asyncMode: Bool = false
    ) {
        self.vaultPath = vaultPath
        self.userInput = userInput
        self.selectedPaths = selectedPaths
        self.actionContext = actionContext
        self.conversationId = conversationId
        self.mode = mode
        self.asyncMode = asyncMode
    }
}

struct TaskCreateResponse: Codable {
    let taskId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case status
    }
}

struct BufferedUploadResponse: Codable {
    let filename: String
    let bufferedPath: String
    let sizeBytes: Int
    let originalPath: String?

    enum CodingKeys: String, CodingKey {
        case filename
        case bufferedPath = "buffered_path"
        case sizeBytes = "size_bytes"
        case originalPath = "original_path"
    }
}

struct TaskRecordDTO: Codable {
    let id: String
    let status: String
    let summary: String?
    let output: TaskRecordOutput?

    struct TaskRecordOutput: Codable {
        let answer: String?
        let summary: String?
        let lintResult: LintResultDTO?
        let sessionId: String?
        let pendingInput: PendingInputDTO?

        enum CodingKeys: String, CodingKey {
            case answer
            case summary
            case lintResult = "lint_result"
            case sessionId = "session_id"
            case pendingInput = "pending_input"
        }
    }
}

struct TaskCancelResponse: Codable {
    let id: String
    let status: String
    let summary: String?
}

struct TaskInputRequest: Codable {
    let message: String
}

struct TaskEvent: Decodable, Identifiable {
    let id: String
    let taskId: String
    let type: String
    let payload: TaskEventPayload
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case type
        case payload
        case data
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        taskId = try container.decodeIfPresent(String.self, forKey: .taskId) ?? ""
        type = try container.decode(String.self, forKey: .type)
        payload = try container.decodeIfPresent(TaskEventPayload.self, forKey: .payload)
            ?? container.decodeIfPresent(TaskEventPayload.self, forKey: .data)
            ?? TaskEventPayload()
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct TaskEventPayload: Codable {
    let summary: String?
    let answer: String?
    let error: String?
    let reason: String?
    let prompt: String?
    let content: String?
    let status: String?
    let output: String?
    let delta: String?
    let stage: String?
    let title: String?
    let detail: String?
    let finalOutputPreview: String?
    let journalEntryId: String?
    let sourcePath: String?
    let kind: String?
    let tool: String?
    let toolUseId: String?
    let category: String?
    let provider: String?
    let sessionId: String?
    let pendingInput: PendingInputDTO?
    let options: [String]?
    let errorCode: String?
    let errorTitle: String?
    let errorMessage: String?
    let recoverySuggestion: String?
    let retryable: Bool?
    let actionLabel: String?
    let actionTarget: String?

    init(
        summary: String? = nil,
        answer: String? = nil,
        error: String? = nil,
        reason: String? = nil,
        prompt: String? = nil,
        content: String? = nil,
        status: String? = nil,
        output: String? = nil,
        delta: String? = nil,
        stage: String? = nil,
        title: String? = nil,
        detail: String? = nil,
        finalOutputPreview: String? = nil,
        journalEntryId: String? = nil,
        sourcePath: String? = nil,
        kind: String? = nil,
        tool: String? = nil,
        toolUseId: String? = nil,
        category: String? = nil,
        provider: String? = nil,
        sessionId: String? = nil,
        pendingInput: PendingInputDTO? = nil,
        options: [String]? = nil,
        errorCode: String? = nil,
        errorTitle: String? = nil,
        errorMessage: String? = nil,
        recoverySuggestion: String? = nil,
        retryable: Bool? = nil,
        actionLabel: String? = nil,
        actionTarget: String? = nil
    ) {
        self.summary = summary
        self.answer = answer
        self.error = error
        self.reason = reason
        self.prompt = prompt
        self.content = content
        self.status = status
        self.output = output
        self.delta = delta
        self.stage = stage
        self.title = title
        self.detail = detail
        self.finalOutputPreview = finalOutputPreview
        self.journalEntryId = journalEntryId
        self.sourcePath = sourcePath
        self.kind = kind
        self.tool = tool
        self.toolUseId = toolUseId
        self.category = category
        self.provider = provider
        self.sessionId = sessionId
        self.pendingInput = pendingInput
        self.options = options
        self.errorCode = errorCode
        self.errorTitle = errorTitle
        self.errorMessage = errorMessage
        self.recoverySuggestion = recoverySuggestion
        self.retryable = retryable
        self.actionLabel = actionLabel
        self.actionTarget = actionTarget
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case answer
        case error
        case reason
        case prompt
        case content
        case status
        case output
        case delta
        case stage
        case title
        case detail
        case finalOutputPreview = "final_output_preview"
        case journalEntryId = "journal_entry_id"
        case sourcePath = "source_path"
        case kind
        case tool
        case toolUseId = "tool_use_id"
        case category
        case provider
        case sessionId = "session_id"
        case pendingInput = "pending_input"
        case options
        case errorCode = "error_code"
        case errorTitle = "error_title"
        case errorMessage = "error_message"
        case recoverySuggestion = "recovery_suggestion"
        case retryable
        case actionLabel = "action_label"
        case actionTarget = "action_target"
    }

    var failurePresentation: TaskFailurePresentation {
        TaskFailurePresentation(
            code: errorCode,
            title: errorTitle ?? "任务执行失败",
            message: errorMessage ?? error ?? summary ?? "任务执行失败。",
            recoverySuggestion: recoverySuggestion,
            retryable: retryable ?? false,
            actionLabel: actionLabel,
            actionTarget: actionTarget
        )
    }
}

struct PendingInputDTO: Codable {
    let tool: String?
    let prompt: String?
    let options: [String]?
    let toolUseId: String?

    enum CodingKeys: String, CodingKey {
        case tool
        case prompt
        case options
        case toolUseId = "tool_use_id"
    }
}

struct UserFacingErrorAction: Equatable {
    let label: String
    let target: String
}

struct TaskFailurePresentation: Decodable, Equatable {
    let code: String?
    let title: String
    let message: String
    let recoverySuggestion: String?
    let retryable: Bool
    let actionLabel: String?
    let actionTarget: String?

    init(
        code: String? = nil,
        title: String,
        message: String,
        recoverySuggestion: String? = nil,
        retryable: Bool = false,
        actionLabel: String? = nil,
        actionTarget: String? = nil
    ) {
        self.code = code
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.retryable = retryable
        self.actionLabel = actionLabel
        self.actionTarget = actionTarget
    }

    enum CodingKeys: String, CodingKey {
        case code
        case errorCode = "error_code"
        case title
        case errorTitle = "error_title"
        case message
        case errorMessage = "error_message"
        case error
        case recoverySuggestion = "recovery_suggestion"
        case retryable
        case actionLabel = "action_label"
        case actionTarget = "action_target"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .errorCode)
            ?? container.decodeIfPresent(String.self, forKey: .code)
        title = try container.decodeIfPresent(String.self, forKey: .errorTitle)
            ?? container.decodeIfPresent(String.self, forKey: .title)
            ?? "任务执行失败"
        message = try container.decodeIfPresent(String.self, forKey: .errorMessage)
            ?? container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .error)
            ?? "任务执行失败。"
        recoverySuggestion = try container.decodeIfPresent(String.self, forKey: .recoverySuggestion)
        retryable = try container.decodeIfPresent(Bool.self, forKey: .retryable) ?? false
        actionLabel = try container.decodeIfPresent(String.self, forKey: .actionLabel)
        actionTarget = try container.decodeIfPresent(String.self, forKey: .actionTarget)
    }

    var displayText: String {
        var parts = [title, message]
        if let recoverySuggestion, !recoverySuggestion.isEmpty {
            parts.append(recoverySuggestion)
        }
        return parts.joined(separator: "\n\n")
    }

    var action: UserFacingErrorAction? {
        guard let actionLabel, let actionTarget, !actionLabel.isEmpty, !actionTarget.isEmpty else {
            return nil
        }
        return UserFacingErrorAction(label: actionLabel, target: actionTarget)
    }
}

// MARK: - Health

struct ServiceHealth: Codable {
    let ok: Bool
    let runnerAvailable: Bool?
    let runnerDetail: String?
    let provider: String?
    let anthropicAPIKeyConfigured: Bool?
    let anthropicBaseURL: String?
    let agentModel: String?
    let agentRuntimeEnabled: Bool?
    let agentRuntimeConfigured: Bool?
    let claudeConfigDir: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case runnerAvailable = "runner_available"
        case runnerDetail = "runner_detail"
        case provider
        case anthropicAPIKeyConfigured = "anthropic_api_key_configured"
        case anthropicBaseURL = "anthropic_base_url"
        case agentModel = "agent_model"
        case agentRuntimeEnabled = "agent_runtime_enabled"
        case agentRuntimeConfigured = "agent_runtime_configured"
        case claudeConfigDir = "claude_config_dir"
    }
}

struct RuntimeConfigDTO: Codable {
    let provider: String?
    let agentModel: String?
    let anthropicBaseURL: String?
    let apiKeyConfigured: Bool?
    let apiKeyPreview: String?
    let apiKeySource: String?
    let agentRuntimeEnabled: Bool?
    let tingwuConfigured: Bool?
    let tingwuRegionId: String?
    let aliyunAccessKeyIdPreview: String?
    let aliyunAccessKeySecretConfigured: Bool?
    let tingwuAppKeyPreview: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case agentModel = "agent_model"
        case anthropicBaseURL = "anthropic_base_url"
        case apiKeyConfigured = "api_key_configured"
        case apiKeyPreview = "api_key_preview"
        case apiKeySource = "api_key_source"
        case agentRuntimeEnabled = "agent_runtime_enabled"
        case tingwuConfigured = "tingwu_configured"
        case tingwuRegionId = "tingwu_region_id"
        case aliyunAccessKeyIdPreview = "aliyun_access_key_id_preview"
        case aliyunAccessKeySecretConfigured = "aliyun_access_key_secret_configured"
        case tingwuAppKeyPreview = "tingwu_app_key_preview"
    }
}

struct RuntimeConfigUpdateRequest: Codable, Sendable {
    let agentModel: String?
    let anthropicBaseURL: String?
    let apiKey: String?
    let clearAPIKey: Bool?
    let aliyunAccessKeyId: String?
    let aliyunAccessKeySecret: String?
    let tingwuAppKey: String?
    let tingwuRegionId: String?
    let clearTingwuConfig: Bool?

    init(
        agentModel: String? = nil,
        anthropicBaseURL: String? = nil,
        apiKey: String? = nil,
        clearAPIKey: Bool? = nil,
        aliyunAccessKeyId: String? = nil,
        aliyunAccessKeySecret: String? = nil,
        tingwuAppKey: String? = nil,
        tingwuRegionId: String? = nil,
        clearTingwuConfig: Bool? = nil
    ) {
        self.agentModel = agentModel
        self.anthropicBaseURL = anthropicBaseURL
        self.apiKey = apiKey
        self.clearAPIKey = clearAPIKey
        self.aliyunAccessKeyId = aliyunAccessKeyId
        self.aliyunAccessKeySecret = aliyunAccessKeySecret
        self.tingwuAppKey = tingwuAppKey
        self.tingwuRegionId = tingwuRegionId
        self.clearTingwuConfig = clearTingwuConfig
    }

    enum CodingKeys: String, CodingKey {
        case agentModel = "agent_model"
        case anthropicBaseURL = "anthropic_base_url"
        case apiKey = "api_key"
        case clearAPIKey = "clear_api_key"
        case aliyunAccessKeyId = "aliyun_access_key_id"
        case aliyunAccessKeySecret = "aliyun_access_key_secret"
        case tingwuAppKey = "tingwu_app_key"
        case tingwuRegionId = "tingwu_region_id"
        case clearTingwuConfig = "clear_tingwu_config"
    }
}

struct RuntimeSmokeTestResponse: Codable {
    let ok: Bool
    let output: String?
    let error: String?
    let runnerAvailable: Bool?
    let provider: String?
    let agentRuntimeConfigured: Bool?
    let anthropicBaseURL: String?
    let agentModel: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case output
        case error
        case runnerAvailable = "runner_available"
        case provider
        case agentRuntimeConfigured = "agent_runtime_configured"
        case anthropicBaseURL = "anthropic_base_url"
        case agentModel = "agent_model"
    }
}

struct APIErrorResponse: Decodable {
    let detail: String?
    let error: TaskFailurePresentation?

    enum CodingKeys: String, CodingKey {
        case detail
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let detailError = try? container.decode(TaskFailurePresentation.self, forKey: .detail)
        if let detailString = try? container.decode(String.self, forKey: .detail) {
            detail = detailString
        } else {
            detail = detailError?.message
        }
        error = (try? container.decode(TaskFailurePresentation.self, forKey: .error)) ?? detailError
    }
}

// MARK: - Journal

struct JournalResponse: Codable {
    let entries: [JournalEntry]
}

struct JournalEntry: Codable, Identifiable {
    let id: String
    let taskId: String?
    let status: String
    let affectedFiles: [String]
    let createdAt: String
    let rolledBackAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case status
        case affectedFiles = "affected_files"
        case createdAt = "created_at"
        case rolledBackAt = "rolled_back_at"
    }
}

// MARK: - Inspirations

struct InspirationAttachmentDTO: Codable, Equatable {
    let filename: String
    let path: String?
    let bufferedPath: String?
    let mimeType: String?
    let sizeBytes: Int?

    enum CodingKeys: String, CodingKey {
        case filename
        case path
        case bufferedPath = "buffered_path"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
    }

    init(
        filename: String,
        path: String? = nil,
        bufferedPath: String? = nil,
        mimeType: String? = nil,
        sizeBytes: Int? = nil
    ) {
        self.filename = filename
        self.path = path
        self.bufferedPath = bufferedPath
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }
}

struct InspirationDTO: Codable, Identifiable, Equatable {
    let id: String
    let path: String
    let content: String
    let attachments: [InspirationAttachmentDTO]
    let createdAt: String
    let updatedAt: String
    let contentHash: String
    let compileStatus: String
    let compileTaskId: String?
    let compiledHash: String?
    let sourcePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case content
        case attachments
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case contentHash = "content_hash"
        case compileStatus = "compile_status"
        case compileTaskId = "compile_task_id"
        case compiledHash = "compiled_hash"
        case sourcePath = "source_path"
    }
}

struct InspirationListResponse: Codable {
    let items: [InspirationDTO]
}

struct InspirationCreateRequest: Codable {
    let vaultPath: String
    let content: String
    let attachments: [InspirationAttachmentDTO]

    enum CodingKeys: String, CodingKey {
        case vaultPath = "vault_path"
        case content
        case attachments
    }
}

struct InspirationUpdateRequest: Codable {
    let vaultPath: String
    let content: String
    let attachments: [InspirationAttachmentDTO]

    enum CodingKeys: String, CodingKey {
        case vaultPath = "vault_path"
        case content
        case attachments
    }
}

struct InspirationCompileRequest: Codable {
    let vaultPath: String

    enum CodingKeys: String, CodingKey {
        case vaultPath = "vault_path"
    }
}

struct InspirationCompileResponse: Codable {
    let compiledCount: Int
    let taskId: String?
    let sourcePath: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case compiledCount = "compiled_count"
        case taskId = "task_id"
        case sourcePath = "source_path"
        case error
    }
}

// MARK: - Lint

struct LintResultDTO: Codable {
    let generatedAt: String?
    let scannedFiles: Int?
    let issues: [LintIssueDTO]
    let issueCounts: [String: Int]?
    let fixableIssueIds: [String]?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case scannedFiles = "scanned_files"
        case issues
        case issueCounts = "issue_counts"
        case fixableIssueIds = "fixable_issue_ids"
    }
}

struct LintIssueDTO: Codable, Identifiable {
    let id: String
    let kind: String
    let severity: String
    let path: String
    let message: String
    let fixable: Bool?

    enum CodingKeys: String, CodingKey {
        case id, kind, severity, path, message, fixable
    }
}
