# TTS and Read Aloud

Keywords: TTS, speech, Piper, Kokoro, Supertonic, Core ML, runtime downloads, read aloud.

Leaf Reader supports document-level read aloud and short selection pronunciation. It uses a selected local runtime when available and falls back to macOS system speech for short words or phrases.

## Entry Points

- Start document read aloud from the reader controls.
- Use the floating player to pause, resume, move between segments, replay, or stop.
- Pronounce selected text or vocabulary from its popover.
- Download, pause, resume, cancel, or remove speech models in Settings.

## Runtime Structure

Piper provides local English speech. Kokoro provides English and Chinese voices through FluidAudio Core ML. Supertonic provides multilingual speech and shares the FluidAudio Core ML runtime where possible. Small executables ship with the app; larger model assets are downloaded on demand.

The selected runnable runtime is preferred. Chinese content switches to Kokoro. A downloaded runtime is considered runnable only when its files exist and the current macOS version is compatible.

## Playback Flow

```text
Reader selection or document text
  -> normalize and segment text
  -> choose a runnable speech backend
  -> generate WAV audio
  -> play and publish progress
  -> update the current passage highlight
```

## Runtime Rules

- Piper's runtime supports Apple Silicon Macs running macOS 12 or later, although the current Leaf Reader app requires macOS 14 or later.
- Kokoro requires macOS 14 or later.
- Supertonic requires macOS 14 or later.
- Installations write `.leafreader-install-manifest.json`; a manifest failure aborts and rolls back installation.
- Download state includes an active task identifier so stale callbacks cannot replace current state.
- Runtime failures remain visible in Settings until a successful download, cancellation, or removal.
- Removing an inactive runtime must not stop current playback.

## Main Files

- `SpeechPlaybackCoordinator.swift`: runtime choice, segmentation, audio files, playback, and progress.
- `SpeechTextPolicy.swift`: normalization and segmentation rules.
- `SpeechRuntimeResourceManager.swift`: compatibility, download URLs, install state, and cleanup.
- `LocalRuntimeDownloader.swift`, `LocalRuntimeDownloadCoordinator.swift`, and `LocalRuntimeDownloadSupport.swift`: downloads, pause/resume/cancel state, partial data, validation, and HTTP errors.
- `AISettingsPanelController+Speech.swift`: speech settings actions.
- `ReaderWindowController+ReadAloud.swift`: PDF and WebKit read-aloud entry points.
- `ReaderWindowController+ReadAloudProgress.swift`: active passage highlighting.
- `SpeechUtteranceFactory.swift`: macOS system-speech configuration.

## Packaging and Verification

- `scripts/build_app.sh` bundles and validates speech runtimes.
- `scripts/audit_app_bundle.sh` reports runtime, library, resource, and symlink sizes.
- `scripts/package_speech_models.sh` packages downloadable models and updates their manifest.
- `scripts/publish_release.sh` uploads speech archives only when `--with-speech-models` is supplied.

Model download URLs use `SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag`, independently of the application release number. Verify modified native runtime binaries with `vtool` or `otool` before release.
