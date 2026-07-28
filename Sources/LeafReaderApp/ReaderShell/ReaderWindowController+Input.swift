import Cocoa
import PDFKit
import WebKit
import LeafReaderCore

extension ReaderWindowController {
    func installKeyboardPagingMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .leftMouseDown]) { [weak self] event in
            guard let self = self,
                  event.window === self.window || event.window === self.selectionActionToolbarWindow else {
                return event
            }
            switch event.type {
            case .keyDown:
                guard self.handlePageKey(event) else { return event }
                return nil
            case .scrollWheel:
                self.markReaderInteraction()
                self.hideSelectionToolbar()
                DispatchQueue.main.async { [weak self] in
                    self?.updateZoomLabel()
                }
                return event
            case .leftMouseDown:
                self.hideSelectionToolbarIfClickingOutsideReader(event)
                if self.handleStoredWordClick(event) {
                    return nil
                }
                if self.handleReadingNoteClick(event) {
                    return nil
                }
                if self.handleAISourceUnderlineClick(event) {
                    return nil
                }
                self.clearAISelectionIfClickingReader(event)
                self.hideSearchOverlayIfClickingReader(event)
                return event
            default:
                return event
            }
        }
    }

    func handleStoredWordClick(_ event: NSEvent) -> Bool {
        guard isMouseEventInsidePDFArea(event),
              let linkID = storedWordID(at: event) else {
            return false
        }
        selectStoredLinkedWord(linkID: linkID)
        return true
    }

    func handleAISourceUnderlineClick(_ event: NSEvent) -> Bool {
        guard isMouseEventInsidePDFArea(event),
              let source = aiSourceLocation(at: event) else {
            return false
        }
        pendingAISourceClickWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let selectedText = self.currentPDFSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard selectedText.isEmpty else { return }
            self.ensureAIConversationSourceBubbleLoaded(source)
            self.pendingAIPanelExpansionAction = { [weak self] in
                self?.aiPanel.scrollToConversationSource(source, prefersHeaderBubble: true)
            }
            self.setAIPanelCollapsed(false, animated: true)
        }
        pendingAISourceClickWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
        return false
    }

    func handleReadingNoteClick(_ event: NSEvent) -> Bool {
        guard isMouseEventInsidePDFArea(event),
              let noteID = readingNoteID(at: event),
              let note = storedReadingNotes.first(where: { $0.id == noteID }) else {
            return false
        }
        openReadingNotePanel(note)
        return true
    }

    func clearAISelectionIfClickingReader(_ event: NSEvent) {
        guard isMouseEventInsidePDFArea(event) else { return }
        clearAISelectionForNavigation()
    }

    func hideSearchOverlayIfClickingReader(_ event: NSEvent) {
        guard !searchOverlay.isHidden else { return }

        let pointInContent = contentArea.convert(event.locationInWindow, from: nil)
        guard contentArea.bounds.contains(pointInContent) else { return }

        let pointInSearch = searchOverlay.convert(event.locationInWindow, from: nil)
        guard !searchOverlay.bounds.contains(pointInSearch) else { return }

        hideSearchOverlay()
    }

    func hideSelectionToolbarIfClickingOutsideReader(_ event: NSEvent) {
        guard event.window === window,
              !selectionActionToolbar.isHidden,
              !isMouseEventInsidePDFArea(event) else {
            return
        }
        hideSelectionToolbar()
    }

    func isMouseEventInsidePDFArea(_ event: NSEvent) -> Bool {
        let pointInWindow = event.locationInWindow
        let point = pdfContainer.convert(pointInWindow, from: nil)
        return pdfContainer.bounds.contains(point)
    }

    func handlePageKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53, !selectionActionToolbar.isHidden {
            hideSelectionToolbar()
            return true
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
            showSearchOverlay()
            return true
        }
        if handleReaderCommandShortcut(event) {
            return true
        }

        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return false }
        guard !isEditingTextInput else { return false }
        if handleReadAloudManualAdvanceKey(event) {
            return true
        }

        switch event.keyCode {
        case 123:
            prevPage()
            return true
        case 124:
            nextPage()
            return true
        default:
            return false
        }
    }

    func handleReadAloudManualAdvanceKey(_ event: NSEvent) -> Bool {
        guard isReadAloudActive,
              readAloudAdvanceMode == .manual,
              !isReadAloudLoading else {
            return false
        }
        let key = event.characters ?? event.charactersIgnoringModifiers ?? ""
        guard let action = ReadAloudManualAdvanceKeyPolicy.action(for: key) else { return false }
        switch action {
        case .next:
            advanceReadAloudFromFloatingControl()
        case .replayCurrent:
            replayReadAloudFromFloatingControl()
        case .replayPrevious:
            previousReadAloudFromFloatingControl()
        }
        return true
    }

    func handleReaderCommandShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.modifierFlags.intersection([.option, .control]).isEmpty,
              !isEditingTextInput,
              !isFirstResponderInsideAIView,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch key {
        case "a":
            selectAllReaderContent()
            return true
        case "c":
            copyReaderSelectionToClipboard()
            return true
        default:
            return false
        }
    }

    func selectAllReaderContent() {
        if currentDocumentKind == .pdf {
            guard let page = pdfView.currentPage,
                  let selection = page.selection(for: page.bounds(for: pdfView.displayBox)) else {
                return
            }
            pdfView.setCurrentSelection(selection, animate: false)
            selectionChanged()
            return
        }

        webView.evaluateJavaScript("""
        (() => {
          const viewportTop = 0;
          const viewportBottom = window.innerHeight || document.documentElement.clientHeight || 0;
          const viewportLeft = 0;
          const viewportRight = window.innerWidth || document.documentElement.clientWidth || 0;
          const isVisibleRect = (rect) =>
            rect.width > 0 &&
            rect.height > 0 &&
            rect.bottom >= viewportTop &&
            rect.top <= viewportBottom &&
            rect.right >= viewportLeft &&
            rect.left <= viewportRight;
          const isSelectableTextNode = (node) => {
            if (!node.nodeValue || !node.nodeValue.trim()) return false;
            const parent = node.parentElement;
            if (!parent) return false;
            const style = window.getComputedStyle(parent);
            if (style.display === 'none' || style.visibility === 'hidden') return false;
            const range = document.createRange();
            range.selectNodeContents(node);
            const visible = Array.from(range.getClientRects()).some(isVisibleRect);
            range.detach?.();
            return visible;
          };
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode: (node) => isSelectableTextNode(node)
              ? NodeFilter.FILTER_ACCEPT
              : NodeFilter.FILTER_REJECT
          });
          let first = null;
          let last = null;
          let node;
          while ((node = walker.nextNode())) {
            if (!first) first = node;
            last = node;
          }
          const selection = window.getSelection();
          selection.removeAllRanges();
          if (!first || !last) return "";
          const range = document.createRange();
          range.setStart(first, 0);
          range.setEnd(last, last.nodeValue.length);
          selection.addRange(range);
          return String(selection || "");
        })();
        """) { [weak self] result, _ in
            let text = self?.trimmedReaderSelection(result as? String) ?? ""
            self?.setWebSelectionFromVisibleText(text)
        }
    }

    func copyReaderSelectionToClipboard() {
        if currentDocumentKind == .pdf {
            copyTextToClipboard(pdfView.currentSelection?.string)
            return
        }

        webView.evaluateJavaScript("String(window.getSelection ? window.getSelection() : '')") { [weak self] result, _ in
            let text = result as? String
            self?.copyTextToClipboard(text)
        }
    }

    func copyTextToClipboard(_ text: String?) {
        let value = trimmedReaderSelection(text)
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func trimmedReaderSelection(_ text: String?) -> String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var isFirstResponderInsideAIView: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === aiPanel || responder.isDescendant(of: aiPanel)
    }

    var isEditingTextInput: Bool {
        guard let responder = window?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable
        }
        return false
    }
}
