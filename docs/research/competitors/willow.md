# Willow feature audit

Checked 2026-10-27. Product: [Willow Voice](https://willowvoice.com/), not unrelated Willow assistants. Primary sources only. Documentation audit; no installed-app or account validation. “Documented” means official help describes a usable workflow; “claimed” means product/plan copy without comparable setup detail.

## Dictation and control

| ID | Feature | Documented behavior / boundary | Evidence |
|---|---|---|---|
| W01 | Dictate into other apps | Focus a text field; hold hotkey; release inserts formatted output at cursor. Mac instructions. | [Dictating][dictating] |
| W02 | Hands-free dictation | Double-tap dictation key; next press finishes and inserts. | [Dictating][dictating] |
| W03 | Multiple configurable hotkeys | Up to four dictation bindings; individual keys or combinations; combination requires modifier; left/right modifier choices. | [Hotkeys][hotkeys] |
| W04 | Dedicated hands-free binding | One press enters hands-free mode instead of double-tap. | [Hotkeys][hotkeys] |
| W05 | Separate writing-assistant binding | Independently configurable assistant/Scribe shortcut. Scribe default: Fn+Control on Mac; left Windows+left Shift on Windows. | [Hotkeys][hotkeys], [Scribe guide][scribe] |
| W06 | Preferred microphone | Select input explicitly; it remains selected when headphones connect, when available. | [Microphone][microphone] |
| W07 | Automatic formatting | Adds punctuation, spacing, paragraph breaks, quotes; adjusts by writing context. | [Formatting][formatting] |
| W08 | Lists | Detects spoken sequences; numbered list via one/two/three; bullets via “bullet” before items. Timing/pause cues also used. | [Formatting][formatting] |
| W09 | Spoken punctuation | Commands for comma, period, question/exclamation mark, quotes, dash/em dash. | [Formatting][formatting] |
| W10 | Explicit line/paragraph breaks | “New line”, “next line”, “new paragraph”. | [Formatting][formatting] |
| W11 | Self-correction during speech | Revises earlier phrase when user backtracks (“no wait, actually…”). | [Formatting][formatting] |
| W12 | Email layout | Separates greeting, body, closing with suitable breaks. | [Formatting][formatting] |
| W13 | Filler removal | Automatic removal claimed; no documented exact preservation rules. | [Dictation product][dictation-product] |
| W14 | Language detection / restriction | Auto detects switching languages; can disable detection and select language(s) to constrain recognition. | [Languages][languages], [Wrong-language recovery][wrong-language] |
| W15 | 100+ languages | Current product and July 2026 plan guide claim 100+; older dictation guide still says 50. Exact model/language matrix absent. | [Plan guide][plans], [Dictating][dictating] |
| W16 | Offline dictation | Current product and July plan guide list offline; Pro entitlement documented. Local engine, supported OS/languages, download and fallback behavior unspecified. | [Dictation product][dictation-product], [Plan guide][plans] |
| W17 | Quiet/noisy speech | Product claims normal speech, whispering and background-noise support. No distinct mode-setting instructions found. | [Dictation product][dictation-product] |
| W18 | Developer context | Product claims code-context reading for filenames, variables, functions. No editor extension/setup contract found. | [Dictation product][dictation-product] |
| W19 | Local history / failed-recording retry | Recent audio may survive failure locally; history offers Retry transcription. iOS long-press transcript exposes retry/copy. | [Recovery][recovery] |
| W20 | Finite dictation sessions | Older help: free 5 minutes, paid 8; July plan guide confirms Pro 8 minutes. Reaching limit finishes dictation and outputs text. Free limit needs current runtime confirmation. | [Session limit][limit], [Plan guide][plans] |
| W21 | Background / Dock control | Close dashboard after selecting “Keep it running”; menu-bar access remains; explicit Quit from menu. | [Dock][dock] |
| W22 | Movable bar / notch view | Floating bar draggable around display; Enable Notch View refreshes/removes floating bar. Not a clearly documented simple hide toggle. | [Bar][bar] |

## Personal vocabulary and style

| ID | Feature | Documented behavior / boundary | Evidence |
|---|---|---|---|
| W23 | Personal dictionary | Add/edit/delete exact spellings for names, products, jargon, acronyms. | [Dictionary][dictionary] |
| W24 | Spoken text expansion | Say configured phrase followed by “shortcut”; inserts full saved template, address, link, signature or repeated message. | [Dictionary][dictionary] |
| W25 | Explicit replacements | iOS Dictionary: enable term replacement, set original and replacement; supports corrected names and phrase→template/link. | [iOS dictionary][ios-dictionary] |
| W26 | Learned vocabulary | iOS dictionary offers Auto Learning section; homepage claims remembered names/terms/abbreviations. Learning trigger and review/undo rules unspecified. | [iOS dictionary][ios-dictionary], [Homepage][homepage] |
| W27 | Vocabulary/shortcut device sync | Same account shares dictionary and shortcuts across Mac, Windows, iOS. Transcript history has different local-only policy. | [Dictionary][dictionary], [Privacy][privacy] |
| W28 | Styles by writing context | Personalization assigns presets for casual messaging, work messaging, email, and notes/other apps; applies automatically in matching apps. Exact app override granularity unspecified. | [Styles][styles] |
| W29 | Concrete style controls | Casual: default, Gen Z, lowercase, casual without final period. Work: default, lowercase, casual standard, excited. Email: default, casual friendly, excited. Notes: casual punctuation, hypercasual, friendly, excited. Presets vary capitalization, punctuation, contractions; Gen Z adds slang replacements. | [Styles][styles] |
| W30 | Learned writing memory | Product and Pro plan claim adaptation to the user's writing style over time. No learning/retention algorithm or user-editable memory workflow documented. | [Homepage][homepage], [Plan guide][plans] |

## Scribe: intentional generation/editing

| ID | Feature | Documented behavior / boundary | Evidence |
|---|---|---|---|
| W31 | Draft from intent | Speak rough intent; generates complete message/document at cursor, adapting format/tone. Distinct from ordinary dictation. | [Scribe guide][scribe] |
| W32 | Contextual reply | Reads visible conversation/screen context and combines with brief spoken reply intent; writes at cursor. | [Scribe guide][scribe] |
| W33 | Selected-text rewrite | Highlight text; speak instruction; replacement appears in place. Supports tone, shortening, detail changes, restructuring. | [Scribe guide][scribe] |
| W34 | Translation command | Select text; request target language; replaces selection with translation. | [Scribe guide][scribe] |
| W35 | Follow-up editing | Guide describes follow-up instructions and commands such as change X to Y, add detail, paragraphs/bullets, convert to Slack message. Conversation persistence mechanics unspecified. | [Scribe guide][scribe] |
| W36 | Personal/team facts in drafts | Saved shortcuts can supply calendar links, email, office address, company introduction naturally in generated reply. | [Scribe guide][scribe] |
| W37 | Mobile rewrite controls | iPhone listing advertises one-tap tighten, expand, tone and grammar adjustment after dictation; app release notes mention Scribe screenshots. | [iPhone listing][app-store] |

## Mobile, teams and privacy

| ID | Feature | Documented behavior / boundary | Evidence |
|---|---|---|---|
| W38 | iPhone voice keyboard | Third-party keyboard; onboarding enables keyboard, Full Access, microphone. Switch with globe; works in supporting app text fields. | [iOS setup][ios-setup] |
| W39 | Background session controls | Foreground activation starts microphone session, then keyboard can dictate across apps. Live Activity toggle, in-app toggle or force-quit ends it. Expiration requires reactivation. | [iOS background][ios-background] |
| W40 | Background timeout / audio routing | Developer App Store response describes configurable 30-second to 2-hour session timeout; October release notes add AirPods/Bluetooth support. Runtime confirmation needed. | [iPhone listing][app-store] |
| W41 | Team vocabulary / snippets | Shared workspace terms and shortcuts; new teammate names automatically added. Personal entries remain separately scoped. | [Collaboration][collaboration] |
| W42 | Workspace invitations | Email, up to 200 comma-separated addresses, or invite link. Individual Pro members can receive workspace vocabulary. | [Collaboration][collaboration] |
| W43 | Organization management | Team dashboard, usage APIs/settings; SAML SSO, SCIM provisioning, centralized privacy/access/admin controls; enforced retention policy. Claimed enterprise capabilities, no admin API schema inspected. | [Enterprise][enterprise] |
| W44 | Optional text context | Privacy guide: context awareness can read small cursor-adjacent text; can switch off; then no on-screen text used. Screen scope for Scribe not separately specified there. | [Privacy][privacy] |
| W45 | Default private processing | Private Mode: no server retention of audio/transcript/context; local audio/history available. Optional improvement mode collects anonymized recognized text, not audio. Device history does not sync. | [Privacy][privacy] |
| W46 | Organization-enforced privacy | Admin-enforced Privacy Mode cannot be disabled by member. Security page says applicable subprocessors covered by enterprise zero-retention contracts. | [Security][security] |
| W47 | HIPAA workflow activation | Privacy settings let user review/sign BAA; account-wide across devices. A contractual/operational feature; cannot be copied by adding a toggle. | [HIPAA setup][hipaa] |
| W48 | Security assurances | Official help claims SOC 2 Type II; reports under NDA; encryption in transit/at rest, MFA/RBAC for production access, data isolation, security logging. Independent audit report not inspected. | [Compliance][compliance], [Encryption][encryption] |

## Implementation implications for RJT

These are design recommendations, not claims about RJT's present implementation:

1. Keep dictation cleanup and intentional writing/editing separate. Spoken instructions must not silently turn literal dictation into an assistant action.
2. Capture insertion target, selection and allowed context at recording start. Validate target before replacement; preserve draft/history on failure or focus changes.
3. Separate exact dictionary hints from deterministic replacement/shortcut expansion. Expansion must preserve saved multi-line content and use an unambiguous invocation rule.
4. Make line/paragraph/list/punctuation commands individually testable against ordinary prose, quoted commands, names and multilingual speech. Avoid aggressive global replacement.
5. Expose clear per-context style presets before automatic learning. Any learned entries need provenance, inspection, deletion and an off switch.
6. Retry from saved local audio without re-recording. Retention controls must describe local storage separately from cloud retention and account sync.
7. Local/offline processing and quiet-speech quality are measurable runtime properties. Marketing language and model availability are insufficient proof.
8. Team sync, SSO/SCIM, compliance and BAA workflows require real service/operations work; represent them honestly in the parity backlog.

## Evidence limits / conflicting docs

- Offline is supported by a July 2026 plan article and current product pages; February troubleshooting still says stable internet required. Prefer newer entitlement evidence, but verify platform/engine/fallback behavior before treating as full offline parity.
- Language count changed from 50 in older help to 100+ in newer plan/product copy. No authoritative exhaustive supported-language list found.
- Current pricing advertises Basic/Pro/Business/Enterprise and Scribe quotas; July help uses Free/Individual/Team/Enterprise; iPhone listing still mentions weekly word cap. Avoid importing obsolete limits or pricing into RJT requirements.
- “End-to-end encrypted” wording appears in product copy; detailed help describes client-server TLS and encryption at rest. No technical evidence of server-blind encryption found.
- HIPAA help mentions Android, whereas pricing marks Android “Coming soon.” Verified public platform scope: Mac, Windows, iPhone. Do not infer released Android support from boilerplate.
- Dedicated Assistant hotkey article predates Scribe branding. Current Scribe guide owns default binding and generation workflows.
- No public desktop release-note archive found through the homepage/help navigation and targeted official-domain search. iPhone release history inspected through 2.13.0 (Oct 15). Most entries generic; Oct 6 entries mention screenshot-assisted Scribe and Bluetooth routing.
- Scribe page says it reads the screen; ordinary-context help discusses cursor-adjacent text. Capture method, screenshot consent, redaction and sensitive-field exclusions remain unspecified.
- Advertised sub-200ms latency and 3× accuracy lack benchmark protocol in inspected sources; omit as acceptance facts.
- iPhone Action Button feature appeared in search snippets for Willow's own LinkedIn posts, but original primary article was not fetched. Omitted from confirmed inventory pending an accessible first-party setup source.

## Source coverage

Read homepage, Dictation, Scribe, Developers, Enterprise, Security, Pricing, Switch and Blog navigation; Getting Started and troubleshooting collections; detailed dictation, hotkey, mic, formatting, style, dictionary, collaboration, Scribe, language, retry/history, session-limit, Dock/bar, iOS setup/background, privacy/compliance/encryption/BAA, plan articles; developer-owned iPhone listing/release history. 48 feature rows. No third-party reviews used as evidence.

[homepage]: https://willowvoice.com/
[dictating]: https://help.willowvoice.com/en/articles/10876920-dictating-with-willow-voice
[hotkeys]: https://help.willowvoice.com/en/articles/10876257-hotkey-settings
[microphone]: https://help.willowvoice.com/en/articles/10876169-microphone-settings
[formatting]: https://help.willowvoice.com/en/articles/13183983-voice-commands-and-automatic-formatting-guide
[dictation-product]: https://willowvoice.com/features/dictation
[languages]: https://help.willowvoice.com/en/articles/10878926-how-do-i-dictate-in-another-language
[wrong-language]: https://help.willowvoice.com/en/articles/13668452-dictation-appears-in-the-wrong-language
[plans]: https://help.willowvoice.com/en/articles/12854184-willow-pricing-plans-overview
[recovery]: https://help.willowvoice.com/en/articles/12279120-dictation-quality-or-transcription-failure-problem
[limit]: https://help.willowvoice.com/en/articles/12772803-how-to-change-your-dictation-time-limit-in-willow
[dock]: https://help.willowvoice.com/en/articles/10878381-how-do-i-hide-willow-voice-from-the-dock
[bar]: https://help.willowvoice.com/en/articles/13706888-how-do-i-get-rid-of-the-floating-app-icon-or-the-bar
[dictionary]: https://help.willowvoice.com/en/articles/13183918-using-personal-dictionary-and-shortcuts
[ios-dictionary]: https://help.willowvoice.com/en/articles/12864717-using-dictionary-terms-on-ios
[styles]: https://help.willowvoice.com/en/articles/12864746-personalization-and-style-matching
[scribe]: https://help.willowvoice.com/en/articles/15043797-introduction-to-scribe-in-willow
[app-store]: https://apps.apple.com/us/app/willow-dictation-ai-keyboard/id6753057525
[ios-setup]: https://help.willowvoice.com/en/articles/12845807-setting-up-permissions-on-ios-keyboard-access-full-access-microphone
[ios-background]: https://help.willowvoice.com/en/articles/12855752-why-am-i-taken-back-to-the-willow-ios-app-before-i-can-dictate
[collaboration]: https://help.willowvoice.com/en/articles/13959267-using-collaboration-features-for-your-team
[enterprise]: https://willowvoice.com/enterprise
[privacy]: https://help.willowvoice.com/en/articles/12854269-how-willow-protects-your-data-and-privacy
[security]: https://willowvoice.com/security
[hipaa]: https://help.willowvoice.com/en/articles/13668475-enable-hipaa-support-in-willow
[compliance]: https://help.willowvoice.com/en/articles/13668493-compliance-certifications-and-security-standards
[encryption]: https://help.willowvoice.com/en/articles/13668518-data-security-and-encryption
