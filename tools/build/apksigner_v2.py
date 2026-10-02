#!/usr/bin/env python3
"""
apksigner_v2.py — a minimal, apksigner-CLI-compatible APK Signature Scheme v2 signer.

WHY THIS EXISTS
  The Mildew cloud build container cannot reach dl.google.com / maven.google.com, so the
  real Android SDK build-tools (apksigner, zipalign) are unavailable. Godot 4.7's
  non-Gradle Android export only needs `apksigner` to sign the APK it assembles from the
  official prebuilt template, so this script implements the subset of the apksigner CLI
  that Godot calls:

      apksigner --version
      apksigner sign --verbose --ks <keystore> --ks-pass pass:<pw> --ks-key-alias <alias> <apk>
      apksigner verify --verbose <apk>

  On a developer machine with the real Android SDK installed, use the real apksigner;
  this file is a container fallback only. See DECISIONS.md (2026-10-02, APK signing).

SCOPE
  * Signs with APK Signature Scheme v2 only (valid for minSdkVersion >= 24; Godot 4.7
    templates declare minSdk 24, and the official apksigner also omits v1 at that level).
  * RSA (PKCS#1 v1.5 + SHA-256, algorithm 0x0103) and EC P-256 (ECDSA + SHA-256, 0x0201).
  * Keystore: PKCS#12 (JDK default). JKS keystores are converted with `keytool` first.
  * Requires the APK to be zip-aligned already (Godot aligns its own output). `verify`
    checks alignment of stored entries (4 bytes; 4096 for .so) and the v2 signature.

Spec: https://source.android.com/docs/security/features/apksigning/v2
"""
import hashlib
import os
import struct
import subprocess
import sys
import tempfile

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography import x509

VERSION = "0.1.0-mildew (v2-only container signer)"
APK_SIG_BLOCK_MAGIC = b"APK Sig Block 42"
V2_BLOCK_ID = 0x7109871A
ALGO_RSA_PKCS1_SHA256 = 0x0103
ALGO_ECDSA_SHA256 = 0x0201
CHUNK = 1024 * 1024


def lp(b: bytes) -> bytes:
    """uint32 little-endian length prefix."""
    return struct.pack("<I", len(b)) + b


def find_eocd(data: bytes) -> int:
    # EOCD is at least 22 bytes; comment up to 65535 bytes.
    start = max(0, len(data) - 22 - 65535)
    idx = data.rfind(b"PK\x05\x06", start)
    while idx != -1:
        comment_len = struct.unpack_from("<H", data, idx + 20)[0]
        if idx + 22 + comment_len == len(data):
            return idx
        idx = data.rfind(b"PK\x05\x06", start, idx)
    raise ValueError("ZIP End of Central Directory not found")


def zip_sections(data: bytes):
    eocd = find_eocd(data)
    cd_size, cd_offset = struct.unpack_from("<II", data, eocd + 12)
    if cd_offset + cd_size != eocd:
        raise ValueError("Central directory does not immediately precede EOCD (zip64/unsupported)")
    # Detect an existing signing block immediately before the central directory.
    sig_block_start = cd_offset
    existing = None
    if cd_offset >= 32 and data[cd_offset - 16:cd_offset] == APK_SIG_BLOCK_MAGIC:
        size_footer = struct.unpack_from("<Q", data, cd_offset - 24)[0]
        sig_block_start = cd_offset - size_footer - 8
        size_header = struct.unpack_from("<Q", data, sig_block_start)[0]
        if size_header != size_footer:
            raise ValueError("Corrupt APK Signing Block (size mismatch)")
        existing = data[sig_block_start:cd_offset]
    return sig_block_start, cd_offset, eocd, existing


def chunk_digest_sha256(sections) -> bytes:
    chunk_digests = []
    for sec in sections:
        for i in range(0, len(sec), CHUNK):
            c = sec[i:i + CHUNK]
            chunk_digests.append(hashlib.sha256(b"\xa5" + struct.pack("<I", len(c)) + c).digest())
    return hashlib.sha256(b"\x5a" + struct.pack("<I", len(chunk_digests)) + b"".join(chunk_digests)).digest()


def content_digest(data: bytes, entries_end: int, cd_offset: int, eocd: int) -> bytes:
    entries = data[:entries_end]
    cd = data[cd_offset:eocd]
    eocd_bytes = bytearray(data[eocd:])
    # For digesting, the EOCD's CD-offset field is replaced by the signing block offset.
    struct.pack_into("<I", eocd_bytes, 16, entries_end)
    return chunk_digest_sha256([entries, cd, bytes(eocd_bytes)])


def load_keystore(path: str, password: str, alias: str):
    with open(path, "rb") as f:
        raw = f.read()
    try:
        key, cert, _ = pkcs12.load_key_and_certificates(raw, password.encode())
        if key is not None and cert is not None:
            return key, cert
    except Exception:
        pass
    # Fallback: convert (e.g. JKS) to PKCS#12 with keytool.
    with tempfile.TemporaryDirectory() as td:
        out = os.path.join(td, "ks.p12")
        subprocess.run([
            "keytool", "-importkeystore", "-noprompt", "-srckeystore", path, "-srcstorepass", password,
            "-srcalias", alias, "-destkeystore", out, "-deststoretype", "PKCS12",
            "-deststorepass", password, "-destkeypass", password,
        ], check=True, capture_output=True)
        with open(out, "rb") as f:
            key, cert, _ = pkcs12.load_key_and_certificates(f.read(), password.encode())
    if key is None or cert is None:
        raise ValueError("Keystore did not contain a private key + certificate for alias %s" % alias)
    return key, cert


def check_alignment(data: bytes, cd_offset: int, eocd: int):
    problems = []
    entries = struct.unpack_from("<H", data, eocd + 10)[0]
    p = cd_offset
    for _ in range(entries):
        if data[p:p + 4] != b"PK\x01\x02":
            raise ValueError("Bad central directory record")
        method = struct.unpack_from("<H", data, p + 10)[0]
        n, e, c = struct.unpack_from("<HHH", data, p + 28)
        lho = struct.unpack_from("<I", data, p + 42)[0]
        name = data[p + 46:p + 46 + n].decode("utf-8", "replace")
        p += 46 + n + e + c
        if method == 0:
            ln, le = struct.unpack_from("<HH", data, lho + 26)
            start = lho + 30 + ln + le
            align = 4096 if name.endswith(".so") else 4
            if start % align:
                problems.append("%s data offset %d not %d-aligned" % (name, start, align))
    return problems


def sign(apk: str, ks: str, ks_pass: str, alias: str, verbose: bool):
    with open(apk, "rb") as f:
        data = f.read()
    entries_end, cd_offset, eocd, _existing = zip_sections(data)
    # Drop any existing signing block; we re-sign from the bare zip.
    bare = data[:entries_end] + data[cd_offset:]
    cd_offset = entries_end
    eocd = find_eocd(bare)
    bare = bytearray(bare)
    struct.pack_into("<I", bare, eocd + 16, cd_offset)
    bare = bytes(bare)
    problems = check_alignment(bare, cd_offset, eocd)
    if problems:
        raise ValueError("APK is not zip-aligned:\n  " + "\n  ".join(problems[:10]))

    key, cert = load_keystore(ks, ks_pass, alias)
    if isinstance(key, rsa.RSAPrivateKey):
        algo = ALGO_RSA_PKCS1_SHA256
    elif isinstance(key, ec.EllipticCurvePrivateKey):
        algo = ALGO_ECDSA_SHA256
    else:
        raise ValueError("Unsupported key type")

    digest = content_digest(bare, cd_offset, cd_offset, eocd)
    cert_der = cert.public_bytes(serialization.Encoding.DER)
    spki = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)

    digests_seq = lp(struct.pack("<I", algo) + lp(digest))
    signed_data = lp(digests_seq) + lp(lp(cert_der)) + lp(b"")
    if algo == ALGO_RSA_PKCS1_SHA256:
        sig = key.sign(signed_data, padding.PKCS1v15(), hashes.SHA256())
    else:
        sig = key.sign(signed_data, ec.ECDSA(hashes.SHA256()))
    signatures_seq = lp(struct.pack("<I", algo) + lp(sig))
    signer = lp(signed_data) + lp(signatures_seq) + lp(spki)
    v2_value = lp(lp(signer))

    pair = struct.pack("<I", V2_BLOCK_ID) + v2_value
    pairs = struct.pack("<Q", len(pair)) + pair
    block_size = len(pairs) + 8 + 16
    block = struct.pack("<Q", block_size) + pairs + struct.pack("<Q", block_size) + APK_SIG_BLOCK_MAGIC

    out = bytearray(bare[:cd_offset] + block + bare[cd_offset:])
    new_eocd = eocd + len(block)
    struct.pack_into("<I", out, new_eocd + 16, cd_offset + len(block))
    tmp = apk + ".signing"
    with open(tmp, "wb") as f:
        f.write(out)
    os.replace(tmp, apk)
    if verbose:
        print("Signed (APK Signature Scheme v2): %s" % apk)
        print("Signer certificate subject: %s" % cert.subject.rfc4514_string())
        print("Signer certificate SHA-256 digest: %s" % hashlib.sha256(cert_der).hexdigest())


def _read_lp(buf, off):
    n = struct.unpack_from("<I", buf, off)[0]
    return buf[off + 4:off + 4 + n], off + 4 + n


def verify(apk: str, verbose: bool) -> bool:
    with open(apk, "rb") as f:
        data = f.read()
    block_start, cd_offset, eocd, block = zip_sections(data)
    if block is None:
        print("DOES NOT VERIFY: no APK Signing Block")
        return False
    problems = check_alignment(data, cd_offset, eocd)
    if problems:
        print("DOES NOT VERIFY: alignment\n  " + "\n  ".join(problems[:10]))
        return False
    # Parse ID-value pairs.
    p = 8
    end = len(block) - 24
    v2 = None
    while p < end:
        plen = struct.unpack_from("<Q", block, p)[0]
        pid = struct.unpack_from("<I", block, p + 8)[0]
        if pid == V2_BLOCK_ID:
            v2 = block[p + 12:p + 8 + plen]
        p += 8 + plen
    if v2 is None:
        print("DOES NOT VERIFY: no v2 signature")
        return False
    signers, _ = _read_lp(v2, 0)
    signer, _ = _read_lp(signers, 0)
    signed_data, o = _read_lp(signer, 0)
    sigs, o = _read_lp(signer, o)
    spki, o = _read_lp(signer, o)
    pub = serialization.load_der_public_key(spki)
    sig_entry, _ = _read_lp(sigs, 0)
    algo = struct.unpack_from("<I", sig_entry, 0)[0]
    sig, _ = _read_lp(sig_entry, 4)
    if algo == ALGO_RSA_PKCS1_SHA256:
        pub.verify(sig, signed_data, padding.PKCS1v15(), hashes.SHA256())
    elif algo == ALGO_ECDSA_SHA256:
        pub.verify(sig, signed_data, ec.ECDSA(hashes.SHA256()))
    else:
        print("DOES NOT VERIFY: unsupported algorithm 0x%x" % algo)
        return False
    digests_seq, o2 = _read_lp(signed_data, 0)
    certs_seq, _ = _read_lp(signed_data, o2)
    d_entry, _ = _read_lp(digests_seq, 0)
    d_algo = struct.unpack_from("<I", d_entry, 0)[0]
    d_val, _ = _read_lp(d_entry, 4)
    expected = content_digest(data, block_start, cd_offset, eocd)
    if d_algo != algo or d_val != expected:
        print("DOES NOT VERIFY: content digest mismatch")
        return False
    cert_der, _ = _read_lp(certs_seq, 0)
    cert = x509.load_der_x509_certificate(cert_der)
    if cert.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo) != spki:
        print("DOES NOT VERIFY: certificate public key does not match signer key")
        return False
    if verbose:
        print("Verifies")
        print("Verified using v1 scheme (JAR signing): false")
        print("Verified using v2 scheme (APK Signature Scheme v2): true")
        print("Number of signers: 1")
        print("Signer #1 certificate DN: %s" % cert.subject.rfc4514_string())
    else:
        print("Verifies")
    return True


def main(argv):
    if not argv or argv[0] in ("--version", "version"):
        print(VERSION)
        return 0
    cmd, args = argv[0], argv[1:]
    verbose = "--verbose" in args or "-v" in args
    opts = {}
    positional = []
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--ks", "--ks-pass", "--ks-key-alias", "--key-pass", "--out"):
            opts[a] = args[i + 1]
            i += 2
            continue
        if not a.startswith("-"):
            positional.append(a)
        i += 1
    if not positional:
        print("usage: apksigner sign|verify ... <apk>", file=sys.stderr)
        return 2
    apk = positional[-1]
    try:
        if cmd == "sign":
            pw = opts.get("--ks-pass", "pass:android")
            if pw.startswith("pass:"):
                pw = pw[5:]
            elif pw.startswith("env:"):
                pw = os.environ.get(pw[4:], "")
            if "--out" in opts:
                import shutil
                shutil.copyfile(apk, opts["--out"])
                apk = opts["--out"]
            sign(apk, opts["--ks"], pw, opts.get("--ks-key-alias", "androiddebugkey"), verbose)
            return 0
        if cmd == "verify":
            return 0 if verify(apk, verbose) else 1
    except Exception as exc:  # noqa: BLE001 — CLI surface
        print("ERROR: %s" % exc, file=sys.stderr)
        return 1
    print("unknown command %s" % cmd, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
