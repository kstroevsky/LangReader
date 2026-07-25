import Cocoa

extension AISettingsPanelController {
    func showValidationAlert(message: String, in panel: NSWindow) {
        let alert = NSAlert()
        alert.messageText = AppText.localized("设置无效", "Invalid Settings")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.confirm)
        alert.applyLeafStyle()
        alert.beginSheetModal(for: panel)
    }
}
