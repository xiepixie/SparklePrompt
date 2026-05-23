# Contributing

Thanks for considering a contribution. SparklePrompt is still a small native
macOS app, but the current implementation includes window privacy, workspaces,
AI streaming, Keychain persistence, and custom shortcuts. Please read
[docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) before making broad changes.

## Development Setup

You need:

- macOS 14 or newer.
- Swift toolchain from Xcode Command Line Tools for normal local builds.
- Full Xcode for universal release binaries.

Common commands:

```bash
git clone https://github.com/xiepixie/SparklePrompt.git
cd SparklePrompt
./run.sh
./build-app.sh
./package-release.sh
```

## Project Map

```text
Sources/SparklePrompt/
  SparklePromptApp.swift        - AppKit app delegate, NSPanel setup, privacy
  SparklePromptViewModel.swift  - state, playback, library, AI, persistence
  SparklePromptView.swift       - main overlay, controls, library, editor
  SettingsView.swift            - provider, role, context, hotkey, privacy UI
  AIService.swift               - streaming requests, retries, provider failover
  Script.swift                  - Workspace and Script models with bookmarks
  KeyEventBridge.swift          - local key/scroll event monitors
  DisplayLink.swift             - CVDisplayLink smooth scroll loop
  KeychainHelper.swift          - macOS Keychain wrapper for API keys

Tools/MakeIcon.swift            - Core Graphics icon generator
build-app.sh                    - local .app assembly
package-release.sh              - universal release zip
run.sh                          - command-line build and launch
docs/IMPLEMENTATION.md          - deeper architecture and behavior notes
```

## Pull Requests

- Keep changes focused: one feature or fix per PR.
- Preserve the local-first library rule: normal imported files should not be
  mutated or deleted by library operations; app-owned AI scripts may be written
  and removed from the shadow directory.
- When changing privacy/window behavior, test normal mode, privacy mode, and
  Ghost Mode.
- When changing library behavior, test both folder-backed scripts and
  AI-generated scripts.
- When changing AI behavior, check at least one remote provider path and one
  local/OpenAI-compatible path when possible.
- Update `README.md`, `docs/IMPLEMENTATION.md`, and
  `SparklePromptViewModel.defaultText` when user-facing shortcuts or workflows
  change.
- Bump `VERSION` and add a `CHANGELOG.md` entry for release-worthy changes.

## Persistence Rules

- Store non-secret preferences in `UserDefaults`.
- Store API keys only in Keychain through `KeychainHelper`.
- Avoid automatic Keychain writes from debounced save paths; the current design
  saves secrets on explicit settings save/close to reduce macOS authorization
  prompts.
- Add migration logic for any persisted schema change.

## Reporting Bugs

Please include:

- macOS version.
- Apple Silicon or Intel.
- App version or commit SHA.
- Whether privacy mode or Ghost Mode was active.
- Whether the script came from a folder import, single-file import, clipboard,
  or AI generation.
- Steps to reproduce, expected behavior, and actual behavior.

## Releasing

```bash
# 1. Bump VERSION and update CHANGELOG.md
echo "0.2.0" > VERSION
$EDITOR CHANGELOG.md

# 2. Build the universal release zip
./package-release.sh

# 3. Tag and publish
git commit -am "Release v0.2.0"
git tag v0.2.0
git push origin main --tags
gh release create v0.2.0 \
    .build/release-package/sparkleprompt-v0.2.0-macos-universal.zip \
    --title "v0.2.0" \
    --notes-file CHANGELOG.md
```

The GitHub Actions workflow at `.github/workflows/release.yml` also builds and
publishes a release automatically when a `v*` tag is pushed.
