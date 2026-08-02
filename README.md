<p align="center">
  <img src="assets/leaf-reader-icon.png" alt="Leaf Reader icon" width="128">
</p>

# Leaf Reader

Leaf Reader is a native macOS reader for PDF, EPUB, and DOCX documents. It is built with Swift, PDFKit, and WebKit, and focuses on a quiet reading experience with fast navigation, document search, reading progress restore, light and dark reader themes, and an optional AI panel for working with selected passages.

Website: <https://leafreader.space/>

### Screenshots

![Leaf Reader word learning in light mode](assets/reader-light-ai-word.png?v=20260524-shadow)

![Leaf Reader bookshelf](assets/reader-bookshelf.png?v=20260524-shadow)

![Leaf Reader settings](assets/reader-settings.png?v=20260524-shadow)

![Leaf Reader settings in dark mode](assets/reader-dark-ai.png?v=20260524-shadow)

![Leaf Reader vocabulary review](assets/reader-dark-vocabulary.png?v=20260524-shadow)

### Download

[Leaf Reader 1.7.9 pkg installer](https://github.com/dowellhz/LeafReader/releases/download/v1.7.9/LeafReader-1.7.9.pkg)

### System Requirements

- macOS 14.0 Sonoma or later.
- The reader supports Apple Silicon and Intel Mac; local TTS runtimes currently require Apple Silicon.
- An API key is optional and only needed for AI features.
- Piper's local runtime has a macOS 12.0 minimum, but the current Leaf Reader app requires macOS 14.0 or later.
- Kokoro local speech requires macOS 14.0 or later on Apple Silicon Macs.

### Highlights

- Open local PDF, EPUB, and DOCX files in one macOS app.
- Restore the last opened document, page, zoom level, and reading position.
- Navigate PDFs with toolbar controls, keyboard paging, scroll paging, and direct page-number entry.
- Search documents with `Command+F`, next and previous result controls, and visible result positioning.
- Switch between light and dark reader themes for the document area, search overlay, recent files panel, and AI chat panel.
- Select text and ask the built-in AI assistant to explain, summarize, or translate passages.
- Read selected English or Chinese text with optional downloadable Piper, Kokoro, or Supertonic output where supported; otherwise Leaf Reader falls back to macOS system voices.
- Keep documents local; AI requests are only sent when the assistant is used with the configured API key.

### Optional Speech Runtimes

Leaf Reader can use Piper, [FluidAudio Kokoro Core ML](https://huggingface.co/FluidInference/kokoro-82m-coreml), or Supertonic Core ML for local text-to-speech. Kokoro provides English and Chinese voices, Piper is used for English read aloud, and Supertonic provides multilingual local speech. Small speech runtime executables are bundled in the installer; large model files are downloaded on demand. Open Settings -> AI Analysis -> Speech to download Piper, Kokoro, or Supertonic.

Runtime priority is automatic: Leaf Reader uses the selected runnable runtime, and Chinese content switches to Kokoro. Short word or phrase selections use Apple TTS directly.

Speech model downloads use the asset tag configured by `SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag`. Regenerated archives should only be published when model files change.

### License

Leaf Reader is licensed under the [Apache License 2.0](LICENSE).

Third-party speech models and runtimes remain copyrighted by their respective projects:

- [FluidAudio Kokoro Core ML](https://huggingface.co/FluidInference/kokoro-82m-coreml) / Kokoro model: Apache License 2.0.
- [Piper](https://github.com/rhasspy/piper): MIT License; Piper voice model assets follow the metadata shipped with the upstream model package.

## What's New in 1.7.9

- Improved PDF read-aloud by learning repeated header and footer rows and skipping them during TTS.
- Page-number and footer rows are removed as whole visual rows, so mixed footer text is not spoken.
- Added launch performance diagnostics and delayed speech setup so everyday app startup stays lighter.
- Added focused regression coverage for PDF footer filtering, low-body-text false positives, and launch timing snapshots.

## Development

### Requirements

- macOS 14.0 Sonoma or later.
- Swift toolchain with Cocoa, PDFKit, WebKit, and CryptoKit frameworks.
- Sparkle for release builds.

### Build From Source

Install Sparkle first:

```sh
brew install --cask sparkle
```

Build and run the app:

```sh
./scripts/build_app.sh
open "Leaf Reader.app"
```

Daily builds default to `--debug --arm64` for faster iteration. Use `./scripts/build_app.sh --release --universal` when you need a local release-style universal app; release packaging already does this automatically.
Use `./scripts/audit_app_bundle.sh` to inspect the generated app, speech runtime sizes, symlinks, and largest bundled resources.

### Tests

Run lightweight logic regression tests:

```sh
./scripts/run_tests.sh
```

Run the full local pre-commit check:

```sh
./scripts/check.sh
```

### Speech Model Packages

Generate speech model packages with:

```sh
./scripts/package_speech_models.sh
```

The packaging script also writes `docs/tts/speech-models-manifest.json` with each asset's file size and SHA256 digest. Publish with `--with-speech-models` only when the model archives change.

### Project Layout

- `Leaf Reader.app` - generated macOS application bundle, ignored by git.
- `Sources/LeafReaderApp/` - native Swift source code organized by product feature.
- `Tests/LeafReaderTests/` - lightweight Swift logic regression tests organized by matching feature.
- `docs/` - GitHub Pages site, manual, and Sparkle update feed.
- `assets/` - README icon and screenshots.
- `release/` - local release artifacts when generated.

### Code Wiki

Developer notes live in `docs/wiki/`:

- [Code Wiki index](docs/wiki/index.md)
- [Code Map](docs/wiki/code-map.md)

Regenerate the code map after larger refactors:

```sh
./scripts/generate_code_wiki.sh
```

### Release

Current version: `1.7.9`

Git tag: `v1.7.9`

Latest installer:

[Leaf Reader-1.7.9.pkg](https://github.com/dowellhz/LeafReader/releases/download/v1.7.9/LeafReader-1.7.9.pkg)

Local release package path:

`release/1.7.9/LeafReader-1.7.9.pkg`

Build the signed release package without publishing:

```sh
./scripts/release_pkg.sh 1.7.9
```

Run the full publish flow from a clean working tree:

```sh
./scripts/publish_release.sh 1.7.9
```

The publish script runs tests, builds/signs/notarizes the pkg, smoke-tests the package payload, reports speech runtime size, commits version/appcast changes, tags the release, pushes `main` and the tag, creates the GitHub Release, uploads the pkg, and verifies the download URL. Pass `--with-speech-models` only when publishing changed speech model archives in `docs/tts/`. Add `--push-wiki --cleanup-releases` to sync GitHub Wiki and clean old ignored local release artifacts after publishing.

## Notes

- Bundle identifier: `com.linlu.leafreader`.
- Automatic updates use Sparkle and the public EdDSA key embedded in `Sources/LeafReaderApp/App/Info.plist`.
- PDF rendering uses PDFKit.
- EPUB and DOCX rendering uses WebKit. DOCX support is optimized for readable text extraction rather than exact Word layout fidelity.
- Search selections are kept separate from AI passage selection so search navigation does not accidentally populate the assistant.
- AI requests use the model, endpoint, language, and API key configured locally in the settings panel.
