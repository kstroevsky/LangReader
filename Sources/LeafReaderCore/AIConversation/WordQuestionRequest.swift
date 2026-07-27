import Foundation

package struct WordQuestionRequest {
    package let text: String
    package let selectedContext: String?

    package init(text: String, selectedContext: String?) {
        self.text = text
        self.selectedContext = selectedContext
    }
}

package struct WordQuestionStartResult {
    package let linkID: String?
    package let selectedContext: String?

    package init(linkID: String?, selectedContext: String?) {
        self.linkID = linkID
        self.selectedContext = selectedContext
    }
}
