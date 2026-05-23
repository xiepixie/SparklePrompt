# Changelog

All notable changes to SparklePrompt will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-05-23

### Added
- Documented the current AI teleprompter implementation, including workspaces,
  provider configuration, privacy mode, Ghost Mode, Keychain storage, and the
  script library data model.
- Added `docs/IMPLEMENTATION.md` as a maintainer map for the AppKit window
  layer, SwiftUI views, view model responsibilities, AI streaming flow,
  persistence, build scripts, and known maintenance risks.

### Changed
- Updated repository links to `https://github.com/xiepixie/SparklePrompt.git`.
- Unified executable, app bundle, window class, build scripts, and
  documentation around the SparklePrompt name.

## [0.1.0] - 2026-05-23

Initial SparklePrompt release baseline.

### Added
- Native macOS SwiftUI teleprompter with floating transparent overlay window.
- Smooth pixel-per-second scroll engine using `CVDisplayLink`.
- Capture privacy via `NSWindow.sharingType = .none`.
- Privacy mode, Ghost Mode, and always-on-top window behavior.
- Script library with workspaces, folder imports, refresh, search, rename,
  move, export, and remove actions.
- AI streaming prompt bar with roles, context controls, provider failover, and
  app-owned shadow storage for AI-generated scripts.
- Configurable providers for DeepSeek, OpenAI-compatible endpoints, Anthropic,
  native Ollama, Msty Ollama, and Msty MLX.
- Markdown-aware prompt rendering, code mode, reasoning block handling, and
  customizable shortcuts.
- Local build, release packaging, generated icon, and GitHub Actions workflows.
