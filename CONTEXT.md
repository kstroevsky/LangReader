# Leaf Reader Domain Context

Leaf Reader is a native macOS reading environment for working with local documents, vocabulary, notes, AI conversations, and spoken playback. This glossary keeps feature and module names aligned with the reader's product language.

## Language

### Reading

**Document**:
A local PDF, EPUB, or DOCX file opened for reading. One Document has one active Document Session at a time.
_Avoid_: Book, file, content

**Document Session**:
The document-scoped reading state from opening through closing, including position, selections, annotations, notes, AI context, and related persistence.
_Avoid_: Runtime state, loaded file state

**Reader Shell**:
The macOS window and presentation surface that displays a Document Session and composes reader features.
_Avoid_: Main controller, reader window logic

### Learning

**Vocabulary Record**:
A saved word occurrence with its document context, location, metadata, and learning state.
_Avoid_: Word item, saved word

**Review Session**:
An ordered interaction in which Vocabulary Records are presented and scored for spaced repetition.
_Avoid_: Trainer, quiz

**Reading Note**:
A document-linked Markdown note that may contain formatted text, images, and AI-assisted edits.
_Avoid_: Annotation, memo

### Assistance

**AI Conversation**:
A persisted sequence of questions and answers associated with a Document Session and optional source locations.
_Avoid_: Chat state, message history

**Read Aloud**:
The reader feature that selects, queues, highlights, and navigates spoken document segments.
_Avoid_: TTS feature, speech playback

**Speech Runtime**:
A locally available engine and model installation capable of synthesizing speech for Read Aloud.
_Avoid_: TTS backend, voice package

## Flagged ambiguities

- **Document** means the reader's domain object; use **file URL** when referring only to filesystem identity.
- **Read Aloud** owns reading interaction; **Speech Runtime** owns synthesis availability and execution.
- **Reading Note** is persisted Markdown content; PDF/Web visual marks are annotations, not Reading Notes.

## Example dialogue

> **Developer:** When the user opens an EPUB, which module restores the last position and linked vocabulary?
>
> **Domain expert:** The Document Session owns restoration. The Reader Shell only presents that session, while Vocabulary Records and Reading Notes remain document-linked data.
>
> **Developer:** Does changing from Piper to Kokoro alter Read Aloud state?
>
> **Domain expert:** No. Read Aloud keeps the queue and current segment; the Speech Runtime changes the synthesis adapter used for those segments.
