# Wispr Flow feature inventory

Checked 2026-10-27. Official product, release notes and detailed help articles only. These are documented competitor capabilities, **not independently tested runtime results**, and not claims that RJT lacks them. Match against RJT source/runtime before choosing work. Primary scope: desktop dictation; mobile, meeting and organization features separated below.

## Dictation, formatting and personalization

| ID | Capability | Documented workflow / boundary | Primary source |
| --- | --- | --- | --- |
| WF01 | Dictation across apps | Desktop hold shortcut, speak, release to insert in focused field. iPhone keyboard; Android accessibility overlay. | [First dictation](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation) |
| WF02 | Hands-free recording | Dedicated toggle shortcut, floating-bar click or double-tap push-to-talk within 500 ms. Third rapid tap cancels. | [Hands-free](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free) |
| WF03 | Cancel and recover | Remappable cancel; cancelled recordings can be retried when retained. Never-store policy prevents recovery. | [Hands-free](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free) |
| WF04 | Cleanup strength | Desktop None / Light / Medium; raw, filler-and-grammar cleanup, or clarity rewriting. Changes affect next dictation. | [Auto Cleanup](https://docs.wisprflow.ai/articles/4283510616-auto-cleanup-control-how-much-flow-edits-your-dictation-beta) |
| WF05 | Preserve original text | History toggles original versus AI-edited transcript without retranscription; copying uses selected version. | [Smart Formatting](https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack) |
| WF06 | Spoken self-correction | Resolves corrections from full utterance context; ordinary uses of correction-like words should remain. | [Smart Formatting](https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack) |
| WF07 | Spoken lists and punctuation | Number/sequence cues create lists; named punctuation, newline and paragraph cues supported. Plain/rich paste spacing differs. | [Smart Formatting](https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack) |
| WF08 | Category writing styles | Personal / Work / Email / Other; Formal, Casual, Very Casual or Excited depending category. Desktop detects web apps by URL. English-only style notice. | [Styles](https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles) |
| WF09 | Email structure | Email destinations receive greetings, sign-offs and line breaks under the selected Email style. | [Styles](https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles) |
| WF10 | Cursor-aware insertion | Surrounding text controls case, spaces and punctuation; selected text boundaries preserved. Chinese/Japanese join without added spaces. Password context excluded. | [Mid-sentence formatting](https://docs.wisprflow.ai/articles/4518230910-why-flow-capitalizes-words-mid-sentence-and-how-to-control-it) |
| WF11 | Per-app transcription format | Desktop automatic, raw, proper-nouns-only capitalization or lowercase options. Formatting and backtracking can be disabled. | [Mid-sentence formatting](https://docs.wisprflow.ai/articles/4518230910-why-flow-capitalizes-words-mid-sentence-and-how-to-control-it) |
| WF12 | Messaging punctuation | Trailing-period removal depends on style, sentence count and cursor context; question/exclamation marks remain. | [Smart Formatting](https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack) |
| WF13 | Multiple language selection | 100+ selectable languages; detection chooses one per dictation. Only 23 automatically identifiable; other languages need explicit selection. | [Languages](https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages) |
| WF14 | Regional/script variants | British/Canadian English, Swiss German, Traditional/Simplified Chinese, Cantonese and explicitly selected Hinglish. Mutually exclusive variants; French punctuation spacing rules. | [Languages](https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages) |
| WF15 | Preserve multilingual output | Cleanup preserves spoken language blend; mixed-language recognition remains less reliable. No automatic translation unless requested. | [Accuracy limits](https://docs.wisprflow.ai/articles/4048537120-what-to-expect-from-flow-accuracy-and-known-limitations) |
| WF16 | Personal vocabulary | Names/jargon added manually; 60-character desktop fields. Optional automatic learning from corrected dictation; filters common words and code-like data. | [Dictionary](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary) |
| WF17 | Exact correction rules | Wrong spelling → saved spelling; case-insensitive whole-word match, longer phrase wins, literal replacement, personal overrides shared. Contractions protected; possessives supported. | [Dictionary](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary) |
| WF18 | Dictionary import and sync | Desktop file import ≤3 MB / 1,000 items, no experimental opt-in. Account words/corrections sync online across platforms. | [Dictionary](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary) |
| WF19 | Vocabulary management | Search, personal/shared filters, star/unstar, sorting, source badges, multi-select edit/share/delete workflow. Shared access depends on account eligibility. | [Dictionary and snippet management](https://docs.wisprflow.ai/articles/9639977157-view-shared-dictionary-words-and-snippets-in-the-admin-portal) |
| WF20 | Voice snippets | Say trigger alone or in sentence to insert static saved text. All plans; trims trigger; case-insensitive boundaries; longest overlap wins; personal overrides shared. | [Snippets](https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets) |
| WF21 | Formatted snippets | Bold, italic, lists and links; multiline preservation. Plain-text fallback for unsupported destinations, repeated trigger or signature combination. | [Snippets](https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets) |
| WF22 | Bulk snippets | Import ≤3 MB / 1,000 items. Desktop trigger ≤60 characters, expansion ≤4,000 including formatting; duplicate dictionary/snippet triggers blocked. | [Snippets](https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets) |

## Editing and developer workflows

| ID | Capability | Documented workflow / boundary | Primary source |
| --- | --- | --- | --- |
| WF23 | Spoken command mode | Separate opt-in shortcut; dictate instruction to edit text, draft reply or search. Sends current field/selection; can copy selection as fallback. Desktop paid access. | [Command Mode](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode) |
| WF24 | Command-mode control | Hands-free lock, cancel, editable-field requirement; noneditable target returns notification. Desktop search opens Perplexity with selection context. | [Command Mode](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode) |
| WF25 | Selection transforms | Desktop shortcut rewrites selection, otherwise readable field or last dictation ≤60 seconds old. 1–3,000 words; iOS Polish 10–3,000. | [Transforms](https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta) |
| WF26 | Reusable custom transforms | Polish, Prompt Engineer and eight named custom prompt slots; shortcut required. Per-prompt examples supported on desktop. | [Transforms](https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta) |
| WF27 | Review, retry and undo | Diff compares original/result; retry starts from original, subsequent transforms use result; undo restores latest rewrite. Rich links/lists can degrade. | [Transforms](https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta) |
| WF28 | Post-dictation transform | Chosen transform runs before paste; failure falls back to original dictation. Optional Scratchpad delivery when auto-paste disabled. | [Transforms](https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta) |
| WF29 | Configurable Polish | Toggle concision, clarity, order, structure and tone rules; add five short custom rules. | [Transforms](https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta) |
| WF30 | Visible code vocabulary | Reads visible variable/function/class names in Cursor, Windsurf and standard VS Code using editor accessibility mode. No VS Code Insiders support. | [IDE support](https://docs.wisprflow.ai/articles/6434410694-use-flow-with-cursor-vs-code-and-other-ides) |
| WF31 | Voice file tagging | Cursor/Windsurf chat only: matches visible filenames, drives @ autocomplete; multiple files, spoken extensions/case variants. Disabled when dictionary/snippet substitution occurs. | [IDE support](https://docs.wisprflow.ai/articles/6434410694-use-flow-with-cursor-vs-code-and-other-ides) |
| WF32 | Coding-terminal insertion | Mac Claude Code/Codex receive long dictations in plain-text chunks. Terminal file references become text rather than attachments. | [IDE support](https://docs.wisprflow.ai/articles/6434410694-use-flow-with-cursor-vs-code-and-other-ides) |

## Recording, delivery, recovery and accessibility

| ID | Capability | Documented workflow / boundary | Primary source |
| --- | --- | --- | --- |
| WF33 | Multiple keyboard/mouse bindings | Up to four bindings per action, three keys each; cancel one binding. Reserved/duplicate validation; per-device persistence. | [Shortcuts](https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts) |
| WF34 | Mouse dictation and Enter | Auxiliary/middle mouse shortcuts; primary clicks excluded. Separate Enter shortcut sends on press. Desktop default-off spoken “press enter” suffix removes phrase and submits only after successful paste; mid-sentence/Command Mode stays text. First detection has a one-time enable/disable prompt. | [Shortcuts](https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts), [Spoken Enter](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free) |
| WF35 | Paste/copy latest transcript | Separate configurable global actions; retry saved failed/cancelled recording where eligible. Terminal/remote recovery uses current target. | [Terminal use](https://docs.wisprflow.ai/articles/6478598909-using-flow-with-linux-wsl-and-terminal-applications) |
| WF36 | Clipboard restoration | Restore supported prior clipboard after paste acceptance; retain newer user clipboard writes. Remote viewers need shared clipboard; delivery delay varies. | [Remote desktops](https://docs.wisprflow.ai/articles/7336156466-use-flow-with-remote-desktops-citrix-rdp-vdi) |
| WF37 | Twenty-minute recording | Desktop warning at 19 min; auto-stop at 20; captured audio transcribed. Recovery for disconnects and failed/partial sessions, subject to saved audio. | [Session duration](https://docs.wisprflow.ai/articles/4841123325-longer-dictation-sessions-now-up-to-20-minutes) |
| WF38 | Dictation audio playback/export | History supports audio playback and extraction for 14 days; original/edited text retained separately. | [Smart Formatting](https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack) |
| WF39 | Microphone selection/ranking | Desktop physical/virtual picker; Mac ranks available physical mics; virtual inputs explicit only, excluded from auto-selection. iPhone can prefer built-in mic with Bluetooth output. | [Microphones](https://docs.wisprflow.ai/articles/8884408990-connect-and-set-up-external-audio-devices) |
| WF40 | Actionable recording errors | No-input warning, missing/disconnected mic and permission-specific recovery. Starting silence is surfaced immediately. | [Release notes, Oct 9](https://wisprflow.ai/whats-new) |
| WF41 | Movable floating status | Rest/record/process state; persistent edge docking, multiple-display cursor-follow behavior, Dock/fullscreen adjustments; indefinite or one-hour hide. | [Flow Bar](https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop) |
| WF42 | Screen-capture exclusion | Optional Notepad exclusion always; Flow Bar excluded during active/reconnecting meeting only. | [Flow Bar](https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop) |
| WF43 | Notification preferences | Desktop tips, announcements, milestones, team updates; device-local. Error/recovery/access alerts remain visible. | [Notifications](https://docs.wisprflow.ai/articles/2250194357-customize-notification-preferences-by-category) |
| WF44 | Keyboard/screen-reader access | Keyboard navigation, history copy/retry, named dialogs/focus handling; VoiceOver/NVDA/JAWS/TalkBack testing; system reduced-motion behavior. Article lists unresolved gaps. | [Accessibility](https://docs.wisprflow.ai/articles/3941699399-keyboard-and-screen-reader-accessibility-in-wispr-flow) |
| WF45 | Light/dark/system theme | Desktop hub appearance choice. | [Release notes, Oct 19](https://wisprflow.ai/whats-new) |
| WF46 | Usage insights | WPM, words, cleanup/dictionary fixes, app/category shares, daily heatmap, streaks. CJK/non-space counting supported; metrics can continue without transcript retention. | [Usage](https://docs.wisprflow.ai/articles/8760230576-your-usage-tab-track-your-dictation-stats-in-wispr-flow) |
| WF47 | Communication profile | Desktop Insights report from stored dictation; initial 2,000-word eligibility plus later milestones. This is a communication report, not proof of speaker-adapted ASR. | [Voice Profile](https://docs.wisprflow.ai/articles/7470830521-voice-profile-updates-when-the-update-your-voice-profile-notification-appears) |

## Mobile and organization scope

| ID | Capability | Documented workflow / boundary | Primary source |
| --- | --- | --- | --- |
| WF48 | iPhone system entry points | App Intents/Shortcuts for clipboard dictation, notes and toggle; Action Button, Back Tap, Control Center, Siri, Lock Screen/Dynamic Island controls. Live Activities required for some starts. | [iPhone shortcuts](https://docs.wisprflow.ai/articles/1986921789-how-to-set-up-flow-shortcuts-for-iphone) |
| WF49 | Android overlay controls | Hold/tap recording, stop/cancel, clipboard fallback, sensitive-field exclusions and automatic permission/service repair guidance. | [First dictation](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation) |
| WF50 | Android snooze | Idle overlay hide for ten minutes; restore via app or two shakes while unlocked, with restricted-app safeguards. | [Snooze](https://docs.wisprflow.ai/articles/3400534884-snooze-the-dictation-bubble) |
| WF51 | Android special fields | Notification replies and browser URL fields; protect existing reply text, clipboard fallback, refuse cross-app insertion after focus changes. Five-minute session limit. | [Special fields](https://docs.wisprflow.ai/articles/5090227041-dictating-in-notification-reply-boxes-and-browser-address-bars) |
| WF52 | Shared team vocabulary/snippets | Shared libraries alongside personal entries; search, sharing, bulk actions, refresh. Eligibility restrictions; some admin disablement hides management but retained entries still apply. | [Library management](https://docs.wisprflow.ai/articles/9639977157-view-shared-dictionary-words-and-snippets-in-the-admin-portal) |
| WF53 | Organization membership/admin | Roles, departments/cost centers, bulk invitations and resends; assigned teams and seats. | [Teams/departments](https://docs.wisprflow.ai/articles/9258004709-assigning-members-to-a-team-department-as-an-admin) |
| WF54 | SAML sign-on | Growth/Enterprise identity-provider configuration; optional enforced SSO and domain restrictions. Enterprise domain capture separate. | [SSO](https://docs.wisprflow.ai/articles/8771213223-configure-sso) |
| WF55 | Directory provisioning | Enterprise SCIM create/update/remove memberships; SSO prerequisite; manual invitation workflow disabled while managed. | [SCIM](https://docs.wisprflow.ai/articles/6159095582-set-up-scim-user-provisioning-in-wispr-flow) |
| WF56 | Managed updates | Desktop MDM update-check frequency; install defers around active dictation/meeting and pending audio saves. | [MDM update policy](https://docs.wisprflow.ai/articles/9967754953-configure-auto-update-policy-via-mdm-updatefrequency) |
| WF57 | Team leaderboard | Pro/Enterprise team usage ranking. Documented release capability; exact current plan/visibility details need live account check. | [Release notes, Jul 29](https://wisprflow.ai/whats-new) |

## Boundaries and conflicting documentation

- No arbitrary audio/video-file transcription upload. Notetaker imports existing **text** meeting exports from Otter/Granola, not their audio. [Audio import limitations](https://docs.wisprflow.ai/articles/7689167034-can-i-upload-audio-files-to-wispr-flow-for-transcription).
- Cloud ASR requires internet; saving desktop audio offline is recovery capability, not offline transcription. [Accuracy limits](https://docs.wisprflow.ai/articles/4048537120-what-to-expect-from-flow-accuracy-and-known-limitations).
- Supported: macOS 12+, Windows x64 10/11, iPhone iOS 18.3+, Android phone 13+. No native Linux/iPad, Windows ARM, VM or remote-desktop installation support; local Flow can deliver into a remote session. [System requirements](https://docs.wisprflow.ai/articles/1036674442-supported-devices-and-system-requirements).
- Newer languages article removes desktop floating-bar picker; homepage/release history still describes it. Use current help workflow as implementation reference, not stale UI.
- Newer Dictionary/Snippets articles allow import without experimental switch and show Android libraries. September bulk-import article still says paid/experimental and no Android library: stale restriction.
- Current Auto Cleanup article offers three levels; older release post lists four, including High. Treat High as retired.
- Session article says crash does not automatically resume/retranscribe/paste; older release notes describe manually recovering retained audio after quitting. No automatic crash-resume guarantee.
- Current help articles disagree about whether desktop recording can start while prior result processes. Require product runtime check; do not copy scheduling assumptions.

## RJT implementation implications

Inference from the documented workflows, not an RJT gap verdict:

1. Shared foundations: a formatting policy (cleanup strength, app/category style, language/script, cursor context), explicit raw/result preservation, and literal vocabulary/snippet matching. Keep content rewriting distinguishable from ASR errors.
2. Treat selection rewrite as an editing operation: preserve original, detect intended selection/field, guard stale target, support diff/retry/undo and safe delivery failure. Do not infer broad voice-control authority from a dictation session.
3. Delivery and recovery deserve first-class behavior: clipboard change ownership, slow targets, focus changes, cancelled/partial sessions, retention-aware retry and recoverable errors.
4. Platform/team/meeting parity are separate projects. A desktop dictation implementation does not establish mobile keyboard, Android overlay, sync backend, SSO or bot-free meeting support.
5. Verify sensitive-field exclusion and context boundaries before using surrounding text/IDE context. Competitor privacy claims are not proof of RJT privacy.

## Source coverage

Homepage, release history, Getting Started and Using Flow collections; detailed articles cited above for formatting, dictionary/snippets, transforms, commands, languages, delivery, audio, shortcuts, accessibility, insights, mobile, SSO/SCIM and MDM. Meeting/privacy sub-audit read 19 additional detail articles. No secondary articles used. No competitor app installed or exercised. Total: 88 capability groups; the rows are product-level groups, not equal-sized engineering tasks.

## Notetaker, Scratchpad, integrations and privacy

These capabilities belong in the gap ledger even if staged after dictation. Bot-free meetings, durable notes and a cloud integration service are substantial independent epics.

| ID | Capability | Documented workflow / boundary | Primary source |
| --- | --- | --- | --- |
| WF58 | Bot-free meeting capture | Desktop captures microphone plus system audio; unscheduled meetings need no calendar. macOS system-audio permission separate; Windows uses default output. | [Notetaker setup](https://docs.wisprflow.ai/articles/3665250541-getting-started-with-notetaker-beta) |
| WF59 | Meeting recording lifecycle | One meeting recording; Stop/Resume appends segments; note window can close independently. Call detection with optional automatic start/countdown. | [Meeting recording](https://docs.wisprflow.ai/articles/9238501024-recording-a-meeting-with-notetaker-beta) |
| WF60 | Recording stop/recovery | Optional call-end stop; silence/sleep handling; configurable 30m–3h cap. Surviving crash audio and interrupted uploads recover with visible processing/retry states. | [Meeting recording](https://docs.wisprflow.ai/articles/9238501024-recording-a-meeting-with-notetaker-beta) |
| WF61 | Calendar connections | Google and Outlook account connections; upcoming meetings, join/record/join-and-record/snooze controls. iCloud unsupported. | [Calendar](https://docs.wisprflow.ai/articles/8955305188-meeting-detection-reminders-and-calendar-in-notetaker-beta) |
| WF62 | Meeting workspace | Upcoming/past meeting hub, preview and floating note; conflict handling. Meeting context persists across devices. | [Notetaker hub](https://docs.wisprflow.ai/articles/9247277218-the-notetaker-hub-your-meetings-in-one-place-beta) |
| WF63 | Live transcript/search | Optional live display, copy/search and follow-scroll; selecting/searching pauses automatic scroll. | [Live transcript](https://docs.wisprflow.ai/articles/4091106439-the-live-transcript-in-notetaker-beta) |
| WF64 | Speaker identification | Numbered speakers plus names read from supported visible meeting interfaces; ambiguous matches remain numbered. | [Live transcript](https://docs.wisprflow.ai/articles/4091106439-the-live-transcript-in-notetaker-beta) |
| WF65 | Private meeting notes | Autosaved manual thoughts separate from summary; editable title. Owner thoughts excluded from normal sharing. | [Notes/editor](https://docs.wisprflow.ai/articles/9406970664-meeting-notes-and-the-editor-in-notetaker-beta) |
| WF66 | Speaker correction | Post-recording per-block or whole-speaker reassignment; manual assignments survive reprocessing. | [Notes/editor](https://docs.wisprflow.ai/articles/9406970664-meeting-notes-and-the-editor-in-notetaker-beta) |
| WF67 | Structured summaries | Topic recap, decisions, owner-grouped next steps; normally automatic after >5 recorded minutes, manual generation otherwise. | [Summaries](https://docs.wisprflow.ai/articles/1422535682-flow-summaries-in-notetaker-beta) |
| WF68 | Editable/updateable summary | User edits separate from manual notes; resumed recording can update summary explicitly, keeping previous result until success. | [Summaries](https://docs.wisprflow.ai/articles/1422535682-flow-summaries-in-notetaker-beta) |
| WF69 | Cited meeting Q&A | Ask within/across meetings, follow-up chats/history, dated queries; cited meeting evidence and catch-up during calls. | [Ask Wispr](https://docs.wisprflow.ai/articles/5694642921-ask-wispr-chat-with-your-meetings-and-notes-beta) |
| WF70 | Explicit AI note editing | Requested edits can modify title, summary or manual notes; ordinary questions should not overwrite them. Shared notes read-only. | [Ask Wispr](https://docs.wisprflow.ai/articles/5694642921-ask-wispr-chat-with-your-meetings-and-notes-beta) |
| WF71 | Meeting export | Full Markdown, summary rich/plain copy, selected/full transcript copy; owner export can include private notes unlike sharing. | [Export/sharing](https://docs.wisprflow.ai/articles/5073796184-sharing-meeting-notes-from-notetaker-beta) |
| WF72 | Controlled note sharing | Invited email, organization-domain or public-link access; transcript exposure depends on invitation/policy. | [Meeting privacy](https://docs.wisprflow.ai/articles/4497184932-notetaker-privacy-and-security-overview) |
| WF73 | Offline meeting capture | Local audio queues for later cloud processing; 500 MB upload bound and free-storage checks. Offline capture does not mean offline summaries. | [Offline meetings](https://docs.wisprflow.ai/articles/5810080970-offline-meeting-recording-in-notetaker) |
| WF74 | Meeting translation | Live/post-meeting translation selector; auto language detection independent of dictation setting. Translation requires connectivity. | [Meeting languages](https://docs.wisprflow.ai/articles/3512887047-use-notetaker-with-multiple-languages) |
| WF75 | Existing meeting import | Granola CSV/ZIP or Otter exports preserve available text and speaker data. Imported audio, playback and reprocessing unsupported. | [Import meetings](https://docs.wisprflow.ai/articles/4484290718-import-your-past-meetings-from-granola-or-otter-into-notetaker) |
| WF76 | Meeting retention/deletion | Ordinary audio retention seven days; unfinished recovery up to 30. Delete meeting content across devices. | [Meeting retention](https://docs.wisprflow.ai/articles/1761520520-transcript-retention-syncing-and-deleting-meetings-in-notetaker-beta) |
| WF77 | Scratchpad drafts | Rich-text typing/dictation with autosave and manual/automatic titles. | [Scratchpad](https://docs.wisprflow.ai/articles/9618237082-using-the-scratchpad-to-save-and-edit-notes) |
| WF78 | Scratchpad organization | Up to five tabs per window; rename/reorder, detach/merge windows, title/body search and device-local pins. | [Scratchpad](https://docs.wisprflow.ai/articles/9618237082-using-the-scratchpad-to-save-and-edit-notes) |
| WF79 | Scratchpad version recovery | Up to 50 versions; restoring first preserves current work; transforms create separate versions. | [Scratchpad](https://docs.wisprflow.ai/articles/9618237082-using-the-scratchpad-to-save-and-edit-notes) |
| WF80 | Recovery destination | Failed/no-target paste can open Scratchpad; configurable reopening and global shortcut. | [Scratchpad](https://docs.wisprflow.ai/articles/9618237082-using-the-scratchpad-to-save-and-edit-notes) |
| WF81 | Notes images/offline/sync | Ten compressed images per note, ≤5 MB each; offline saves and account sync; iPhone image support differs. Dictation-storage toggle does not gate current note sync. | [Scratchpad](https://docs.wisprflow.ai/articles/9618237082-using-the-scratchpad-to-save-and-edit-notes) |
| WF82 | Remote MCP authorization | Read-only account server; authorize Claude/ChatGPT/Gemini/Cursor or compatible client. Desktop app need not run. | [Remote MCP](https://docs.wisprflow.ai/articles/9551372685-connect-an-mcp-client-to-wispr-flow-remote-mcp-server) |
| WF83 | Permissioned external context | MCP serves eligible meetings/transcripts/tasks/notes/Scratchpad/calendar context; not dictation/chat history; no mutations. | [Remote MCP](https://docs.wisprflow.ai/articles/9551372685-connect-an-mcp-client-to-wispr-flow-remote-mcp-server) |
| WF84 | Cross-device preferences | Vocabulary, snippets, eligible styles/languages, plan and aggregate stats sync. Keyboard shortcuts/mic/sounds remain device-specific. History sync documentation inconsistent. | [Device sync](https://docs.wisprflow.ai/articles/5284722493-sync-flow-across-your-devices) |
| WF85 | Context-aware recognition | Nearby text, app/website category and visible names/code terms inform recognition; context opt-out and sensitive-field exclusions. Says no screenshots. | [Context awareness](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness) |
| WF86 | Local cursor adjustment | Local spacing/case/punctuation can operate while contextual cloud reading disabled; app/domain metadata still transmitted. | [Context awareness](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness) |
| WF87 | Separate privacy controls | Training, dictation cloud storage and context are independent settings. Processing/usage metadata continue; reports may be retained. | [Data controls](https://docs.wisprflow.ai/articles/9609615338-private-cloud-sync-and-data-sharing-preferences-in-wispr-flow) |
| WF88 | Managed policy boundaries | Organization locks for storage/training/context/meeting/MCP; participant/domain policy; BAA blocks Notetaker/MCP. Meeting audit-certification scope differs from dictation. | [Meeting privacy](https://docs.wisprflow.ai/articles/4497184932-notetaker-privacy-and-security-overview), [MCP](https://docs.wisprflow.ai/articles/9551372685-connect-an-mcp-client-to-wispr-flow-remote-mcp-server) |

Additional unresolved details from primary documentation:

- Meeting-language article says 21 but lists 22 including Hinglish; do not promise exact count.
- Live-transcript article describes live speaker names; editor article says names appear after stopping. Runtime check required.
- Current data-controls article separates required meeting cloud processing from dictation storage; older calendar setup still describes Cloud Sync prerequisite.
- Free/Pro model-training defaults conflict between setup/data-controls and security overview; toggle independence established, default unresolved.
- General device-sync article calls history local while data-controls describes cloud history access; specify tested data types instead of claiming universal sync.
- New MCP article includes notes/Scratchpad/calendar context; older release says only meeting transcripts. Prefer detailed current article, verify actual tool access on connected account.
- Meeting privacy article says Notetaker launched after prior SOC 2/ISO audit periods and was not assessed within them. Do not extend general product certification claims to every new subsystem.
