import Foundation

package struct KokoroWorkerResponse: Codable, Equatable {
    package let id: String
    package let ok: Bool
    package let error: String?

    package init(
        id: String,
        ok: Bool,
        error: String?
    ) {
        self.id = id
        self.ok = ok
        self.error = error
    }
}

package struct KokoroWorkerResponseReader {
    private let requestID: String
    private let decoder = JSONDecoder()
    private var buffer = Data()

    package init(requestID: String) {
        self.requestID = requestID
    }

    package mutating func append(_ data: Data) -> KokoroWorkerResponse? {
        guard !data.isEmpty else { return nil }
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            guard let response = try? decoder.decode(KokoroWorkerResponse.self, from: Data(lineData)),
                  response.id == requestID else {
                continue
            }
            return response
        }
        return nil
    }
}
