import Foundation

package struct DocumentQuestionPromptRequest: Sendable {
    package let question: String
    package let questionSubject: String
    package let context: String

    package init(question: String, questionSubject: String = "", context: String) {
        self.question = question
        self.questionSubject = questionSubject
        self.context = context
    }
}

/// A note editor asks the reader for document-aware context without sharing a
/// callback lifetime with another editor.  The handler deliberately returns a
/// value instead of retaining a completion: the editor owns and cancels the
/// request-scoped task that awaits it.
package typealias DocumentQuestionPromptHandler = @MainActor @Sendable (
    _ request: DocumentQuestionPromptRequest
) async -> String?
