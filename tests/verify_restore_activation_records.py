from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


def canonical(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def domain_digest(prefix: str, version: str, value: object) -> str:
    payload = prefix.encode("utf-8") + b"\x00" + version.encode("utf-8") + b"\x00" + canonical(value)
    return hashlib.sha256(payload).hexdigest()


def marker_value(source: str, marker: str) -> str:
    match = re.search(rf"(?<![A-Za-z0-9]){re.escape(marker)}([^\r\n]*)", source)
    if match is None:
        raise AssertionError(f"missing {marker}")
    return match.group(1).strip().strip('".')


def vector_digest(source: str, key: str) -> str:
    if key in {"M1", "M2"}:
        start = source.find(f"{key} is ")
        if start < 0:
            raise AssertionError(key)
        match = re.search(r"exact input bytes are [0-9a-f]+ and its SHA-256 is ([0-9a-f]{64})", source[start:])
        if match is None:
            raise AssertionError(key)
        return match.group(1)
    return marker_value(source, f"{key}.sha256=")


def main() -> int:
    parser = argparse.ArgumentParser(description="Independently verify MATLAB-generated E3 records")
    parser.add_argument("records", type=Path)
    args = parser.parse_args()
    records_path = args.records
    payload = json.loads(records_path.read_text(encoding="utf-8"))
    if set(payload) != {"geometry", "geometry_digest", "projection", "projection_digest", "identity", "identity_digest", "map_m1_digest", "map_m2_digest", "kernel_digest"}:
        raise AssertionError("generated record payload has an unexpected closed-schema shape")
    # The pinned vectors: the activation digest's test vectors (fixtures/restore_vectors.md)
    vectors_file = Path(__file__).resolve().parent / "fixtures" / "restore_vectors.md"
    if not vectors_file.is_file():
        raise AssertionError("could not locate fixtures/restore_vectors.md from verifier")
    source = vectors_file.read_text(encoding="utf-8")
    expected = {key: vector_digest(source, key) for key in ("M1", "M2", "K1", "G1", "P1")}
    checks = {
        "geometry": (domain_digest("OM-ACTIVATION-GEOMETRY", "geometry-v1", payload["geometry"]), payload["geometry_digest"], expected["G1"]),
        "projection": (domain_digest("OM-PROJECTION-CONTRACT", "projection-v1", payload["projection"]), payload["projection_digest"], expected["P1"]),
        "identity": (domain_digest("OM-RECORDING-IDENTITY", "recording-identity-v1", payload["identity"]), payload["identity_digest"], None),
        "map_m1": (payload["map_m1_digest"], expected["M1"], expected["M1"]),
        "map_m2": (payload["map_m2_digest"], expected["M2"], expected["M2"]),
        "kernel": (payload["kernel_digest"], expected["K1"], expected["K1"]),
    }
    for name, (actual, recorded, vector) in checks.items():
        if actual != recorded:
            raise AssertionError(f"{name}: generated={actual} recorded={recorded} independent={vector}")
        if vector is not None and actual != vector:
            raise AssertionError(f"{name}: {actual} != independent expected {vector}")
        print(f"E3_RECORD_OK {name} {actual}")
    print(f"E3_RECORDS_OK count={len(checks)} python={sys.executable}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
