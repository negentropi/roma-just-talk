# Roma Just Talk proposal for YZU Startup Challenge 2026

- **Team name:** [Choose with the student team; 20-character limit]
- **Project name:** Roma Just Talk
- **One-line description:** Speak before Shift.
- **Track:** Practical group
- **Field:** AI and information technology
- **Captain:** [YZU student, department and year]
- **Members:** [Names, departments, years, and actual roles]
- **Advisor:** [Optional]

**Draft for discussion, not for upload.** The final proposal must use the organiser's A4 PDF format. The team name, members, rights statement, and evidence are still open.

## 1. Summary

Roma Just Talk is a Mac dictation app for people who start speaking before they press a shortcut. With ordinary push-to-talk recording, the first words can be lost; the speaker then pauses, repeats them, or repairs the text. Roma keeps a short microphone buffer on the Mac. When the user presses Left Shift, the app can include those earlier seconds with the rest of the recording and insert the transcript into the active app. Users may choose local recognition or configure a cloud provider.

A beta Mac app and its source are public. What we cannot yet show is how often this problem occurs for other people, whether Roma solves it reliably in their daily work, or whether they would pay for it. The proposed student team would test those questions with Mac users who already dictate, improve the weakest parts of the setup and recording flow, and bring a measured demo to the final. We want introductions to potential testers and advice on Mac app distribution. Roma builds on the GPLv3 VoiceInk project; the proposal will identify VoiceInk's work, Felix's work before this competition, and what the student team adds.

## 2. Problem and market

Imagine someone drafting a message on a Mac. They start the sentence out loud, then reach for the dictation key. Recording that begins only after the key press misses the opening words. The person has to repeat them or edit the result. Roma addresses that moment.

We have not measured how often it happens. Our first research group would be 10 to 20 Mac users who already dictate several times a day. We would recruit through the public project and local student networks, watch them complete their usual writing tasks, and ask what they use now. We would record missed opening words, corrections, and whether they choose to use Roma again after two weeks. These observations would tell us whether the problem is worth solving before we estimate a larger market.

Typing, built-in Mac dictation, and established dictation apps are all credible alternatives. The question is whether keeping words spoken before the shortcut matters enough for people to change their routine.

## 3. Solution and technology

The user speaks, presses Left Shift, continues, then releases it to insert text. Roma's short rolling buffer lets the transcription path receive audio from before the key press. The app also has local speech-recognition choices and options for user-configured cloud providers. The product idea is the timing of the interaction. Roma does not claim to have invented a speech model.

Roma is a fork of [VoiceInk](https://github.com/Beingpax/VoiceInk). VoiceInk supplies much of the existing Mac app, and other open-source libraries support speech recognition and shortcuts. Roma's pre-roll interaction and its handoff from buffered to live audio are work done on the fork. Before submission, the team will attach commit links that separate upstream code, Felix's earlier changes, and new student work. The app remains subject to GPLv3 and the licences of its other dependencies. We will ask the organiser how to describe that history under the form's originality statement.

Local recognition can keep transcription on the Mac after any required model download. Cloud recognition sends audio to the chosen provider. The public beta also has release and privacy limitations, which we will state alongside the demo rather than ask judges to infer them from the source code.

Speech recognition is the AI function in the product. Felix has used generative AI tools while developing and documenting Roma and has made the product and acceptance decisions. The student team will record its own use of those tools for the final AI disclosure.

## 4. Existing work and validation

The [source repository](https://github.com/negentropi/roma-just-talk) and [v1.95.1 Mac beta](https://github.com/negentropi/roma-just-talk/releases/tag/v1.95.1) are public. There is also a [browser demo](https://github.com/negentropi/roma-just-talk/tree/without/no-adhoc-macos-tcc/landing-vercel/demo) that explains the interaction. It uses the browser's speech recognition, so it cannot stand in for a test of the Mac app.

For this application, we still need a dated recording of the published Mac app capturing words spoken before the shortcut and inserting the result into another app. The separate evidence PDF will state the exact app version, Mac, macOS version, microphone, model, spoken phrase, and inserted text. We have no verified user count, retention result, sales figure, or measured advantage over another app to report here.

The student team will run the same short writing tasks with participants' current method and Roma. It will record the opening words captured, corrections, time to usable text, and failures. A judge should be able to see both successes and limits in those results.

## 5. Business model

Pricing is undecided. The beta is publicly downloadable, but that does not show demand for a paid product. We will ask frequent dictation users what they pay for now, where those tools fall short, and what they would pay for a reliable fix. We can then test one clear offer with interested users.

Any paid offer must respect GPLv3. The inherited code cannot be treated as exclusive property. Costs we need to measure include release signing, support, and any hosting used for cloud features. The public release is our starting distribution channel; we have not measured how many people it brings in or keeps.

## 6. Competition

| Current option | Why people use it | What Roma needs to prove |
| --- | --- | --- |
| Typing and editing | Familiar and precise; no microphone setup | Voice is useful for the tasks we target |
| Built-in Mac dictation | Already available on the computer | Lost opening words are common enough to justify switching |
| Established dictation apps | Mature recognition and workflows | Roma's timing benefit outweighs setup and trust costs |

A shortcut can be copied. If Roma earns a place in someone's routine, it will be because the whole recording and insertion flow works reliably and the app is clear about permissions and data handling. We need to test that claim with users.

## 7. Team

| Member | School and department | Work in this project | Relevant experience |
| --- | --- | --- | --- |
| [YZU student captain] | [Department and year] | Submission, interviews, team coordination | [Fill from actual work] |
| [Student 2] | [School, department, year] | Mac testing and demo | [Fill from actual work] |
| [Student 3] | [School, department, year] | Market research and pitch | [Fill from actual work] |

[Fill this section after the students agree to join. Name any missing role. Keep Felix's work before the team formed separate from work done by entrants.]

## 8. Resources and next steps

| Date | Work | Evidence that it is done |
| --- | --- | --- |
| October 2026 | Form the eligible team and submit | The centre sends its registration-success email |
| November 2026 | Test first-word capture with Mac users | Consented task records, including failures and corrections |
| December 2026 | Present the product | Five-minute pitch, three-minute Q&A, tested live demo and video backup |
| January 2027 | Improve installation and first use | Published download tested on named Mac and macOS versions |
| March 2027 | Decide what to offer users | Repeat-use results and responses to a specific price or offer |

We would use the centre's help to meet prospective testers and speak with a mentor who knows Mac software distribution and open-source business models. The team will add a costed budget after it checks actual prices. We can consider FITI or U-start with the centre once the team and rights questions are settled.

## Source and rights note

VoiceInk is the original GPLv3 Mac app. Roma is a public fork. The final proposal will cite upstream code and dependencies, Felix's existing commits, and each entrant's new work. The organiser's rules require disclosure of third-party technology and its licence. We will seek written guidance on how the existing fork fits the captain's originality declaration before signing it.
