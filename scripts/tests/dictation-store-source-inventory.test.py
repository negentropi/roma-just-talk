#!/usr/bin/env python3
import ast
import hashlib
import json
import os
import stat
import subprocess
import tempfile
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
DRIVER = "scripts/run-dictation-store-seed-check.sh"
KNOWN_BAD = "0ada98ede86a4b546576dd8e7e6aab17fc775c99"
CALLERS = ["whisper_source", "package_state"]
COMMON = ["require", "digest", "load", "git"]
CURRENT = [*COMMON, "tracked_sources", "tree", "dependency_state", "verify_dependencies", *CALLERS]


def git(root, *arguments, input=None):
    return subprocess.check_output(
        ["git", "-C", str(root), "-c", "core.hooksPath=/dev/null", *arguments],
        input=input, stderr=subprocess.PIPE
    )


def functions(source, names, filename):
    block = source.split("<<'PY'\n", 1)[1].rsplit("\nPY\n", 1)[0]
    parsed = ast.parse(block, filename=filename)
    selected = [node for node in parsed.body if isinstance(node, ast.FunctionDef) and node.name in names]
    assert sorted(node.name for node in selected) == sorted(names), "Missing or duplicate actual inventory function"
    namespace = {"hashlib": hashlib, "json": json, "os": os, "stat": stat, "subprocess": subprocess, "Path": Path}
    exec(compile(ast.Module(body=selected, type_ignores=[]), filename, "exec"), namespace)
    hashes = {node.name: hashlib.sha256(ast.get_source_segment(block, node).encode()).hexdigest() for node in selected}
    return namespace, hashes


def write_json(path, value):
    path.write_text(json.dumps(value, sort_keys=True))


def fails(operation, kind, *messages):
    try:
        operation()
    except kind as error:
        assert not messages or any(message.lower() in str(error).lower() for message in messages), str(error)
        return type(error).__name__
    raise AssertionError("Expected rejection did not occur")


def fixture(root):
    packages = root / "packages"
    checkout = packages / "checkouts/fixture"
    checkout.mkdir(parents=True)
    git(checkout, "init", "-q")
    git(checkout, "config", "core.filemode", "true")
    contents = {
        "regular.txt": b"Cafe\xcc\x81\r\nfixture\n",
        "executable.sh": b"#!/bin/sh\nexit 0\n",
        "name with spaces\nand newline.txt": b"literal path fixture\n",
        "payload/child.txt": b"directory contents\n"
    }
    links = {"A directory link": "payload", "file link": "regular.txt", "dangling link": "missing target\nliteral"}
    for name, data in contents.items():
        path = checkout / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    (checkout / "executable.sh").chmod(0o755)
    for name, target in links.items():
        (checkout / name).symlink_to(target)
    git(checkout, "add", "-A")
    git(checkout, "-c", "user.name=Store Inventory Fixture", "-c", "user.email=store-inventory@example.invalid", "-c", "commit.gpgsign=false", "commit", "-qm", "test: source inventory fixture")
    revision = git(checkout, "rev-parse", "HEAD").decode().strip()
    repo = root / "repo"
    repo.mkdir()
    lock = "Package.resolved"
    write_json(repo / lock, {"pins": [{"identity": "fixture", "state": {"revision": revision}}]})
    write_json(packages / "workspace-state.json", {"object": {"dependencies": [{
        "packageRef": {"identity": "fixture", "location": "https://example.invalid/fixture.git"},
        "state": {"checkoutState": {"revision": revision}}, "subpath": "fixture"
    }]}})
    for name in ["Makefile", "scripts/verify-static-whisper-xcframework.sh", "scripts/verify-static-whisper-app.sh", "scripts/verify-adhoc-library-validation.sh"]:
        path = repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"source inventory fixture\n")
    framework = root / "framework"
    framework.mkdir()
    (framework / "Info.plist").write_bytes(b"framework inventory fixture\n")
    output = root / "frozen"
    output.mkdir()
    bindings = {"whisper": checkout, "packages": packages, "repo": repo, "lock_path": lock, "framework": framework, "output": output}
    expected = {}
    for name, data in contents.items():
        expected[name] = {
            "git_mode": "100755" if name == "executable.sh" else "100644",
            "git_object": git(checkout, "rev-parse", "HEAD:" + name).decode().strip(),
            "kind": "file", "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()
        }
    for name, target in links.items():
        expected[name] = {"git_mode": "120000", "git_object": git(checkout, "rev-parse", "HEAD:" + name).decode().strip(), "kind": "symlink", "target": target}
    return checkout, bindings, expected


def check():
    old, old_hashes = functions(git(REPO, "show", KNOWN_BAD + ":" + DRIVER).decode(), [*COMMON, *CALLERS], KNOWN_BAD + ":" + DRIVER)
    current, current_hashes = functions((REPO / DRIVER).read_text(), CURRENT, DRIVER)
    with tempfile.TemporaryDirectory(prefix="rjt-store-source-inventory-") as temporary:
        checkout, bindings, expected = fixture(Path(temporary))
        old.update(bindings)
        current.update(bindings)
        red = {}
        for caller in CALLERS:
            try:
                old[caller]()
            except IsADirectoryError as error:
                assert Path(error.filename) == checkout / "A directory link", "Known-bad failure crossed a different boundary"
                red[caller] = "IsADirectoryError on tracked directory symlink"
            else:
                raise AssertionError("Actual known-bad caller did not reproduce the directory-symlink failure: " + caller)
        assert current["tracked_sources"](checkout) == expected
        assert current["whisper_source"]()["tracked_sources"] == expected
        assert current["package_state"]()["fixture"]["tracked_sources"] == expected
        frozen_dependency = current["dependency_state"]()
        frozen_package = current["package_state"]()
        output = bindings["output"]
        write_json(output / "dependencies-frozen.json", frozen_dependency)
        write_json(output / "packages-frozen.json", frozen_package)
        current["verify_dependencies"]()

        def reject_drift(label):
            changed = current["tracked_sources"](checkout)
            assert changed != expected, label
            assert current["whisper_source"]()["tracked_sources"] == changed
            fails(current["package_state"], RuntimeError, "tracked changes")
            fails(current["verify_dependencies"], RuntimeError, "Shared static Whisper")
            write_json(output / "dependencies-frozen.json", current["dependency_state"]())
            fails(current["verify_dependencies"], RuntimeError, "tracked changes")
            write_json(output / "dependencies-frozen.json", frozen_dependency)

        link = checkout / "A directory link"
        link.unlink()
        link.symlink_to("regular.txt")
        reject_drift("Tracked link target drift must change the frozen inventory")
        link.unlink()
        link.symlink_to("payload")
        original = (checkout / "regular.txt").read_bytes()
        (checkout / "regular.txt").write_bytes(b"changed regular source bytes\n")
        reject_drift("Tracked file content drift must change the frozen inventory")
        (checkout / "regular.txt").write_bytes(original)
        current["verify_dependencies"]()
        (checkout / "regular.txt").write_bytes(b"staged source drift\n")
        git(checkout, "add", "--", "regular.txt")
        fails(current["package_state"], RuntimeError, "tracked changes")
        (checkout / "regular.txt").write_bytes(original)
        git(checkout, "add", "--", "regular.txt")
        current["verify_dependencies"]()

        executable = checkout / "executable.sh"
        for changed_mode in [0o644, 0o655]:
            executable.chmod(changed_mode)
            fails(lambda: current["tracked_sources"](checkout), RuntimeError, "executable mode")
        executable.chmod(0o755)
        link.unlink()
        link.write_text("changed filesystem kind\n")
        fails(lambda: current["tracked_sources"](checkout), RuntimeError, "filesystem kind")
        link.unlink()
        link.symlink_to("payload")
        revision = git(checkout, "rev-parse", "HEAD").decode().strip()
        git(checkout, "update-index", "--add", "--cacheinfo", "160000", revision, "unsupported-gitlink")
        fails(lambda: current["tracked_sources"](checkout), RuntimeError, "160000", "gitlink")
        git(checkout, "update-index", "--force-remove", "--", "unsupported-gitlink")
        object_id = expected["regular.txt"]["git_object"]
        git(checkout, "update-index", "--index-info", input=("100644 " + object_id + " 1\tconflicted.txt\n").encode())
        fails(lambda: current["tracked_sources"](checkout), RuntimeError, "unmerged", "stage")
        git(checkout, "update-index", "--force-remove", "--", "conflicted.txt")
        current["verify_dependencies"]()
    return {
        "classification": "source-inventory-regression-passed", "known_bad_commit": KNOWN_BAD,
        "actual_known_bad_failures": red, "known_bad_function_sha256": old_hashes,
        "candidate_function_sha256": current_hashes,
        "candidate_controls": ["actual helper and both callers preserve Git modes, objects, file bytes and literal link targets", "directory, file and dangling symlinks", "space and newline filenames", "real frozen dependency comparison rejects link-target and file-content drift", "package inventory rejects staged and unstaged tracked changes before freezing", "executable and filesystem kind drift rejected", "gitlink and unmerged Git stage rejected"],
        "scope": "Source-inventory regression only; no app, SwiftData, dependency build or native store execution."
    }


if __name__ == "__main__":
    print(json.dumps(check(), sort_keys=True))
