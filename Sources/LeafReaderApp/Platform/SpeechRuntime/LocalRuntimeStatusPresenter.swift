import Foundation
import LeafReaderCore

package struct LocalRuntimeStatusContext {
    package let descriptor: LocalRuntimeDescriptor
    package let installState: LocalRuntimeInstallState
    package let isSupported: Bool
    package let isDownloading: Bool
    package let isPaused: Bool
    package let downloadFailureMessage: String?
    package let inferenceFailureText: String?

    package init(
        descriptor: LocalRuntimeDescriptor,
        installState: LocalRuntimeInstallState,
        isSupported: Bool,
        isDownloading: Bool,
        isPaused: Bool,
        downloadFailureMessage: String?,
        inferenceFailureText: String?
    ) {
        self.descriptor = descriptor
        self.installState = installState
        self.isSupported = isSupported
        self.isDownloading = isDownloading
        self.isPaused = isPaused
        self.downloadFailureMessage = downloadFailureMessage
        self.inferenceFailureText = inferenceFailureText
    }
}

/// Formats runtime installation state for settings and owns its localized copy.
package enum LocalRuntimeStatusPresenter {
    package static func availabilityText(
        isSupported: Bool,
        downloaded: Bool,
        minimumSystemVersionText: String
    ) -> String? {
        guard !(isSupported && downloaded) else { return nil }
        if !isSupported {
            return AppText.localized(
                "需要 \(minimumSystemVersionText)",
                "Requires \(minimumSystemVersionText)"
            )
        }
        if downloaded {
            return AppText.localized("文件不完整", "Incomplete files")
        }
        return AppText.localized("未下载", "Not downloaded")
    }

    package static func statusText(_ context: LocalRuntimeStatusContext) -> String {
        let descriptor = context.descriptor
        let size = descriptor.downloadSizeText
        let summary = descriptor.summaryText
        if context.isDownloading {
            if context.isPaused {
                return AppText.localized("已暂停 · \(size)", "Paused · \(size)")
            }
            return AppText.localized("下载中 · \(size)", "Downloading · \(size)")
        }
        if !context.isSupported {
            if context.installState == .complete {
                return AppText.localized(
                    "已下载 · 需要 \(descriptor.minimumSystemVersionText) 或更高",
                    "Downloaded · Requires \(descriptor.minimumSystemVersionText) or later"
                )
            }
            if let failure = context.downloadFailureMessage {
                return AppText.localized(
                    "未下载 · \(summary) · 需要 \(descriptor.minimumSystemVersionText) 或更高 · \(size) · 上次失败：\(failure)",
                    "Not downloaded · \(summary) · Requires \(descriptor.minimumSystemVersionText) or later · \(size) · Last failed: \(failure)"
                )
            }
            return AppText.localized(
                "未下载 · \(summary) · 需要 \(descriptor.minimumSystemVersionText) 或更高 · \(size)",
                "Not downloaded · \(summary) · Requires \(descriptor.minimumSystemVersionText) or later · \(size)"
            )
        }
        if context.installState == .complete {
            if let failure = context.inferenceFailureText {
                return AppText.localized(
                    "已安装 · \(size) · \(failure)",
                    "Installed · \(size) · \(failure)"
                )
            }
            return AppText.localized("已安装 · \(size)", "Installed · \(size)")
        }
        if let text = incompleteInstallStatusText(descriptor: descriptor, installState: context.installState) {
            return text
        }
        if let failure = context.downloadFailureMessage {
            return AppText.localized(
                "未下载 · \(summary) · \(size) · 上次失败：\(failure)",
                "Not downloaded · \(summary) · \(size) · Last failed: \(failure)"
            )
        }
        return AppText.localized("未下载 · \(summary) · \(size)", "Not downloaded · \(summary) · \(size)")
    }

    package static func incompleteInstallStatusText(
        descriptor: LocalRuntimeDescriptor,
        installState: LocalRuntimeInstallState
    ) -> String? {
        switch installState {
        case .missingRuntime:
            return AppText.localized(
                "缺少运行时 · 模型已安装 · \(descriptor.downloadSizeText)",
                "Missing runtime · Model installed · \(descriptor.downloadSizeText)"
            )
        case .missingModel:
            return AppText.localized(
                "运行时已安装 · 缺少模型 · \(descriptor.downloadSizeText)",
                "Runtime installed · Missing model · \(descriptor.downloadSizeText)"
            )
        case .missingRuntimeAndModel:
            return AppText.localized(
                "缺少运行时和模型 · \(descriptor.summaryText) · \(descriptor.downloadSizeText)",
                "Missing runtime and model · \(descriptor.summaryText) · \(descriptor.downloadSizeText)"
            )
        case .complete:
            return nil
        }
    }
}
