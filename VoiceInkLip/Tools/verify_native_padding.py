#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess


if os.environ.get("GITHUB_ACTIONS") != "true" or platform.system() != "Darwin":
    raise SystemExit("Run only on the disposable native macOS proof host.")

root = Path(__file__).resolve().parents[2]
source = root / "VoiceInkLip/Sources/VoiceInkLip/MouthVideoProcessor.swift"
candidate = source.read_bytes()
proof = Path(os.environ["LIP_PROOF_DIR"]) / "padding-regression"
proof.mkdir()
known_bad = "885549f0637d18a5c8148b3b5bdb43fc333460ba"
subprocess.run(["git", "fetch", "--no-tags", "--depth=1", "origin", known_bad], cwd=root, check=True)
bad_source = subprocess.check_output(["git", "show", known_bad + ":VoiceInkLip/Sources/VoiceInkLip/MouthVideoProcessor.swift"], cwd=root)
build = ["swift", "build", "--package-path", "VoiceInkLip", "--scratch-path", os.environ["LIP_BUILD_DIR"],
         "--configuration", "release", "--product", "LipDictationProof", "--jobs", "4"]


def compile_source(label):
    with (proof / (label + ".log")).open("wb") as log:
        subprocess.run(build, cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)


results = []
try:
    source.write_bytes(bad_source)
    compile_source("known-bad-build")
    for label in ("a", "b", "c"):
        receipt = proof / (label + "-known-bad.json")
        video = Path(os.environ["LIP_PROOF_DIR"]) / "fixtures" / (label + "-silent.mp4")
        with (proof / (label + "-known-bad.log")).open("wb") as log:
            result = subprocess.run([
                os.environ["LIP_PROOF_BIN"], "infer", "--model-directory", os.environ["LIP_MODEL_DIR"],
                "--video", str(video), "--receipt", str(receipt),
            ], stdout=log, stderr=subprocess.STDOUT)
        observed = json.loads(receipt.read_text())
        assert result.returncode != 0 and observed["status"] == "error", observed
        assert observed.get("errorCode") == "mouthVideo.missingFace" and observed.get("errorFrame") == 0, observed
        assert not observed.get("text"), observed
        results.append({"fixture": label, "videoSHA256": observed["videoSHA256"], "knownBadRejectedPadding": True})
finally:
    source.write_bytes(candidate)
    assert source.read_bytes() == candidate
    compile_source("candidate-build")

(proof / "receipt.json").write_text(json.dumps({
    "knownBad": known_bad,
    "candidateSourceSHA256": hashlib.sha256(candidate).hexdigest(),
    "sameHostSameFixturesSameRuntime": True,
    "results": results,
    "candidateAcceptance": "The following native inference and face-control steps must pass after restoring this exact source.",
}, indent=2) + "\n")
