import Cocoa
import LeafReaderCore

extension AISettingsPanelController {
    /// Saves the panel, then round-trips one message. Driven by the SwiftUI
    /// Model page, which owns the button's disabled state.
    func testChatConnection() {
        guard let panel, let modelSettings else { return }
        guard saveCurrentSettings(in: panel) else { return }
        modelSettings.isTestingConnection = true
        AIClient().send(messages: [
            ChatMessage(role: "system", content: "Reply with OK only."),
            ChatMessage(role: "user", content: "connection test")
        ]) { [weak self] result in
            DispatchQueue.main.async {
                self?.modelSettings?.isTestingConnection = false
                self?.showConnectionResult(result, successMessage: AppText.localized("模型连接正常。", "Chat model connection works."))
            }
        }
    }

    /// Saves the panel, then embeds one probe string. Driven by the SwiftUI
    /// AI Analysis page, which owns the button's disabled state.
    func testEmbeddingConnection() {
        guard let panel, let embeddingSettings else { return }
        guard saveCurrentSettings(in: panel) else { return }
        guard let config = EmbeddingClient.configFromCurrentAISettings() else {
            let result: Result<String, Error> = .failure(NSError(domain: "embedding", code: -1, userInfo: [
                NSLocalizedDescriptionKey: AppText.localized("请先配置向量 API Key，或选择本地向量接口。", "Configure an embedding API key first, or choose a local embedding endpoint.")
            ]))
            showConnectionResult(result, successMessage: "")
            return
        }
        embeddingSettings.isTestingConnection = true
        EmbeddingClient().embed(texts: ["Leaf Reader connection test."], config: config) { [weak self] result in
            DispatchQueue.main.async {
                self?.embeddingSettings?.isTestingConnection = false
                self?.showConnectionResult(result.map { "\($0.first?.count ?? 0)" }, successMessage: AppText.localized("向量连接正常。", "Embedding connection works."))
            }
        }
    }

    func showConnectionResult<T>(_ result: Result<T, Error>, successMessage: String) {
        let alert = NSAlert()
        switch result {
        case .success:
            alert.messageText = AppText.localized("测试成功", "Test Succeeded")
            alert.informativeText = successMessage
            alert.alertStyle = .informational
            alert.icon = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        case .failure(let error):
            alert.messageText = AppText.localized("测试失败", "Test Failed")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        }
        alert.addButton(withTitle: AppText.confirm)
        alert.applyLeafStyle()
        if let panel {
            alert.beginSheetModal(for: panel)
        } else {
            alert.runModal()
        }
    }
}
