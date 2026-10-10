"""The OpenAI Images API: the key, the calls (list models, generate, edit) and what to do when one fails.

The key is OPENAI_API_KEY from the environment, else OPENAI_API_KEY or OPEN_AI in all-minigames-sites/alexa/.env (the
way voice_audition.api_key() finds ElevenLabs'). It is never printed, logged or written anywhere: an error shows the
HTTP status and OpenAI's message only, with anything key-like in that message masked.

Retry rules: 429 waits for retry-after (unless the account is out of quota); 5xx, a dropped connection or a timeout
backs off 2, 4, 8, 16 and 32 seconds; 401/403 means the key is wrong or the organisation isn't verified (GPT image
models need a verified organisation); any other 4xx fails that request at once.
"""
import os
import re
import sys
import time

import requests

from .brand import MINI

API = "https://api.openai.com/v1"
TIMEOUT = 300
BACKOFF = [2, 4, 8, 16, 32]

_key = None


class ApiError(RuntimeError):
    def __init__(self, status, message, code=None):
        self.status, self.message, self.code = status, masked(message), code
        super().__init__(f"OpenAI {status}: {self.message}" if status else f"OpenAI: {self.message}")


def masked(text):
    """Text with anything that looks like an API key cut down to "sk-…"."""
    return re.sub(r"sk-[A-Za-z0-9_\-*]{3,}", "sk-…", str(text or ""))


def api_key():
    global _key
    if _key:
        return _key
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        env = MINI / "alexa" / ".env"
        lines = env.read_text(encoding="utf-8", errors="replace").splitlines() if env.exists() else []
        found = {}
        for line in lines:
            name, _, value = line.partition("=")
            name, value = name.strip(), value.strip().strip('"').strip("'")
            if name in ("OPENAI_API_KEY", "OPEN_AI") and value:
                found[name] = value
        key = found.get("OPENAI_API_KEY") or found.get("OPEN_AI") or ""
    if not key:
        sys.exit("No OPENAI_API_KEY in the environment, or OPENAI_API_KEY / OPEN_AI in all-minigames-sites/alexa/.env")
    _key = key
    return key


def _error(r):
    """OpenAI's error code and message from a failed response (never the request, which has the key in it)."""
    try:
        e = r.json().get("error") or {}
        return e.get("code") or e.get("type"), e.get("message") or r.reason
    except ValueError:
        return None, (r.text or r.reason or "")[:200]


def call(method, path, json_body=None, data=None, files=None, say=print):
    """One API call, retried by the rules above. Returns the response's JSON."""
    attempt = 0
    while True:
        try:
            r = requests.request(method, API + path, headers={"Authorization": "Bearer " + api_key()},
                                 json=json_body, data=data, files=files, timeout=TIMEOUT)
        except (requests.ConnectionError, requests.Timeout) as e:
            if attempt >= len(BACKOFF):
                raise ApiError(0, f"no answer from OpenAI ({type(e).__name__}) after {attempt + 1} tries") from None
            say(f"  no answer ({type(e).__name__}); trying again in {BACKOFF[attempt]} s")
            time.sleep(BACKOFF[attempt])
            attempt += 1
            continue
        if r.ok:
            return r.json()
        code, message = _error(r)
        if r.status_code in (401, 403):
            raise ApiError(r.status_code, f"key invalid or organisation not verified ({message})", code)
        if r.status_code == 429 and code not in ("insufficient_quota", "billing_hard_limit_reached") \
                and attempt < len(BACKOFF):
            try:
                wait = float(r.headers.get("retry-after") or BACKOFF[attempt])
            except ValueError:
                wait = BACKOFF[attempt]
            say(f"  rate limited; waiting {wait:g} s")
            time.sleep(min(wait, 120))
            attempt += 1
            continue
        if r.status_code >= 500 and attempt < len(BACKOFF):
            say(f"  OpenAI {r.status_code}; trying again in {BACKOFF[attempt]} s")
            time.sleep(BACKOFF[attempt])
            attempt += 1
            continue
        raise ApiError(r.status_code, message, code)


def models():
    """Every model id the key can use."""
    return sorted(m["id"] for m in call("GET", "/models")["data"])


def image_models():
    return [m for m in models() if "image" in m or m.startswith("dall-e")]


def generate(body, say=print):
    return call("POST", "/images/generations", json_body=body, say=say)


def edit(body, images, mask=None, say=print):
    """An edit: body's fields as multipart form fields, images as PNG bytes (several go as image[])."""
    field = "image[]" if len(images) > 1 else "image"
    files = [(field, (f"input-{i}.png", data, "image/png")) for i, data in enumerate(images)]
    if mask is not None:
        files.append(("mask", ("mask.png", mask, "image/png")))
    form = {k: str(v) for k, v in body.items()}
    return call("POST", "/images/edits", data=form, files=files, say=say)
