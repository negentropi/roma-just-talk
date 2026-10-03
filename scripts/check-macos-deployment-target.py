#!/usr/bin/env python3
"""Reject app payloads whose Mac minimum exceeds the supported launch floor."""

import argparse
import pathlib
import plistlib
import re
import subprocess
import sys

SUPPORTED_MACOS = "14.2.1"
MACHO_MAGIC = {
    bytes.fromhex(value)
    for value in ("feedface", "cefaedfe", "feedfacf", "cffaedfe",
                  "cafebabe", "bebafeca", "cafebabf", "bfbafeca")
}


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError(f"invalid macOS version {value!r}")
    return tuple(map(int, value.split("."))) + (0,) * (3 - len(value.split(".")))


def macos_minimums(load_commands):
    sections = re.split(r"^.*\(architecture [^)]+\):\s*$", load_commands,
                        flags=re.MULTILINE)
    if len(sections) > 1:
        sections = sections[1:]
    minimums = []
    for section in sections:
        mac_versions = []
        for command in re.split(r"^Load command \d+\s*$", section,
                                flags=re.MULTILINE):
            fields = dict(re.findall(r"^\s*(cmd|platform|minos|version)\s+(\S+)",
                                     command, flags=re.MULTILINE))
            if fields.get("cmd") == "LC_VERSION_MIN_MACOSX":
                mac_versions.append(fields.get("version"))
            elif (fields.get("cmd") == "LC_BUILD_VERSION"
                  and fields.get("platform", "").upper() in {"1", "MACOS"}):
                mac_versions.append(fields.get("minos"))
        # Swift compatibility libraries may also declare Mac Catalyst. Only their
        # macOS command governs this launch; every architecture still needs one.
        if not mac_versions:
            raise ValueError("Mach-O architecture has no macOS minimum")
        minimums.extend(version(value) for value in mac_versions)
    return minimums


def check_app(app):
    if not (app / "Contents/Info.plist").is_file():
        raise ValueError("missing macOS app Contents/Info.plist")
    failures = []
    count = 0
    floor = version(SUPPORTED_MACOS)
    for path in sorted(app.rglob("*")):
        if path.is_symlink() or not path.is_file():
            continue
        relative = path.relative_to(app)
        if path.name == "Info.plist":
            with path.open("rb") as stream:
                info = plistlib.load(stream)
            minimum = info.get("LSMinimumSystemVersion")
            if minimum is not None and version(minimum) > floor:
                failures.append(f"{relative}: Info.plist requires macOS {minimum}")
            if relative == pathlib.Path("Contents/Info.plist") and minimum is None:
                failures.append("app Info.plist has no LSMinimumSystemVersion")
        with path.open("rb") as stream:
            if stream.read(4) not in MACHO_MAGIC:
                continue
        result = subprocess.run(["otool", "-arch", "all", "-l", str(path)], check=True,
                                capture_output=True, text=True)
        for minimum in macos_minimums(result.stdout):
            if minimum > floor:
                text = ".".join(map(str, minimum))
                failures.append(f"{relative}: Mach-O requires macOS {text}")
        count += 1
    if not count:
        failures.append("app contains no macOS Mach-O payload")
    if failures:
        raise ValueError("\n".join(failures))
    print(f"Verified macOS {SUPPORTED_MACOS} deployment floor: {count} Mach-O files")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    args = parser.parse_args()
    try:
        check_app(args.app)
    except (OSError, ValueError, plistlib.InvalidFileException,
            subprocess.CalledProcessError) as error:
        print(f"Deployment gate failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
