import Foundation
@testable import VoiceInkCore

final class FillerWordsTests: XCTestCase {
    func testDefaultWordsMatchMacOSCleanupDefaults() {
        XCTAssertEqual(
            VoiceInkFillerWords.defaultWords,
            ["uh", "um", "uhm", "umm", "uhh", "uhhh", "hmm", "hm", "mmm", "mm", "mh", "ehh"]
        )
    }

    func testSubmissionPlanInsertsWordAndClearsDraft() {
        XCTAssertEqual(
            VoiceInkFillerWords.submissionPlan("  LIKE  ", existingWords: ["um"]),
            VoiceInkFillerWordSubmissionPlan(
                updatedWords: ["um", "like"],
                draftAfterSubmit: "",
                alertPresentation: nil,
                didInsert: true
            )
        )
        XCTAssertTrue(VoiceInkFillerWords.submissionPlan("like", existingWords: ["um"]).didInsert)
        XCTAssertEqual(
            VoiceInkFillerWords.submissionPlan("like", existingWords: ["um"])
                .updatedWordsIfChanged(from: ["um"]),
            ["um", "like"]
        )
    }

    func testSubmissionPlanAppliesAcceptedWordsToRuntimeState() {
        let plan = VoiceInkFillerWords.submissionPlan("LIKE", existingWords: ["um"])
        var words = ["um"]

        plan.applyRuntimeState(currentWords: words) { words = $0 }

        XCTAssertEqual(words, ["um", "like"])
    }

    func testSubmissionPlanKeepsBlankDraftWithoutAlert() {
        XCTAssertEqual(
            VoiceInkFillerWords.submissionPlan("   ", existingWords: ["um"]),
            VoiceInkFillerWordSubmissionPlan(
                updatedWords: ["um"],
                draftAfterSubmit: "   ",
                alertPresentation: nil
            )
        )
        XCTAssertFalse(VoiceInkFillerWords.submissionPlan("   ", existingWords: ["um"]).didInsert)
        XCTAssertFalse(VoiceInkFillerWords.submissionPlan("", existingWords: ["um"]).didInsert)
        XCTAssertNil(
            VoiceInkFillerWords.submissionPlan("   ", existingWords: ["um"])
                .updatedWordsIfChanged(from: ["um"])
        )
    }

    func testSubmissionPlanKeepsDuplicateDraftAndBuildsSharedAlert() {
        XCTAssertEqual(
            VoiceInkFillerWords.submissionPlan("UM", existingWords: ["um"]),
            VoiceInkFillerWordSubmissionPlan(
                updatedWords: ["um"],
                draftAfterSubmit: "UM",
                alertPresentation: .duplicateFillerWord(message: "This filler word is already in the list.")
            )
        )
        XCTAssertFalse(VoiceInkFillerWords.submissionPlan("UM", existingWords: ["um"]).didInsert)
        XCTAssertNil(
            VoiceInkFillerWords.submissionPlan("UM", existingWords: ["um"])
                .updatedWordsIfChanged(from: ["um"])
        )
    }

    func testDraftAvailabilityUsesSharedNormalization() {
        XCTAssertFalse(VoiceInkFillerWords.hasDraft(" \n\t "))
        XCTAssertTrue(VoiceInkFillerWords.hasDraft(" LIKE "))
    }

    func testDraftStateUsesSharedSubmitAvailability() {
        XCTAssertFalse(VoiceInkFillerWordDraftState(draft: " \n\t ").canSubmit)
        XCTAssertTrue(VoiceInkFillerWordDraftState(draft: " LIKE ").canSubmit)
    }

    func testEditorPresentationOwnsPlatformVisibilityPolicy() {
        XCTAssertEqual(
            VoiceInkFillerWords.editorPresentation(isEnabled: false, words: ["um"]),
            VoiceInkFillerWordEditorPresentation(
                shouldShowEditor: false,
                shouldShowWordList: false
            )
        )
        XCTAssertEqual(
            VoiceInkFillerWords.editorPresentation(isEnabled: true, words: []),
            VoiceInkFillerWordEditorPresentation(
                shouldShowEditor: true,
                shouldShowWordList: false
            )
        )
        XCTAssertEqual(
            VoiceInkFillerWords.editorPresentation(isEnabled: true, words: ["um"]),
            VoiceInkFillerWordEditorPresentation(
                shouldShowEditor: true,
                shouldShowWordList: true
            )
        )
    }

    func testDraftStateSubmitsAndClearsAcceptedWord() {
        let submission = VoiceInkFillerWordDraftState(draft: " LIKE ")
            .submitting(existingWords: ["um"])

        XCTAssertEqual(
            submission.plan,
            VoiceInkFillerWordSubmissionPlan(
                updatedWords: ["um", "like"],
                draftAfterSubmit: "",
                alertPresentation: nil,
                didInsert: true
            )
        )
        XCTAssertEqual(submission.draftStateAfterSubmit, VoiceInkFillerWordDraftState())
        XCTAssertNil(submission.alertPresentation)
    }

    func testDraftStateKeepsDuplicateDraftAndBuildsSharedAlert() {
        let submission = VoiceInkFillerWordDraftState(draft: "UM")
            .submitting(existingWords: ["um"])

        XCTAssertEqual(submission.plan.updatedWords, ["um"])
        XCTAssertEqual(submission.draftStateAfterSubmit, VoiceInkFillerWordDraftState(draft: "UM"))
        XCTAssertEqual(
            submission.alertPresentation,
            .duplicateFillerWord(message: "This filler word is already in the list.")
        )
    }

    func testDraftSubmissionAppliesRuntimeStateAfterStoragePlan() {
        let submission = VoiceInkFillerWordDraftState(draft: "LIKE")
            .submitting(existingWords: ["um"])
        var events = [String]()
        var appliedPlan: VoiceInkFillerWordSubmissionPlan?
        var draftState = VoiceInkFillerWordDraftState(draft: "LIKE")
        var alertPresentation: VoiceInkDictionaryAlertPresentation? = .vocabulary(message: "stale")

        let returnedSubmission = submission.applyRuntimeState(
            applyPlan: {
                events.append("plan")
                appliedPlan = $0
            },
            setDraftState: {
                events.append("draft")
                draftState = $0
            },
            setAlertPresentation: {
                events.append("alert")
                alertPresentation = $0
            }
        )

        XCTAssertEqual(returnedSubmission, submission)
        XCTAssertEqual(events, ["plan", "draft", "alert"])
        XCTAssertEqual(appliedPlan, submission.plan)
        XCTAssertEqual(draftState, VoiceInkFillerWordDraftState())
        XCTAssertNil(alertPresentation)
    }

    func testRemovingDropsWordsCaseInsensitively() {
        XCTAssertEqual(
            VoiceInkFillerWords.removing("UM", from: ["uh", "um", "like"]),
            ["uh", "like"]
        )
    }

    func testRemovingAtOffsetsMatchesIOSListDeletion() {
        XCTAssertEqual(
            VoiceInkFillerWords.removing(at: IndexSet([1, 3]), from: ["uh", "um", "like", "hmm"]),
            ["uh", "like"]
        )
    }
}
