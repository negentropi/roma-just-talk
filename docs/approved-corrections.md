# Save an approved correction

Open **past**, expand a transcript, choose **Recognized**, **Original** or **Enhanced**, then choose **Save Correction** beside that text. Recognized appears on new records when captured recognition differs from Original. Original keeps its existing meaning: text processed before AI enhancement.

1. Copy or enter the exact phrase from the captured text.
2. Choose the occurrence if the phrase appears more than once. The surrounding text identifies each match.
3. Enter how the phrase should be written, then choose **Preview**.
4. Review the exact phrase, replacement, matching kind and source. Choose **Approve** to save it, or **Cancel** to leave the library unchanged.

Changing either phrase invalidates the preview. A changed or deleted source transcript requires a fresh capture. Approval does not edit the transcript or text already inserted into another app. Ordinary typing does not create corrections automatically.

Approved entries match one literal phrase, including commas, without matching letter case. Their replacement preserves spaces, line breaks, symbols and Unicode spelling. Replacement output does not become input to another literal rule. Existing comma-alternative entries keep their saved matching behavior.

In **Dictionary → Word Replacements**, review, turn off, edit or delete an entry. Editing preserves its identity, matching kind and source reference. An editor opened before another change must be reopened to avoid overwriting the newer values. Unsupported stored data is shown explicitly and cannot be enabled or edited as an ordinary rule.

Custom, Light and Clarity use enabled replacements. None keeps recognition text unchanged. Light/Clarity capture the library when the operation starts, so changes affect the next operation. Custom reads the current operation's library.

An approved entry survives deletion of its source History record. Dictionary then identifies the source as deleted. The entry retains the phrase pair and source reference, without retaining another complete transcript.

Settings backups preserve replacement identities, dates, enable state, matching kind and provenance. Full-record imports check the current library before importing any selected settings. Conflicts show the incoming and existing records; close the review to leave the import unapplied. Older map-only backups retain their additive merge behavior.

Native application and interaction verification is tracked in the [correction implementation plan](research/competitors/correction-learning-design.md). Source review alone does not establish runtime behavior or CloudKit synchronization.
