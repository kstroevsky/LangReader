import Foundation

package enum LocalRuntimeFamily: String, Codable, Hashable {
    case speech
    case localLLM
}

package struct LocalRuntimeInstallManifest: Codable, Equatable {
    package let family: LocalRuntimeFamily
    package let runtimeID: String
    package let cacheDirectoryPaths: [String]

    package init(family: LocalRuntimeFamily, runtimeID: String, cacheDirectoryPaths: [String]) {
        self.family = family
        self.runtimeID = runtimeID
        self.cacheDirectoryPaths = cacheDirectoryPaths
    }

    package init(runtimeID: String, cacheDirectoryPaths: [String]) {
        self.init(family: .speech, runtimeID: runtimeID, cacheDirectoryPaths: cacheDirectoryPaths)
    }

    package init(legacySpeechRuntimeID runtimeID: String, cacheDirectoryPaths: [String]) {
        self.init(family: .speech, runtimeID: runtimeID, cacheDirectoryPaths: cacheDirectoryPaths)
    }

    private enum CodingKeys: String, CodingKey {
        case family
        case runtimeID
        case cacheDirectoryPaths
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        family = try container.decodeIfPresent(LocalRuntimeFamily.self, forKey: .family) ?? .speech
        runtimeID = try container.decode(String.self, forKey: .runtimeID)
        cacheDirectoryPaths = try container.decode([String].self, forKey: .cacheDirectoryPaths)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(family, forKey: .family)
        try container.encode(runtimeID, forKey: .runtimeID)
        try container.encode(cacheDirectoryPaths, forKey: .cacheDirectoryPaths)
    }
}

package enum LocalRuntimeInstallState: Equatable {
    case complete
    case missingRuntime
    case missingModel
    case missingRuntimeAndModel

    package static func state(hasRuntime: Bool, hasModel: Bool) -> LocalRuntimeInstallState {
        switch (hasRuntime, hasModel) {
        case (true, true):
            return .complete
        case (false, true):
            return .missingRuntime
        case (true, false):
            return .missingModel
        case (false, false):
            return .missingRuntimeAndModel
        }
    }
}

package struct LocalRuntimeDescriptor {
    package let family: LocalRuntimeFamily
    package let id: String
    package let title: String
    package let summaryText: String
    package let downloadSizeText: String
    package let minimumSystemVersion: OperatingSystemVersion
    package let minimumSystemVersionText: String
    package let downloadURL: URL
    package let manifestURL: URL?
    package let installDirectory: URL
    package let bundledInstallDirectory: URL?
    package let installDirectories: [URL]
    package let executableURL: URL
    package let bundledExecutableURL: URL?
    package let modelDirectory: URL
    package let requiredPaths: [URL]

    package init(
        family: LocalRuntimeFamily,
        id: String,
        title: String,
        summaryText: String,
        downloadSizeText: String,
        minimumSystemVersion: OperatingSystemVersion,
        minimumSystemVersionText: String,
        downloadURL: URL,
        manifestURL: URL?,
        installDirectory: URL,
        bundledInstallDirectory: URL?,
        installDirectories: [URL],
        executableURL: URL,
        bundledExecutableURL: URL?,
        modelDirectory: URL,
        requiredPaths: [URL]
    ) {
        self.family = family
        self.id = id
        self.title = title
        self.summaryText = summaryText
        self.downloadSizeText = downloadSizeText
        self.minimumSystemVersion = minimumSystemVersion
        self.minimumSystemVersionText = minimumSystemVersionText
        self.downloadURL = downloadURL
        self.manifestURL = manifestURL
        self.installDirectory = installDirectory
        self.bundledInstallDirectory = bundledInstallDirectory
        self.installDirectories = installDirectories
        self.executableURL = executableURL
        self.bundledExecutableURL = bundledExecutableURL
        self.modelDirectory = modelDirectory
        self.requiredPaths = requiredPaths
    }
}

package struct LocalRuntimeDownloadPlan {
    package let descriptor: LocalRuntimeDescriptor
    package let archiveURL: URL
    package let manifestURL: URL?
    package let expectedAssetName: String

    package init(
        descriptor: LocalRuntimeDescriptor,
        archiveURL: URL,
        manifestURL: URL?,
        expectedAssetName: String
    ) {
        self.descriptor = descriptor
        self.archiveURL = archiveURL
        self.manifestURL = manifestURL
        self.expectedAssetName = expectedAssetName
    }
}

package struct LocalRuntimeDownloadKey: Hashable {
    package let family: LocalRuntimeFamily
    package let id: String

    package init(family: LocalRuntimeFamily, id: String) {
        self.family = family
        self.id = id
    }

    package init(descriptor: LocalRuntimeDescriptor) {
        self.init(family: descriptor.family, id: descriptor.id)
    }
}

package struct LocalRuntimeRegistry {
    package let downloadPlans: [LocalRuntimeDownloadPlan]

    package var descriptors: [LocalRuntimeDescriptor] {
        downloadPlans.map(\.descriptor)
    }

    package init(downloadPlans: [LocalRuntimeDownloadPlan]) {
        self.downloadPlans = downloadPlans
    }

    package func descriptor(family: LocalRuntimeFamily, id: String) -> LocalRuntimeDescriptor? {
        descriptors.first { $0.family == family && $0.id == id }
    }

    package func downloadPlan(family: LocalRuntimeFamily, id: String) -> LocalRuntimeDownloadPlan? {
        downloadPlans.first { $0.descriptor.family == family && $0.descriptor.id == id }
    }
}

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
