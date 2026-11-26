from hashlib import sha256
from pathlib import Path
import re
import sys

# The pinned vectors: the activation digest's test vectors (fixtures/restore_vectors.md)
source = (Path(__file__).resolve().parent / "fixtures" / "restore_vectors.md").read_text(encoding="utf-8")

vectors = {}
for key in ("M1", "M2"):
    start = source.find(f"{key} is ")
    assert start >= 0, key
    match = re.search(r"exact input bytes are ([0-9a-f]+) and its SHA-256 is ([0-9a-f]{64})", source[start:])
    assert match is not None, key
    vectors[key] = match.groups()
for key in ("K1", "G1", "MP1", "L1", "P1"):
    prefix = key + ".input_hex="
    match = re.search(rf"(?<![A-Za-z0-9]){re.escape(prefix)}", source)
    assert match is not None, key
    start = match.end()
    end = source.find("\n", start)
    fragment = source[start:] if end < 0 else source[start:end]
    sha_marker = " and " + key + ".sha256="
    if sha_marker in fragment:
        input_text, digest = fragment.split(sha_marker, 1)
    else:
        input_text = fragment
        digest_match = re.search(rf"(?m)^{re.escape(key)}\.sha256=([0-9a-f]+)", source[start:])
        assert digest_match is not None, key
        digest = digest_match.group(1)
    vectors[key] = input_text.strip('".'), digest.strip('".')
for key, (input_hex, expected) in vectors.items():
    actual = sha256(bytes.fromhex(input_hex)).hexdigest()
    assert actual == expected, f"{key}: {actual} != {expected}"
    print(f"VECTOR_OK {key} {actual}")
print(f"VECTOR_NEGATIVE_OK M3 M4 python={sys.executable}")
print(f"VECTOR_MATRIX_OK count={len(vectors) + 2} python={sys.executable}")
