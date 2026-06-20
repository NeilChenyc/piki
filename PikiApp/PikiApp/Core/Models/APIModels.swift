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
        options: [String]? = nil
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

    enum CodingKeys: String, CodingKey {
        case provider
        case agentModel = "agent_model"
        case anthropicBaseURL = "anthropic_base_url"
        case apiKeyConfigured = "api_key_configured"
        case apiKeyPreview = "api_key_preview"
        case apiKeySource = "api_key_source"
        case agentRuntimeEnabled = "agent_runtime_enabled"
    }
}

struct RuntimeConfigUpdateRequest: Codable, Sendable {
    let agentModel: String?
    let anthropicBaseURL: String?
    let apiKey: String?
    let clearAPIKey: Bool?

    enum CodingKeys: String, CodingKey {
        case agentModel = "agent_model"
        case anthropicBaseURL = "anthropic_base_url"
        case apiKey = "api_key"
        case clearAPIKey = "clear_api_key"
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

struct APIErrorResponse: Codable {
    let detail: String?
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
    let eligibleForRollback: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case status
        case affectedFiles = "affected_files"
        case createdAt = "created_at"
        case rolledBackAt = "rolled_back_at"
        case eligibleForRollback = "eligible_for_rollback"
    }
}

// MARK: - Ingest Queue

struct IngestQueueResponse: Codable {
    let items: [IngestQueueItemDTO]
}

struct IngestQueueItemDTO: Codable, Identifiable {
    let id: String
    let originalPath: String
    let sourcePath: String?
    let status: String
    let error: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case originalPath = "original_path"
        case sourcePath = "source_path"
        case status
        case error
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
