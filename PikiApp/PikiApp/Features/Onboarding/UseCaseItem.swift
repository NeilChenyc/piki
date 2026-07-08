import Foundation

struct UseCaseItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let description: String
    let starterPrompt: String

    static let allCases: [UseCaseItem] = [
        UseCaseItem(
            id: "book-notes",
            icon: "book.closed",
            title: "读书笔记",
            description: "上传读书笔记或摘录，自动提取核心概念并整理进知识库。",
            starterPrompt: "请帮我整理这份读书笔记，提取核心概念并建立相关 wiki 页面。"
        ),
        UseCaseItem(
            id: "podcast",
            icon: "mic",
            title: "播客内容",
            description: "上传播客链接或文稿，自动整理并沉淀进知识库。",
            starterPrompt: "请帮我整理这期播客的内容，提取要点并沉淀到知识库。"
        ),
        UseCaseItem(
            id: "article",
            icon: "doc.richtext",
            title: "文章与资料",
            description: "导入文章或 Markdown 文件，把知识沉淀为自己的资产。",
            starterPrompt: "请帮我 ingest 这份资料并整理进知识库。"
        ),
    ]
}
