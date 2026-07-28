import Foundation

package struct LocalRuntimeDownloadManifestAsset: Codable, Equatable {
    package let assetName: String
    package let byteSize: Int64?
    package let sha256: String

    package init(assetName: String, byteSize: Int64?, sha256: String) {
        self.assetName = assetName
        self.byteSize = byteSize
        self.sha256 = sha256
    }

    package init(name: String, size: Int64?, sha256: String) {
        self.init(assetName: name, byteSize: size, sha256: sha256)
    }

    package var name: String {
        assetName
    }

    package var size: Int64? {
        byteSize
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case size
        case assetName
        case byteSize
        case sha256
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assetName = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decode(String.self, forKey: .assetName)
        byteSize = try container.decodeIfPresent(Int64.self, forKey: .size)
            ?? container.decodeIfPresent(Int64.self, forKey: .byteSize)
        sha256 = try container.decode(String.self, forKey: .sha256)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assetName, forKey: .name)
        try container.encodeIfPresent(byteSize, forKey: .size)
        try container.encode(sha256, forKey: .sha256)
    }
}

package struct LocalRuntimeDownloadManifest: Decodable, Equatable {
    package typealias Asset = LocalRuntimeDownloadManifestAsset

    package let generatedAt: String?
    package let assets: [Asset]

    package init(
        generatedAt: String?,
        assets: [Asset]
    ) {
        self.generatedAt = generatedAt
        self.assets = assets
    }

    package func asset(named fileName: String) -> Asset? {
        assets.first { $0.assetName == fileName }
    }
}
