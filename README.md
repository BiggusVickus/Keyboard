# Taalhulp: an EN / DE / NL keyboard with a grammar coach

A custom iOS keyboard for typing English, German and Dutch. It has autocorrect, a grammar check (de/het, word order, verb forms…) with English explanations, and a built-in translator.

## Status

| Milestone | What | State |
|---|---|---|
| 0 | Project setup, runs on iPhone | ✅ code ready, needs a first build on the Mac |
| 1 | Basic keyboard: 3 layouts, language key, shift/caps lock, delete repeat, long-press accents | ✅ code ready |
| – | Settings app: languages, autocorrect strength, grammar level, AI provider (Claude / local LLM) | ✅ code ready (the settings are saved; the keyboard doesn't use the grammar ones yet) |
| 2 | Autocorrect + suggestion bar | ⏳ |
| 3 | Grammar check (LanguageTool) with error/tip chips and Accept | ⏳ |
| 4 | English explanations, de/het dictionary, learning log | ⏳ |
| 4b | Claude / local LLM: Explain, "Is this correct?", Improve | ⏳ |
| 5 | Translator panel | ⏳ |
| 6 | Finishing touches (key previews, dark mode, return key types) | ⏳ |

## First-time setup on the Mac

1. **Install Xcode** from the Mac App Store. Open it once and let it install the iOS components.
2. **Install XcodeGen**, which generates the Xcode project from `project.yml`:
   ```sh
   # Install Homebrew first if you don't have it: https://brew.sh
   brew install xcodegen
   ```
3. **Get this folder onto the Mac.** A private GitHub repo is easiest. A USB stick or cloud drive also works.
4. **Add your Apple ID to Xcode:** Xcode → Settings → Accounts → **+** → Apple ID. Click your account and copy the **Team ID** (10 characters).
5. **Edit `project.yml`:**
   - Paste your Team ID into `DEVELOPMENT_TEAM: ""`.
   - Bundle IDs must be unique worldwide. Replace `com.victor` with something of your own, such as `com.victorpiaskowski`. Change it in **all** places in `project.yml`, and in `Packages/KeyboardCore/Sources/KeyboardCore/Settings/SettingsStore.swift` (`appGroupID`).
6. **Generate and open the project:**
   ```sh
   cd path/to/Keyboard
   xcodegen
   open Taalhulp.xcodeproj
   ```
   Run `xcodegen` again whenever files are added or `project.yml` changes.
7. **Prepare the iPhone:** connect it with a cable, then go to Settings → Privacy & Security → **Developer Mode** → on (the iPhone restarts).
8. In Xcode, pick the **Taalhulp** scheme and your iPhone at the top, then press **⌘R**.
   The first time, the iPhone may ask you to trust the developer: Settings → General → VPN & Device Management → your Apple ID → Trust.
9. Open the Taalhulp app on the iPhone and follow the **Setup** tab to turn on the keyboard.

> **Free Apple ID vs. paid developer account:** with a free Apple ID, apps stop working after 7 days and need a fresh ⌘R. The $99/year Apple Developer Program removes that limit. If Xcode reports a problem with **App Groups** on a free account, the keyboard still runs, but settings changed in the app won't reach the keyboard until you join the program.

## Everyday development

- **Run the unit tests** (no iPhone needed):
  ```sh
  cd Packages/KeyboardCore
  swift test
  ```
- **Debug the keyboard itself:** pick the **TaalhulpKeyboard** scheme and press ⌘R. Xcode asks which app to run it in; pick **Notes**. Breakpoints and `print()` in the keyboard code then work.
- **Memory:** iOS kills keyboards that use too much memory (around 50–70 MB). Check the memory gauge in Xcode's Debug Navigator (⌘7) while typing.

## Project layout

```
project.yml                 XcodeGen definition (app + keyboard + shared package)
App/                        The Taalhulp app: setup instructions and settings
KeyboardExtension/          The keyboard
  KeyboardViewController    Entry point iOS talks to; hosts the SwiftUI keyboard
  KeyboardViewModel         Keyboard state and what each key does
  Views/                    KeyboardView (rows + top bar), KeyButton (one key)
Packages/KeyboardCore/      Shared code, no UIKit, unit tested
  Language, Layouts/        EN / DE / NL layouts and long-press accents
  Typing/TypingEngine       Shift, caps lock, auto-capitalisation, double-space period
  Settings/                 TaalhulpSettings + SettingsStore (shared via App Group)
```

## AI options

| Option | Cost | Quality for NL/DE grammar | Needs |
|---|---|---|---|
| None | free | LanguageTool rules only | – |
| Claude (Haiku / Sonnet / Opus / Fable, or any model ID) | about $0.35–13/month with light use | best | API key from platform.claude.com, separate from a Claude.ai subscription |
| Local LLM (Ollama / LM Studio) | free | fair to good, depends on the model and the Mac's memory | Mac switched on and reachable (Wi-Fi or Tailscale) |
| Apple on-device | free | weaker, experimental | Apple Intelligence; may not work in keyboards |
