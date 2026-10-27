#!/usr/bin/env python3
import ast
import copy
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
KNOWN_BAD = "5bf8e4df18d3e38756a431122b5fa98208daeb2c"
SCRIPTS = [
    "scripts/run-writing-feature-regression.sh",
    "scripts/run-writing-settings-ui-regression.sh",
]
PRODUCT_FILES = {
    "Package.swift": "// Root package\n",
    "VoiceInk/Packages/Native/Package.swift": "// App package\n",
    "VoiceInkCore/Package.swift": "// Core package\n",
    "VoiceInkNVIDIA/Package.swift": "// NVIDIA package\n",
    "VoiceInkQwen/Package.swift": "// Qwen package\n",
    "VoiceInk.xcodeproj/project.pbxproj": "// Mac app project\n",
    "iOS/Package.swift": "// iOS package\n",
    "iOS/VoiceInk-ios.xcodeproj/project.pbxproj": "// iOS app project\n",
}
ARCHIVED_FILES = [
    "docs/research/competitors/evidence/ollama-identity-40545355522/native/baseline/package/Package.swift",
    "docs/research/competitors/evidence/ollama-identity-40545355522/native/candidate/package/Package.swift",
    "Tools/unrelatedRuntimeHarness/Package.swift",
]


def git(root, *arguments):
    return subprocess.check_output(["git", "-C", str(root), *arguments], stderr=subprocess.PIPE)


def declaration_function(source, filename):
    matches = []
    for block in re.findall(r"<<'PY'[^\n]*\n(.*?)\nPY(?:\n|$)", source, re.S):
        module = ast.parse(block, filename=filename)
        functions = [node for node in ast.walk(module) if isinstance(node, ast.FunctionDef) and node.name == "declarations"]
        if functions:
            matches.append((module, functions))
    assert len(matches) == 1 and len(matches[0][1]) == 1, filename
    module, functions = matches[0]
    dependencies = [node for node in module.body if isinstance(node, (ast.Import, ast.ImportFrom))]
    dependencies += [
        node for node in module.body
        if isinstance(node, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id in {"PRODUCT", "digest"} for target in node.targets)
    ]
    extracted = ast.fix_missing_locations(ast.Module(body=copy.deepcopy([*dependencies, functions[0]]), type_ignores=[]))
    namespace = {}
    exec(compile(extracted, filename, "exec"), namespace)
    return namespace["declarations"], hashlib.sha256(ast.dump(functions[0]).encode()).hexdigest()


def write(root, relative, content):
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def stage(root):
    git(root, "add", "-A")


def check_script(script, root):
    old_source = git(REPO, "show", f"{KNOWN_BAD}:{script}").decode()
    old, old_hash = declaration_function(old_source, f"{KNOWN_BAD}:{script}")
    current, current_hash = declaration_function((REPO / script).read_text(), script)
    baseline, candidate = root / "baseline", root / "candidate"
    for checkout in [baseline, candidate]:
        checkout.mkdir()
        git(checkout, "init", "-q")
        for path, content in PRODUCT_FILES.items():
            write(checkout, path, content)
        stage(checkout)
    assert old(baseline) == old(candidate), "The unchanged fixture must match under the known-bad census."
    expected = current(baseline)
    assert set(expected) == set(PRODUCT_FILES), f"Live build declarations missing from {script}: {set(PRODUCT_FILES) - set(expected)}"
    for path in ARCHIVED_FILES:
        write(candidate, path, "// Retained standalone evidence package\n")
    stage(candidate)
    assert old(baseline) != old(candidate), "The known-bad census did not reproduce the archived-manifest failure."
    assert expected == current(candidate), "Archived evidence or an unrelated Tools harness changed the live build census."

    rejected = []
    for path, content in PRODUCT_FILES.items():
        write(candidate, path, content + "// Actual build declaration changed\n")
        stage(candidate)
        assert current(candidate) != expected, f"Real declaration drift was accepted: {script}: {path}"
        rejected.append(path)
        write(candidate, path, content)
        stage(candidate)
        assert current(candidate) == expected, f"Restored live declaration did not converge: {path}"

    added = "VoiceInkCore/Extensions/Package.swift"
    write(candidate, added, "// Additional live package\n")
    stage(candidate)
    assert current(candidate) != expected, "An added live package declaration was ignored."
    (candidate / added).unlink()
    stage(candidate)
    assert current(candidate) == expected

    removed = "VoiceInkQwen/Package.swift"
    (candidate / removed).unlink()
    stage(candidate)
    assert current(candidate) != expected, "A removed live package declaration was ignored."
    write(candidate, removed, PRODUCT_FILES[removed])
    stage(candidate)
    assert current(candidate) == expected
    return {
        "script": script,
        "known_bad_revision": KNOWN_BAD,
        "old_function_sha256": old_hash,
        "current_function_sha256": current_hash,
        "known_bad_rejects_identical_products_with_archived_manifests": True,
        "current_accepts_identical_products_with_archived_manifests": True,
        "real_declaration_changes_rejected": rejected,
        "added_live_manifest_rejected": True,
        "removed_live_manifest_rejected": True,
    }


def main():
    with tempfile.TemporaryDirectory(prefix="rjt-declaration-census-") as temporary:
        results = []
        for index, script in enumerate(SCRIPTS):
            root = Path(temporary) / str(index)
            root.mkdir()
            results.append(check_script(script, root))
    print(json.dumps({"valid": True, "comparisons": results}, indent=2))


if __name__ == "__main__":
    main()
