import Cocoa
import LeafReaderCore

extension AISettingsPanelController {
    func startCurrentVectorIndex() {
        guard let panel, saveCurrentSettings(in: panel) else { return }
        onStartVectorIndex?()
        refreshCurrentVectorIndexStatus()
    }

    func toggleCurrentVectorIndex() {
        onToggleVectorIndexPaused?()
        refreshCurrentVectorIndexStatus()
    }

    func cancelCurrentVectorIndex() {
        onCancelVectorIndex?()
        refreshCurrentVectorIndexStatus()
    }

    func clearCurrentVectorIndex() {
        onClearCurrentVectorIndex?()
        refreshCurrentVectorIndexStatus()
        refreshVectorCacheStatus()
    }

    func refreshCurrentVectorIndexStatus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.cacheSettings?.refresh(currentBookStatus: self.currentVectorIndexStatus?() ?? AppText.noPDF)
            self.refreshVectorCacheStatus()
        }
    }

    func startCacheRefreshTimer() {
        cacheRefreshTimer?.invalidate()
        cacheRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.panel?.isVisible == true else { return }
                self.cacheSettings?.refresh(currentBookStatus: self.currentVectorIndexStatus?() ?? AppText.noPDF)
                self.refreshVectorCacheStatus()
            }
        }
    }

    func closePanel(notifySaved: Bool) {
        guard let panel, !isClosing else { return }
        isClosing = true
        shouldNotifySavedAfterClose = notifySaved
        cacheRefreshTimer?.invalidate()
        cacheRefreshTimer = nil
        speechVoicePreviewWorkItem?.cancel()
        speechVoicePreviewWorkItem = nil
        removeAppActivationObserver()
        if let sheet = panel.attachedSheet {
            panel.endSheet(sheet)
            sheet.orderOut(nil)
        }
        ModalOverlayManager.shared.dismiss(panel, attachedTo: parentWindow)
        self.panel = nil
        isClosing = false
        let shouldNotifySaved = shouldNotifySavedAfterClose
        shouldNotifySavedAfterClose = false
        if shouldNotifySaved {
            DispatchQueue.main.async { [weak self] in
                self?.onSaved?()
            }
        }
    }

    func closeWithoutSaving() {
        closePanel(notifySaved: false)
    }

    func clearVectorCache() {
        let alert = NSAlert()
        alert.messageText = AppText.localized("清除全部 AI 分析缓存？", "Clear all AI analysis cache?")
        alert.informativeText = AppText.localized(
            "这会删除本机所有书籍的向量分析缓存。之后再次使用文档问答时，会按需重新生成。",
            "This deletes vector analysis cache for all books on this Mac. It will be rebuilt on demand when document Q&A is used again."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.localized("清除", "Clear"))
        alert.addButton(withTitle: AppText.cancel)
        alert.applyLeafStyle()
        guard let panel else { return }
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.cacheSettings?.refresh(cacheStatus: AppText.localized("正在清除分析缓存...", "Clearing analysis cache..."))
            self?.vectorCacheQueue.async { [weak self] in
                PDFEmbeddingStore()?.deleteAll()
                DispatchQueue.main.async {
                    self?.refreshVectorCacheStatus()
                }
            }
        }
    }

    func refreshVectorCacheStatus() {
        vectorCacheQueue.async { [weak self] in
            let text = Self.vectorCacheStatusText()
            DispatchQueue.main.async { [weak self] in
                guard self?.panel?.isVisible == true else { return }
                self?.cacheSettings?.refresh(cacheStatus: text)
            }
        }
    }

    nonisolated static func vectorCacheStatusText() -> String {
        guard let store = PDFEmbeddingStore() else {
            return AppText.localized("缓存不可用", "Cache unavailable")
        }
        let size = formatBytes(store.cacheSizeBytes())
        let count = store.documentCount()
        return AppText.localized(
            "\(size) · \(count) 本书 · 超过 1GB 自动清理",
            "\(size) · \(count) books · Auto-cleans over 1GB"
        )
    }

    nonisolated static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(value)) \(units[index])"
        }
        return String(format: "%.1f %@", value, units[index])
    }
}
