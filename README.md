# SparklePrompt

SparklePrompt is a native macOS AI teleprompter: a transparent, always-on-top
reading window with smooth scrolling, script workspaces, capture privacy, and
streaming AI generation built directly into the overlay.

It is written in SwiftUI and AppKit. There is no Electron shell, browser view,
plugin host, or bundled web runtime.

[![Latest release](https://img.shields.io/github/v/release/xiepixie/SparklePrompt?display_name=tag)](https://github.com/xiepixie/SparklePrompt/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](#)

---

## Download

1. Download **`sparkleprompt-v*-macos-universal.zip`** from the
   [Releases page](https://github.com/xiepixie/SparklePrompt/releases/latest).
2. Unzip it and move `SparklePrompt.app` to `/Applications`.
3. First launch only: right-click the app, choose **Open**, then confirm
   **Open** in the macOS security dialog. The release is ad-hoc signed rather
   than signed with a paid Apple Developer ID.

If macOS still blocks the app after extraction, run:

```bash
xattr -cr "/Applications/SparklePrompt.app"
```

## What It Does

SparklePrompt is for reading prepared material while presenting, interviewing,
recording, or screen-sharing. The main window floats above other apps, can be
made visually subtle, and can opt out of macOS screen capture paths so you can
see the prompt while capture software sees through it.

Current implementation highlights:

- **Transparent floating prompt** with adjustable scroll speed, font size,
  line spacing, text opacity, background opacity, reading line color, and theme
  accent.
- **Capture privacy mode** using `NSWindow.sharingType = .none`, plus an
  accessory activation policy so the app can hide from the Dock while the
  protected overlay remains visible to you.
- **Ghost Mode** for short locked sessions: enables privacy, always-on-top, and
  mouse click-through after a 3-second preparation countdown, then restores
  interaction after the configured session duration.
- **Script library with workspaces**: import `.txt`, `.md`, or `.text` files,
  drag in folders, search script contents, refresh folder-backed workspaces,
  rename, move, remove, and export scripts.
- **Read-only mounted source files**: imported disk files are cached and tracked
  with bookmarks; removing them from SparklePrompt does not delete the original
  file. AI-generated scripts are stored in the app's own shadow directory.
- **Streaming AI prompt bar** with role prompts, personal style memory,
  optional current-script or workspace-wide context, auto-follow scrolling,
  cancellation, retry, and provider failover.
- **AI providers**: DeepSeek, OpenAI-compatible endpoints, Anthropic, native
  Ollama, Msty Ollama, and Msty MLX.
- **Markdown-aware rendering** with headings, strong emphasis, code-block
  layout, optional forced code mode, and hidden/styled `<think>` reasoning
  blocks.
- **Customizable shortcuts** from the in-app settings panel.

## Everyday Workflow

Open the app, press `L` to show the script library, and import either individual
text/Markdown files or a whole folder. Folder imports become workspaces and can
be refreshed from disk later. Press `Space` to start or pause scrolling, use the
arrow keys to adjust speed, and press `H` when you want a cleaner reading view.

For AI-assisted drafting, press `A`, type a request, and send it. SparklePrompt
creates a new AI script in the current workspace and streams the response into
the teleprompter. You can include the current script as context, use the whole
workspace as context, or turn context off from the prompt bar/settings.

## Keyboard Shortcuts

These are the default shortcuts. They can be changed in
**Settings -> Hotkeys**.

| Key | Action |
| --- | --- |
| `Space` | Play / pause scrolling |
| `R` | Reset scroll and timer |
| `Up` / `Down` | Increase / decrease scroll speed |
| `=` / `-` | Larger / smaller text |
| `M` | Toggle horizontal mirror |
| `F` | Toggle vertical flip |
| `H` | Show / hide the controls bar |
| `E` | Edit the current script |
| `V` | Paste clipboard contents into a new inbox script |
| `T` | Toggle always-on-top |
| `S` | Enter privacy mode; press twice in quick succession to exit |
| `K` | Start / pause speech timer |
| `Shift + K` | Reset speech timer |
| `L` | Show / hide the script library |
| `Option + [` / `Option + ]` | Previous / next script in current workspace |
| `Command + Option + [` / `Command + Option + ]` | Previous / next workspace |
| `A` | Show / hide AI prompt bar |
| `[` / `]` | Decrease / increase background opacity |
| `,` / `.` | Decrease / increase text opacity |
| `Esc` | Close settings/editor/AI prompt, or stop default Esc window behavior |

## Privacy Modes

Privacy mode combines capture exclusion and stealthier app activation:

- The window sets `sharingType` to `.none`, which asks macOS capture APIs such
  as ScreenCaptureKit and `CGWindowList` to omit it.
- The app switches to `.accessory` activation policy, hiding it from the Dock.
- Always-on-top is forced while privacy mode is active.
- The presentation style becomes lower-contrast and can apply blur.
- Release `.app` bundles start as an agent app (`LSUIElement`) so a persisted
  privacy-mode launch can apply capture protection before the first visible
  frame.

Ghost Mode is a stricter temporary session. It starts with a 3-second countdown,
then enables mouse click-through, privacy mode, and always-on-top while the
timer runs. Use it when you need the prompt visible but want clicks to reach the
app underneath.

Capture exclusion depends on macOS and the recorder honoring native window
sharing flags. Test your exact recorder before relying on it for a live event.

## AI Configuration

Open settings and configure providers under **Model Providers**:

- API keys are saved in macOS Keychain.
- Provider URLs, selected models, roles, context options, failover order, and
  appearance settings are saved in `UserDefaults`.
- Local Ollama/Msty providers can use their local endpoints without a remote
  API key.
- Model discovery uses each provider's model-list endpoint when available.

AI generation stores its output in:

```text
~/Library/Application Support/SparklePrompt/ai_scripts/<workspace-id>/
```

Those generated scripts can be renamed, deleted, moved between workspaces, or
exported. Deleting an AI script removes its shadow file; deleting a normal
imported script only removes SparklePrompt's library entry.

## Build From Source

Requirements:

- macOS 14 or newer
- Swift toolchain from Xcode Command Line Tools for normal local builds
- Full Xcode for universal arm64 + x86_64 release packaging

Local development:

```bash
git clone https://github.com/xiepixie/SparklePrompt.git
cd SparklePrompt
./build-app.sh
```

Release packaging:

```bash
./package-release.sh
```

Command-line launch:

```bash
./run.sh
```

## Project Layout

```text
.
├── Package.swift
├── Sources/SparklePrompt/
│   ├── SparklePromptApp.swift        # AppKit window, privacy, sidebar resizing
│   ├── SparklePromptViewModel.swift  # app state, playback, library, AI, persistence
│   ├── SparklePromptView.swift       # main overlay, controls, library, editor
│   ├── SettingsView.swift            # provider, role, context, hotkey, privacy settings
│   ├── AIService.swift               # streaming provider client, retry, failover
│   ├── Script.swift                  # Workspace and Script models with bookmarks
│   ├── KeyEventBridge.swift          # local keyboard and scroll monitors
│   ├── DisplayLink.swift             # CVDisplayLink scroll engine
│   └── KeychainHelper.swift          # API key persistence
├── Tools/MakeIcon.swift
├── docs/IMPLEMENTATION.md
├── build-app.sh
├── package-release.sh
└── run.sh
```

For a deeper map of the current implementation, see
[docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md).

## Contributing

Issues and PRs are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for local
development notes and the implementation rules that matter for this codebase.

## License

[MIT](LICENSE) - © 2026 Stephen Adams.
