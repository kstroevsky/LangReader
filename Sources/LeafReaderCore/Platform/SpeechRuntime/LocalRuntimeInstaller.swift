import Foundation

package struct LocalRuntimeInstaller {
    package let plan: LocalRuntimeDownloadPlan
    package let install: (URL) throws -> Void

    package init(
        plan: LocalRuntimeDownloadPlan,
        install: @escaping (URL) throws -> Void
    ) {
        self.plan = plan
        self.install = install
    }

    package func installDownloadedArchive(_ archiveURL: URL, asset: LocalRuntimeDownloadManifestAsset?) throws {
        try LocalRuntimeDownloadSupport.validateArchive(at: archiveURL)
        try LocalRuntimeDownloadSupport.validateArchiveManifest(archiveURL, asset: asset)
        try LocalRuntimeDownloadSupport.validateAvailableDiskSpace(for: plan, archiveURL: archiveURL, asset: asset)
        try install(archiveURL)
    }
}
