import Foundation

package enum VocabularyFilter: Int {
    case due = 0
    case new = 1
    case all = 2
}

package enum VocabularyReviewPriority: String {
    case oldWordsFirst
    case newWordsFirst
    case frequencyFirst
}
