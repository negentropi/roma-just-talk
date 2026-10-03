#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

MODELS = ("Transcription.swift", "VocabularyWord.swift", "WordReplacement.swift", "SessionMetric.swift")
INPUT_LOCKS = {
    "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved": "2cdda5176a184329f2ca828316bfdefd9578d94bfed96a2b48b34b42b851e84c",
    "VoiceInkCore/Package.resolved": "146873579ca308c62a7a0bc5b8d4743d1bc2d8be0fab818e0bb032126b26ffa2",
    "VoiceInkNVIDIA/Package.resolved": "3a6af795e40cc28c19650da7cdaaf41c127bb2924e37deda63e246f2242bb639",
}
APP_ATOMICS = {"revision": "b601256eab081c0f92f059e12818ac1d4f178ff7", "version": "1.3.0"}
CORE_ATOMICS = {"revision": "0442cb5a3f98ab802acb777929fdb446bda11a34", "version": "1.3.1"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pins(path):
    result = {}
    document = json.loads(path.read_text())
    if document.get("version") not in (2, 3):
        raise ValueError("Unsupported lock format")
    entries = document["pins"]
    if not isinstance(entries, list) or not entries:
        raise ValueError("Missing resolved package pins")
    for pin in entries:
        identity = pin["identity"]
        if not isinstance(identity, str) or not identity or identity in result:
            raise ValueError("Invalid or duplicate package identity")
        if pin["kind"] != "remoteSourceControl":
            raise ValueError("Unexpected package kind")
        if not isinstance(pin["location"], str) or not pin["location"]:
            raise ValueError("Missing package source")
        revision = pin["state"]["revision"]
        if not isinstance(revision, str) or len(revision) != 40 or any(c not in "0123456789abcdef" for c in revision):
            raise ValueError("Invalid package revision")
        result[identity] = pin
    return result


def canonical_location(location):
    return location.rstrip("/").removesuffix(".git")


def same_pin(first, second):
    return (first["kind"] == second["kind"] and first["state"] == second["state"] and
            canonical_location(first["location"]) == canonical_location(second["location"]))


def merge_pins(inputs):
    merged, provenance, conflicts = {}, {}, []
    for name, entries in inputs:
        for identity, pin in entries.items():
            if identity not in merged:
                merged[identity], provenance[identity] = pin, name
            elif not same_pin(merged[identity], pin):
                selected = merged[identity]
                allowed = (identity == "swift-atomics" and selected["state"] == APP_ATOMICS and
                           pin["state"] == CORE_ATOMICS and selected["kind"] == pin["kind"] and
                           canonical_location(selected["location"]) == canonical_location(pin["location"]) == "https://github.com/apple/swift-atomics" and
                           provenance[identity] == next(iter(INPUT_LOCKS)) and name in tuple(INPUT_LOCKS)[1:])
                if not allowed:
                    raise ValueError(f"Conflicting package pins for {identity}: {provenance[identity]} vs {name}")
                conflicts.append({"identity": identity, "selectedSource": provenance[identity],
                                  "selectedPin": selected, "otherSource": name, "otherPin": pin,
                                  "decision": "Candidate run37131204306 compiled app Swift Atomics1.3.0"})
    return merged, conflicts


def seed_union(repo, destination):
    inputs, receipts = [], {}
    for relative, expected_sha in INPUT_LOCKS.items():
        path = repo / relative
        if sha(path) != expected_sha:
            raise ValueError(f"Committed input lock changed: {relative}")
        committed = subprocess.check_output(["git", "-C", str(repo), "show", "HEAD:" + relative])
        if committed != path.read_bytes():
            raise ValueError(f"Input lock differs from committed bytes: {relative}")
        entries = pins(path)
        inputs.append((relative, entries))
        receipts[relative] = {"sha256": expected_sha, "pinCount": len(entries)}
    merged, conflicts = merge_pins(inputs)
    with destination.open("x") as output:
        json.dump({"version": 2, "pins": [merged[key] for key in sorted(merged)]}, output, sort_keys=True, indent=2)
        output.write("\n")
    return {"inputs": receipts, "unionPinCount": len(merged), "unionSHA256": sha(destination),
            "conflicts": conflicts, "appPinAuthority": {"runID": 37131204306,
                "sourceSHA": "71daeaee964811da3ec71ad66370eee1d013e5d0",
                "logLines": [1611, 25839, 48682], "swiftAtomicsVersion": "1.3.0"}}


def verify_lock(expected, actual):
    app = pins(expected)
    resolved = pins(actual)
    for identity, pin in resolved.items():
        if identity not in app or not same_pin(pin, app[identity]):
            raise ValueError(f"Package pin differs from bound production graphs: {identity}")
    return {identity: pin["state"]["revision"] for identity, pin in resolved.items()}


def verify_checkouts(lock, scratch):
    expected = pins(lock)
    dependencies = json.loads((scratch / "workspace-state.json").read_text())["object"]["dependencies"]
    if not isinstance(dependencies, list):
        raise ValueError("Invalid SwiftPM workspace dependency list")
    observed = {}
    for dependency in dependencies:
        identity = dependency["packageRef"]["identity"]
        if dependency["state"]["name"] != "sourceControlCheckout":
            if identity in expected:
                raise ValueError(f"Pinned dependency is not a source checkout: {identity}")
            continue
        if identity not in expected or identity in observed:
            raise ValueError(f"Unexpected or duplicate checkout: {identity}")
        wanted = expected[identity]
        revision = dependency["state"]["checkoutState"]["revision"]
        if revision != wanted["state"]["revision"]:
            raise ValueError(f"Workspace revision mismatch: {identity}")
        if canonical_location(dependency["packageRef"]["location"]) != canonical_location(wanted["location"]):
            raise ValueError(f"Workspace source mismatch: {identity}")
        checkout = (scratch / "checkouts" / dependency["subpath"]).resolve(strict=True)
        if checkout.parent != (scratch / "checkouts").resolve():
            raise ValueError(f"Checkout escapes build directory: {identity}")
        top = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "--show-toplevel"], text=True).strip()
        actual = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
        dirty = subprocess.check_output(["git", "-C", str(checkout), "status", "--porcelain", "--untracked-files=all"], text=True)
        if Path(top).resolve() != checkout or actual != revision or dirty:
            raise ValueError(f"Dirty or mismatched actual checkout: {identity}")
        observed[identity] = {"revision": actual, "location": wanted["location"], "checkout": str(checkout)}
    if observed.keys() != expected.keys():
        raise ValueError("Actual source checkouts do not match resolved lock identities")
    return observed


def verify_models(repo, probe):
    result = {}
    for name in MODELS:
        source = repo / "VoiceInk" / "Models" / name
        copied = probe / "Sources" / "VoiceInk" / name
        if source.read_bytes() != copied.read_bytes():
            raise ValueError(f"Production model copy differs: {name}")
        result[name] = sha(source)
    return result


def self_test():
    with tempfile.TemporaryDirectory(prefix="swiftdata-exact-input-test-") as directory:
        root = Path(directory)
        expected, actual = root / "expected.json", root / "actual.json"
        pin = {"identity": "dependency", "kind": "remoteSourceControl", "location": "https://example.invalid/source.git",
               "state": {"revision": "a" * 40, "version": "1.0.0"}}
        expected.write_text(json.dumps({"version": 2, "pins": [pin]}))
        actual.write_text(expected.read_text())
        assert verify_lock(expected, actual) == {"dependency": "a" * 40}
        mutations = [
            {"pins": []}, {"pins": [pin, pin]},
            {"pins": [{**pin, "state": {"revision": "b" * 40, "version": "1.0.0"}}]},
            {"pins": [{**pin, "location": "https://example.invalid/other.git"}]},
            {"pins": [{**pin, "identity": "unlisted"}]},
        ]
        for mutation in mutations:
            mutation["version"] = 2
            actual.write_text(json.dumps(mutation))
            try:
                verify_lock(expected, actual)
            except (ValueError, KeyError, TypeError):
                continue
            raise AssertionError("Invalid lock was accepted")
        first_name, second_name, third_name = INPUT_LOCKS
        atomics = {**pin, "identity": "swift-atomics", "location": "https://github.com/apple/swift-atomics.git", "state": APP_ATOMICS}
        core_atomics = {**atomics, "state": CORE_ATOMICS}
        absent = {**pin, "identity": "grpc"}
        merged, conflicts = merge_pins([(first_name, {"swift-atomics": atomics}),
            (second_name, {"swift-atomics": core_atomics, "grpc": absent}),
            (third_name, {"swift-atomics": core_atomics, "grpc": absent})])
        assert merged == {"swift-atomics": atomics, "grpc": absent} and len(conflicts) == 2
        normalized = {**pin, "location": pin["location"].removesuffix(".git")}
        assert same_pin(pin, normalized)
        for changed in ({**absent, "state": CORE_ATOMICS}, {**core_atomics, "state": {"revision": "c" * 40, "version": "1.3.2"}}):
            entries = [(first_name, {changed["identity"]: {**changed, "state": APP_ATOMICS}}),
                       (second_name, {changed["identity"]: changed})]
            try:
                merge_pins(entries)
            except ValueError:
                continue
            raise AssertionError("Unobserved conflict was accepted")
        scratch = root / "scratch"
        checkout = scratch / "checkouts" / "dependency"
        checkout.mkdir(parents=True)
        expected.write_text(json.dumps({"version": 2, "pins": [pin]}))
        dependency = {"packageRef": {"identity": "dependency", "location": pin["location"]},
                      "state": {"name": "sourceControlCheckout", "checkoutState": pin["state"]},
                      "subpath": "dependency"}
        workspace = scratch / "workspace-state.json"
        workspace.write_text(json.dumps({"object": {"dependencies": [dependency]}}))
        subprocess.run(["git", "init", "--quiet", str(checkout)], check=True)
        source = checkout / "source.swift"
        source.write_text("original\n")
        subprocess.run(["git", "-C", str(checkout), "add", "source.swift"], check=True)
        subprocess.run(["git", "-C", str(checkout), "-c", "user.name=Probe test fixture",
                        "-c", "user.email=probe-test@example.invalid", "-c", "commit.gpgsign=false",
                        "commit", "--quiet", "-m", "test fixture"], check=True)
        revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
        fixture_pin = {**pin, "state": {"revision": revision}}
        expected.write_text(json.dumps({"version": 2, "pins": [fixture_pin]}))
        dependency["state"]["checkoutState"] = fixture_pin["state"]
        workspace.write_text(json.dumps({"object": {"dependencies": [dependency]}}))
        assert verify_checkouts(expected, scratch)["dependency"]["revision"] == revision
        for dirty_path, text in ((source, "modified\n"), (checkout / "untracked.swift", "untracked\n")):
            dirty_path.write_text(text)
            try:
                verify_checkouts(expected, scratch)
            except ValueError:
                pass
            else:
                raise AssertionError("Dirty actual checkout accepted")
            if dirty_path == source:
                source.write_text("original\n")
        (checkout / "untracked.swift").rename(root / "retained-untracked.swift")
        wrong_pin = {**fixture_pin, "state": {"revision": "b" * 40}}
        expected.write_text(json.dumps({"version": 2, "pins": [wrong_pin]}))
        dependency["state"]["checkoutState"] = wrong_pin["state"]
        workspace.write_text(json.dumps({"object": {"dependencies": [dependency]}}))
        try:
            verify_checkouts(expected, scratch)
        except ValueError:
            pass
        else:
            raise AssertionError("Mismatched actual HEAD accepted")
        expected.write_text(json.dumps({"version": 2, "pins": [fixture_pin]}))
        dependency["state"]["checkoutState"] = fixture_pin["state"]
        workspace.write_text(json.dumps({"object": {"dependencies": [dependency, dependency]}}))
        try:
            verify_checkouts(expected, scratch)
        except ValueError:
            pass
        else:
            raise AssertionError("Duplicate checkout accepted")
        repo, probe = root / "repo", root / "probe"
        (repo / "VoiceInk" / "Models").mkdir(parents=True)
        (probe / "Sources" / "VoiceInk").mkdir(parents=True)
        for name in MODELS:
            (repo / "VoiceInk" / "Models" / name).write_text(name)
            (probe / "Sources" / "VoiceInk" / name).write_text(name)
        verify_models(repo, probe)
        (probe / "Sources" / "VoiceInk" / "SessionMetric.swift").write_text("altered")
        try:
            verify_models(repo, probe)
        except ValueError:
            return
        raise AssertionError("Modified model was accepted")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--models", nargs=2, metavar=("REPO", "PROBE"), type=Path)
    parser.add_argument("--locks", nargs=2, metavar=("APP", "PROBE"), type=Path)
    parser.add_argument("--union", nargs=2, metavar=("REPO", "DESTINATION"), type=Path)
    parser.add_argument("--checkouts", nargs=2, metavar=("LOCK", "SCRATCH"), type=Path)
    args = parser.parse_args()
    if sum((args.self_test, args.models is not None, args.locks is not None, args.union is not None, args.checkouts is not None)) != 1:
        parser.error("Choose one input verification operation")
    if args.self_test:
        self_test()
        print("Exact model and dependency input rejection tests passed")
    elif args.models:
        print(json.dumps(verify_models(*args.models), sort_keys=True, indent=2))
    elif args.locks:
        print(json.dumps(verify_lock(*args.locks), sort_keys=True, indent=2))
    elif args.union:
        print(json.dumps(seed_union(*args.union), sort_keys=True, indent=2))
    else:
        print(json.dumps(verify_checkouts(*args.checkouts), sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
