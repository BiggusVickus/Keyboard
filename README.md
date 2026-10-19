# Taalhulp: an EN / DE / NL keyboard with a grammar coach

A custom iOS keyboard for typing English, German and Dutch. It has autocorrect, a grammar check (de/het, word order, verb forms…) with English explanations, and a built-in translator.

## Status

| Milestone | What | State |
|---|---|---|
| 0 | Project setup, runs on iPhone | ✅ code ready, needs a first build on the Mac |
| 1 | Basic keyboard: 3 layouts, language key, shift/caps lock, delete repeat, long-press accents | ✅ code ready |
| – | Settings app: languages, autocorrect strength, grammar level, AI provider (Claude / local LLM) | ✅ code ready |
| 2 | Autocorrect + suggestion bar (undo, learned words, contacts, text replacements) | ✅ code ready |
| 3 | Grammar check (LanguageTool) with red error / blue tip chips and Accept | ✅ code ready |
| 4 | English explanations, offline de/het checker, learning log (Learn tab) | ✅ code ready |
| 4b | Claude / local LLM / Apple on-device: Explain, "Is this correct?", Improve | ✅ code ready |
| 5 | Translator panel | ✅ code ready |
| 6 | Finishing touches: key previews, dark keyboards, return key labels, e-mail/URL keys | ✅ code ready |
| 7 | iOS key sounds, space-bar trackpad, long-press on every page, period + web endings, QWERTY German, faster touch handling, touch map (normal / larger / trained) | ✅ code ready |
| – | Windows: automatic 7-day refresh when the iPhone is plugged in | ✅ scripts ready, not yet run on Windows |

"Code ready" means: `KeyboardCore` builds and its 115 unit tests pass, and the app and keyboard compile for iOS (`xcodebuild`). They haven't been tried on an iPhone yet; see [First build: what to check](#first-build-what-to-check).

## Using the keyboard

- **Suggestion bar:** up to three words. A highlighted word replaces what you typed when you press space (in *Automatic* mode). Tap “typed” (in quotes) to keep your word; the keyboard learns it. Right after an autocorrection, tap ↩︎ to undo it.
- **Grammar chips:** after a short pause the text is checked. 🔴 red = error, 🔵 blue = optional tip. Tap a chip for an English explanation, then **Accept** the fix, **Explain** (asks the AI) or **Ignore**.
- **de/het, deze/dit, die/dat:** works offline with about 230,000 Dutch nouns and plurals from Wiktionary, a hand-checked list of 640 common nouns, and rules for the rest (*-je* → het, *-heid* → de, compounds). It catches *het auto*, *deze huis*, *met die huis*, *het meisjes* and *een grote huis*. It only flags what it is sure about: words that can also be something else (*Ik gooi het **weg***, *Het **rook** lekker*), names, and *die*/*dat* used as "who" or "that" are left alone. Run over 20,000 real Dutch sentences, it flagged 29, about a third of them real mistakes; most of the rest are words that take either article in parts of the language area (*duin*, *pedaal*), for which Wiktionary lists only one.
- **✦ button:** *Is this correct?* and *Improve* send the current sentence to the AI picked in Settings. *Translate* opens a box above the keys: type there, then **Insert**. *Use my text* translates the sentence you just wrote and replaces it.
- **Text expansions** (Settings → Text expansions): your own shortcuts, e.g. `mvg` → *Met vriendelijke groet,*. While you type the shortcut, the bar above the keys shows what it becomes. Space or punctuation expands it, tapping the bar expands it right away, and ✕ keeps what you typed. Right after expanding, the bar offers ↩︎ to undo it.
- **Learn tab** (in the app): every accepted fix, grouped by topic (de/het, word order, verb forms…), with the rule.
- **Layouts:** all three languages are QWERTY. German umlauts and ß are on long-press (a → ä, o → ö, u → ü, s → ß).
- **Long-press:** letters show accents; on the 123 and #+= pages, `!` → ¡, `?` → ¿, `0` → °, `€`/`$` → other currencies, `-` → – —, `"` → „ “ ” « », `'` → ‘ ’ ‚. Slide to pick, lift to type.
- **Period and web endings:** a `.` key sits right of the space bar. Hold it for `.nl .com .be …` (Dutch), `.de .com .at .ch …` (German) or `.com .org .net .co.uk …` (English).
- **Trackpad:** hold the space bar, like on Apple's keyboard. The keys make way for the text around your cursor, with a blue floating cursor that glides smoothly under your finger in any direction, and a grey cursor where it will land. The cursor in the app follows along live. (iOS doesn't let other keyboards draw a floating cursor inside the app itself, so it's shown in the keyboard.)
- **Sounds and haptics:** the real iOS key sounds: one for letters, one for delete, one for shift/space/return/123. They play the moment your finger touches the key, and follow the silent switch. Turn off under Settings → Typing → Key sounds. Both need Full Access.
- **Touch map** (Settings → Touch map): *Normal*: every key has its own area, and taps in the gaps go to the nearest key. *Larger letters*: letters also reach 6 pt into shift, delete and the space bar. *Custom (trained)*: tap **Train my touch map…**, type 5 sentences, and the keyboard learns where you really hit each letter. **Train more…** adds another round. The picture in Settings shows which key each spot types; for a trained map your taps are drawn on it as a heat map.

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

> **Free Apple ID vs. paid developer account:** with a free Apple ID, apps stop working after 7 days and need a fresh ⌘R (or see [Automatic 7-day refresh from Windows](#automatic-7-day-refresh-from-windows)). The $99/year Apple Developer Program removes that limit. If Xcode reports a problem with **App Groups** on a free account, the keyboard still runs, but settings changed in the app won't reach the keyboard until you join the program.

## First build: what to check

These parts could not be tried without a Mac and iPhone:

1. **Build errors in the app or keyboard.** Fix them as Xcode reports them; the shared code in `KeyboardCore` already compiles.
2. **Grammar fixes in the middle of the text.** Accept moves the cursor with `adjustTextPosition` (UTF-16 offsets), replaces the words, and moves back. Try it in Notes and in WhatsApp, including text with emoji before the fix.
3. **Key previews on the top row.** The bubble must not be cut off at the top. If it is, make the preview in `KeyButton.swift` a bit lower.
4. **Apple on-device AI.** It may not be allowed inside keyboards. If it fails, the keyboard says so; pick Claude or a local LLM instead.
5. **LanguageTool rule names.** `GrammarTopic.swift` maps rule IDs and message keywords to topics. Look at a few real chips and adjust where the topic is wrong.
6. **Key sounds.** They use the system sounds 1104 / 1155 / 1156 and need Full Access. If they're silent, check the silent switch first.
7. **Bottom-row speed.** iOS holds back touches right next to the home indicator for a moment (the "System gesture gate timed out" lines in the console). A keyboard can't turn that off. Compare fast typing on the space bar with Apple's keyboard.
8. **Trackpad** in Notes, Mail and WhatsApp. The text shown in the keyboard comes from what iOS lets a keyboard see around the cursor (usually the current paragraph or a few hundred characters), so in very long texts you can only move within that part per drag; let go and hold again to go further. The line breaks in the keyboard's copy can differ from the app's, but the character position is exact.
9. **Touch map after training.** Settings → Touch map → Custom should feel at least as accurate as Normal. If not, train another round or switch back.

## Automatic 7-day refresh from Windows

With a free Apple ID, the app stops opening after 7 days. These scripts re-sign it from a Windows PC every time you plug the iPhone in by cable, with nothing to click. They use **plumesign** (the command-line part of the open-source [Impactor](https://github.com/claration/Impactor)), signing in with your own Apple ID like Xcode does.

**Once, on the Mac:** build the app as an .ipa (Xcode must be signed in to your Apple ID):
```sh
sh Tools/build_ipa.sh        # → build/Taalhulp.ipa
```
Copy `build/Taalhulp.ipa` and the `Tools/windows` folder to the PC.

**Once, on the PC:**
1. Install **iTunes** ([support.apple.com/106372](https://support.apple.com/en-us/106372)): it brings Apple's USB drivers. Plug in the iPhone, unlock it and tap **Trust**.
2. In PowerShell, in the copied `windows` folder:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Setup-AutoRefresh.ps1 -AppleId you@example.com -Ipa ..\Taalhulp.ipa
   ```
   Type your Apple ID password and the 2FA code when asked (once). Your password isn't stored; plumesign keeps a session token in `%APPDATA%\PlumeImpactor`.

**From then on:** plug in the iPhone. Within seconds a background task re-signs and reinstalls Taalhulp, and a Windows notification says "Taalhulp refreshed". Plugging in again within 12 hours does nothing (change with `-MinHoursBetweenRefreshes 0` to refresh on every connection). Settings, learned words and the learning log survive each refresh.

- **Refresh right now:** `powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\TaalhulpRefresh\Watch-iPhone.ps1" -Once`
- **New build from the Mac:** `.\Setup-AutoRefresh.ps1 -Ipa ..\Taalhulp.ipa -UpdateIpaOnly`
- **"Apple sign-in expired":** `.\Setup-AutoRefresh.ps1 -LoginOnly -AppleId you@example.com`
- **Log:** `%LOCALAPPDATA%\TaalhulpRefresh\refresh.log`. **Remove:** `.\Setup-AutoRefresh.ps1 -Uninstall`

Things to know:
- The PC must be logged in (the watcher runs in your Windows session). The iPhone needs Developer Mode on, as for Xcode.
- plumesign renames the App Group to `group.com.victorpiaskowski.taalhulp.<TEAMID>`. `SettingsStore` reads the group from the app's provisioning profile, so app and keyboard still share settings. The first Windows-signed install starts with fresh settings (it's a new group); after that they stay.
- The first run creates a signing certificate named after the PC. Free accounts allow only a few, so Xcode on the Mac may ask to create a new one the next time you press ⌘R. That's fine.
- The app keeps its bundle ID, so it replaces the Xcode-installed copy instead of adding a second app (free accounts allow 3 sideloaded apps).

## Everyday development

- **Run the unit tests** (no iPhone needed):
  ```sh
  cd Packages/KeyboardCore
  swift test
  ```
- **Debug the keyboard itself:** pick the **TaalhulpKeyboard** scheme and press ⌘R. Xcode asks which app to run it in; pick **Notes**. Breakpoints and `print()` in the keyboard code then work.
- **Memory:** iOS kills keyboards that use too much memory (around 50–70 MB). Check the memory gauge in Xcode's Debug Navigator (⌘7) while typing.
- **LanguageTool limits:** the free public server allows about 20 checks per minute. The keyboard waits 1.2 s after you stop typing and caches results. If you hit the limit often, run your own server (`docker run -p 8010:8010 erikvl87/languagetool`) and set its URL in Settings.
- **Tests without a Mac:** the shared package also builds on Linux, e.g. with Docker:
  ```sh
  docker run --rm -v "$PWD/Packages/KeyboardCore:/pkg" -w /pkg swift:6.1-noble swift test
  ```

## Project layout

```
project.yml                 XcodeGen definition (app + keyboard + shared package)
App/                        The Taalhulp app: setup, Learn tab (learning log), settings, touch trainer + press map
Tools/build_ipa.sh          Builds build/Taalhulp.ipa for the Windows auto-refresh
Tools/windows/              Setup-AutoRefresh.ps1 (one-time setup), Watch-iPhone.ps1 (refreshes on USB connect)
KeyboardExtension/          The keyboard
  KeyboardViewController    Entry point iOS talks to; hosts the SwiftUI keyboard
  KeyboardViewModel         Keyboard state: keys, suggestions, grammar, panels, AI, translator
  Services/                 UITextChecker spell checker, AI client factory, Apple on-device AI
  Services/KeyFeedback      iOS key sounds and haptics, played on touch down
  Views/                    KeyboardView, TopBar (suggestions + chips), KeyCap (how a key looks),
                            KeyTouchHandler (all touches: taps, long-press popups, delete repeat, trackpad),
                            TrackpadView (floating cursor over a TextKit copy of the text)
  Views/Panels/             Grammar details, ✦ tools, AI review, translator bar
Packages/KeyboardCore/      Shared code, no UIKit, unit tested
  Language, Layouts/        EN / DE / NL layouts, long-press alternates, web endings, key geometry (frames)
  Touch/                    Touch map: hit testing (normal / larger / custom), trained profile, trainer + sentences
  Typing/                   TypingEngine (shift, capitalisation, double-space period), FieldTraits (return key…)
  Text/                     Words and sentences before the cursor, replacing text, TextBuffer, text expansions
  Spelling/                 Autocorrector (suggestions, when to auto-fix), learned words
  Grammar/                  LanguageTool client, offline de/het checker, topics + English explanations
  AI/                       Claude (HTTPS), OpenAI-compatible local server, prompts (Assistant)
  Learning/                 Learning log
  Settings/                 TaalhulpSettings + SettingsStore (shared via App Group)
```

## The de/het word list

`Packages/KeyboardCore/Sources/KeyboardCore/Resources/DutchNouns.txt` (7 MB) is built from Wiktionary by `Tools/build_dutch_nouns.py`. The keyboard memory-maps it and searches it directly, so it doesn't count against the keyboard's memory limit. To rebuild it with newer Wiktionary data:

```sh
curl -LO https://kaikki.org/dictionary/downloads/nl/nl-extract.jsonl.gz          # Dutch Wiktionary, ~130 MB
curl -LO https://kaikki.org/dictionary/Dutch/kaikki.org-dictionary-Dutch.jsonl  # English Wiktionary, Dutch words, ~250 MB
python3 Tools/build_dutch_nouns.py nl-extract.jsonl.gz kaikki.org-dictionary-Dutch.jsonl     > Packages/KeyboardCore/Sources/KeyboardCore/Resources/DutchNouns.txt
cd Packages/KeyboardCore && swift test
```

Sites such as welklidwoord.nl offer no download and no permission to reuse their data, so Wiktionary is used instead.

**Licence:** the word list is derived from [Wiktionary](https://www.wiktionary.org) (Dutch and English editions), © Wiktionary contributors, licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). It was extracted with [wiktextract](https://github.com/tatuylonen/wiktextract) / [kaikki.org](https://kaikki.org) (Tatu Ylonen, *Wiktextract: Wiktionary as Machine-Readable Structured Data*, LREC 2022) and reduced to word, de/het and adjective forms. The list itself may only be shared under the same licence. The app shows this credit on the Setup tab.

## AI options

| Option | Cost | Quality for NL/DE grammar | Needs |
|---|---|---|---|
| None | free | LanguageTool rules only | – |
| Claude (Haiku / Sonnet / Opus / Fable, or any model ID) | about $0.35–13/month with light use | best | API key from platform.claude.com, separate from a Claude.ai subscription. Opus, Sonnet and Fable requests use Anthropic's automatic fallback model if a safety filter wrongly declines one. |
| Local LLM (Ollama / LM Studio) | free | fair to good, depends on the model and the Mac's memory | Mac switched on and reachable (Wi-Fi or Tailscale) |
| Apple on-device | free | weaker, experimental | Apple Intelligence; may not work in keyboards |
