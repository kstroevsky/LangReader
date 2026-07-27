import Foundation

package struct DocumentQuestionPromptRequest {
    package let question: String
    package let questionSubject: String
    package let context: String

    package init(question: String, questionSubject: String = "", context: String) {
        self.question = question
        self.questionSubject = questionSubject
        self.context = context
    }
}

package typealias DocumentQuestionPromptHandler = (
    _ request: DocumentQuestionPromptRequest,
    _ completion: @escaping (String?) -> Void
) -> Void
