"""Pinned native Qwen runner and resumable, verified model downloads. Standard library only."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import time

REPO = Path(__file__).resolve().parents[2]
NATIVE_REPO = "https://github.com/gabriele-mastrapasqua/qwen3-tts.git"
NATIVE_REV = "ef339be58a778b062e1c14382347964552eae007"


def home() -> Path:
    return Path(os.environ.get("MILDEW_VOICE_HOME", str(REPO / "voice" / ".local"))).expanduser().resolve()


def atomic_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temp.replace(path)


def digest(path: Path, algorithm="sha256") -> str:
    h = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def run(args: list[str], log: Path | None = None, timeout=None) -> None:
    # argv only: dialogue, instructions and paths are never executed as shell code.
    if log:
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("w") as stream:
            p = subprocess.Popen(args, stdout=stream, stderr=subprocess.STDOUT,
                                 env={**os.environ, "OPENBLAS_NUM_THREADS": "1"})
            started = time.monotonic()
            try:
                while p.poll() is None:
                    if timeout and time.monotonic() - started > timeout:
                        raise TimeoutError("generation exceeded the configured time limit")
                    try:
                        p.wait(timeout=30 if timeout is None else min(30, timeout))
                    except subprocess.TimeoutExpired:
                        print(f"  still working; log: {log}", flush=True)
            except BaseException:
                p.terminate()
                try:
                    p.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    p.kill()
                    p.wait()
                raise
            if p.returncode:
                raise RuntimeError(f"command failed ({p.returncode}); see {log}")
    else:
        subprocess.run(args, check=True, timeout=timeout)


def models() -> dict:
    return json.loads((REPO / "voice/models.lock.json").read_text())


def verified(path: Path, meta: dict) -> bool:
    if not path.is_file() or path.stat().st_size != meta["size"]:
        return False
    if "sha256" in meta:
        return digest(path) == meta["sha256"]
    blob = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(blob)).encode() + b"\0" + blob).hexdigest() == meta["git_sha1"]


def download(kind: str) -> Path:
    spec = models()[kind]
    dest = home() / "models" / kind
    dest.mkdir(parents=True, exist_ok=True)
    valid = {f["path"]: verified(dest / f["path"], f) for f in spec["files"]}
    remaining = sum(max(0, f["size"] - ((dest / (f["path"] + ".part")).stat().st_size
                    if (dest / (f["path"] + ".part")).exists() else 0))
                    for f in spec["files"] if not valid[f["path"]])
    if shutil.disk_usage(dest).free < remaining + 512 * 1024**2:
        raise RuntimeError(f"need {remaining / 1024**3:.1f} GiB plus 0.5 GiB free for {kind}")
    print(f"{kind}: pinned {spec['repo']}@{spec['revision']}; checking/download on this device", flush=True)
    for meta in spec["files"]:
        path = dest / meta["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        if valid[meta["path"]]:
            stale_part = path.with_name(path.name + ".part")
            if stale_part.exists():
                stale_part.unlink()
            print(f"  verified {meta['path']}", flush=True)
            continue
        part = path.with_name(path.name + ".part")
        if part.exists() and part.stat().st_size > meta["size"]:
            part.unlink()
        url = f"https://huggingface.co/{spec['repo']}/resolve/{spec['revision']}/{meta['path']}"
        print(f"  fetching {meta['path']} ({meta['size'] / 1024**2:.1f} MiB)", flush=True)
        if not verified(part, meta):
            run(["curl", "--fail", "--location", "--retry", "5", "--retry-delay", "3",
                 "--connect-timeout", "30", "--speed-limit", "1024", "--speed-time", "120",
                 "--continue-at", "-", "--output", str(part), url])
        if not verified(part, meta):
            # A complete but corrupt file cannot be resumed. Preserve it for inspection.
            if part.exists() and part.stat().st_size >= meta["size"]:
                part.replace(part.with_suffix(".bad"))
            raise RuntimeError(f"integrity check failed: {meta['path']}; rerun download {kind}")
        part.replace(path)
        if part.exists():
            part.unlink()
    atomic_json(dest / ".verified.json", {"revision": spec["revision"], "files": spec["files"]})
    return dest


def model_path(kind: str) -> Path:
    dest = home() / "models" / kind
    spec = models()[kind]
    marker = dest / ".verified.json"
    if not marker.exists() or json.loads(marker.read_text()).get("revision") != spec["revision"]:
        raise RuntimeError(f"model not installed/verified: run ./mildew voice download {kind}")
    for f in spec["files"]:
        path = dest / f["path"]
        if not path.exists() or path.stat().st_size != f["size"]:
            raise RuntimeError(f"model incomplete: run ./mildew voice download {kind}")
    return dest


def binary() -> Path:
    path = home() / "native" / "qwen_tts"
    marker = home() / "native" / ".mildew-build.json"
    if not path.exists() or not marker.exists() or json.loads(marker.read_text()).get("revision") != NATIVE_REV:
        raise RuntimeError("native runner missing: run ./mildew voice setup --no-model")
    return path


def setup(no_model=False) -> None:
    termux = "/com.termux/" in os.environ.get("PREFIX", "")
    if termux:
        run(["pkg", "install", "-y", "python", "git", "clang", "make", "pkg-config", "libopenblas", "ffmpeg", "curl"])
    for name in ("git", "make", "ffmpeg", "ffprobe", "curl"):
        if not shutil.which(name):
            raise RuntimeError(f"{name} required. Termux: pkg install python git clang make pkg-config libopenblas ffmpeg curl")
    dest = home() / "native"
    if not dest.exists():
        run(["git", "clone", "--no-checkout", "--filter=blob:none", NATIVE_REPO, str(dest)])
    run(["git", "-C", str(dest), "fetch", "--depth", "1", "origin", NATIVE_REV])
    run(["git", "-C", str(dest), "checkout", "--detach", NATIVE_REV])
    prefix = os.environ.get("PREFIX", "/usr")
    cc = "clang" if shutil.which("clang") else "gcc"
    flags = f"-Wall -Wextra -O3 -ffast-math -D_GNU_SOURCE -DUSE_BLAS -DUSE_OPENBLAS -I{prefix}/include -I{prefix}/include/openblas -Ivendor -DQWEN_SIMD_PROFILE=\\\"native\\\""
    # Keep portable ARMv8 instructions. Runtime dispatch chooses faster kernels safely.
    arch = "-march=armv8-a" if platform.machine() in ("aarch64", "arm64") else "-mavx2 -mfma"
    run(["make", "-C", str(dest), "blas", f"CC={cc}", "SIMD=portable",
         f"ARCH_FLAGS={arch}", f"CFLAGS_BASE={flags} {arch}",
         f"LDLIBS=-lm -lpthread -L{prefix}/lib -lopenblas", "-j2"], home() / "logs/setup.log")
    run([str(dest / "qwen_tts"), "--help"], home() / "logs/native-help.log", timeout=60)
    atomic_json(dest / ".mildew-build.json", {"revision": NATIVE_REV, "platform": platform.platform()})
    if not no_model:
        download("design")
    print("Setup complete. Next: ./mildew voice audition welcome_01 --takes 3", flush=True)
