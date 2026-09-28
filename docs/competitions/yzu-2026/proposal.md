# YZU Startup Challenge 2026 — practical-track proposal draft

- **Team name:** [20 characters maximum; choose with team]
- **Proposal name:** Roma Just Talk
- **One sentence:** Speak before Shift.
- **Sector:** AI and ICT
- **Captain:** [YZU student, department/year]
- **Members and roles:** [3–6 total; use names and department/year only in proposal]
- **Advisor:** [optional]
- **Language:** English

> Export to selectable-text A4 PDF using the organizer's format: 12 pt Arial or Times New Roman, 1.5 spacing, numbered pages. Maximum eight body pages, separate cover; cite any appendix. Do not include IDs, phone numbers, or addresses. The name and one-liner must match the form exactly.

## 1. Summary

Roma Just Talk is a macOS dictation prototype for people who think of a sentence before they can reach a keyboard shortcut. Conventional push-to-talk starts recording after activation; a first word can be lost or the speaker has to pause. Roma keeps a short rolling microphone buffer on the Mac and joins it to audio captured after the shortcut. The intended interaction is to speak naturally, press Left Shift, then release to insert text into the active app. Users can choose local or configured cloud speech recognition. A public beta and source repository exist; the team has not yet established a verified customer count or repeat-use metric. Our next step is to test whether this interaction reduces lost opening words and interruption in real writing tasks, then learn whether users will adopt or pay for it. We seek users for a controlled pilot and advice on distribution, accessibility, privacy, and commercialization. The current app is derived from GPLv3 VoiceInk; our proposal concerns the differentiated interaction and continuing development, with third-party rights disclosed below.

## 2. Problem and market

**Concrete moment.** A student, writer, or knowledge worker is composing in a Mac app. They start speaking as an idea arrives but the dictation shortcut has not yet been pressed. Standard recording misses the beginning, so they repeat themselves, edit the first phrase, or stop to prepare the input tool. This friction is small per episode but interrupts a frequent workflow. Roma targets people who write across many desktop apps, especially those who already try voice input and are dissatisfied with activation delay.

**First reachable segment.** Begin with 10–20 Mac users who dictate multiple times a day, recruited through the existing public project and YZU/community channels. Run short task observations and a two-week opt-in pilot. Measure first-word capture, time to usable text, correction burden, and retention. This is a testable beachhead, **not** a claim about market size. Estimate TAM/SAM/SOM only after obtaining sourced platform and willingness-to-pay data; do not insert an invented revenue figure.

**Current alternatives.** Keyboard typing, built-in macOS dictation, and third-party dictation apps. Users may already be satisfied with these alternatives; the study must identify when Roma is meaningfully better and when it is not.

## 3. Solution and technology

The user speaks, presses Left Shift, continues speaking, and releases to insert text. Roma maintains a short pre-roll buffer so the opening phrase can enter the transcription pipeline. The app integrates with the macOS text-insertion flow and offers local model options or user-configured cloud providers. The distinctive product hypothesis is the **speak-before-hotkey** interaction, not a proprietary speech model.

The published codebase is a fork of [VoiceInk](https://github.com/Beingpax/VoiceInk). VoiceInk's macOS base and open-source speech libraries remain credited. Roma's team should itemize its own design and implementation contributions, especially pre-roll capture and the buffered-to-live handoff, using a commit-backed appendix. Distribution and reuse must respect GPLv3 and each dependency's license. **Organizer clarification on the declaration of originality remains pending.**

**Privacy and reliability.** Local transcription is an option. Cloud transcription sends data to the configured provider; it must be described accurately. The current public beta's signing, notarization, and data-handling limitations should be shown in the [Trust disclosure](https://github.com/negentropi/roma-just-talk/blob/without/no-adhoc-macos-tcc/landing-vercel/index.html), then checked against the release artifact before a public pitch. Do not imply a production-ready safety guarantee.

**AI use disclosure.** Speech recognition powers the product. Generative AI tools have also helped build and document the code, under human product and acceptance decisions. State the specific tools and scope used by the actual entrant team before submission. The contest permits AI tools and asks for truthful disclosure.

## 4. Existing work and validation

**Built:** a public [source repository](https://github.com/negentropi/roma-just-talk), [v1.95.1 beta release](https://github.com/negentropi/roma-just-talk/releases/tag/v1.95.1), and a [browser interaction demo](https://github.com/negentropi/roma-just-talk/tree/without/no-adhoc-macos-tcc/landing-vercel/demo). The browser demo illustrates the shortcut flow; it is not itself proof that the Mac app works end to end. Include dated screenshots of a verified app run and a working public demo link in the separate evidence PDF once checked.

**Not yet validated for this submission:** active users, retention, paid demand, first-word recovery rate in a user study, and measured advantage over alternatives. A downloaded release and automated build do not prove these outcomes. The pilot will use a fixed sentence/task set and record version, macOS version, hardware, microphone, model, exact spoken text, trigger timing, output, corrections, and consent. This makes the product claim falsifiable.

## 5. Business model

**Hypothesis:** a free evaluation path could lead to paid convenience or support for heavy users, or an organization could sponsor deployment. No price or plan is committed here. First interview target users about existing spend and test a concrete offer against alternatives. Because the application code is GPLv3, any paid model must respect the right to source and redistribute under that license. Do not claim exclusive ownership of the inherited code or promise a proprietary code license. Costs to estimate include model hosting when cloud options are used, release signing, support, and acquisition. The first distribution path is the public release and a clear onboarding page; effectiveness remains unmeasured.

## 6. Competition

| Option | Useful strength | Question Roma must answer |
| --- | --- | --- |
| Typing and editing | Familiar, precise, no mic setup | Is voice input faster for the target task? |
| Built-in macOS dictation | Present on the Mac, low acquisition friction | Is first-word recovery important enough to switch? |
| Established dictation apps | Mature recognition and workflows | Can Roma's interaction and control justify setup and trust costs? |

The comparison should be tested on real tasks; no unsupported accuracy, RAM, price, or speed ranking is proposed. The differentiated shortcut can be copied, so durable value would need to come from execution quality, reliability, user trust, and workflow learning.

## 7. Team

| Member | YZU or other school, department/year | Owned work | Evidence of ability |
| --- | --- | --- | --- |
| [Captain] | [YZU] | Product direction, submission, user research | [Specific work] |
| [Member 2] | [School] | macOS engineering and demo reliability | [Specific work] |
| [Member 3] | [School] | Market research, pilot recruitment, business model | [Specific work] |

Assign actual work and confirm each person's consent. An advisor is optional. If a role is unfilled, name the gap rather than listing a nominal teammate. The product predates this competition; distinguish founder work and new teammate contributions honestly.

## 8. Next six months and resources

| By | Deliverable | Completion test |
| --- | --- | --- |
| 2026-10-16 | Eligible team and application | Center confirms received and then accepted; both PDFs conform |
| 2026-11 | First-word pilot | 10+ consented Mac users; versioned task records and correction results |
| 2026-12 | Final pitch and live demo | Rehearsed 5-minute talk; 3-minute Q&A; offline video backup |
| 2027-01 | Onboarding and release quality | Tested published download on target macOS versions, documented blockers |
| 2027-03 | Demand decision | Repeat-use and willingness-to-pay evidence; explicit continue/pivot choice |

**Requested support:** introductions to target users and a mentor for Mac software distribution or open-source commercialization. Budget to be filled only after team agrees on line items and quotes: participant incentives, test hardware/access, Developer ID/notarization, and hosting if needed. Consider FITI/U-start with center guidance after eligibility and IP questions are resolved.

## Source and rights note for appendix

VoiceInk: original upstream macOS application, GPLv3. Roma Just Talk: a public fork that retains VoiceInk credits and adds a speech-first pre-roll direction. Third-party libraries and model licenses should be listed from the release's dependency manifest. The team's own contribution list must be verified against Git history before the captain attests to originality. The organizer's rules say third-party technology and licenses must be stated; the captain should seek a written ruling on this fork before submission.
