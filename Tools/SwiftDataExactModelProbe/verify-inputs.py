#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import tempfile

MODELS = ("Transcription.swift", "VocabularyWord.swift", "WordReplacement.swift", "SessionMetric.swift")
APP_LOCK_SHA = "2cdda5176a184329f2ca828316bfdefd9578d94bfed96a2b48b34b42b851e84c"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pins(path):
    result = {}
    entries = json.loads(path.read_text())["pins"]
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


def verify_lock(expected, actual):
    app = pins(expected)
    resolved = pins(actual)
    for identity, pin in resolved.items():
        if identity not in app or pin != app[identity]:
            raise ValueError(f"Package pin differs from app build graph: {identity}")
    return {identity: pin["state"]["revision"] for identity, pin in resolved.items()}


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
        expected.write_text(json.dumps({"pins": [pin]}))
        actual.write_text(expected.read_text())
        assert verify_lock(expected, actual) == {"dependency": "a" * 40}
        mutations = [
            {"pins": []}, {"pins": [pin, pin]},
            {"pins": [{**pin, "state": {"revision": "b" * 40, "version": "1.0.0"}}]},
            {"pins": [{**pin, "location": "https://example.invalid/other.git"}]},
            {"pins": [{**pin, "identity": "unlisted"}]},
        ]
        for mutation in mutations:
            actual.write_text(json.dumps(mutation))
            try:
                verify_lock(expected, actual)
            except (ValueError, KeyError, TypeError):
                continue
            raise AssertionError("Invalid lock was accepted")
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
    args = parser.parse_args()
    if sum((args.self_test, args.models is not None, args.locks is not None)) != 1:
        parser.error("Choose one input verification operation")
    if args.self_test:
        self_test()
        print("Exact model and dependency input rejection tests passed")
    elif args.models:
        print(json.dumps(verify_models(*args.models), sort_keys=True, indent=2))
    else:
        if sha(args.locks[0]) != APP_LOCK_SHA:
            raise ValueError("App lock differs from the pinned failing candidate")
        print(json.dumps(verify_lock(*args.locks), sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
