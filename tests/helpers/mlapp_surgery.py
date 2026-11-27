#!/usr/bin/env python3
"""mlapp_surgery.py — .mlapp ZIP surgery helper.

Cross-platform, reproducible replacement of the matlab/document.xml member
inside an App Designer .mlapp archive (which is a ZIP file).

What it does:
  - reads/writes project-owned text explicitly as UTF-8;
  - uses pathlib, repository-relative discovery and tempfile;
  - rejects duplicate member names;
  - preserves member order, names, compression type, timestamps, external
    attributes, flags and all non-target member bytes;
  - requires [Content_Types].xml first;
  - replaces exactly one matlab/document.xml member;
  - parses XML before repack;
  - writes to a new archive, verifies it, then allows atomic replacement;
  - emits JSON containing before/after archive SHA-256, XML SHA-256/size,
    ordered member metadata, duplicate count, testzip result, changed-member
    list, and non-target byte equality;
  - fails closed on zero-match or multiple-match replacement;
  - never edits appdesigner/appModel.mat by hand.

CLI usage:
  # Replace XML and write candidate archive:
  python tests/helpers/mlapp_surgery.py \
      --source  analyse_optical_mapping.mlapp \
      --edited-xml /tmp/document_edited.xml \
      --output  /tmp/candidate.mlapp

  # Verify a candidate against source (no source XML needed):
  python tests/helpers/mlapp_surgery.py \
      --source  analyse_optical_mapping.mlapp \
      --output  /tmp/candidate.mlapp \
      --verify-only

Exit codes: 0 = success / 1 = failure.
The JSON evidence report is written to stdout.

No hard-coded drive letters; uses only
repository-relative or explicitly supplied paths.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
import xml.etree.ElementTree as ET
import struct
import zipfile
from pathlib import Path

TARGET_MEMBER = "matlab/document.xml"
FIRST_MEMBER  = "[Content_Types].xml"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def member_meta(zi: zipfile.ZipInfo) -> dict:
    """Extract all preserved metadata fields for one ZipInfo entry."""
    return {
        "filename":        zi.filename,
        "file_size":       zi.file_size,
        "compress_size":   zi.compress_size,
        "compress_type":   zi.compress_type,
        "date_time":       list(zi.date_time),
        "CRC":             zi.CRC,
        "comment":         zi.comment.decode("latin-1") if zi.comment else "",
        "extra":           zi.extra.hex() if zi.extra else "",
        "create_system":   zi.create_system,
        "create_version":  zi.create_version,
        "extract_version": zi.extract_version,
        "flag_bits":       zi.flag_bits,
        "volume":          zi.volume,
        "internal_attr":   zi.internal_attr,
        "external_attr":   zi.external_attr,
    }


def inspect_archive(path: Path) -> tuple[dict, dict]:
    """Return (report_dict, {member_name: bytes}) for all archive members."""
    report: dict = {
        "path":      str(path),
        "sha256":    sha256_of(path.read_bytes()),
        "members":   [],
        "testzip":   None,
        "duplicates": 0,
        "first_member": None,
        "xml_sha256": None,
        "xml_size":   None,
    }
    payloads: dict[str, bytes] = {}

    with zipfile.ZipFile(path, "r") as zf:
        report["testzip"] = zf.testzip()  # None means OK
        infos = zf.infolist()
        names = [zi.filename for zi in infos]
        dups  = [n for n in names if names.count(n) > 1]
        report["duplicates"] = len(set(dups))
        if infos:
            report["first_member"] = infos[0].filename

        for zi in infos:
            raw = zf.read(zi.filename)
            payloads[zi.filename] = raw
            entry = member_meta(zi)
            entry["payload_sha256"] = sha256_of(raw)
            report["members"].append(entry)

    if TARGET_MEMBER in payloads:
        report["xml_sha256"] = sha256_of(payloads[TARGET_MEMBER])
        report["xml_size"]   = len(payloads[TARGET_MEMBER])

    return report, payloads


def validate_source(src_report: dict) -> list[str]:
    """Return list of blocking errors for the source archive."""
    errors: list[str] = []

    if src_report["testzip"] is not None:
        errors.append(f"testzip reported bad member: {src_report['testzip']}")

    if src_report["duplicates"] > 0:
        errors.append(f"Source archive has {src_report['duplicates']} duplicate member name(s).")

    if src_report["first_member"] != FIRST_MEMBER:
        errors.append(
            f"First member is '{src_report['first_member']}'; expected '{FIRST_MEMBER}'."
        )

    # Python's high-level zipfile writer normalises general-purpose flags
    # when writing. Fail closed instead of claiming exact preservation for
    # an archive whose flags cannot be reproduced safely.
    flagged = [m["filename"] for m in src_report["members"] if m["flag_bits"] != 0]
    if flagged:
        errors.append(
            "Source archive uses unsupported non-zero ZIP flag_bits for: "
            + ", ".join(flagged)
        )

    xml_count = sum(1 for m in src_report["members"] if m["filename"] == TARGET_MEMBER)
    if xml_count == 0:
        errors.append(f"Source archive has no '{TARGET_MEMBER}' member.")
    elif xml_count > 1:
        errors.append(f"Source archive has {xml_count} '{TARGET_MEMBER}' members (duplicate).")

    return errors


def parse_xml(data: bytes, label: str) -> None:
    """Parse XML bytes; raise ValueError with label if malformed."""
    try:
        ET.fromstring(data)
    except ET.ParseError as exc:
        raise ValueError(f"XML parse error in {label}: {exc}") from exc


# ---------------------------------------------------------------------------
# Surgery
# ---------------------------------------------------------------------------

def build_candidate(
    src_path: Path,
    src_payloads: dict[str, bytes],
    src_report: dict,
    new_xml_bytes: bytes,
    out_path: Path,
) -> dict:
    """
    Write a new archive to out_path that is identical to src_path except
    matlab/document.xml is replaced with new_xml_bytes.
    Returns a dict of changed-member information.
    """
    changed: list[str] = []

    # Build ordered ZipInfo list from source
    with zipfile.ZipFile(src_path, "r") as src_zf:
        src_infos = src_zf.infolist()
        archive_comment = src_zf.comment

    # Write candidate to a temp file first, then move to out_path
    tmp_fd, tmp_path_str = tempfile.mkstemp(suffix=".mlapp.tmp",
                                             dir=out_path.parent)
    tmp_path = Path(tmp_path_str)
    try:
        with open(tmp_fd, "wb") as _:
            pass  # close the fd; we'll open via zipfile

        with zipfile.ZipFile(tmp_path, "w") as out_zf:
            out_zf.comment = archive_comment
            for zi in src_infos:
                # Preserve all metadata by cloning the ZipInfo
                new_zi = zipfile.ZipInfo(zi.filename)
                new_zi.date_time       = zi.date_time
                new_zi.compress_type   = zi.compress_type
                new_zi.comment         = zi.comment
                new_zi.extra           = zi.extra
                new_zi.create_system   = zi.create_system
                new_zi.create_version  = zi.create_version
                new_zi.extract_version = zi.extract_version
                new_zi.flag_bits       = zi.flag_bits
                new_zi.volume          = zi.volume
                new_zi.internal_attr   = zi.internal_attr
                new_zi.external_attr   = zi.external_attr

                if zi.filename == TARGET_MEMBER:
                    payload = new_xml_bytes
                    changed.append(zi.filename)
                else:
                    payload = src_payloads[zi.filename]

                out_zf.writestr(new_zi, payload)

        # zipfile.writestr replaces an external_attr of 0 with 0o600 << 16
        # (Python 3.13+), and apps last saved by MATLAB have 0 there: put
        # the source values back in the central directory
        restore_external_attr(tmp_path, src_infos)

        # Atomic move
        tmp_path.replace(out_path)

    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise

    return {"changed_members": changed}


def restore_external_attr(path: Path, src_infos: list) -> None:
    """Write each member's source external_attr into the central directory."""
    data = bytearray(path.read_bytes())
    eocd = data.rfind(b"PK")
    if eocd < 0:
        raise ValueError("no end of central directory record")
    _, cd_offset = struct.unpack_from("<II", data, eocd + 12)
    pos = cd_offset
    for zi in src_infos:
        if data[pos:pos + 4] != b"PK":
            raise ValueError(f"central directory entry for {zi.filename!r} not where expected")
        name_len, extra_len, comment_len = struct.unpack_from("<HHH", data, pos + 28)
        name = bytes(data[pos + 46:pos + 46 + name_len]).decode("utf-8", "replace")
        if name != zi.filename:
            raise ValueError(f"central directory order differs: {name!r} vs {zi.filename!r}")
        struct.pack_into("<I", data, pos + 38, zi.external_attr)
        pos += 46 + name_len + extra_len + comment_len
    path.write_bytes(bytes(data))


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

def verify_candidate(
    src_path: Path,
    src_report: dict,
    src_payloads: dict[str, bytes],
    cand_path: Path,
) -> tuple[bool, list[str], dict]:
    """
    Verify that cand_path satisfies the §11.2 contract relative to src_path.
    Returns (ok, list_of_failures, evidence_dict).
    """
    failures: list[str] = []
    cand_report, cand_payloads = inspect_archive(cand_path)
    evidence: dict = {
        "source_sha256":     src_report["sha256"],
        "candidate_sha256":  cand_report["sha256"],
        "source_xml_sha256": src_report["xml_sha256"],
        "candidate_xml_sha256": cand_report["xml_sha256"],
        "source_xml_size":   src_report["xml_size"],
        "candidate_xml_size": cand_report["xml_size"],
    }

    # 1. testzip
    if cand_report["testzip"] is not None:
        failures.append(f"Candidate testzip: bad member '{cand_report['testzip']}'")

    # 2. No duplicates
    if cand_report["duplicates"] > 0:
        failures.append(f"Candidate has {cand_report['duplicates']} duplicate member name(s).")

    # 3. Archive comment preserved
    with zipfile.ZipFile(src_path,  "r") as z1: src_comment  = z1.comment
    with zipfile.ZipFile(cand_path, "r") as z2: cand_comment = z2.comment
    if src_comment != cand_comment:
        failures.append("Archive comment differs.")

    # 4. Member count
    if len(src_report["members"]) != len(cand_report["members"]):
        failures.append(
            f"Member count differs: source={len(src_report['members'])} "
            f"candidate={len(cand_report['members'])}"
        )
    else:
        # 5. Member-by-member comparison
        for sm, cm in zip(src_report["members"], cand_report["members"]):
            fn = sm["filename"]
            if fn != cm["filename"]:
                failures.append(f"Member order/name mismatch: '{fn}' vs '{cm['filename']}'")
                continue

            # Metadata fields that must be preserved exactly
            for field in ("date_time", "compress_type", "create_system",
                          "create_version", "extract_version", "flag_bits",
                          "volume", "comment", "extra", "internal_attr",
                          "external_attr"):
                if sm.get(field) != cm.get(field):
                    failures.append(
                        f"Member '{fn}': {field} differs "
                        f"(src={sm.get(field)!r} cand={cm.get(field)!r})"
                    )

            if fn == TARGET_MEMBER:
                # XML payload MUST differ from source
                if sm["payload_sha256"] == cm["payload_sha256"]:
                    failures.append(
                        f"'{TARGET_MEMBER}' payload is unchanged (expected a replacement)."
                    )
                # XML must parse
                try:
                    parse_xml(cand_payloads[fn], f"candidate {fn}")
                except ValueError as exc:
                    failures.append(str(exc))
            else:
                # All other payloads must be byte-identical
                if sm["payload_sha256"] != cm["payload_sha256"]:
                    failures.append(
                        f"Non-target member '{fn}' payload differs: "
                        f"src={sm['payload_sha256'][:16]}... "
                        f"cand={cm['payload_sha256'][:16]}..."
                    )

    # 6. First member
    if cand_report["first_member"] != FIRST_MEMBER:
        failures.append(
            f"First member is '{cand_report['first_member']}'; expected '{FIRST_MEMBER}'."
        )

    # 7. XML parses
    if TARGET_MEMBER in cand_payloads:
        try:
            parse_xml(cand_payloads[TARGET_MEMBER], f"candidate {TARGET_MEMBER}")
        except ValueError as exc:
            failures.append(str(exc))

    evidence["failures"] = failures
    evidence["candidate_members"] = cand_report["members"]
    return len(failures) == 0, failures, evidence


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=".mlapp ZIP surgery helper."
    )
    parser.add_argument("--source",      required=True, help="Source .mlapp path.")
    parser.add_argument("--edited-xml",  default=None,  help="Edited document.xml path.")
    parser.add_argument("--output",      required=True, help="Output .mlapp path.")
    parser.add_argument("--verify-only", action="store_true",
                        help="Only verify --output against --source; do not write.")
    args = parser.parse_args(argv)

    src_path  = Path(args.source).resolve()
    out_path  = Path(args.output).resolve()
    edit_path = Path(args.edited_xml).resolve() if args.edited_xml else None

    result: dict = {"success": False, "errors": [], "evidence": {}}

    # ---- Inspect source --------------------------------------------------
    try:
        src_report, src_payloads = inspect_archive(src_path)
    except Exception as exc:
        result["errors"].append(f"Cannot open source archive: {exc}")
        print(json.dumps(result, indent=2))
        return 1

    src_errors = validate_source(src_report)
    if src_errors:
        result["errors"].extend(src_errors)
        result["evidence"]["source"] = src_report
        print(json.dumps(result, indent=2))
        return 1

    result["evidence"]["source_sha256"] = src_report["sha256"]
    result["evidence"]["source_xml_sha256"] = src_report["xml_sha256"]
    result["evidence"]["source_members"] = src_report["members"]

    # ---- Verify-only mode ------------------------------------------------
    if args.verify_only:
        if not out_path.exists():
            result["errors"].append(f"--output does not exist: {out_path}")
            print(json.dumps(result, indent=2))
            return 1
        ok, failures, evidence = verify_candidate(
            src_path, src_report, src_payloads, out_path
        )
        result["success"] = ok
        result["evidence"].update(evidence)
        if not ok:
            result["errors"].extend(failures)
        print(json.dumps(result, indent=2))
        return 0 if ok else 1

    # ---- Surgery mode ----------------------------------------------------
    if edit_path is None:
        result["errors"].append("--edited-xml is required when not using --verify-only.")
        print(json.dumps(result, indent=2))
        return 1

    if not edit_path.exists():
        result["errors"].append(f"Edited XML not found: {edit_path}")
        print(json.dumps(result, indent=2))
        return 1

    # Read and parse new XML
    try:
        new_xml_bytes = edit_path.read_bytes()
        parse_xml(new_xml_bytes, str(edit_path))
    except Exception as exc:
        result["errors"].append(f"Edited XML error: {exc}")
        print(json.dumps(result, indent=2))
        return 1

    result["evidence"]["new_xml_sha256"] = sha256_of(new_xml_bytes)
    result["evidence"]["new_xml_size"]   = len(new_xml_bytes)

    # Write candidate
    try:
        changed_info = build_candidate(
            src_path, src_payloads, src_report, new_xml_bytes, out_path
        )
        result["evidence"]["changed_members"] = changed_info["changed_members"]
    except Exception as exc:
        result["errors"].append(f"Archive build failed: {exc}")
        print(json.dumps(result, indent=2))
        return 1

    # Verify the written candidate
    ok, failures, evidence = verify_candidate(
        src_path, src_report, src_payloads, out_path
    )
    result["success"] = ok
    result["evidence"].update(evidence)
    if not ok:
        result["errors"].extend(failures)

    print(json.dumps(result, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
