# Getting Started

Keywords: installation, macOS, PDF, EPUB, DOCX, AI settings, translation, vocabulary.

## Download and Install

1. Download the current `.pkg` installer from the project website or GitHub Releases.
2. Open the package and follow the installer.
3. Launch Leaf Reader from Applications.

Leaf Reader requires macOS 14 or later. The reader supports Apple Silicon and Intel Macs; downloadable local speech runtimes require Apple Silicon.

## First Launch

The bookshelf appears when no document is open. Drag a supported file into the window or use `Command + O` to choose one. Recent documents remain available from the bookshelf.

## Open a Document

Leaf Reader supports PDF, EPUB, and DOCX files. It restores the last page or reading position when a document is reopened. PDF documents use PDFKit; EPUB and DOCX content is rendered with WebKit.

## Configure AI

AI features are optional. Open Settings and provide the model endpoint, model name, and API key required by your provider. Normal reading, document search, existing-note editing, note export, and local features do not send model requests.

Only text included in an AI action is sent to the configured provider. Documents otherwise remain local.

## Translate or Explain Text

Select text in the document and choose an action from the floating toolbar. Available actions include explanation, summary, translation, and follow-up questions. Without a configured model, Leaf Reader directs you to Settings.

## Create Reading Notes

With a model key configured, select a passage and choose Note to create a note linked to the current book and location. The current selection toolbar shows this creation action together with the AI actions only when the selected model is configured. After creation, ordinary editing, images, search, favorites, and export work locally; only explicit AI assistance sends note content to the provider. See [Reading Notes](reading-notes.md).

## Save Vocabulary

Select a word, look it up, and save it to the current book's vocabulary. Saved words can be reviewed, highlighted when the document is reopened, and exported. See [Vocabulary and Highlights](word-highlights.md).

## Check for Updates

Use the application update command to ask Sparkle for the latest available release. See [Troubleshooting](troubleshooting.md) if the check fails.

## Related Pages

- [Shortcuts](shortcuts.md)
- [Reading Notes](reading-notes.md)
- [AI Chat](ai-chat.md)
- [TTS and Read Aloud](tts.md)
- [Vocabulary and Highlights](word-highlights.md)
- [Troubleshooting](troubleshooting.md)
