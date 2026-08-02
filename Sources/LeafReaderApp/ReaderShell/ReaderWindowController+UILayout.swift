import Cocoa

struct ReaderToolbarSetup {
    let toolbar: NSView
    let hosting: NSView
}

struct ReaderBottomBarSetup {
    let bottomBar: NSView
    let hosting: NSView
}

enum ReaderUILayout {
    static let toolbarHeight: CGFloat = 58
    static let bottomBarHeight: CGFloat = 52
    static let collapsedAIPanelWidth: CGFloat = 1
    static let resizeHandleWidth: CGFloat = 6
    static let aiHandleTopOffset: CGFloat = 90

    static let settingsLeading: CGFloat = 18
    static let settingsButtonSize: CGFloat = 32
    static let shelfButtonLeading: CGFloat = 18
    static let shelfButtonWidth: CGFloat = 88
    static let vocabularyLibraryButtonLeading: CGFloat = 10
    static let vocabularyLibraryButtonWidth: CGFloat = 88
    static let notesButtonLeading: CGFloat = 10
    static let notesButtonWidth: CGFloat = 86
    static let vocabularyButtonLeading: CGFloat = 10
    static let vocabularyButtonWidth: CGFloat = 92
    static let bottomButtonHeight: CGFloat = 30

    static let coverLeading: CGFloat = 128
    static let coverSize = CGSize(width: 28, height: 38)
    static let titleLeading: CGFloat = 10
    static let titleMaxWidth: CGFloat = 230
    static let titleToReadAloudMinimum: CGFloat = 14
    static let readAloudButtonWidth: CGFloat = 82
    static let readAloudStopLeading: CGFloat = 6
    static let readAloudStopButtonWidth: CGFloat = 82
    static let readAloudTrailingToZoom: CGFloat = 14

    static let zoomCenterOffset: CGFloat = -80
    static let zoomGroupSize = CGSize(width: 132, height: 32)
    static let zoomButtonWidth: CGFloat = 40
    static let zoomDividerWidth: CGFloat = 1
    static let zoomFieldWidth: CGFloat = 50

    static let pageLabelCenterOffset: CGFloat = 130
    static let pageLabelWidth: CGFloat = 170
    static let searchUnderlineLeading: CGFloat = 6
    static let searchUnderlineSize = CGSize(width: 74, height: 28)
    static let searchButtonLeading: CGFloat = 2
    static let iconButtonSize: CGFloat = 28

    static let relatedFormsToggleTrailing: CGFloat = -12
    static let pageLayoutTrailing: CGFloat = -8
    static let pageLayoutButtonWidth: CGFloat = 84
    static let cropButtonTrailing: CGFloat = -8
    static let cropButtonWidth: CGFloat = 84
    static let toolbarButtonHeight: CGFloat = 30

    static let searchOverlayTop: CGFloat = 10
    static let searchOverlaySize = CGSize(width: 560, height: 70)
    static let loadingIndicatorYOffset: CGFloat = -16
    static let loadingLabelTop: CGFloat = 14
    static let loadingLabelHorizontalInset: CGFloat = 32

    static let tocButtonWidth: CGFloat = 88
    static let navigationStackSpacing: CGFloat = 20
    static let navigationStackCenterOffset: CGFloat = 104

    static let embeddingTrailing: CGFloat = -18
    static let embeddingButtonWidth: CGFloat = 58
    static let embeddingButtonHeight: CGFloat = 26
    static let embeddingButtonSpacing: CGFloat = -8
    static let embeddingStatusTrailing: CGFloat = -10
    static let embeddingStatusLeadingMinimum: CGFloat = 16
    static let embeddingStatusMaxWidth: CGFloat = 220
}

extension ReaderWindowController {
    func installReaderLayoutConstraints(
        contentView: NSView,
        toolbarSetup: ReaderToolbarSetup,
        bottomBarSetup: ReaderBottomBarSetup
    ) {
        let toolbar = toolbarSetup.toolbar
        let toolbarHosting = toolbarSetup.hosting
        let bottomBar = bottomBarSetup.bottomBar
        let hosting = bottomBarSetup.hosting

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: ReaderUILayout.toolbarHeight),

            bottomBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomBarHeight),

            contentArea.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            contentArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            pdfContainer.topAnchor.constraint(equalTo: contentArea.topAnchor),
            pdfContainer.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            pdfContainer.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            pdfContainer.trailingAnchor.constraint(equalTo: aiPanel.leadingAnchor),

            pdfView.topAnchor.constraint(equalTo: pdfContainer.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: pdfContainer.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: pdfContainer.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: pdfContainer.bottomAnchor),

            pdfDimOverlay.topAnchor.constraint(equalTo: pdfContainer.topAnchor),
            pdfDimOverlay.leadingAnchor.constraint(equalTo: pdfContainer.leadingAnchor),
            pdfDimOverlay.trailingAnchor.constraint(equalTo: pdfContainer.trailingAnchor),
            pdfDimOverlay.bottomAnchor.constraint(equalTo: pdfContainer.bottomAnchor),

            webView.topAnchor.constraint(equalTo: pdfContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: pdfContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: pdfContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: pdfContainer.bottomAnchor),

            aiPanel.topAnchor.constraint(equalTo: contentArea.topAnchor),
            aiPanel.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            aiPanel.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),

            resizeHandle.topAnchor.constraint(equalTo: contentArea.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            resizeHandle.centerXAnchor.constraint(equalTo: aiPanel.leadingAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: ReaderUILayout.resizeHandleWidth),

            aiHandleButton.topAnchor.constraint(equalTo: contentArea.topAnchor, constant: ReaderUILayout.aiHandleTopOffset),
            aiHandleLeadingConstraint,
            aiHandleButton.widthAnchor.constraint(equalToConstant: SideHandleButton.handleWidth),
            aiHandleButton.heightAnchor.constraint(equalToConstant: SideHandleButton.handleHeight),

            hosting.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor),

            // The top toolbar's buttons are a SwiftUI view filling the bar; it
            // positions the edge clusters from the same `ReaderUILayout` constants.
            toolbarHosting.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            toolbarHosting.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            toolbarHosting.topAnchor.constraint(equalTo: toolbar.topAnchor),
            toolbarHosting.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),

            // The editable centre cluster is AppKit, layered on top of the hosting
            // view (editable fields can't get first responder inside it) and
            // anchored to the window centre, matching the SwiftUI edge clusters.
            zoomGroupView!.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            zoomGroupView!.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor, constant: ReaderUILayout.zoomCenterOffset),

            pageLabel.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor, constant: ReaderUILayout.pageLabelCenterOffset),
            pageLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pageLabel.widthAnchor.constraint(equalToConstant: ReaderUILayout.pageLabelWidth),
            pageLabel.heightAnchor.constraint(equalToConstant: ReaderUILayout.zoomGroupSize.height),

            searchUnderlineButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: ReaderUILayout.searchUnderlineLeading),
            searchUnderlineButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchUnderlineButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.searchUnderlineSize.width),
            searchUnderlineButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.searchUnderlineSize.height),

            searchButton.leadingAnchor.constraint(equalTo: searchUnderlineButton.trailingAnchor, constant: ReaderUILayout.searchButtonLeading),
            searchButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.iconButtonSize),
            searchButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.iconButtonSize),

            searchOverlay.topAnchor.constraint(equalTo: contentView.topAnchor, constant: ReaderUILayout.searchOverlayTop),
            searchOverlay.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            searchOverlay.widthAnchor.constraint(equalToConstant: ReaderUILayout.searchOverlaySize.width),
            searchOverlay.heightAnchor.constraint(equalToConstant: ReaderUILayout.searchOverlaySize.height),

            loadingOverlay.topAnchor.constraint(equalTo: contentArea.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor, constant: ReaderUILayout.loadingIndicatorYOffset),
            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: ReaderUILayout.loadingLabelTop),
            loadingLabel.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: loadingOverlay.leadingAnchor, constant: ReaderUILayout.loadingLabelHorizontalInset),
            loadingLabel.trailingAnchor.constraint(lessThanOrEqualTo: loadingOverlay.trailingAnchor, constant: -ReaderUILayout.loadingLabelHorizontalInset),

        ])
    }
}
