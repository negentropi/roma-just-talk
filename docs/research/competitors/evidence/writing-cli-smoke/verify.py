#!/usr/bin/env python3
"""Rebuild the pure prompt/check code and verify retained synthetic outputs offline."""

import hashlib
import json
import re
import runpy
import shutil
import subprocess
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
IDS = ("japanese-to-english", "english-to-traditional-chinese", "concise-selection")

PROMPT_DRIVER = '''
@main struct Driver {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for fixture in [WritingProviderFixture.japaneseToEnglish, .englishToTraditionalChinese, .conciseSelection] {
            let request = try VoiceInkWritingActionRequest(kind: fixture.kind, transcript: fixture.transcript, selectedText: fixture.selectedText, targetLanguage: fixture.targetLanguage)
            let payload = ["kind": request.kind.rawValue, "systemMessage": request.systemMessage, "userMessage": request.userMessage, "promptName": request.promptName]
            try encoder.encode(payload).write(to: folder.appendingPathComponent(fixture.id + ".request.json"))
            try encoder.encode(fixture).write(to: folder.appendingPathComponent(fixture.id + ".fixture.json"))
            let fullPrompt = VoiceInkLocalCLIPreference.fullPrompt(systemPrompt: request.systemMessage, userPrompt: request.userMessage)
            try fullPrompt.write(to: folder.appendingPathComponent(fixture.id + ".full-prompt.txt"), atomically: true, encoding: .utf8)
        }
        print("Prepared three production-constructed synthetic requests")
    }
}
'''

RESULT_VALIDATOR = '''
private struct ValidationReceipt: Encodable {
    let fixture: WritingProviderFixture
    let output: String
    let checks: [WritingProviderCheck]
    let passed: Bool
}
@main struct Validator {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for fixture in [WritingProviderFixture.japaneseToEnglish, .englishToTraditionalChinese, .conciseSelection] {
            let input = try Data(contentsOf: folder.appendingPathComponent(fixture.id + ".cli.json"))
            let result = try JSONSerialization.jsonObject(with: input) as! [String: Any]
            guard result["is_error"] as? Bool == false, result["subtype"] as? String == "success", let output = result["result"] as? String else { fatalError("CLI did not return a successful text result for " + fixture.id) }
            let checks = fixture.checks(output)
            let passed = checks.allSatisfy { $0.passed }
            try encoder.encode(ValidationReceipt(fixture: fixture, output: output, checks: checks, passed: passed)).write(to: folder.appendingPathComponent(fixture.id + ".validation.json"))
            precondition(passed, fixture.id + ": " + checks.filter { !$0.passed }.map { $0.requirement }.joined(separator: "; "))
            print("PASS " + fixture.id + " (" + String(checks.count) + " bounded semantic checks)")
        }
    }
}
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def swift_block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        if text[end] == "{":
            depth += 1
        elif text[end] == "}":
            depth -= 1
        end += 1
    return text[start:end]


def compile_and_run(source, name, folder):
    path = folder / (name + ".swift")
    path.write_text(source)
    binary = folder / name
    subprocess.run(["swiftc", "-parse-as-library", str(path), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(folder)], check=True)


def main():
    manifest = json.loads((HERE / "source-manifest.json").read_text())
    for name, expected in manifest["retained_files"].items():
        if digest((HERE / name).read_bytes()) != expected:
            raise SystemExit("Retained evidence hash mismatch: " + name)
    repo = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], cwd=HERE, text=True).strip())
    texts = {}
    for path, expected in manifest["source_files"].items():
        data = subprocess.check_output(["git", "show", manifest["source_sha"] + ":" + path], cwd=repo)
        if digest(data) != expected:
            raise SystemExit("Recorded source hash mismatch: " + path)
        texts[Path(path).name] = data.decode()

    writing = texts["WritingActions.swift"].split("/// The same boundary runs in the Mac pipeline")[0]
    language_source = texts["LanguageCatalog.swift"]
    option = language_source.split("public enum VoiceInkTranscriptionLanguagePresentation")[0]
    language_data = language_source.split("    public static let all: [String: String] = [", 1)[1].split("    public static let englishOnly", 1)[0]
    languages = "public enum VoiceInkLanguageCatalog {\n"
    for name in ("autoDetectCode", "autoDetectName"):
        languages += re.search(r"    public static let " + name + r" = [^\n]+", language_source).group(0) + "\n"
    languages += "    public static let all: [String: String] = [" + language_data
    languages += swift_block(language_source, "    public static func sortedOptions(") + "\n}\n"
    wrapper = "public enum VoiceInkLocalCLIPreference {\n" + swift_block(texts["AIProviderCatalog.swift"], "    public static func fullPrompt(systemPrompt:") + "\n}\n"
    fixture_source = texts["WritingActionProviderTests.swift"]
    fixtures = fixture_source[fixture_source.index("private struct WritingProviderFixture:"):fixture_source.index("private struct WritingProviderReceipt:")]
    prompt_source = "\n".join((writing, option, languages, wrapper, fixtures, PROMPT_DRIVER))
    kind = texts["WritingActions.swift"].split("public struct VoiceInkWritingActionPreferences:")[0]
    validator_source = kind + "\n" + fixtures + "\n" + RESULT_VALIDATOR
    if digest(prompt_source.encode()) != manifest["driver_sha256"]:
        raise SystemExit("Reconstructed prompt driver differs from the recorded driver")
    if digest(validator_source.encode()) != manifest["validation_driver_sha256"]:
        raise SystemExit("Reconstructed result validator differs from the recorded validator")

    with tempfile.TemporaryDirectory(prefix="rjt-writing-cli-evidence-") as temporary:
        folder = Path(temporary)
        compile_and_run(prompt_source, "PromptDriver", folder)
        for case in IDS:
            request = json.loads((HERE / (case + ".request.json")).read_text())
            if json.loads((folder / (case + ".request.json")).read_text()) != request:
                raise SystemExit("Reconstructed request differs: " + case)
            if (folder / (case + ".full-prompt.txt")).read_bytes() != (HERE / (case + ".full-prompt.txt")).read_bytes():
                raise SystemExit("Reconstructed full prompt differs: " + case)
            receipt = json.loads((HERE / (case + ".cli-receipt.json")).read_text())
            recorded = manifest["requests"][case]
            if receipt["original_cli_result_sha256"] != recorded["cli_result_sha256"] or receipt["reported_models"] != recorded["cli_reported_models"]:
                raise SystemExit("CLI receipt metadata differs: " + case)
            observed = {key: receipt[key] for key in ("is_error", "subtype", "result")}
            (folder / (case + ".cli.json")).write_text(json.dumps(observed))
        compile_and_run(validator_source, "ResultValidator", folder)
        for case in IDS:
            regenerated = json.loads((folder / (case + ".validation.json")).read_text())
            retained = json.loads((HERE / (case + ".validation.json")).read_text())
            if regenerated != retained:
                raise SystemExit("Regenerated checks differ: " + case)
        supplemental_source = prompt_source[:prompt_source.index("@main struct Driver {")] + (HERE / "supplemental-driver.swift").read_text()
        if digest(supplemental_source.encode()) != manifest["supplemental_driver_sha256"]:
            raise SystemExit("Reconstructed supplemental driver differs from the recorded driver")
        shutil.copyfile(HERE / "additional-cases.json", folder / "additional-cases.json")
        compile_and_run(supplemental_source, "SupplementalDriver", folder)
        supplemental_checks = runpy.run_path(str(HERE / "supplemental_checks.py"))["checks"]
        for fixture in json.loads((HERE / "additional-cases.json").read_text()):
            case = fixture["id"]
            for suffix in ("request.json", "full-prompt.txt"):
                regenerated = (folder / (case + "." + suffix)).read_bytes()
                retained = (HERE / (case + "." + suffix)).read_bytes()
                if regenerated != retained:
                    raise SystemExit("Reconstructed supplemental request differs: " + case)
            receipt = json.loads((HERE / (case + ".cli-receipt.json")).read_text())
            recorded = manifest["supplemental_requests"][case]
            if receipt["original_cli_result_sha256"] != recorded["cli_result_sha256"] or receipt["reported_models"] != recorded["cli_reported_models"]:
                raise SystemExit("Supplemental CLI receipt metadata differs: " + case)
            checks = supplemental_checks(case, receipt["result"])
            regenerated = {"fixture": fixture, "output": receipt["result"], "checks": checks, "passed": all(check["passed"] for check in checks)}
            retained = json.loads((HERE / (case + ".validation.json")).read_text())
            if regenerated != retained or not regenerated["passed"]:
                raise SystemExit("Regenerated supplemental checks differ or fail: " + case)
            print("PASS " + case + " (" + str(len(checks)) + " bounded semantic checks)")
    print("PASS: retained hashes, source-bound prompts, and bounded checks verified offline")


if __name__ == "__main__":
    main()
