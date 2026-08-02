# Leaf Reader Documentation

Documentation for using, developing, and releasing Leaf Reader.

## Current Release

- Current version: `1.7.9`

<div class="hero-actions" markdown>

[Website](https://leafreader.space/){ .button .primary }
[Download Leaf Reader](https://github.com/dowellhz/LeafReader/releases/download/v1.7.9/LeafReader-1.7.9.pkg){ .button }
[GitHub](https://github.com/dowellhz/LeafReader){ .button }

</div>

## User Documentation

<div class="grid" markdown>

[**Getting Started** - Install Leaf Reader, open documents, and configure AI features.](getting-started.md){ .card }

[**Reading Notes** - Create, edit, enhance, and export notes.](reading-notes.md){ .card }

[**Vocabulary and Highlights** - Save words, restore highlights, review, and export.](word-highlights.md){ .card }

[**Shortcuts** - Keyboard controls for reading, navigation, speech, and notes.](shortcuts.md){ .card }

[**AI Chat** - Explain, summarize, translate, and ask follow-up questions.](ai-chat.md){ .card }

[**TTS and Read Aloud** - Configure local speech runtimes and control playback.](tts.md){ .card }

[**Troubleshooting** - Resolve common update, signing, paging, AI, data, and wiki issues.](troubleshooting.md){ .card }

</div>

## Engineering Documentation

<div class="grid" markdown>

[**Architecture** - System structure and module boundaries.](architecture.md){ .card }

[**Feature Map** - Find source files by product feature.](feature-map.md){ .card }

[**Development Tasks** - Entry points for common engineering work.](development-tasks.md){ .card }

[**Document Loading** - PDF, EPUB, DOCX, and HTML rendering flow.](document-loading.md){ .card }

[**AI Analysis Cache** - Document indexing, embedding cache, and analysis state.](ai-analysis-cache.md){ .card }

[**Release Process** - Versioning, packaging, signing, appcast, and publishing.](release-process.md){ .card }

[**Release Checklist** - Pre-release checks for packages, updates, docs, and runtime assets.](release-checklist.md){ .card }

[**Release Runbook** - Build, sign, publish, and verify a release.](release-runbook.md){ .card }

[**Security** - Secrets, signing credentials, generated artifacts, and incident handling.](security.md){ .card }

[**Code Map** - Generated module summary.](code-map.md){ .card }

[**Type Index** - Generated Swift type index.](type-index.md){ .card }

</div>

## Common Commands

```sh
./scripts/check.sh
./scripts/build_docs_site.sh
./scripts/release_pkg.sh <version>
./scripts/publish_release.sh <version>
./scripts/update_wiki.sh --push
```
