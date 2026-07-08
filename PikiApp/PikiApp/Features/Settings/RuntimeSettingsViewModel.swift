import Foundation

@Observable
@MainActor
final class RuntimeSettingsViewModel {
    enum BannerState: Equatable {
        case none
        case info(String)
        case success(String)
        case error(String)
    }

    // MARK: - Runtime status (read from backend)
    var isLoading = false
    var hasLoaded = false
    var provider = "claude"
    var currentModel = ""
    var currentBaseURL = ""
    var apiKeyConfigured = false
    var runtimeEnabled = false
    var bannerState: BannerState = .none

    // MARK: - Presets
    var presets: [ConfigurationPreset] = []
    var activePresetId: UUID?
    var isApplyingPreset = false

    // MARK: - Preset sheet
    var showPresetSheet = false
    var editingPreset: ConfigurationPreset?
    var draftName = ""
    var draftModel = ""
    var draftBaseURL = ""
    var draftAPIKey = ""

    // MARK: - Smoke test
    var isRunningSmokeTest = false

    // MARK: - Podcast transcription
    var tingwuConfigured = false
    var tingwuRegionId = "cn-beijing"
    var aliyunAccessKeyIdPreview = ""
    var aliyunAccessKeySecretConfigured = false
    var tingwuAppKeyPreview = ""
    var draftAliyunAccessKeyId = ""
    var draftAliyunAccessKeySecret = ""
    var draftTingwuAppKey = ""
    var draftTingwuRegionId = "cn-beijing"
    var isSavingTingwuConfig = false
    var isClearingTingwuConfig = false
    var showTingwuHelpSheet = false

    // MARK: - Vault
    var isInitializingVault = false
    var vaultInitMessage: String?

    // MARK: - Computed

    var canSavePreset: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSaveTingwuConfig: Bool {
        guard !draftTingwuRegionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard !isSavingTingwuConfig && !isClearingTingwuConfig else { return false }
        if tingwuConfigured { return true }
        return !draftAliyunAccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftAliyunAccessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftTingwuAppKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Load

    func load(appState: AppState, force: Bool = false) async {
        guard force || !hasLoaded else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        presets = PresetStorage.load()

        do {
            let config = try await appState.runtimeService.getRuntimeConfig()
            applyConfig(config)
            detectActivePreset()
        } catch {
            bannerState = .error("无法加载运行时配置。")
        }
    }

    // MARK: - Preset Management

    func prepareNewPreset() {
        editingPreset = nil
        draftName = ""
        draftModel = ""
        draftBaseURL = "https://api.anthropic.com"
        draftAPIKey = ""
        showPresetSheet = true
    }

    func prepareEditPreset(_ preset: ConfigurationPreset) {
        editingPreset = preset
        draftName = preset.name
        draftModel = preset.agentModel
        draftBaseURL = preset.anthropicBaseURL
        draftAPIKey = preset.apiKey
        showPresetSheet = true
    }

    func savePreset() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = editingPreset,
           let index = presets.firstIndex(where: { $0.id == existing.id }) {
            presets[index].name = name
            presets[index].agentModel = model
            presets[index].anthropicBaseURL = baseURL
            if !apiKey.isEmpty {
                presets[index].apiKey = apiKey
            }
        } else {
            let preset = ConfigurationPreset(
                name: name,
                agentModel: model,
                anthropicBaseURL: baseURL,
                apiKey: apiKey
            )
            presets.append(preset)
        }

        PresetStorage.save(presets)
        showPresetSheet = false
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        if activePresetId == id {
            activePresetId = nil
        }
        PresetStorage.save(presets)
    }

    func applyPreset(_ preset: ConfigurationPreset, appState: AppState) async {
        isApplyingPreset = true
        bannerState = .info("正在切换配置「\(preset.name)」...")
        defer { isApplyingPreset = false }

        let request = RuntimeConfigUpdateRequest(
            agentModel: preset.agentModel,
            anthropicBaseURL: preset.anthropicBaseURL.isEmpty ? nil : preset.anthropicBaseURL,
            apiKey: preset.apiKey.isEmpty ? nil : preset.apiKey,
            clearAPIKey: nil
        )

        do {
            let config = try await appState.runtimeService.updateRuntimeConfig(request)
            applyConfig(config)
            activePresetId = preset.id
            updateLastUsed(id: preset.id)
            await appState.refreshServiceHealth()
            bannerState = .success("已切换到「\(preset.name)」。")
        } catch {
            bannerState = .error("切换失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Smoke Test

    func runSmokeTest(appState: AppState) async {
        isRunningSmokeTest = true
        bannerState = .info("正在运行 Smoke Test...")
        defer { isRunningSmokeTest = false }

        do {
            let response = try await appState.runtimeService.smokeTestRuntime()
            if response.ok {
                let msg = response.output?.trimmingCharacters(in: .whitespacesAndNewlines)
                bannerState = .success(msg?.isEmpty == false ? msg! : "Smoke test passed.")
            } else {
                bannerState = .error(response.error ?? "Smoke test failed.")
            }
            await appState.refreshServiceHealth()
        } catch {
            bannerState = .error("Smoke test failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Podcast Transcription

    func saveTingwuConfig(appState: AppState) async {
        guard canSaveTingwuConfig else { return }
        isSavingTingwuConfig = true
        bannerState = .info("正在保存播客转录配置...")
        defer { isSavingTingwuConfig = false }

        let accessKeyId = trimmedOrNil(draftAliyunAccessKeyId)
        let accessKeySecret = trimmedOrNil(draftAliyunAccessKeySecret)
        let appKey = trimmedOrNil(draftTingwuAppKey)
        let regionId = draftTingwuRegionId.trimmingCharacters(in: .whitespacesAndNewlines)

        let request = RuntimeConfigUpdateRequest(
            aliyunAccessKeyId: accessKeyId,
            aliyunAccessKeySecret: accessKeySecret,
            tingwuAppKey: appKey,
            tingwuRegionId: regionId,
            clearTingwuConfig: nil
        )

        do {
            let config = try await appState.runtimeService.updateRuntimeConfig(request)
            applyConfig(config)
            bannerState = .success("播客转录配置已保存。")
        } catch {
            bannerState = .error("保存播客转录配置失败：\(error.localizedDescription)")
        }
    }

    func clearTingwuConfig(appState: AppState) async {
        guard !isSavingTingwuConfig && !isClearingTingwuConfig else { return }
        isClearingTingwuConfig = true
        bannerState = .info("正在清空播客转录配置...")
        defer { isClearingTingwuConfig = false }

        let request = RuntimeConfigUpdateRequest(clearTingwuConfig: true)

        do {
            let config = try await appState.runtimeService.updateRuntimeConfig(request)
            applyConfig(config)
            bannerState = .success("已清空保存在 Piki 的播客转录配置。")
        } catch {
            bannerState = .error("清空播客转录配置失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Vault Initialization

    func initializeVault(at url: URL) async {
        isInitializingVault = true
        vaultInitMessage = nil
        defer { isInitializingVault = false }

        do {
            try Self.ensureVaultExists(at: url)
            vaultInitMessage = "仓库初始化成功。"
        } catch {
            vaultInitMessage = "初始化失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Private

    private func applyConfig(_ config: RuntimeConfigDTO) {
        provider = config.provider?.isEmpty == false ? config.provider! : "claude"
        currentModel = config.agentModel ?? ""
        currentBaseURL = config.anthropicBaseURL ?? ""
        apiKeyConfigured = config.apiKeyConfigured ?? false
        runtimeEnabled = config.agentRuntimeEnabled ?? false
        tingwuConfigured = config.tingwuConfigured ?? false
        tingwuRegionId = nonEmpty(config.tingwuRegionId) ?? "cn-beijing"
        aliyunAccessKeyIdPreview = config.aliyunAccessKeyIdPreview ?? ""
        aliyunAccessKeySecretConfigured = config.aliyunAccessKeySecretConfigured ?? false
        tingwuAppKeyPreview = config.tingwuAppKeyPreview ?? ""
        resetTingwuDrafts()
    }

    private func resetTingwuDrafts() {
        draftAliyunAccessKeyId = ""
        draftAliyunAccessKeySecret = ""
        draftTingwuAppKey = ""
        draftTingwuRegionId = tingwuRegionId
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private func detectActivePreset() {
        activePresetId = presets.first { preset in
            preset.agentModel == currentModel
                && preset.anthropicBaseURL == currentBaseURL
        }?.id
    }

    private func updateLastUsed(id: UUID) {
        if let index = presets.firstIndex(where: { $0.id == id }) {
            presets[index].lastUsedAt = Date()
            PresetStorage.save(presets)
        }
    }

    static func ensureVaultExists(at url: URL, fileManager: FileManager = .default) throws {
        let dirs = [
            "raw/inbox",
            "raw/sources",
            "raw/assets",
            "wiki/sources",
            "wiki/concepts",
            "wiki/entities",
            "wiki/domains",
            "wiki/synthesis",
            "system",
        ]

        for dir in dirs {
            let dirURL = url.appending(path: dir, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        try writeTemplateIfMissing(at: url.appending(path: "AGENTS.md"), content: defaultAgentsTemplate, fileManager: fileManager)
        try writeTemplateIfMissing(at: url.appending(path: "purpose.md"), content: defaultPurposeTemplate, fileManager: fileManager)
        try writeTemplateIfMissing(at: url.appending(path: "wiki/index.md"), content: defaultIndexTemplate, fileManager: fileManager)
    }

    private static func writeTemplateIfMissing(at url: URL, content: String, fileManager: FileManager) throws {
        guard !fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let defaultAgentsTemplate = """
    # Piki Agent 协议

    本文件是 Piki vault 的执行协议。你是维护这个中文 LLM Wiki 的 Agent。

    你的目标不是临时回答一次问题，而是持续维护一个可复用、可增长、可追溯的知识库。

    ## 1. 角色与目标

    - 你负责读取来源、整理知识、更新页面、维护索引、追加日志、标记冲突。
    - 用户负责提供来源、提出问题、决定是否要把结论沉淀进知识库。
    - 默认优先复用已有 `wiki/`，而不是每次从 `raw/` 全量重读。

    成功标准：

    - 回答主要基于已编译的 `wiki/`。
    - ingest 后，知识进入合适的 `wiki/` 页面，而不是只留下孤立摘要。
    - 知识内容被维护在正确层级：来源内容进 `wiki/sources/`，实体进 `wiki/entities/`，概念进 `wiki/concepts/`，主题域进 `wiki/domains/`，跨来源结论进 `wiki/synthesis/`。
    - `wiki/index.md` 和 `wiki/log.md` 始终同步、可信。
    - 冲突被明确标记，不被静默覆盖。

    ## 2. 读取顺序

    处理任务时，默认遵循以下顺序：

    1. 先读本文件。
    2. 再读 `purpose.md`。
    3. 再读 `wiki/index.md`。
    4. 只有在任务需要时，继续读取相关 `wiki/` 页面。
    5. 只有当 `wiki/` 不足以支撑任务时，才回看相关 `raw/` 来源。
    6. 除非任务明确与 intake 或系统维护有关，否则不要优先读取 `system/`。

    ## 3. 目录职责

    ### 3.1 `raw/`

    `raw/` 是来源归档层，不是主要回答层。

    - `raw/inbox/`：待处理来源入口。
    - `raw/assets/`：原始附件、归档文件。
    - `raw/sources/`：canonical 来源页。

    规则：

    - `raw/` 以归档为主。
    - 不要把 `raw/` 当成长期写作工作区。
    - 不要为了“修正文案”而重写历史来源；优先新增归档、补充说明或在 `wiki/` 中修正理解。

    ### 3.2 `wiki/`

    `wiki/` 是主要知识层，也是默认回答层。

    当前目录约定：

    - `wiki/sources/`：来源页，回答“这个来源说了什么”
    - `wiki/entities/`：实体页，回答“这个实体是谁、做了什么、与什么相关”
    - `wiki/concepts/`：概念页，回答“这个概念是什么、如何与其他知识连接”
    - `wiki/domains/`：主题域页，回答“这个领域的结构和关键页面是什么”
    - `wiki/synthesis/`：综合页，承载跨来源结论、比较和阶段性判断
    - `wiki/index.md`：主导航页
    - `wiki/log.md`：追加式操作日志

    规则：

    - 正常 query 优先依赖 `wiki/`。
    - `wiki/` 中的知识应可复用，避免写成一次性聊天内容。
    - 一个新来源通常应影响多个页面，而不只是一页来源页。

    ### 3.3 `system/`

    非系统维护任务中，不要读取、关注或改动 `system/`。

    ### 3.4 `AGENTS.md`

    - 本文件定义规则，只读。
    - 除非用户明确要求更新协议，否则不要改写本文件。

    ## 4. 硬约束

    以下规则优先级最高：

    - 默认使用中文写作。
    - 标题、摘要、结论、关系说明、综合判断必须以中文为主。
    - 可以保留必要英文术语，但要提供中文上下文。
    - 不要编造事实。
    - 不要静默覆盖冲突结论。
    - 普通 query 默认不写入知识库。
    - 无明确要求时，不要做大范围重写、批量扩写或风格统一。

    ## 5. 标准工作流

    ### 5.1 Query

    当用户只是提问时：

    1. 先读 `wiki/index.md`。
    2. 只读取和问题直接相关的 `wiki/` 页面。
    3. 优先基于 `wiki/` 回答。
    4. 如果 `wiki/` 足够，不要回退到 `raw/`。
    5. 如果 `wiki/` 不足，明确指出知识缺口；仅在必要时回看少量相关来源。

    ### 5.2 Ingest

    当用户的意向是把信息沉淀到知识库中时，执行 ingest。

    典型意向包括：

    - 明确要求“沉淀到知识库”
    - 明确要求“入库”
    - 明确要求“记录这个文档”
    - 明确要求“整理并保存”
    - 明确要求“生成来源页 / 实体页 / 概念页 / 综合页”

    ingest 的目标是把来源编译进 wiki，而不是仅把文件放进仓库。

    标准顺序：

    1. 确认来源材料。
    2. 完成 `raw/` 层归档。
    3. 写入或更新对应的 `wiki/sources/` 页面。
    4. 按需更新相关的 `wiki/entities/`、`wiki/concepts/`、`wiki/domains/`、`wiki/synthesis/`。
    5. 更新 `wiki/index.md`。
    6. 在 `wiki/log.md` 追加记录。

    规则：

    - 新来源不应只改来源页就结束。
    - 要把知识整合进现有页面结构。
    - 如果重要概念或实体频繁出现但还没有页面，应考虑补页。
    - 如果新来源推翻旧判断，应更新相关页面并显式标记变化。

    ### 5.3 Lint / 健康检查

    lint 的目标是发现问题并做定向修复，不是借机重做整个库。

    优先关注：

    - 断裂链接
    - 孤立页
    - 缺失索引项
    - 内容过薄页面
    - 被新来源推翻但未更新的结论
    - 缺少必要交叉链接的页面
    - 提及频繁但尚未成页的重要概念或实体

    规则：

    - 只修复问题直接涉及的页面。
    - 只在必要时修改 `wiki/index.md` 和 `wiki/log.md`。
    - 不要顺手做无关扩写、重构或大规模整理。

    ## 6. 页面写作契约

    所有新写入或显著更新的页面都应满足：

    - 内容可被未来复用。
    - 说明“这是什么”。
    - 说明“与哪些页面相关”。
    - 在有新信息时，说明“新增了什么认识”。
    - 必要时说明“冲突”。

    优先写页面，不优先写聊天腔总结。

    ### 6.1 frontmatter 最小要求

    新页面或显著重写页面时，优先补齐最基本字段。

    - `title`：中文标题
    - `type`：页面类型
    - 按需补充 `tags`
    - 来源页按需补充 `raw_source` 或等价来源字段

    不要为了追求统一而给旧页面批量补字段或强行套模板。

    ## 7. 链接与关系

    - 重要名词首次出现后，若已有对应页面，优先补 `[[wikilink]]`。
    - 新建页面时，主动补至少一个上游或同层链接，避免孤立。
    - 来源页与综合页都应尽量连回相关核心页面。

    ### 7.1 链接写法

    默认使用 Obsidian 风格 `[[wikilink]]`，路径使用 vault 相对路径且不带 `.md`：

    - `[[sources/页面名]]`
    - `[[entities/实体名]]`
    - `[[concepts/概念名]]`
    - `[[domains/领域名]]`
    - `[[synthesis/综合页名]]`

    ### 7.2 何时不要写链接

    如果目标页尚不存在，不要制造断链占位 wikilink。

    - 此时优先写纯文本名称 + `（待创建）`
    - 只有在你准备同时创建目标页时，才写新的 `[[wikilink]]`

    ### 7.3 来源引用

    - 当页面结论明显来自某个来源页时，应在正文相关段落或页尾显式链接对应来源页。
    - 优先引用 `wiki/sources/...`，而不是直接引用 `raw/...`。
    - 只有在需要强调原始归档位置时，才额外提及 `raw/...`。

    ## 8. `wiki/index.md` 规则

    `wiki/index.md` 是主导航，不是时间日志。

    规则：

    - 按类别列出重要页面。
    - 每个条目尽量有一句话摘要。
    - ingest 新页面后同步更新。
    - 新建重要页面但未进入索引，通常视为维护不完整。

    ### 8.1 索引条目格式

    优先使用下面这种格式：

    `- [[category/页面名]] — 一句话摘要。`

    例如：

    `- [[concepts/大模型维基]] — 把原始资料编译成持久 wiki 的核心概念。`

    规则：

    - 每个条目只写一句高密度摘要。
    - 摘要优先写“这页解决什么问题”，不要写空泛描述。
    - 分类标题与真实目录保持一致，如 `sources`、`concepts`、`entities`、`domains`、`synthesis`。

    ## 9. `wiki/log.md` 规则

    `wiki/log.md` 是时间导向的追加日志。

    规则：

    - 只追加，不重写旧记录。
    - 标题格式固定为：

    `## [YYYY-MM-DD] 操作 | 简短标题`

    - 单条日志应尽量写清：
      - 来源或任务是什么
      - 修改了哪些路径
      - 做了什么类型的知识更新

    ### 9.1 日志内容格式

    标题下优先使用短列表记录，而不是长段落。

    建议格式：

    ```markdown
    ## [YYYY-MM-DD] 操作 | 简短标题

    - 来源/任务：...
    - 修改路径：`wiki/...`、`raw/...`
    - 结果：...
    ```

    规则：

    - 日志记录事实，不写聊天口吻。
    - 修复类日志要写清问题和修复结果。
    - ingest 类日志至少写清来源和新增/更新页面。

    ## 10. 冲突与不确定性处理

    遇到冲突时：

    - 不要静默覆盖旧说法。
    - 在相关页面明确写出冲突点。
    - 如果可以判断新旧优先级，说明依据。
    - 如果不能判断，保留多种说法并标记待复核。

    ## 11. 执行前自检

    在完成一轮任务前，自检以下问题：

    - 是否优先使用了 `wiki/` 而不是盲目重扫 `raw/`？
    - 如果做了 ingest，是否同步更新了来源页、索引和日志？
    - 如果做了写入，内容是否可复用，而不是聊天原话转存？
    - 如果发现冲突，是否明确标记？
    - 是否避免了与当前任务无关的大范围改动？
    """

    private static let defaultPurposeTemplate = """
    # Purpose

    Describe this vault's purpose.
    """

    private static let defaultIndexTemplate = """
    # Wiki Index

    Welcome to your Piki vault.

    ## Categories
    - [Sources](sources/)
    - [Concepts](concepts/)
    - [Entities](entities/)
    - [Domains](domains/)
    - [Synthesis](synthesis/)
    """

}
