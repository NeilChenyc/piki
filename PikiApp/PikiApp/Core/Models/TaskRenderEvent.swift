import Foundation

enum TaskRenderEvent {
    case progress(stage: String, title: String, detail: String, category: String)
    case answerDelta(String)
    case traceDelta(String)
    case trace(kind: String, title: String, summary: String, category: String?, status: String?)
    case toolStarted(key: String, title: String, summary: String, category: String)
    case toolFinished(key: String, title: String, summary: String, category: String, status: String)
    case inputRequired(taskId: String?, prompt: String?)
    case inputResolved
    case completed(content: String?)
    case cancelled(content: String?)
    case failed(TaskFailurePresentation)
    case runStarted
    case runCompleted(preview: String?)
    case ignored(statusText: String?)
}

extension TaskEvent {
    var renderEvent: TaskRenderEvent {
        switch type {
        case "agent.progress":
            return .progress(
                stage: payload.stage ?? payload.title ?? "progress",
                title: payload.title ?? "正在继续处理",
                detail: payload.detail ?? "",
                category: payload.category ?? "model"
            )
        case "message.delta":
            return .answerDelta(payload.delta ?? "")
        case "agent.trace.delta":
            return .traceDelta(payload.delta ?? "")
        case "agent.trace.event":
            return .trace(
                kind: payload.kind ?? "event",
                title: payload.title ?? "Agent 事件",
                summary: payload.summary ?? payload.detail ?? "",
                category: payload.category,
                status: payload.status
            )
        case "tool.started":
            return .toolStarted(
                key: renderToolKey,
                title: payload.title ?? renderTraceTitle,
                summary: payload.summary ?? payload.tool ?? "",
                category: payload.category ?? "tool"
            )
        case "tool.finished":
            return .toolFinished(
                key: renderToolKey,
                title: payload.title ?? "工具调用完成",
                summary: payload.summary ?? payload.tool ?? "",
                category: payload.category ?? "tool",
                status: "completed"
            )
        case "tool.failed":
            return .toolFinished(
                key: renderToolKey,
                title: payload.title ?? "工具调用失败",
                summary: payload.error ?? payload.tool ?? "",
                category: payload.category ?? "tool",
                status: "failed"
            )
        case "task.completed":
            return .completed(content: payload.answer ?? payload.summary ?? payload.content)
        case "task.cancelled":
            return .cancelled(content: payload.summary ?? payload.content)
        case "task.failed":
            return .failed(payload.failurePresentation)
        case "agent.run.started":
            return .runStarted
        case "agent.run.completed":
            return .runCompleted(preview: payload.finalOutputPreview)
        case "agent.input_requested":
            return .inputRequired(
                taskId: taskId.isEmpty ? nil : taskId,
                prompt: payload.pendingInput?.prompt ?? payload.prompt ?? payload.detail ?? payload.summary
            )
        case "agent.input_resolved":
            return .inputResolved
        default:
            return .ignored(statusText: type.hasSuffix(".started") ? renderFriendlyStatus : nil)
        }
    }

    var renderTraceTitle: String {
        switch payload.category {
        case "read": return "正在阅读 Wiki"
        case "write": return "正在写入 Wiki"
        case "command": return "正在转换文档"
        case "convert": return "正在转换文档"
        default: return payload.title ?? "Agent 事件"
        }
    }

    var renderFriendlyStatus: String {
        switch type {
        case "source_intake.started": return "正在整理资料"
        case "ingest.started": return "正在整理资料"
        case "agent.run.started": return "正在思考和生成"
        default: return "正在处理"
        }
    }

    var renderToolKey: String {
        if let toolUseId = payload.toolUseId, !toolUseId.isEmpty {
            return "tool_use:\(toolUseId)"
        }
        let tool = payload.tool ?? payload.category ?? "tool"
        let subject = renderToolSubject
        if !subject.isEmpty {
            return "tool:\(tool):\(subject)"
        }
        let title = payload.title ?? renderTraceTitle
        let summary = payload.summary ?? payload.tool ?? ""
        return "tool:\(tool):\(title):\(summary)"
    }

    private var renderToolSubject: String {
        let raw = (
            payload.sourcePath
            ?? payload.summary
            ?? payload.detail
            ?? payload.tool
            ?? ""
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !raw.isEmpty else { return "" }

        if raw.contains("system/source_manifest.json") {
            return "内部来源索引（source_manifest）"
        }

        let prefixes = ["Read：", "Read:", "Write：", "Write:", "Edit：", "Edit:", "Glob：", "Glob:", "Grep：", "Grep:"]
        let cleaned = prefixes.reduce(raw) { partial, prefix in
            partial.hasPrefix(prefix) ? String(partial.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) : partial
        }

        for marker in ["wiki/", "raw/", "inbox/", "system/"] {
            if let range = cleaned.range(of: marker) {
                return String(cleaned[range.lowerBound...])
            }
        }

        let normalizedPath = cleaned.replacingOccurrences(of: "\\", with: "/")
        let components = normalizedPath.split(separator: "/")
        if components.count >= 3 {
            return components.suffix(3).joined(separator: "/")
        }
        return cleaned
    }
}
