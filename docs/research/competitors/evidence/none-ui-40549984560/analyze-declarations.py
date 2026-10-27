#!/usr/bin/env python3
"""Reproduce the prebuild census mismatch from immutable Git objects; no worktree mutation."""
import hashlib
import json
import subprocess

revisions = {"baseline": "bdd608cf6111e8d7e88c12678f530318713acf67",
             "candidate": "5bf8e4df18d3e38756a431122b5fa98208daeb2c"}
product_roots = {"VoiceInk", "VoiceInkCore", "VoiceInkNVIDIA", "VoiceInkQwen", "VoiceInk.xcodeproj", "iOS"}
rows = {}
for lane, revision in revisions.items():
    names = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", revision], text=True).splitlines()
    declarations = [name for name in names if name == "Package.swift" or name.endswith("/Package.swift")
                    or name == "VoiceInk.xcodeproj/project.pbxproj"]
    rows[lane] = {name: hashlib.sha256(subprocess.check_output(["git", "show", revision + ":" + name])).hexdigest()
                  for name in declarations}
changed = [name for name in sorted(rows["baseline"].keys() | rows["candidate"].keys())
           if rows["baseline"].get(name) != rows["candidate"].get(name)]
actual_build_changes = [name for name in changed if name == "Package.swift" or name.split("/", 1)[0] in product_roots]
assert len(changed) == 2 and all(name.startswith("docs/research/competitors/evidence/ollama-identity-40545355522/") for name in changed)
assert not actual_build_changes
print(json.dumps({"revisions": revisions, "declarations": rows, "changed": changed,
                  "actual_build_declaration_changes": actual_build_changes}, indent=2, sort_keys=True))
