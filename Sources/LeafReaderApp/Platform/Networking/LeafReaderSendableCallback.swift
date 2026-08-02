import Foundation

/// Explicitly marks a callback crossing a Foundation async boundary. The
/// callback is invoked only by the owning operation; the wrapper prevents the
/// Swift 6 compiler from treating caller-side captures as worker-owned state.
final class LeafReaderSendableCallback<Value>: @unchecked Sendable {
    private let body: (Value) -> Void

    init(_ body: @escaping (Value) -> Void) {
        self.body = body
    }

    func call(_ value: Value) {
        body(value)
    }
}
