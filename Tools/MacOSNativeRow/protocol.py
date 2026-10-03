import base64
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
import stat
import subprocess
import tempfile
from types import MappingProxyType
import warnings
import zipfile
import zlib

from PIL import Image, ImageStat


class Rejected(ValueError):
    pass


def require(condition, reason):
    if not condition:
        raise Rejected(reason)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode()


def decode(raw):
    def pairs(items):
        value = {}
        for key, item in items:
            require(key not in value, "duplicate-json-key")
            value[key] = item
        return value
    def nonfinite(_):
        raise Rejected("nonfinite-json")
    def finite_float(value):
        parsed = float(value)
        require(math.isfinite(parsed), "nonfinite-json")
        return parsed
    try:
        return json.loads(raw, object_pairs_hook=pairs, parse_constant=nonfinite, parse_float=finite_float)
    except Rejected:
        raise
    except (UnicodeError, ValueError, RecursionError) as error:
        raise Rejected("invalid-json") from error


def member_name(name):
    require(isinstance(name, str) and name and len(name) <= 1024 and "\\" not in name
            and not any(ord(char) < 32 for char in name), "unsafe-member")
    path = PurePosixPath(name)
    require(not path.is_absolute() and path.as_posix() == name and all(part not in (".", "..") for part in name.split("/")), "unsafe-member")
    return name


def archive_snapshot(raw, expected_sha256, expected_size, max_transport_bytes=12 * 1024 * 1024):
    require(isinstance(raw, bytes) and len(raw) == expected_size and digest(raw) == expected_sha256, "api-artifact-bytes")
    require(0 < len(raw) <= max_transport_bytes, "transport-capacity")
    files, seen = {}, set()
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            items = archive.infolist()
            require(len(items) <= 20000 and sum(item.file_size for item in items) <= 512 * 1024 * 1024, "archive-capacity")
            for item in items:
                name = member_name(item.filename[:-1] if item.is_dir() else item.filename)
                require(name not in seen, "duplicate-member")
                seen.add(name)
                mode = item.external_attr >> 16
                require(not item.flag_bits & 1 and not stat.S_ISLNK(mode)
                        and stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR), "archive-member-type")
                if item.is_dir():
                    continue
                require(item.file_size <= 16 * 1024 * 1024, "member-capacity")
                files[name] = archive.read(item)
    except (zipfile.BadZipFile, EOFError, RuntimeError, NotImplementedError, zlib.error) as error:
        raise Rejected("invalid-archive") from error
    return MappingProxyType(files)


def verify_signature(raw, signature, identity, namespace, public_key):
    require(isinstance(identity, str) and identity and isinstance(namespace, str) and namespace
            and not any(char.isspace() for char in identity + namespace) and '"' not in namespace,
            "trusted-signer-shape")
    try:
        key = base64.b64decode(public_key.split()[1], validate=True)
        require(public_key.split()[0] == "ssh-ed25519" and len(public_key.split()) == 2
                and key[:19] == b"\x00\x00\x00\x0bssh-ed25519\x00\x00\x00\x20" and len(key) == 51, "trusted-key-shape")
    except (AttributeError, IndexError, TypeError, ValueError) as error:
        raise Rejected("trusted-key-shape") from error
    require(isinstance(signature, bytes) and 0 < len(signature) <= 16384, "signature-capacity")
    with tempfile.TemporaryDirectory(prefix="roma-native-row-signature-") as directory:
        root = Path(directory)
        allowed, detached = root / "allowed_signers", root / "signature"
        allowed.write_text(f'{identity} namespaces="{namespace}" {public_key}\n')
        detached.write_bytes(signature)
        try:
            result = subprocess.run(["ssh-keygen", "-Y", "verify", "-f", str(allowed), "-I", identity,
                                     "-n", namespace, "-s", str(detached)], input=raw, capture_output=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise Rejected("signature-verifier-unavailable") from error
    require(result.returncode == 0, "broker-signature-invalid")


def native_call(files, phase, code, title, browser, earliest_ms, expires_ms, now_ms):
    path = phase + "/original-entry.json"
    require(path in files, "original-call-missing")
    raw = files[path]
    entry = decode(raw)
    require(isinstance(entry, dict), "original-call-shape")
    item = entry.get("item", {})
    require(isinstance(item, dict) and (item.get("type"), item.get("server"), item.get("tool"), item.get("status"))
            == ("mcpToolCall", "cua_repl", "js", "completed") and item.get("error") is None, "call-incomplete-or-error")
    require(item.get("arguments") == {"code": code, "title": title}, "call-profile-or-challenge")
    started, completed = entry.get("startedAtMs"), entry.get("completedAtMs")
    require(type(started) is int and type(completed) is int and earliest_ms <= started <= completed < expires_ms
            and completed <= now_ms, "call-stale-or-unordered")
    identity = entry.get("turnId"), item.get("id")
    require(all(isinstance(value, str) and value for value in identity), "call-identity")
    result = item.get("result", {})
    require(isinstance(result, dict) and result.get("isError", False) is False, "call-result-error")
    meta = result.get("_meta", {})
    require(isinstance(meta, dict), "call-browser-target")
    browser_meta, surface = meta.get("browser_use"), meta.get("codex/toolSurface")
    require(isinstance(browser_meta, dict) and isinstance(surface, dict) and browser_meta.get("url") == browser["url"]
            and surface.get("backend") == browser["backend"] and surface.get("browserId") == browser["browserId"], "call-browser-target")
    content = result.get("content")
    require(isinstance(content, list) and all(isinstance(block, dict) for block in content), "call-content")
    images, members = [], {path}
    for index, block in enumerate(content):
        if block.get("type") != "image":
            continue
        suffix = {"image/png": "png", "image/jpeg": "jpg"}.get(block.get("mimeType"))
        require(suffix is not None, "unsupported-image-mime")
        try:
            data = base64.b64decode(block["data"], validate=True)
        except (KeyError, TypeError, ValueError) as error:
            raise Rejected("invalid-image-base64") from error
        name = phase + f"/image-{index:03d}.{suffix}"
        require(0 < len(data) <= 16 * 1024 * 1024 and files.get(name) == data, "substituted-or-missing-image")
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", Image.DecompressionBombWarning)
                with Image.open(io.BytesIO(data)) as image:
                    require(image.format == {"png": "PNG", "jpg": "JPEG"}[suffix]
                            and 0 < image.width * image.height <= 64 * 1024 * 1024, "image-format-or-capacity")
                    image.verify()
                with Image.open(io.BytesIO(data)) as image:
                    image.load()
                    require(max(ImageStat.Stat(image.convert("RGB")).mean) >= 2, "black-image")
        except Rejected:
            raise
        except Exception as error:
            raise Rejected("malformed-image") from error
        images.append({"index": index, "sha256": digest(data), "bytes": len(data)})
        members.add(name)
    require(images, "call-image-missing")
    return {"phase": phase, "turnId": identity[0], "itemId": identity[1], "startedAtMs": started,
            "completedAtMs": completed, "entrySha256": digest(raw), "images": images}, members


def inventory(files, names):
    return [{"path": name, "sha256": digest(files[name]), "size": len(files[name])} for name in sorted(names)]


def signed_inventory(files, origin, names, identity, namespace, public_key):
    require(set(files) == set(names) | {"broker-origin.json", "broker-origin.json.sig"}, "unapproved-response-file")
    require(origin.get("files") == inventory(files, names), "broker-inventory-mismatch")
    raw = files["broker-origin.json"]
    require(raw == canonical(origin), "broker-inventory-not-canonical")
    verify_signature(raw, files["broker-origin.json.sig"], identity, namespace, public_key)
    return digest(raw)
