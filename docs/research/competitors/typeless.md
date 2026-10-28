# Typeless feature audit

Checked 2026-10-27. Official `typeless.com` product, help, policy and release pages; developer-written App Store release history. This is a documented-feature inventory, not an installed-app test. Exclude lookalike domains and unrelated open-source projects with the same name.

## Dictation and language

| ID | Documented behavior | Source |
| --- | --- | --- |
| T01 | Writes into the field where dictation began, across desktop apps. | [Dictate](https://www.typeless.com/help/quickstart/dictate) |
| T02 | Tap shortcut to start; tap again to finish. Default Mac Fn, Windows Right Alt. Voice bar and interaction sound indicate capture. | [Dictate](https://www.typeless.com/help/quickstart/dictate) |
| T03 | Removes spoken filler. | [Product](https://www.typeless.com/) |
| T04 | Removes unnecessary repetition. | [Product](https://www.typeless.com/) |
| T05 | Resolves spoken self-corrections to the final intention. | [Product](https://www.typeless.com/) |
| T06 | Formats lists, steps and key points. | [Product](https://www.typeless.com/) |
| T07 | Rephrases rough thoughts into polished writing. | [Product](https://www.typeless.com/) |
| T08 | Uses spoken side notes as context, reorders thoughts, and handles later changes. These are AI behavior claims requiring semantic tests. | [Mac release notes, July 8](https://www.typeless.com/help/release-notes/macos) |
| T09 | Automatically detects 100+ spoken languages, including mixed-language speech. | [Product](https://www.typeless.com/) |
| T10 | Configurable regional variants for English, Chinese, Spanish, French and Portuguese. | [Dictate](https://www.typeless.com/help/quickstart/dictate) |
| T11 | Dedicated Translate mode produces target-language writing with formatting and preserved tone. | [Translate](https://www.typeless.com/help/quickstart/translate) |
| T12 | Save multiple translation targets; reorder them; choose a target from the voice bar while using Translate. | [Translate](https://www.typeless.com/help/quickstart/translate) |
| T13 | Separate translation shortcut. Mac Fn + Left Shift; finish with main Fn shortcut. | [Translate](https://www.typeless.com/help/quickstart/translate) |
| T14 | Whisper mode appears in the plan comparison. No dedicated behavior or setting documentation found. | [Pricing](https://www.typeless.com/pricing) |

## Voice editing, answers and actions

| ID | Documented behavior | Source |
| --- | --- | --- |
| T15 | Ask anything has a separate shortcut. Mac Fn + Space; finish with main Fn shortcut. | [Ask anything](https://www.typeless.com/help/quickstart/ask-anything) |
| T16 | Rewrite any editable selection by spoken instruction; replace selection directly. Supports tone, format and detail changes. | [Ask anything](https://www.typeless.com/help/quickstart/ask-anything) |
| T17 | Ask about read-only selected text; summarize, explain or translate while preserving the original selection. | [Ask anything](https://www.typeless.com/help/quickstart/ask-anything) |
| T18 | Ask general questions, including current web information; show answers in a pop-up card. | [Ask anything](https://www.typeless.com/help/quickstart/ask-anything) |
| T19 | Voice-requested web searches open the relevant website with search prepared. Exact service/action allowlist undocumented. | [Ask anything](https://www.typeless.com/help/quickstart/ask-anything) |
| T20 | Help me write expands brief instructions into replies, emails, posts or documents inside the active field. Uses Ask anything. | [Help me write, Mac 2.8.0](https://www.typeless.com/help/release-notes/macos/use-help-me-write-desktop) |

## Personalization and dictionary

| ID | Documented behavior | Source |
| --- | --- | --- |
| T21 | Learns general phrasing, tone and writing habits with use; no initial setup. | [Personalization](https://www.typeless.com/help/quickstart/personalization) |
| T22 | Personalization progress card and detailed report. | [Personalization](https://www.typeless.com/help/quickstart/personalization) |
| T23 | Disable personalization to stop learning and use generic phrasing. | [Personalization](https://www.typeless.com/help/quickstart/personalization) |
| T24 | Adapts tone to the current app. | [Product](https://www.typeless.com/) |
| T25 | Manually add words or phrases. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T26 | Automatically learns preferred spelling when users correct dictated words. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T27 | Filter dictionary by automatic/manual origin. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T28 | Import dictionary from CSV on desktop. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T29 | Search, edit and delete dictionary entries. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T30 | Select and delete multiple words, including within search results. | [Mac release notes, September 8](https://www.typeless.com/help/release-notes/macos) |

## History, recovery and privacy controls

| ID | Documented behavior | Source |
| --- | --- | --- |
| T31 | History includes dictations and Ask anything, with separate desktop filters. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T32 | Copy a previous transcript. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T33 | Send per-transcript feedback, including dictated feedback. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T34 | Retry failed processing using the same audio. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T35 | Download original audio on desktop; share audio on mobile. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T36 | Delete individual transcripts or all history. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T37 | Local retention choices: forever, year, month, week, 24 hours or never. | [History and dictionary](https://www.typeless.com/help/quickstart/history-and-dictionary) |
| T38 | Expired history automatically disappears; recover missed output during retention window. | [Missing transcript](https://www.typeless.com/help/troubleshooting/missing-transcript) |
| T39 | Nine-minute session limit, countdown after eight minutes, automatic History save at limit. | [Dictation limit](https://www.typeless.com/help/troubleshooting/dictation-limit) |
| T40 | Optional history text cloud sync; explicit enable step, initial synchronization and cross-device history. | [Cloud Sync, Mac 2.4.0](https://www.typeless.com/help/release-notes/macos/keep-your-history-synced) |
| T41 | Disabling cloud sync deletes cloud history text. Cloud transcription and contextual processing remain part of normal operation. | [Data controls, October 13](https://www.typeless.com/data-controls) |
| T42 | Policy says audio and relevant app/text context are discarded after processing; feedback has separate exceptions. This is a vendor policy claim. | [Privacy, October 13](https://www.typeless.com/privacy) |

## Settings, input and desktop behavior

| ID | Documented behavior | Source |
| --- | --- | --- |
| T43 | Change individual shortcuts for Dictate, Translate and Ask anything. | [Settings](https://www.typeless.com/help/quickstart/settings) |
| T44 | Multiple shortcuts per mode support external keyboards; remove additional shortcuts individually. | [Settings](https://www.typeless.com/help/quickstart/settings) |
| T45 | Mouse middle/side buttons can trigger modes. | [Mac release notes, September 16](https://www.typeless.com/help/release-notes/macos) |
| T46 | Follow default microphone or select a particular device; visible input-level test. | [Settings](https://www.typeless.com/help/quickstart/settings) |
| T47 | Toggle start/stop interaction sounds. | [Settings](https://www.typeless.com/help/quickstart/settings) |
| T48 | Mute other audio during dictation. | [Settings](https://www.typeless.com/help/quickstart/settings) |
| T49 | Launch at login; optionally show Mac Dock icon. | [Settings](https://www.typeless.com/help/quickstart/settings) |
| T50 | Light, dark or system appearance; 58 interface languages. | [Settings](https://www.typeless.com/help/quickstart/settings) |
| T51 | Home and menu-bar update checks. | [Update help](https://www.typeless.com/help/troubleshooting/check-for-updates) |
| T52 | Activity days, current/longest streak, usage heatmap, and shareable insight cards. | [Mac release notes, August 11 and September 1](https://www.typeless.com/help/release-notes/macos) |

## Mobile differences

| ID | Documented behavior | Source |
| --- | --- | --- |
| T53 | System keyboard with tap-to-start/tap-to-finish dictation. | [Dictate](https://www.typeless.com/help/quickstart/dictate) |
| T54 | Selected-text voice editing through keyboard button; replaces selection. | [Speak to edit](https://www.typeless.com/help/quickstart/speak-to-edit) |
| T55 | Hold Speak and swipe up to select translation target. | [Translate](https://www.typeless.com/help/quickstart/translate) |
| T56 | Keep recording while keyboard closes or user switches app; return to keyboard to finish. | [iOS developer release history, 1.7.0](https://apps.apple.com/us/app/typeless-ai-voice-keyboard/id6749257650) |
| T57 | Swipe to ordinary typing keyboard; learned suggestions; 36 keyboard languages. | [iOS developer release history, 1.5.0](https://apps.apple.com/us/app/typeless-ai-voice-keyboard/id6749257650) |
| T58 | Optional iOS Picture in picture mode avoids activation app switching; off-screen controller, idle microphone off. | [Picture in picture, iOS 1.9.0](https://www.typeless.com/help/release-notes/ios/picture-in-picture) |
| T59 | Mobile Help me write button; automatic dictionary entries from Swipe-to-type corrections. | [iOS developer release history, 2.7.0 and 2.8.0](https://apps.apple.com/us/app/typeless-ai-voice-keyboard/id6749257650) |
| T60 | Traditional Chinese Zhuyin and Japanese flick typing. | [iOS release notes, August 18 and May 18](https://www.typeless.com/help/release-notes/ios) |

## Platform and organization coverage

| ID | Documented behavior | Source |
| --- | --- | --- |
| T61 | Mac Apple Silicon/Intel, Windows, Linux, iOS and Android. Linux announcement September 24, 2026. | [FAQ](https://www.typeless.com/help/faqs), [Linux release](https://www.typeless.com/help/release-notes/linux) |
| T62 | Google, Apple and email sign-in; organization SSO where configured. | [Installation](https://www.typeless.com/help/installation-and-setup) |
| T63 | Guided microphone/Accessibility setup and microphone test; interactive examples for each mode. | [Installation](https://www.typeless.com/help/installation-and-setup) |
| T64 | Pro offers team members, central billing/invoices and team usage analytics. | [Pricing](https://www.typeless.com/pricing) |
| T65 | Enterprise lists SSO, SCIM/JIT provisioning, domain capture, configurable audit retention and enforced HIPAA controls. | [Pricing](https://www.typeless.com/pricing) |

## Implementation implications for RJT

These are recommendations derived from the inventory, not claims about current RJT code.

- Model Dictate, Translate and Ask as separate session intents. Preserve the original insertion target throughout capture and processing.
- Separate editing selected text from answering about selected text. A summary of read-only text must not replace a selection.
- Translate needs a target language independent of recognition language. Preserve ordered favorites and regional variants.
- Dictionary learning needs correction attribution, source tracking, review and removal. Never infer a preferred spelling from unrelated typing.
- Recover failed sessions from retained audio. Apply retention to recordings and transcripts consistently, including `Never` and crash leftovers.
- Keep context disclosure explicit. Cloud processing, local history and optional sync are different settings and storage paths.
- Test meaning preservation with answer-hidden audio cases for repetitions, false starts, corrected names, mixed languages and reordered ideas. A cleanup prompt alone does not establish parity.
- Test shortcuts across tap/hold/release order, external keyboards and mouse events; preserve ordinary key/button use when inactive.
- Voice web actions need typed destinations and properly encoded queries. Do not let generated content become arbitrary shell or navigation commands.

## Coverage and limits

65 numbered capabilities, including mobile and organization features. Read all seven Quickstart articles, installation, FAQ, pricing, Ask marketing page, history recovery, recording limit, shortcut conflicts, permission/update/microphone troubleshooting, data controls, privacy, Mac/iOS/Linux release material and iOS developer release history. No account created, product installed or paid feature tested.

Important unresolved points:

- The Mac/Windows/iOS release index returned an empty body through direct page extraction. Search indexing exposed its release entries; individual Help me write, sync and Picture in picture pages were also read. Do not assume the index proves an installed latest version.
- History guide still says device-only history. October 13 data controls and August 26 release explain optional cloud history; preserve that exception in comparisons.
- Whisper mode has no concrete behavior description in the reviewed help articles. Marketing speed, accuracy, battery and compliance claims were not independently measured or audited.
- No public detailed contract found for correction-observation windows, supported web-action destinations, selection safety, rich text preservation, undo, personalization storage/reset or sync encryption/key ownership.
- Nine-minute limit comes from the current official article. Third-party lookalike help pages report other values and were excluded.
- Native desktop Ask features should not be assumed to work identically on mobile. Mobile documentation names Speak to edit and Help me write separately.
