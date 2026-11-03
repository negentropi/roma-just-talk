#!/usr/bin/env python3
"""Verify source-only lip resources without downloading or loading weights."""

import ast
import hashlib
import json
import math
from pathlib import Path
import re
import struct

import onnx


TOOLS = Path(__file__).resolve().parent
RESOURCES = TOOLS.parents[1] / "Sources/VoiceInkLip/Resources"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_path(value):
    return all(
        part not in ("", ".", "..")
        and not part.startswith("-")
        and re.fullmatch(r"[A-Za-z0-9_.-]+", part)
        for part in value.split("/")
    )


manifest = json.loads((RESOURCES / "manifest.json").read_text())
graph_path = RESOURCES / "visual-ctc.onnx"
assert digest(graph_path) == manifest["graph_sha256"] == "0d98db3a949252b205cbc1fc57dee372ed61243aaf917ec684fde26c05e39f29"
assert graph_path.stat().st_size == manifest["graph_bytes"] == 910_911
assert manifest["checkpoint_sha256"] == "8dd3bbf4e8d6287e87e7c3d9bc65f6238b4d75b12040e10f5589e3c6e76bda8f"
assert manifest["checkpoint_bytes"] == 1_975_266_407
assert manifest["format_version"] == 1
assert manifest["source_revision"] == "9fd9a3743c41ba93532258b340d123c20fe25432"
assert not list(RESOURCES.rglob("*.bin"))
assert not list(RESOURCES.rglob("*.pth"))

entries, basenames, destinations = set(), set(), set()
for destination, storage in manifest["storages"].items():
    entry = storage["zip_entry"]
    assert safe_path(destination) and re.fullmatch(r"storages/[0-9]+\.bin", destination)
    assert safe_path(entry) and re.fullmatch(r"archive/data/[0-9]+", entry)
    basename = entry.rsplit("/", 1)[1].lower()
    assert destination.lower() not in destinations and entry.lower() not in entries and basename not in basenames
    destinations.add(destination.lower())
    entries.add(entry.lower())
    basenames.add(basename)
    assert 0 < storage["bytes"] <= manifest["checkpoint_bytes"]
    assert re.fullmatch(r"[0-9a-f]{64}", storage["sha256"])
assert len(entries) == 658
assert sum(storage["bytes"] for storage in manifest["storages"].values()) == 1_361_670_500

graph = onnx.load_model(str(graph_path), load_external_data=False)
initializers = {entry["name"]: entry for entry in manifest["initializers"]}
assert len(initializers) == len(graph.graph.initializer) == 658
for tensor in graph.graph.initializer:
    assert tensor.data_location == onnx.TensorProto.EXTERNAL
    for field in ("raw_data", "float_data", "int32_data", "string_data", "int64_data", "double_data", "uint64_data"):
        assert not getattr(tensor, field), (tensor.name, field)
    external = {entry.key: entry.value for entry in tensor.external_data}
    declaration = initializers[tensor.name]
    assert external["location"] == declaration["location"]
    assert safe_path(external["location"])
    storage = manifest["storages"][external["location"]]
    offset, length = int(external["offset"]), int(external["length"])
    assert offset == declaration["offset"] >= 0
    assert length == declaration["length"] == math.prod(tensor.dims) * 4 > 0
    assert offset + length <= storage["bytes"]
    assert list(tensor.dims) == declaration["shape"]
    assert tensor.data_type == onnx.TensorProto.FLOAT

tokens = json.loads((RESOURCES / "tokens.json").read_text())
units = (TOOLS / "Upstream/unigram1000_units.txt").read_text().splitlines()
assert tokens == ["<blank>"] + [unit.split()[0] for unit in units] + ["<eos>"]
assert len(tokens) == 1049
assert digest(RESOURCES / "tokens.json") == manifest["tokens_sha256"]

face = json.loads((RESOURCES / "face-alignment.json").read_text())
raw = (TOOLS / "Upstream/20words_mean_face.npy").read_bytes()
assert hashlib.sha256(raw).hexdigest() == face["source_sha256"] == "dbf68b2044171e1160716df7c53e8bbfaa0ee8c61fb41171d04cb6092bb81422"
assert raw[:8] == b"\x93NUMPY\x01\x00"
header_size = struct.unpack("<H", raw[8:10])[0]
header = ast.literal_eval(raw[10:10 + header_size].decode("latin1"))
assert header == {"descr": "<f8", "fortran_order": False, "shape": (68, 2)}
coordinates = struct.unpack("<136d", raw[10 + header_size:])
assert face["points"] == [list(coordinates[index:index + 2]) for index in range(0, 136, 2)]
assert face["stable_points"] == [28, 33, 36, 39, 42, 45, 48, 54]
assert all(math.isfinite(value) and 0 <= value < 256 for value in coordinates)

assert digest(RESOURCES / "ThirdParty/RAVEn-MIT.txt") == digest(TOOLS / "Upstream/LICENSE")
assert "1bU-bFxEiXNXNoOLKaAz6_9j7XuE7f_6r" in (TOOLS / "Upstream/README.md").read_text()
runtime_notices = json.loads((TOOLS / "Upstream/runtime-license-sources.json").read_text())
for source, bundled in (("onnxruntime-LICENSE.txt", "ONNXRuntime-MIT.txt"), ("onnxruntime-ThirdPartyNotices.txt", "ONNXRuntime-ThirdPartyNotices.txt")):
    assert digest(RESOURCES / "ThirdParty" / bundled) == runtime_notices[source]["sha256"]

print(json.dumps({
    "graph_sha256": digest(graph_path),
    "graph_bytes": graph_path.stat().st_size,
    "external_initializers": len(initializers),
    "inline_learned_bytes": 0,
    "installed_storage_bytes": sum(storage["bytes"] for storage in manifest["storages"].values()),
    "manifest_paths_safe": True,
    "face_coordinates_match_publisher": True,
    "tokens_match_publisher": True,
    "notices_match_sources": True,
}, indent=2))
