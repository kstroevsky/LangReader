import Foundation

package struct ChatMessage: Codable, Sendable {
    package let role: String
    package let content: String
    package let linkID: String?

    package init(role: String, content: String, linkID: String? = nil) {
        self.role = role
        self.content = content
        self.linkID = linkID
    }
}

package struct TranscriptEntry: Codable {
    package let role: String
    package let content: String
    package let linkID: String?

    package init(role: String, content: String, linkID: String? = nil) {
        self.role = role
        self.content = content
        self.linkID = linkID
    }
}

package enum AppText {
    package enum Language: String, CaseIterable {
        case system
        case chinese
        case english

        package var title: String {
            switch self {
            case .system:
                return AppText.localized("跟随系统", "System")
            case .chinese:
                return "中文"
            case .english:
                return "English"
            }
        }
    }

    package static let languageDefaultsKey = "appLanguage"

    package static var selectedLanguage: Language {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: languageDefaultsKey),
                  let language = Language(rawValue: rawValue) else {
                return .system
            }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageDefaultsKey)
            UserDefaults.standard.synchronize()
        }
    }

    package static var isChinese: Bool {
        switch selectedLanguage {
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        case .chinese:
            return true
        case .english:
            return false
        }
    }

    package static func localized(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }

    package static var askAI: String { localized("✨ 语言助手", "✨ Language Assistant") }
    package static var explainPrefix: String { localized("解释", "Explain") }
    package static var userRole: String { localized("我", "Me") }
    package static var aiRole: String { "AI" }
    package static var errorRole: String { localized("错误", "Error") }
    package static var none: String { localized("（暂无）", "(None)") }
    package static var thinking: String { localized("正在思考...", "Thinking...") }
    package static var generating: String { localized("正在生成...", "Generating...") }
    package static var tapToExpand: String { localized("点击展开/收起", "Click to expand/collapse") }
    package static var followUpPlaceholder: String { localized("继续追问", "Ask a follow-up") }
    package static var send: String { localized("发送", "Send") }
    package static var noPDF: String { localized("没有加载书籍", "No book loaded") }
    package static var fullScreen: String { localized("全屏", "Full") }
    package static var windowed: String { localized("窗口", "Window") }
    package static var cover: String { localized("首页", "Cover") }
    package static var prev: String { localized("上一页", "Prev") }
    package static var next: String { localized("下一页", "Next") }
    package static var settings: String { localized("设置", "Settings") }
    package static var close: String { localized("关闭", "Close") }
    package static var model: String { localized("模型", "Model") }
    package static var modelHelp: String { localized("选择你要使用的 AI 模型。", "Choose the AI model you want to use.") }
    package static var language: String { localized("语言", "Language") }
    package static var languageHelp: String { localized("选择界面语言和 AI 回答语言。", "Choose the UI language and AI response language.") }
    package static var apiKeyPlaceholder: String { localized("请输入你的 API Key", "Enter your API Key") }
    package static var keyHelp: String {
        localized("你的 API Key 将安全存储，仅用于你自己的请求。", "Your API Key is stored locally and only used for your own requests.")
    }
    package static var showAPIKey: String { localized("显示 API Key", "Show API Key") }
    package static var hideAPIKey: String { localized("隐藏 API Key", "Hide API Key") }
    package static var cancel: String { localized("取消", "Cancel") }
    package static var confirm: String { localized("确认", "Confirm") }
}
