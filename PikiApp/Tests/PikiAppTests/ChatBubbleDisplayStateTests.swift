import Foundation
import Testing
@testable import PikiApp

@Suite("Chat bubble display state")
struct ChatBubbleDisplayStateTests {
    @Test
    func collapsedStatePrefersRunningTraceItem() {
        let message = ChatMessage(
            id: "assistant-1",
            role: .assistant,
            content: "",
            timestamp: .now,
            traceItems: [
                ChatTraceItem(
                    key: "run",
                    kind: "agent_run",
                    title: "正在思考",
                    summary: "规划中",
                    category: "model",
                    status: "completed"
                ),
                ChatTraceItem(
                    key: "tool",
                    kind: "tool_started",
                    title: "搜索文件",
                    summary: "正在检索",
                    category: "read",
                    status: "running"
                )
            ],
            isRunning: true,
            isTraceExpanded: false,
            hasStartedAnswering: false,
            isAgentRun: true,
            runStatus: "running"
        )

        let state = ChatBubbleDisplayState(message: message)

        #expect(!state.shouldShowTraceSummaryRow)
        #expect(!state.shouldShowExpandedTraceHistory)
        #expect(state.currentTraceItem?.title == "搜索文件")
        #expect(state.headerStatusText == "搜索文件")
    }

    @Test
    func collapsedCompletedStateFallsBackToLastTraceItem() {
        let message = ChatMessage(
            id: "assistant-2",
            role: .assistant,
            content: "done",
            timestamp: .now,
            traceItems: [
                ChatTraceItem(
                    key: "run",
                    kind: "agent_run",
                    title: "正在思考",
                    summary: "规划中",
                    category: "model",
                    status: "completed"
                ),
                ChatTraceItem(
                    key: "finish",
                    kind: "tool_finished",
                    title: "整理回答",
                    summary: "已完成",
                    category: "write",
                    status: "completed"
                )
            ],
            isRunning: false,
            isTraceExpanded: false,
            hasStartedAnswering: true,
            isAgentRun: true,
            runStatus: "completed"
        )

        let state = ChatBubbleDisplayState(message: message)

        #expect(!state.shouldShowTraceSummaryRow)
        #expect(!state.shouldShowExpandedTraceHistory)
        #expect(state.currentTraceItem?.title == "整理回答")
        #expect(state.headerStatusText == "整理回答")
    }

    @Test
    func assistantAgentRunUsesPikiHeaderLabel() {
        let message = ChatMessage(
            id: "assistant-3",
            role: .assistant,
            content: "hello",
            timestamp: .now,
            traceItems: [],
            isRunning: false,
            isTraceExpanded: false,
            hasStartedAnswering: true,
            isAgentRun: true,
            runStatus: "completed"
        )

        let state = ChatBubbleDisplayState(message: message)

        #expect(state.headerTitle == "piki")
    }

    @Test
    func runningAgentRunPromotesCurrentTraceTitleIntoHeader() {
        let message = ChatMessage(
            id: "assistant-4",
            role: .assistant,
            content: "",
            timestamp: .now,
            traceItems: [
                ChatTraceItem(
                    key: "run",
                    kind: "agent_run",
                    title: "正在分析上下文",
                    summary: "读取文件中",
                    category: "model",
                    status: "running"
                )
            ],
            isRunning: true,
            isTraceExpanded: false,
            hasStartedAnswering: false,
            isAgentRun: true,
            runStatus: "running"
        )

        let state = ChatBubbleDisplayState(message: message)

        #expect(state.headerStatusText == "正在分析上下文")
        #expect(!state.shouldShowTraceSummaryRow)
        #expect(state.shouldAnimateHeaderStatusText)
    }

    @Test
    func completedAgentRunDoesNotAnimateHeaderStatusText() {
        let message = ChatMessage(
            id: "assistant-4b",
            role: .assistant,
            content: "已完成",
            timestamp: .now,
            traceItems: [
                ChatTraceItem(
                    key: "run",
                    kind: "agent_run",
                    title: "正在分析上下文",
                    summary: "读取文件中",
                    category: "model",
                    status: "completed"
                )
            ],
            isRunning: false,
            isTraceExpanded: false,
            hasStartedAnswering: true,
            isAgentRun: true,
            runStatus: "completed"
        )

        let state = ChatBubbleDisplayState(message: message)

        #expect(!state.shouldAnimateHeaderStatusText)
    }

    @Test
    func runningAgentRunPrefersReasoningTraceAsPreviewContent() {
        let message = ChatMessage(
            id: "assistant-5",
            role: .assistant,
            content: "",
            timestamp: .now,
            traceItems: [
                ChatTraceItem(
                    key: "run",
                    kind: "agent_run",
                    title: "正在思考",
                    summary: "规划中",
                    category: "model",
                    status: "running"
                ),
                ChatTraceItem(
                    key: "reasoning",
                    kind: "model_delta",
                    title: "思考过程",
                    summary: "先检查当前 wiki 结构，再决定是否需要读取附件。",
                    category: "model",
                    status: "running"
                )
            ],
            isRunning: true,
            isTraceExpanded: false,
            hasStartedAnswering: false,
            isAgentRun: true,
            runStatus: "running"
        )

        let state = ChatBubbleDisplayState(message: message)

        #expect(state.runningReasoningPreview == "先检查当前 wiki 结构，再决定是否需要读取附件。")
        #expect(state.runningFallbackText == nil)
    }

    @Test
    func runningAgentRunFallsBackToLegacyPlaceholderWhenNoReasoningPreviewExists() {
        let message = ChatMessage(
            id: "assistant-6",
            role: .assistant,
            content: "",
            timestamp: .now,
            traceItems: [
                ChatTraceItem(
                    key: "tool",
                    kind: "tool_started",
                    title: "正在阅读 Wiki",
                    summary: "wiki/index.md",
                    category: "read",
                    status: "running"
                )
            ],
            isRunning: true,
            isTraceExpanded: false,
            hasStartedAnswering: false,
            isAgentRun: true,
            runStatus: "running"
        )

        let state = ChatBubbleDisplayState(message: message)

        #expect(state.runningReasoningPreview == nil)
        #expect(state.runningFallbackText == "正在执行本轮任务…")
    }

    @Test
    func completedAgentRunDoesNotShowReasoningPreview() {
        let message = ChatMessage(
            id: "assistant-7",
            role: .assistant,
            content: "最终回复",
            timestamp: .now,
            traceItems: [
                ChatTraceItem(
                    key: "reasoning",
                    kind: "model_delta",
                    title: "思考过程",
                    summary: "中间推理",
                    category: "model",
                    status: "completed"
                )
            ],
            isRunning: false,
            isTraceExpanded: false,
            hasStartedAnswering: true,
            isAgentRun: true,
            runStatus: "completed"
        )

        let state = ChatBubbleDisplayState(message: message)

        #expect(state.runningReasoningPreview == nil)
        #expect(state.runningFallbackText == nil)
    }
}
