import TipKit

struct HomeTip: Tip {
    var title: Text { Text("主要交互入口") }
    var message: Text? { Text("在这里上传文件、提问或运行健康检查，Piki 帮你把信息沉淀为知识。") }
    var image: Image? { Image(systemName: "house.fill") }
}

struct InboxTip: Tip {
    var title: Text { Text("资料箱") }
    var message: Text? { Text("拖入文件到这里，Piki 会帮你整理并编入知识库。") }
    var image: Image? { Image(systemName: "tray.fill") }
}

struct WikiTip: Tip {
    var title: Text { Text("知识浏览") }
    var message: Text? { Text("已整理的知识在这里浏览，页面之间自动建立交叉引用。") }
    var image: Image? { Image(systemName: "book.fill") }
}

struct SettingsTip: Tip {
    var title: Text { Text("配置管理") }
    var message: Text? { Text("在这里配置大模型 API、选择知识仓库路径、管理配置模板。") }
    var image: Image? { Image(systemName: "slider.horizontal.3") }
}
