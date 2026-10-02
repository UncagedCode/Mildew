#!/usr/bin/env python3
"""Graham Factory: free-first ElevenLabs TTS asset generator for Mildew.

Standard-library only. Generates one short utterance per request, uses request stitching
for continuity, caches results, and refuses to exceed a configurable free-use budget.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_MANIFEST = HERE / "manifest.json"
DEFAULT_STYLES = HERE / "styles.json"
DEFAULT_STATE = HERE / ".graham_state.json"
DEFAULT_OUT = HERE / "generated_audio"
API_BASE = "https://api.elevenlabs.io/v1"


class GrahamFactoryError(RuntimeError):
    pass


def load_dotenv(path: pathlib.Path) -> None:
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def read_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: pathlib.Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(path)


def safe_filename(value: str) -> str:
    out = []
    for c in value.lower():
        if c.isalnum() or c in ("-", "_"):
            out.append(c)
        else:
            out.append("_")
    return "".join(out).strip("_")


@dataclass
class Config:
    api_key: str
    voice_id: str
    model_id: str = "eleven_v4"
    output_format: str = "mp3_44100_128"
    speed: float = 1.0
    stability: float = 0.50
    similarity_boost: float = 0.75
    seed: int = 1998
    hard_cap: int = 8000

    @classmethod
    def from_env(cls) -> "Config":
        api_key = os.getenv("ELEVENLABS_API_KEY", "").strip()
        voice_id = os.getenv("GRAHAM_VOICE_ID", "").strip()
        if not api_key:
            raise GrahamFactoryError("ELEVENLABS_API_KEY is missing. Copy .env.example to .env and fill it locally.")
        if not voice_id:
            raise GrahamFactoryError("GRAHAM_VOICE_ID is missing. Copy Graham's ElevenLabs voice ID into .env.")
        return cls(
            api_key=api_key,
            voice_id=voice_id,
            model_id=os.getenv("GRAHAM_MODEL_ID", "eleven_v4").strip(),
            output_format=os.getenv("GRAHAM_OUTPUT_FORMAT", "mp3_44100_128").strip(),
            speed=float(os.getenv("GRAHAM_SPEED", "1.0")),
            stability=float(os.getenv("GRAHAM_STABILITY", "0.50")),
            similarity_boost=float(os.getenv("GRAHAM_SIMILARITY", "0.75")),
            seed=int(os.getenv("GRAHAM_SEED", "1998")),
            hard_cap=int(os.getenv("GRAHAM_MONTHLY_HARD_CAP", "8000")),
        )


class ElevenClient:
    def __init__(self, config: Config):
        self.config = config

    def _request(self, method: str, url: str, body: Optional[Dict[str, Any]] = None):
        headers = {
            "xi-api-key": self.config.api_key,
            "Content-Type": "application/json",
            "User-Agent": "Mildew-Graham-Factory/1.0",
        }
        data = None if body is None else json.dumps(body).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            return urllib.request.urlopen(req, timeout=90)
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise GrahamFactoryError(f"ElevenLabs API error {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise GrahamFactoryError(f"Network error calling ElevenLabs: {exc}") from exc

    def subscription(self) -> Dict[str, Any]:
        with self._request("GET", f"{API_BASE}/user/subscription") as resp:
            return json.loads(resp.read().decode("utf-8"))

    def synthesize(
        self,
        text: str,
        previous_request_ids: Optional[List[str]] = None,
        previous_text: Optional[str] = None,
        next_text: Optional[str] = None,
    ) -> tuple[bytes, Dict[str, str]]:
        qs = urllib.parse.urlencode({"output_format": self.config.output_format})
        url = f"{API_BASE}/text-to-speech/{urllib.parse.quote(self.config.voice_id)}?{qs}"
        body: Dict[str, Any] = {
            "text": text,
            "model_id": self.config.model_id,
            "seed": self.config.seed,
            "voice_settings": {
                "stability": self.config.stability,
                "similarity_boost": self.config.similarity_boost,
                "speed": self.config.speed,
            },
        }
        if previous_request_ids:
            body["previous_request_ids"] = previous_request_ids[-3:]
        elif previous_text:
            body["previous_text"] = previous_text
        if next_text:
            body["next_text"] = next_text
        with self._request("POST", url, body) as resp:
            audio = resp.read()
            headers = {k.lower(): v for k, v in resp.headers.items()}
        return audio, headers


def render_line(item: Dict[str, Any], styles: Dict[str, str]) -> str:
    mood = item.get("mood", "presenter")
    if mood not in styles:
        raise GrahamFactoryError(f"Unknown mood '{mood}' for line '{item.get('id')}'.")
    tag = styles[mood].strip()
    text = str(item["text"]).strip()
    return f"{tag}\n{text}" if tag else text


def fingerprint(item: Dict[str, Any], rendered: str, config: Config) -> str:
    payload = {
        "id": item["id"],
        "rendered": rendered,
        "voice_id": config.voice_id,
        "model_id": config.model_id,
        "output_format": config.output_format,
        "speed": config.speed,
        "stability": config.stability,
        "similarity_boost": config.similarity_boost,
        "seed": config.seed,
    }
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()


def projected_character_cost(rendered_lines: List[str]) -> int:
    # ElevenLabs exposes exact character-cost only after generation. Preflight uses literal
    # request length as a conservative, transparent approximation for the free-tier guard.
    return sum(len(x) for x in rendered_lines)


def budget_snapshot(subscription: Dict[str, Any], config: Config, projected: int = 0) -> Dict[str, Any]:
    used = int(subscription.get("character_count") or 0)
    account_limit = int(subscription.get("character_limit") or 0)
    effective_limit = min(config.hard_cap, account_limit) if account_limit > 0 else config.hard_cap
    remaining = max(0, effective_limit - used)
    return {
        "tier": subscription.get("tier", "unknown"),
        "used": used,
        "account_limit": account_limit,
        "factory_hard_cap": config.hard_cap,
        "effective_limit": effective_limit,
        "remaining": remaining,
        "projected": projected,
        "would_fit": projected <= remaining,
        "current_overage": subscription.get("current_overage"),
    }


def load_state(path: pathlib.Path) -> Dict[str, Any]:
    if not path.exists():
        return {"version": 1, "lines": {}}
    data = read_json(path)
    data.setdefault("version", 1)
    data.setdefault("lines", {})
    return data


def ordered_manifest(path: pathlib.Path) -> List[Dict[str, Any]]:
    data = read_json(path)
    lines = data["lines"] if isinstance(data, dict) else data
    seen = set()
    for item in lines:
        if "id" not in item or "text" not in item:
            raise GrahamFactoryError("Each manifest line needs id and text.")
        if item["id"] in seen:
            raise GrahamFactoryError(f"Duplicate manifest id: {item['id']}")
        seen.add(item["id"])
    return lines


def select_lines(lines: List[Dict[str, Any]], ids: Optional[List[str]]) -> List[Dict[str, Any]]:
    if not ids:
        return lines
    wanted = set(ids)
    found = [x for x in lines if x["id"] in wanted]
    missing = wanted - {x["id"] for x in found}
    if missing:
        raise GrahamFactoryError("Unknown line id(s): " + ", ".join(sorted(missing)))
    return found


def print_budget(snap: Dict[str, Any]) -> None:
    print("Graham Factory budget")
    print(f"  ElevenLabs tier:       {snap['tier']}")
    print(f"  Account usage:         {snap['used']} / {snap['account_limit']} characters")
    print(f"  Factory hard cap:      {snap['factory_hard_cap']} characters")
    print(f"  Effective free cap:    {snap['effective_limit']} characters")
    print(f"  Remaining under cap:   {snap['remaining']} characters")
    if snap["projected"]:
        print(f"  Planned this command:  {snap['projected']} characters")
        print(f"  Budget result:         {'OK' if snap['would_fit'] else 'STOP'}")


def cmd_status(config: Config, client: ElevenClient) -> int:
    snap = budget_snapshot(client.subscription(), config)
    print_budget(snap)
    if snap.get("current_overage"):
        print("  Current overage field: ", snap["current_overage"])
    return 0


def cmd_plan(config: Config, manifest_path: pathlib.Path, styles_path: pathlib.Path, ids: Optional[List[str]], state_path: pathlib.Path) -> int:
    lines = select_lines(ordered_manifest(manifest_path), ids)
    styles = read_json(styles_path)
    state = load_state(state_path)
    rendered = []
    print("Generation plan")
    for item in lines:
        speech = render_line(item, styles)
        fp = fingerprint(item, speech, config)
        cached = state["lines"].get(item["id"], {})
        hit = cached.get("fingerprint") == fp and pathlib.Path(cached.get("path", "")).exists()
        print(f"  {'CACHED' if hit else 'GENERATE':8}  {item['id']:28}  {item.get('mood','presenter')}")
        if not hit:
            rendered.append(speech)
    print(f"\nUncached estimated characters: {projected_character_cost(rendered)}")
    return 0


def generate(
    config: Config,
    client: ElevenClient,
    manifest_path: pathlib.Path,
    styles_path: pathlib.Path,
    state_path: pathlib.Path,
    out_dir: pathlib.Path,
    ids: Optional[List[str]],
    force: bool,
) -> int:
    all_lines = ordered_manifest(manifest_path)
    selected = select_lines(all_lines, ids)
    styles: Dict[str, str] = read_json(styles_path)
    state = load_state(state_path)

    tasks: List[tuple[Dict[str, Any], str, str]] = []
    for item in selected:
        rendered = render_line(item, styles)
        fp = fingerprint(item, rendered, config)
        cached = state["lines"].get(item["id"], {})
        cached_path = pathlib.Path(cached.get("path", "")) if cached.get("path") else None
        is_cached = bool(cached_path and cached_path.exists() and cached.get("fingerprint") == fp)
        if force or not is_cached:
            tasks.append((item, rendered, fp))

    if not tasks:
        print("Nothing to generate: every selected line is cached and current.")
        return 0

    projected = projected_character_cost([x[1] for x in tasks])
    subscription = client.subscription()
    snap = budget_snapshot(subscription, config, projected)
    print_budget(snap)
    if not snap["would_fit"]:
        raise GrahamFactoryError(
            "Refusing to generate: this command would exceed the configured free-use hard cap. "
            "Wait for the monthly allowance to reset, lower the selection, or deliberately change GRAHAM_MONTHLY_HARD_CAP."
        )

    out_dir.mkdir(parents=True, exist_ok=True)
    id_to_index = {item["id"]: i for i, item in enumerate(all_lines)}
    recent_request_ids: List[str] = []

    for n, (item, rendered, fp) in enumerate(tasks, start=1):
        idx = id_to_index[item["id"]]
        prev_item = all_lines[idx - 1] if idx > 0 else None
        next_item = all_lines[idx + 1] if idx + 1 < len(all_lines) else None
        previous_text = render_line(prev_item, styles) if prev_item else None
        next_text = render_line(next_item, styles) if next_item else None

        stitched_ids: List[str] = []
        for pidx in range(max(0, idx - 3), idx):
            prior = all_lines[pidx]
            entry = state["lines"].get(prior["id"], {})
            req_id = entry.get("request_id")
            if req_id:
                stitched_ids.append(req_id)
        if recent_request_ids:
            stitched_ids = (stitched_ids + recent_request_ids)[-3:]

        print(f"[{n}/{len(tasks)}] {item['id']} ...", flush=True)
        audio, headers = client.synthesize(
            rendered,
            previous_request_ids=stitched_ids[-3:] or None,
            previous_text=previous_text,
            next_text=next_text,
        )
        if not audio:
            raise GrahamFactoryError(f"Empty audio returned for {item['id']}")

        ext = ".mp3" if config.output_format.startswith("mp3_") else ".bin"
        filename = safe_filename(item["id"]) + ext
        path = out_dir / filename
        path.write_bytes(audio)
        request_id = headers.get("request-id") or headers.get("request_id") or ""
        raw_cost = headers.get("character-cost") or headers.get("character_cost")
        try:
            actual_cost = int(raw_cost) if raw_cost is not None else len(rendered)
        except ValueError:
            actual_cost = len(rendered)

        state["lines"][item["id"]] = {
            "fingerprint": fp,
            "path": str(path.resolve()),
            "request_id": request_id,
            "character_cost": actual_cost,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "model_id": config.model_id,
            "output_format": config.output_format,
            "seed": config.seed,
            "mood": item.get("mood", "presenter"),
            "text": item["text"],
        }
        write_json(state_path, state)
        if request_id:
            recent_request_ids.append(request_id)
            recent_request_ids = recent_request_ids[-3:]
        print(f"      saved {path.name} ({actual_cost} chars)")
        time.sleep(0.15)

    print("\nGeneration complete. No runtime API dependency is introduced into the game.")
    return 0


def cmd_report(state_path: pathlib.Path) -> int:
    state = load_state(state_path)
    lines = state.get("lines", {})
    if not lines:
        print("No generated Graham assets recorded yet.")
        return 0
    total = 0
    print("Graham Factory local cache")
    for key in sorted(lines):
        item = lines[key]
        path = pathlib.Path(item.get("path", ""))
        ok = path.exists()
        cost = int(item.get("character_cost", 0) or 0)
        total += cost
        print(f"  {'OK' if ok else 'MISSING':7} {key:28} {cost:5}  {path.name}")
    print(f"\nRecorded generated character cost: {total}")
    return 0


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Generate Graham Mildew voice assets with a free-first ElevenLabs workflow.")
    p.add_argument("--env", default=str(HERE / ".env"), help="Path to local .env file")
    p.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    p.add_argument("--styles", default=str(DEFAULT_STYLES))
    p.add_argument("--state", default=str(DEFAULT_STATE))
    p.add_argument("--out", default=str(DEFAULT_OUT))
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("status", help="Show ElevenLabs account usage and Graham Factory hard cap")
    plan = sub.add_parser("plan", help="Show what would generate without spending credits")
    plan.add_argument("ids", nargs="*")
    missing = sub.add_parser("missing", help="Generate only uncached/current-missing assets")
    missing.add_argument("ids", nargs="*")
    one = sub.add_parser("regenerate", help="Force regeneration of selected IDs")
    one.add_argument("ids", nargs="+")
    sub.add_parser("report", help="Show local generated-asset cache")
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = parser().parse_args(argv)
    load_dotenv(pathlib.Path(args.env))
    try:
        config = Config.from_env()
        manifest = pathlib.Path(args.manifest)
        styles = pathlib.Path(args.styles)
        state = pathlib.Path(args.state)
        out = pathlib.Path(args.out)
        client = ElevenClient(config)
        if args.command == "status":
            return cmd_status(config, client)
        if args.command == "plan":
            return cmd_plan(config, manifest, styles, args.ids or None, state)
        if args.command == "missing":
            return generate(config, client, manifest, styles, state, out, args.ids or None, False)
        if args.command == "regenerate":
            return generate(config, client, manifest, styles, state, out, args.ids, True)
        if args.command == "report":
            return cmd_report(state)
    except GrahamFactoryError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
