import LeafReaderCore

extension ReaderWindowController {
    func activateReaderBackend(for kind: ReaderDocumentKind) {
        activeReaderBackend = kind == .pdf ? pdfReaderAdapter : webReaderAdapter
    }

    var activePagedReaderBackend: (any ReaderPagedBackend)? {
        activeReaderBackend as? any ReaderPagedBackend
    }
}
