import Cocoa
import NaturalLanguage
import LeafReaderCore

extension ReaderWindowController {
    @objc func showVocabularyPreparation() {
        guard currentFileMD5 != nil else {
            NSSound.beep()
            return
        }
        vocabularyPreparationCoordinator.resetForCurrentDocument()
        vocabularyPreparationPanelController.present()
    }

    func offerVocabularyPreparationIfNeeded(generation: Int) {
        guard documentSession.acceptsLoad(generation: generation),
              let documentID = currentFileMD5,
              window?.attachedSheet == nil else { return }
        let store = VocabularyPreparationSessionStore(documentID: documentID)
        var session = store.load() ?? VocabularyPreparationSession()
        guard session.invitationState == .notOffered else { return }
        session.invitationState = .offered
        store.save(session)

        let alert = NSAlert()
        alert.messageText = AppText.localized("阅读前准备词汇？", "Prepare vocabulary before reading?")
        alert.informativeText = AppText.localized(
            "可先做 20–80 个快速自评题，再创建一份带概率估计的学习列表。阅读不会被阻止。",
            "Take a quick 20–80 item self-assessment and create a probabilistic learning list. Reading remains available."
        )
        alert.addButton(withTitle: AppText.localized("准备词汇", "Prepare Vocabulary"))
        alert.addButton(withTitle: AppText.localized("暂不", "Not now"))
        alert.applyLeafStyle()
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self,
                  self.documentSession.acceptsLoad(generation: generation),
                  self.currentFileMD5 == documentID else { return }
            if response == .alertFirstButtonReturn {
                self.vocabularyPreparationCoordinator.resetForCurrentDocument()
                self.vocabularyPreparationPanelController.present()
                self.vocabularyPreparationCoordinator.startAnalysis()
            } else {
                var dismissed = store.load() ?? session
                dismissed.invitationState = .dismissed
                store.save(dismissed)
            }
        }
    }
}
