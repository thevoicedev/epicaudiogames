"""Auditions ElevenLabs voices for Alexa's lines: the same few lines in each voice, to pick one by ear.

Every line Alexa used to say is spoken by one voice in the app (phase 3). This renders a handful of real lines from
the games in each candidate voice with ElevenLabs' "with timestamps" endpoint, the one the full render will use (its
character timings give the transcript's word times), and saves, per voice:
  tools/cache/audition/<voice>/<n>.mp3     each line
  tools/cache/audition/<voice>/<n>.json    its character timings
  tools/cache/audition/<voice>.mp3         all the lines in a row, for listening

The API key is ELEVENLABS_API_KEY, from the environment or all-minigames-sites/alexa/.env; it is never printed.

Usage (from the repo root):
  python tools/voice_audition.py --list                   # the account's American female voices
  python tools/voice_audition.py rachel:21m00Tcm4TlvDq8ikWAM jessica:cgSgspJ2msm6clMCkdW9 ...
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MINI = Path(os.environ.get("MINIGAMES_DIR") or ROOT.parent / "all-minigames-sites")
OUT = ROOT / "tools" / "cache" / "audition"
API = "https://api.elevenlabs.io"
MODEL = "eleven_multilingual_v2"
SETTINGS = {"stability": 0.5, "similarity_boost": 0.75, "style": 0.15, "use_speaker_boost": True}

# Real lines Alexa says in the next games (Leaning Tower of Pizza, Pirate Quest, Nuclear War, Alien Customs), and
# one of the app's own.
LINES = [
    "Pinocchio, we need you to save Venice from the evil pizza robot! It's out of control, and flooding Venice with pizzas.",
    "I will ask you true or false questions, and you need to lie about the answer.",
    "What's the plan, Cap'n? Say: map, or supplies.",
    "You have three bombs left. Would you like to use one?",
    "Welcome back to Alien Customs! You are on level two. Are you ready to play?",
    "You finished Noodle Rush, and found the Dragon Fire ending! Want to play again?",
]


def api_key():
    if os.environ.get("ELEVENLABS_API_KEY"):
        return os.environ["ELEVENLABS_API_KEY"].strip()
    env = MINI / "alexa" / ".env"
    for line in env.read_text(encoding="utf-8").splitlines() if env.exists() else []:
        k, _, v = line.partition("=")
        if k.strip() == "ELEVENLABS_API_KEY" and v.strip():
            return v.strip().strip('"').strip("'")
    sys.exit("No ELEVENLABS_API_KEY in the environment or in all-minigames-sites/alexa/.env")


def call(path, body=None):
    req = urllib.request.Request(API + path, headers={"xi-api-key": api_key(), "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def list_voices():
    for v in call("/v1/voices")["voices"]:
        labels = v.get("labels") or {}
        if labels.get("gender") == "female" and "americ" in str(labels.get("accent", "")).lower():
            print(f"{v['name']:40} {v['voice_id']}  {v.get('category', '')}: "
                  f"{labels.get('age', '')} {labels.get('description') or labels.get('descriptive', '')} {labels.get('use_case', '')}")


def render(name, voice_id):
    folder = OUT / name
    folder.mkdir(parents=True, exist_ok=True)
    parts = []
    for i, text in enumerate(LINES, 1):
        mp3 = folder / f"{i}.mp3"
        if not mp3.exists():
            r = call(f"/v1/text-to-speech/{voice_id}/with-timestamps?output_format=mp3_44100_128",
                     {"text": text, "model_id": MODEL, "voice_settings": SETTINGS})
            mp3.write_bytes(base64.b64decode(r["audio_base64"]))
            (folder / f"{i}.json").write_text(json.dumps({"text": text, "alignment": r.get("alignment")}), encoding="utf-8")
        parts.append(mp3)
    # All the lines in a row, with a short pause between them.
    listing = folder / "parts.txt"
    silence = folder / "gap.mp3"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "0.7",
                    "-b:a", "128k", str(silence)], check=True)
    listing.write_text("".join(f"file '{p.name}'\nfile 'gap.mp3'\n" for p in parts), encoding="utf-8")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(listing), "-ac", "1",
                    "-b:a", "96k", str(OUT / f"{name}.mp3")], check=True, cwd=folder)
    print(f"{name}: {len(parts)} lines -> {(OUT / f'{name}.mp3').relative_to(ROOT)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--list", action="store_true", help="list the account's American female voices")
    ap.add_argument("voices", nargs="*", help="name:voice_id pairs to audition")
    args = ap.parse_args()
    if args.list:
        list_voices()
        return
    for pair in args.voices:
        name, _, voice_id = pair.partition(":")
        render(name, voice_id)


if __name__ == "__main__":
    main()
