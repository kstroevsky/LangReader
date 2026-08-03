import Foundation
import SQLite3
import LeafReaderCore

struct WordRecordSQLiteJSONCodec {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func encode<T: Encodable>(_ value: T?) -> String? {
        guard let value, let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func decode<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

enum WordRecordSQLiteBindIndex: Int32 {
    case documentID = 1
    case id = 2
    case word = 3
    case firstSourceField = 4
    case secondSourceField = 5
    case thirdSourceField = 6
    case question = 7
    case answer = 8
    case dictionaryTags = 9
    case dictionaryFrequency = 10
    case createdAt = 11
    case srsJSON = 12
}

struct PDFWordRecordSQLiteMapper {
    enum Column: Int32 {
        case id = 0
        case word = 1
        case pageIndex = 2
        case boundsJSON = 3
        case context = 4
        case question = 5
        case answer = 6
        case dictionaryTags = 7
        case dictionaryFrequency = 8
        case createdAt = 9
        case srsJSON = 10
    }

    static let selectSQL = """
    SELECT id, word, page_index, bounds_json, context, question, answer, dictionary_tags, dictionary_frequency, created_at, srs_json
    FROM pdf_word_records
    WHERE document_id = ?
    ORDER BY created_at ASC, id ASC
    """

    static let insertSQL = """
    INSERT OR REPLACE INTO pdf_word_records(
        document_id, id, word, page_index, bounds_json, context, question, answer, dictionary_tags, dictionary_frequency, created_at, srs_json
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    let codec: WordRecordSQLiteJSONCodec

    func decode(from statement: OpaquePointer?) -> StoredPDFWordRecord? {
        guard let id = stringColumn(statement, Column.id.rawValue),
              let word = stringColumn(statement, Column.word.rawValue),
              let boundsJSON = stringColumn(statement, Column.boundsJSON.rawValue),
              let bounds = codec.decode(StoredPDFWordRect.self, from: boundsJSON),
              let question = stringColumn(statement, Column.question.rawValue),
              let answer = stringColumn(statement, Column.answer.rawValue) else {
            return nil
        }
        return StoredPDFWordRecord(
            id: id,
            word: word,
            pageIndex: Int(sqlite3_column_int(statement, Column.pageIndex.rawValue)),
            bounds: bounds,
            context: optionalStringColumn(statement, Column.context.rawValue),
            question: question,
            answer: answer,
            dictionaryTags: optionalStringColumn(statement, Column.dictionaryTags.rawValue),
            dictionaryFrequency: optionalIntColumn(statement, Column.dictionaryFrequency.rawValue),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, Column.createdAt.rawValue)),
            srs: codec.decode(VocabularySRSState.self, from: optionalStringColumn(statement, Column.srsJSON.rawValue))
        )
    }

    func bind(documentID: String, record: StoredPDFWordRecord, to statement: OpaquePointer?) {
        bindText(documentID, at: .documentID, statement: statement)
        bindText(record.id, at: .id, statement: statement)
        bindText(record.word, at: .word, statement: statement)
        sqlite3_bind_int(statement, WordRecordSQLiteBindIndex.firstSourceField.rawValue, Int32(record.pageIndex))
        bindText(codec.encode(record.bounds) ?? "{}", at: .secondSourceField, statement: statement)
        bindOptionalText(record.context, at: .thirdSourceField, statement: statement)
        bindText(record.question, at: .question, statement: statement)
        bindText(record.answer, at: .answer, statement: statement)
        bindOptionalText(record.dictionaryTags, at: .dictionaryTags, statement: statement)
        bindOptionalInt(record.dictionaryFrequency, at: .dictionaryFrequency, statement: statement)
        sqlite3_bind_double(statement, WordRecordSQLiteBindIndex.createdAt.rawValue, record.createdAt.timeIntervalSince1970)
        bindOptionalText(codec.encode(record.srs), at: .srsJSON, statement: statement)
    }
}

struct PDFVocabularySQLiteMapper {
    enum Column: Int32 {
        case occurrenceID = 0
        case vocabularyID = 1
        case word = 2
        case lemma = 3
        case surfaceForm = 4
        case pageIndex = 5
        case boundsJSON = 6
        case textAnchorJSON = 7
        case context = 8
        case question = 9
        case answer = 10
        case dictionaryTags = 11
        case dictionaryFrequency = 12
        case createdAt = 13
        case srsJSON = 14
    }

    static let selectSQL = """
    SELECT occurrence.id, word.id, word.word, word.lemma, occurrence.surface_form,
           occurrence.page_index, occurrence.bounds_json, occurrence.text_anchor_json,
           occurrence.context, word.question, word.answer, word.dictionary_tags,
           word.dictionary_frequency, occurrence.created_at, word.srs_json
    FROM pdf_vocabulary_occurrences AS occurrence
    JOIN pdf_vocabulary_words AS word
      ON word.document_id = occurrence.document_id AND word.id = occurrence.vocabulary_id
    WHERE occurrence.document_id = ?
    ORDER BY word.created_at ASC, occurrence.page_index ASC, occurrence.created_at ASC, occurrence.id ASC
    """

    let codec: WordRecordSQLiteJSONCodec

    func decode(from statement: OpaquePointer?) -> StoredPDFWordRecord? {
        guard let id = stringColumn(statement, Column.occurrenceID.rawValue),
              let vocabularyID = stringColumn(statement, Column.vocabularyID.rawValue),
              let word = stringColumn(statement, Column.word.rawValue),
              let boundsJSON = stringColumn(statement, Column.boundsJSON.rawValue),
              let bounds = codec.decode(StoredPDFWordRect.self, from: boundsJSON),
              let question = stringColumn(statement, Column.question.rawValue),
              let answer = stringColumn(statement, Column.answer.rawValue) else {
            return nil
        }
        return StoredPDFWordRecord(
            id: id,
            vocabularyID: vocabularyID,
            word: word,
            lemma: optionalStringColumn(statement, Column.lemma.rawValue),
            surfaceForm: optionalStringColumn(statement, Column.surfaceForm.rawValue) ?? word,
            pageIndex: Int(sqlite3_column_int(statement, Column.pageIndex.rawValue)),
            bounds: bounds,
            textAnchor: codec.decode(TextQuoteAnchor.self, from: optionalStringColumn(statement, Column.textAnchorJSON.rawValue)),
            context: optionalStringColumn(statement, Column.context.rawValue),
            question: question,
            answer: answer,
            dictionaryTags: optionalStringColumn(statement, Column.dictionaryTags.rawValue),
            dictionaryFrequency: optionalIntColumn(statement, Column.dictionaryFrequency.rawValue),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, Column.createdAt.rawValue)),
            srs: codec.decode(VocabularySRSState.self, from: optionalStringColumn(statement, Column.srsJSON.rawValue))
        )
    }
}

struct WebWordRecordSQLiteMapper {
    enum Column: Int32 {
        case id = 0
        case vocabularyID = 1
        case word = 2
        case lemma = 3
        case surfaceForm = 4
        case context = 5
        case occurrenceIndex = 6
        case scrollProgress = 7
        case question = 8
        case answer = 9
        case dictionaryTags = 10
        case dictionaryFrequency = 11
        case createdAt = 12
        case srsJSON = 13
    }

    private enum Bind: Int32 {
        case documentID = 1
        case id = 2
        case vocabularyID = 3
        case word = 4
        case lemma = 5
        case surfaceForm = 6
        case context = 7
        case occurrenceIndex = 8
        case scrollProgress = 9
        case question = 10
        case answer = 11
        case dictionaryTags = 12
        case dictionaryFrequency = 13
        case createdAt = 14
        case srsJSON = 15
    }

    static let selectSQL = """
    SELECT id, vocabulary_id, word, lemma, surface_form, context,
           occurrence_index, scroll_progress, question, answer,
           dictionary_tags, dictionary_frequency, created_at, srs_json
    FROM web_word_records
    WHERE document_id = ?
    ORDER BY created_at ASC, id ASC
    """

    static let insertSQL = """
    INSERT OR REPLACE INTO web_word_records(
        document_id, id, vocabulary_id, word, lemma, surface_form, context,
        occurrence_index, scroll_progress, question, answer, dictionary_tags,
        dictionary_frequency, created_at, srs_json
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    let codec: WordRecordSQLiteJSONCodec

    func decode(from statement: OpaquePointer?) -> StoredWebWordRecord? {
        guard let id = stringColumn(statement, Column.id.rawValue),
              let word = stringColumn(statement, Column.word.rawValue),
              let context = stringColumn(statement, Column.context.rawValue),
              let question = stringColumn(statement, Column.question.rawValue),
              let answer = stringColumn(statement, Column.answer.rawValue) else {
            return nil
        }
        return StoredWebWordRecord(
            id: id,
            vocabularyID: optionalStringColumn(statement, Column.vocabularyID.rawValue),
            word: word,
            lemma: optionalStringColumn(statement, Column.lemma.rawValue),
            surfaceForm: optionalStringColumn(statement, Column.surfaceForm.rawValue),
            context: context,
            occurrenceIndex: sqlite3_column_type(statement, Column.occurrenceIndex.rawValue) == SQLITE_NULL
                ? nil
                : Int(sqlite3_column_int(statement, Column.occurrenceIndex.rawValue)),
            scrollProgress: sqlite3_column_double(statement, Column.scrollProgress.rawValue),
            question: question,
            answer: answer,
            dictionaryTags: optionalStringColumn(statement, Column.dictionaryTags.rawValue),
            dictionaryFrequency: optionalIntColumn(statement, Column.dictionaryFrequency.rawValue),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, Column.createdAt.rawValue)),
            srs: codec.decode(VocabularySRSState.self, from: optionalStringColumn(statement, Column.srsJSON.rawValue))
        )
    }

    func bind(documentID: String, record: StoredWebWordRecord, to statement: OpaquePointer?) {
        bindText(documentID, index: Bind.documentID.rawValue, statement: statement)
        bindText(record.id, index: Bind.id.rawValue, statement: statement)
        bindOptionalText(record.vocabularyID, index: Bind.vocabularyID.rawValue, statement: statement)
        bindText(record.word, index: Bind.word.rawValue, statement: statement)
        bindOptionalText(record.lemma, index: Bind.lemma.rawValue, statement: statement)
        bindOptionalText(record.surfaceForm, index: Bind.surfaceForm.rawValue, statement: statement)
        bindText(record.context, index: Bind.context.rawValue, statement: statement)
        bindOptionalInt(record.occurrenceIndex, index: Bind.occurrenceIndex.rawValue, statement: statement)
        sqlite3_bind_double(statement, Bind.scrollProgress.rawValue, record.scrollProgress)
        bindText(record.question, index: Bind.question.rawValue, statement: statement)
        bindText(record.answer, index: Bind.answer.rawValue, statement: statement)
        bindOptionalText(record.dictionaryTags, index: Bind.dictionaryTags.rawValue, statement: statement)
        bindOptionalInt(record.dictionaryFrequency, index: Bind.dictionaryFrequency.rawValue, statement: statement)
        sqlite3_bind_double(statement, Bind.createdAt.rawValue, record.createdAt.timeIntervalSince1970)
        bindOptionalText(codec.encode(record.srs), index: Bind.srsJSON.rawValue, statement: statement)
    }
}

private func bindText(_ value: String, index: Int32, statement: OpaquePointer?) {
    sqlite3_bind_text(statement, index, value, -1, WORD_RECORD_SQLITE_TRANSIENT)
}

private func bindOptionalText(_ value: String?, index: Int32, statement: OpaquePointer?) {
    guard let value else {
        sqlite3_bind_null(statement, index)
        return
    }
    sqlite3_bind_text(statement, index, value, -1, WORD_RECORD_SQLITE_TRANSIENT)
}

private func bindOptionalInt(_ value: Int?, index: Int32, statement: OpaquePointer?) {
    guard let value else {
        sqlite3_bind_null(statement, index)
        return
    }
    sqlite3_bind_int64(statement, index, sqlite3_int64(value))
}

func bindText(_ value: String, at index: WordRecordSQLiteBindIndex, statement: OpaquePointer?) {
    sqlite3_bind_text(statement, index.rawValue, value, -1, WORD_RECORD_SQLITE_TRANSIENT)
}

func bindOptionalText(_ value: String?, at index: WordRecordSQLiteBindIndex, statement: OpaquePointer?) {
    guard let value else {
        sqlite3_bind_null(statement, index.rawValue)
        return
    }
    bindText(value, at: index, statement: statement)
}

func bindOptionalInt(_ value: Int?, at index: WordRecordSQLiteBindIndex, statement: OpaquePointer?) {
    guard let value else {
        sqlite3_bind_null(statement, index.rawValue)
        return
    }
    sqlite3_bind_int(statement, index.rawValue, Int32(value))
}

func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard let pointer = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: pointer)
}

func optionalStringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : stringColumn(statement, index)
}

func optionalIntColumn(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
    sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, index))
}

let WORD_RECORD_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
