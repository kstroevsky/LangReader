import Foundation
import LeafReaderCore

typealias SpeechModelManifest = LocalRuntimeDownloadManifest

extension SpeechRuntimeResourceManager {
    static func decodeModelManifest(_ data: Data) throws -> SpeechModelManifest {
        try JSONDecoder().decode(SpeechModelManifest.self, from: data)
    }

    static func bundledModelManifest() -> SpeechModelManifest? {
        guard let url = Bundle.main.url(forResource: "speech-models-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decodeModelManifest(data)
    }

    static func modelManifestDecodeResult(
        data: Data,
        bundledManifest: SpeechModelManifest?
    ) -> Result<SpeechModelManifest?, Error> {
        do {
            return .success(try decodeModelManifest(data))
        } catch {
            if let bundledManifest {
                NSLog(
                    "LeafReader speech model manifest: invalid remote manifest, using bundled manifest (%@)",
                    String(describing: error)
                )
                return .success(bundledManifest)
            }
            return .failure(error)
        }
    }

    static func fetchModelManifest(
        from manifestURL: URL = Runtime.modelManifestURL
    ) async throws -> SpeechModelManifest? {
        do {
            let (data, response) = try await URLSession.shared.data(from: manifestURL)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            if statusCode == 404 {
                return bundledModelManifest()
            }
            guard (200...299).contains(statusCode) else {
                throw NSError(
                    domain: LocalRuntimeDownloadSupport.downloadErrorDomain,
                    code: statusCode,
                    userInfo: [NSLocalizedDescriptionKey: AppText.localized("模型校验清单下载失败，请稍后重试。", "Model checksum manifest download failed. Please try again later.")]
                )
            }
            return try decodeModelManifest(data)
        } catch let error as DecodingError {
            if let bundledManifest = bundledModelManifest() {
                NSLog("LeafReader speech model manifest: invalid remote manifest, using bundled manifest (%@)", String(describing: error))
                return bundledManifest
            }
            throw error
        } catch {
            let bundledManifest = bundledModelManifest()
            NSLog(
                "LeafReader speech model manifest: unavailable, using bundled manifest=%d (%@)",
                bundledManifest != nil,
                String(describing: error)
            )
            return bundledManifest
        }
    }
}
