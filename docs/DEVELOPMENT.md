# Lyra Voice

Local macOS dictation prototype powered by `whisper.cpp`.

## Model Sources

OpenAI's `openai/whisper` repository provides the official Whisper code and PyTorch model names. This app uses `whisper.cpp`, so it needs GGML model files instead of PyTorch `.pt` files.

Use:

- `ggml-tiny.bin` for very fast testing.
- `ggml-small.bin` for a light everyday model.
- `ggml-medium.bin` for a balanced model.
- `ggml-large-v3-turbo.bin` for the fast high-quality mode.
- `ggml-large-v3.bin` for the most accurate local mode.

The project downloads GGML models from `ggerganov/whisper.cpp` on Hugging Face:

```sh
scripts/download-models.sh
```

Override the model directory:

```sh
LYRAVOICE_MODEL_DIR="$HOME/.cache/openwhispr/whisper-models" scripts/download-models.sh
```

## Checks

```sh
swift run LyraVoiceCoreSmokeTests
swift build
```

## Run Dev App

Use the app bundle for manual microphone testing. It includes the macOS
permission strings that are not available when running directly through
`swift run`.

```sh
scripts/build-dev-app.sh
open "build/Lyra Voice.app"
```

Shortcut:

```sh
scripts/run-dev-app.sh
```

Then use the `LV` menu bar item:

- `Открыть Lyra Voice` opens the visual control window.
- The app now also opens as a normal macOS window/Dock app, not only as a menu
  bar utility. Dock reopen also brings the control window back.
- The control window is the primary interface. Its sidebar now follows the
  reference-informed IA: `Home`, `Modes`, `Vocabulary`, `Models`, `Sound`,
  `System`, and `History`.
- Existing controls are grouped by user intent: hotkeys and polish live in
  `Modes`; replacement dictionary lives in `Vocabulary`; Whisper model,
  language, prompt, `whisper-cli` path, and model directory live in `Models`;
  microphone, media handling, and feedback sounds live in `Sound`; auto-paste,
  interface language, Dock/login behavior, and permission buttons live in
  `System`; recent dictations live in `History`.
- Use the model selector in the control window to switch between `Tiny`,
  `Small`, `Medium`, `Turbo`, and `Large v3`. Each option shows a speed and
  accuracy score plus an approximate download size. The app can download a
  missing selected model into the configured model folder and shows download
  progress.
- New installs default to
  `~/Library/Application Support/LyraVoice/Models` for downloaded models.
- `Apply Settings` saves language, prompt, binary path, and model directory to
  `~/Library/Application Support/LyraVoice/settings.json`.
- `Set key` in the shortcut settings assigns two independent shortcuts:
  `Start / Stop` and `Hold to dictate`. Both are available at the same time.
- `Start Recording` asks for microphone permission when needed and shows the
  compact overlay at the bottom edge of the screen and plays a light start
  sound.
- `Cancel Recording` cancels an active recording from the control window; the
  overlay cancel button and Escape do the same while recording.
- `Stop and Transcribe` transcribes with the selected local model, copies the text
  to the clipboard, tries to paste it into the active app, saves it to history,
  and plays a light stop sound. During processing, the overlay bars animate.
  Long single-block dictation is lightly split into readable paragraphs after
  transcription.
- The control window exposes the same actions as buttons: start recording, stop
  and transcribe, cancel recording, run bundled test audio, copy the latest
  dictation, open history, and open macOS permission panes.
- `Open Microphone Settings` opens the macOS privacy pane if permission was
  denied.
- `Open Accessibility Settings` opens the macOS privacy pane needed for
  automatic paste. Without this permission, dictation still copies to the
  clipboard.
