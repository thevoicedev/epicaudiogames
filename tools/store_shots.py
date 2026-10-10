"""Raw store screenshots of the Android app, from the emulator. Each scene in brand/scenes.json is a cold start of the
debug build with launch extras (DebugLaunch.kt in android/app/src/debug/, which reads the iOS launch arguments' names:
ios/EpicAudioGames/Debug/DebugLaunch.swift), a wait for the app's "EpicShots" log lines, and a screencap, at each of
its target sizes: phone 1080x1920, 7-inch tablet 1200x1920 and 10-inch tablet 1600x2560 at 320 dpi (and turned to
landscape), and a Wear OS watch from a second adb device. make_art.py shots android --sizes ... (or `frame` here)
then puts them on the brand background with their captions (brand/shots.json).

Around the captures the emulator is made tidy, and put back as it was afterwards, even when a capture fails or the
run is stopped with Ctrl+C: SystemUI's demo mode (9:41, a full battery, Wi-Fi, no notifications), the screen size and
density, the font scale, the rotation, the microphone and notification permissions, and the app's saved games and
settings (its shared_prefs, copied out and back with run-as: the scenes start with EpicReset). What it changes is
written to build/store-shots/android/device-state.json first, so `restore` can put it back after a run was killed.

Scenes are data (brand/scenes.json): the extras (true/false go as --ez, everything else as --es, unless "types" says
otherwise; check them against DebugLaunch.kt), the font scale, and the steps before the screencap: wait for a log
line (a regular expression, searched in the EpicShots lines of the app's new process), sleep, tap a test tag (found
with uiautomator: never with TalkBack on), swipe, press a key.

Usage (from the repo root, with the emulator running and the debug build installed:
android\\gradlew.bat -p android :app:installDebug):
  py -3.13 tools/store_shots.py list                          the targets and scenes, and the adb commands they make
  py -3.13 tools/store_shots.py android                       every scene at its targets -> build/store-shots/android/raw/
  py -3.13 tools/store_shots.py android --targets phone --only 01_games,07_shop
  py -3.13 tools/store_shots.py android --dry-run             the commands, without a device
  py -3.13 tools/store_shots.py android --wear emulator-5556  the Wear OS scenes too, from the watch emulator
  py -3.13 tools/store_shots.py restore                       put the emulator back after a run that was killed
  py -3.13 tools/store_shots.py frame android --sizes phone,7in,10in,10in-land     (as make_art.py shots)
  py -3.13 tools/store_shots.py check                         every framed shot against the stores' rules
Capturing needs only Python's standard library (and adb); frame needs Pillow, numpy and fontTools.
"""
import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCENES = ROOT / "brand" / "scenes.json"
SHOTS = ROOT / "brand" / "shots.json"
OUT = ROOT / "build" / "store-shots" / "android"
STATE = OUT / "device-state.json"
PREFS_BACKUP = OUT / "app-prefs.tar"
PERMISSIONS = ("android.permission.RECORD_AUDIO", "android.permission.POST_NOTIFICATIONS")
# The settings a run changes, as (namespace, key).
SETTINGS = (("global", "sysui_demo_allowed"), ("system", "font_scale"), ("system", "accelerometer_rotation"),
            ("system", "user_rotation"))
STEP_KINDS = ("wait", "sleep", "tap", "swipe", "key")
EXTRA_TYPES = ("bool", "string", "int", "float")


class ShotError(Exception):
    pass


def rel(path):
    path = Path(path).resolve()
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def write_bytes(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    os.replace(tmp, path)


# ----- brand/scenes.json -----

def load_scenes(path=SCENES):
    """brand/scenes.json, checked: raises ShotError listing every problem."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise ShotError(f"{rel(path)}: {e}")
    problems = check_scenes(data)
    if problems:
        raise ShotError(f"{rel(path)}:\n  " + "\n  ".join(problems))
    return data


def check_scenes(data):
    """What's wrong with a scenes file (a list of sentences; empty when it's fine)."""
    out = []
    for key in ("package", "activity", "logTag", "extras", "targets", "scenes"):
        if key not in data:
            out.append(f"no {key}")
    if out:
        return out
    types = data["extras"].get("types", {})
    for name, kind in types.items():
        if kind not in EXTRA_TYPES:
            out.append(f"extras.types.{name}: {kind!r} isn't one of {', '.join(EXTRA_TYPES)}")
    for name in data["extras"].get("always", {}):
        if name not in types:
            out.append(f"extras.always has {name}, which extras.types doesn't name")
    for name, t in data["targets"].items():
        if t.get("device") == "wear":
            continue
        size = t.get("size")
        if not (isinstance(size, list) and len(size) == 2 and all(isinstance(v, int) and v > 0 for v in size)):
            out.append(f"targets.{name}: size should be [width, height]")
        if t.get("density") is not None and not isinstance(t.get("density"), int):
            out.append(f"targets.{name}: density should be a whole number of dpi, or null for the screen's own")
        if t.get("rotation", 0) not in (0, 1, 2, 3):
            out.append(f"targets.{name}: rotation is 0 to 3 (quarter turns)")
    seen = set()
    for i, scene in enumerate(data["scenes"]):
        where = f"scenes[{i}] ({scene.get('name', '?')})"
        if not re.fullmatch(r"[A-Za-z0-9_-]+", scene.get("name", "")):
            out.append(f"{where}: name should be letters, digits, _ and -")
        targets = scene.get("targets") or []
        if not targets:
            out.append(f"{where}: no targets")
        for t in targets:
            if t not in data["targets"]:
                out.append(f"{where}: target {t} isn't in targets")
            elif (t, scene.get("name")) in seen:
                out.append(f"{where}: a second {scene.get('name')} for {t}")
            seen.add((t, scene.get("name")))
        for name, value in (scene.get("extras") or {}).items():
            if name not in types:
                out.append(f"{where}: extra {name} isn't in extras.types (a typo, or add it there)")
            elif value is not None and not isinstance(value, (bool, str, int, float)):
                out.append(f"{where}: extra {name} should be true/false, a number or text")
        scale = scene.get("fontScale", 1.0)
        if not (isinstance(scale, (int, float)) and 0.85 <= scale <= 2.0):
            out.append(f"{where}: fontScale is 0.85 to 2.0")
        if "steps" in scene and ("wait" in scene or "after" in scene):
            out.append(f"{where}: steps, or wait and after, not both")
        for j, step in enumerate(scene_steps(scene)):
            kinds = [k for k in STEP_KINDS if k in step]
            if len(kinds) != 1:
                out.append(f"{where}: step {j + 1} should be one of {', '.join(STEP_KINDS)}")
                continue
            if kinds[0] == "wait":
                try:
                    re.compile(step["wait"])
                except re.error as e:
                    out.append(f"{where}: step {j + 1}: {step['wait']!r} isn't a regular expression ({e})")
            if kinds[0] == "swipe" and not (isinstance(step["swipe"], list) and len(step["swipe"]) == 4 and
                                            all(isinstance(v, (int, float)) and 0 <= v <= 1 for v in step["swipe"])):
                out.append(f"{where}: step {j + 1}: swipe is [x1, y1, x2, y2] as shares of the screen (0 to 1)")
        phone = scene.get("phone")
        if phone and any(t for t in targets if data["targets"].get(t, {}).get("device") != "wear"):
            out.append(f"{where}: only a Wear OS scene sets up the phone first (phone)")
    return out


def scene_steps(scene):
    """A scene's steps: its own, or the short form (wait for a line, then sleep `after` seconds)."""
    if "steps" in scene:
        return scene["steps"]
    steps = []
    if scene.get("wait"):
        steps.append({"wait": scene["wait"], "timeout": scene.get("timeout", 30)})
    steps.append({"sleep": scene.get("after", 1.0)})
    return steps


def scene_extras(data, scene):
    """The extras a scene starts with: brand/scenes.json's always ones, then its own (null takes one away)."""
    extras = dict(data["extras"].get("always", {}))
    extras.update(scene.get("extras") or {})
    return {k: v for k, v in extras.items() if v is not None}


def extra_args(extras, types):
    """am's arguments for the extras: --ez for a flag, --es for text (numbers too, unless types says int/float)."""
    args = []
    for key, value in extras.items():
        kind = types.get(key) or ("bool" if isinstance(value, bool) else "string")
        if kind == "bool":
            flag = value if isinstance(value, bool) else str(value).lower() in ("1", "true", "yes")
            args += ["--ez", key, "true" if flag else "false"]
        elif kind == "int":
            args += ["--ei", key, str(int(value))]
        elif kind == "float":
            args += ["--ef", key, repr(float(value))]
        else:
            text = ("true" if value else "false") if isinstance(value, bool) else \
                repr(value) if isinstance(value, float) else str(value)
            args += ["--es", key, text]
    return args


def sh_quote(word):
    """One word for the device's shell (adb shell joins its arguments into one command line)."""
    word = str(word)
    if word and re.fullmatch(r"[A-Za-z0-9_./:=@%+,-]+", word):
        return word
    return "'" + word.replace("'", "'\\''") + "'"


def am_start(component, extras, types):
    """The cold start of the app with its extras: one command line for the device's shell."""
    return " ".join(sh_quote(w) for w in ["am", "start", "-S", "-W", "-n", component] + extra_args(extras, types))


def component_of(data):
    activity = data["activity"]
    return f"{data['package']}/{activity}"


def raw_root(data, out=None):
    root = Path(out) if out else ROOT / data.get("raw", "build/store-shots/android/raw")
    return root if root.is_absolute() else ROOT / root


def raw_path(data, target_name, scene_name, out=None):
    sub = data["targets"][target_name].get("rawDir") or ""
    return raw_root(data, out) / sub / f"{scene_name}.png"


def target_size(target):
    """The screen size a target's screencap has: its size, turned for rotation 1 and 3."""
    w, h = target["size"]
    return (h, w) if target.get("rotation", 0) in (1, 3) else (w, h)


# ----- adb -----

def find_adb():
    exe = shutil.which("adb")
    if exe:
        return exe
    homes = [os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT")]
    if os.environ.get("LOCALAPPDATA"):
        homes.append(str(Path(os.environ["LOCALAPPDATA"]) / "Android" / "Sdk"))
    homes.append(str(Path.home() / "Library" / "Android" / "sdk"))
    for home in homes:
        if home:
            for name in ("adb.exe", "adb"):
                p = Path(home) / "platform-tools" / name
                if p.exists():
                    return str(p)
    raise ShotError("adb isn't on PATH or in the Android SDK (platform-tools)")


def devices(exe):
    """The serials adb lists as ready ("device")."""
    p = subprocess.run([exe, "devices"], capture_output=True, text=True, timeout=30)
    found = []
    for line in p.stdout.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            found.append(parts[0])
    return found


class Adb:
    """adb for one device. dry: print the commands instead, and answer queries with nothing."""

    def __init__(self, exe, serial, dry=False):
        self.exe, self.serial, self.dry = exe, serial, dry

    def cmd(self, *args):
        return [self.exe, "-s", self.serial, *[str(a) for a in args]]

    def run(self, *args, timeout=60, check=True, binary=False):
        if self.dry:
            print(f"  adb -s {self.serial} " + " ".join(str(a) for a in args))
            return b"" if binary else ""
        try:
            p = subprocess.run(self.cmd(*args), capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise ShotError(f"adb {' '.join(str(a) for a in args)}: no answer in {timeout} s")
        if check and p.returncode != 0:
            err = (p.stderr or p.stdout).decode("utf-8", "replace").strip()
            raise ShotError(f"adb {' '.join(str(a) for a in args)}: {err or f'exit {p.returncode}'}")
        return p.stdout if binary else p.stdout.decode("utf-8", "replace").replace("\r\n", "\n")

    def shell(self, command, **kw):
        return self.run("shell", command, **kw)

    def exec_out(self, command, **kw):
        return self.run("exec-out", command, binary=True, **kw)

    def setting(self, namespace, key):
        """A setting's value, or None when it isn't set."""
        value = self.shell(f"settings get {namespace} {key}").strip()
        return None if value in ("", "null") else value

    def put_setting(self, namespace, key, value):
        if value is None:
            self.shell(f"settings delete {namespace} {key}", check=False)
        else:
            self.shell(f"settings put {namespace} {key} {sh_quote(value)}")

    def device_time(self):
        """The device's clock (seconds since 1970, to the millisecond where the shell's date can)."""
        if self.dry:
            return 0.0
        text = self.shell("date +%s.%N").strip()
        try:
            return float(text) if re.fullmatch(r"\d+\.\d+", text) else float(self.shell("date +%s").strip())
        except ValueError:
            raise ShotError(f"the device's date gave {text!r}")

    def pid(self, package):
        text = self.shell(f"pidof {package}", check=False).strip()
        return int(text.split()[0]) if text and text.split()[0].isdigit() else None


def pick_device(exe, serial=None, any_device=False):
    found = devices(exe)
    if serial:
        if serial not in found:
            raise ShotError(f"{serial} isn't ready (adb devices lists: {', '.join(found) or 'nothing'})")
        chosen = serial
    else:
        emulators = [s for s in found if s.startswith("emulator-")]
        if not emulators:
            raise ShotError("no emulator is running: start one, e.g. "
                            "& \"$env:LOCALAPPDATA\\Android\\Sdk\\emulator\\emulator.exe\" -avd EpicAudioGames_Pixel")
        if len(emulators) > 1:
            raise ShotError(f"several emulators are running ({', '.join(emulators)}): say which with --serial")
        chosen = emulators[0]
    adb = Adb(exe, chosen)
    qemu = (adb.shell("getprop ro.kernel.qemu", check=False).strip() == "1" or
            adb.shell("getprop ro.boot.qemu", check=False).strip() == "1")
    if not (qemu or chosen.startswith("emulator-")) and not any_device:
        raise ShotError(f"{chosen} isn't an emulator: the run changes the screen size, settings and permissions "
                        f"(--any-device to allow it)")
    if adb.shell("getprop sys.boot_completed", check=False).strip() != "1":
        raise ShotError(f"{chosen} hasn't finished starting up")
    return adb


class LogReader:
    """adb logcat from a device time on (-T), the given tags only, read in a thread: (time, pid, tag, message)."""

    LINE = re.compile(r"^\s*(\d+\.\d+)\s+(\d+)\s+\d+\s+[VDIWEF]\s+(.*?)\s*:\s(.*)$")

    def __init__(self, adb, since, tags):
        self.lines = []
        self.cond = threading.Condition()
        self.proc = None
        if adb.dry:
            print(f"  adb logcat -v epoch -T {since:.3f} {' '.join(t + ':V' for t in tags)} *:S")
            return
        self.proc = subprocess.Popen(adb.cmd("logcat", "-v", "epoch", "-T", f"{since:.3f}",
                                             *[f"{t}:V" for t in tags], "*:S"),
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.thread = threading.Thread(target=self._read, daemon=True)
        self.thread.start()

    def _read(self):
        for raw in self.proc.stdout:
            m = self.LINE.match(raw.decode("utf-8", "replace").rstrip("\r\n"))
            if m:
                with self.cond:
                    self.lines.append((float(m.group(1)), int(m.group(2)), m.group(3), m.group(4)))
                    self.cond.notify_all()

    def wait_for(self, pattern, start, timeout, tag=None, pid=None):
        """The first line from index `start` on whose message matches (from that pid and tag, when given):
        (index, line), or None after `timeout` seconds."""
        regex = re.compile(pattern)
        deadline = time.monotonic() + timeout
        with self.cond:
            i = start
            while True:
                while i < len(self.lines):
                    t, p, g, msg = self.lines[i]
                    if (tag is None or g == tag) and (pid is None or p == pid) and regex.search(msg):
                        return i, self.lines[i]
                    i += 1
                left = deadline - time.monotonic()
                if left <= 0 or self.proc is None:
                    return None
                self.cond.wait(min(left, 0.5))

    def close(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def png_size(data):
    """A PNG's (width, height), or None if it isn't one."""
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", data[16:24])


# ----- The device's state: saved before, put back after -----

def parse_wm(text, what):
    """`wm size` / `wm density`: (physical, override or None)."""
    physical = re.search(r"Physical " + what + r": (\S+)", text)
    override = re.search(r"Override " + what + r": (\S+)", text)
    return (physical.group(1) if physical else None), (override.group(1) if override else None)


def parse_permission(dump, permission):
    """From dumpsys package: (granted, [flags]) for a permission, or None when it isn't listed."""
    m = re.search(r"^\s*" + re.escape(permission) + r": granted=(true|false)(?:, flags=\[\s*([^\]]*)\])?", dump, re.M)
    if not m:
        return None
    flags = [f for f in re.split(r"[|\s]+", m.group(2) or "") if f]
    return m.group(1) == "true", flags


def save_state(adb, package, keep_app_data):
    """What the run will change, as it is now (also written to device-state.json)."""
    state = {"serial": adb.serial, "package": package, "settings": {}, "permissions": {}, "prefs": None}
    for namespace, key in SETTINGS:
        state["settings"][f"{namespace}/{key}"] = adb.setting(namespace, key)
    state["wmSize"] = parse_wm(adb.shell("wm size"), "size")[1]
    state["wmDensity"] = parse_wm(adb.shell("wm density"), "density")[1]
    dump = adb.shell(f"dumpsys package {package}")
    for permission in PERMISSIONS:
        found = parse_permission(dump, permission)
        if found:
            state["permissions"][permission] = {"granted": found[0], "flags": found[1]}
    if keep_app_data:
        there = adb.shell(f"run-as {package} ls -d shared_prefs", check=False).strip()
        if there == "shared_prefs":
            data = adb.exec_out(f"run-as {package} tar -cf - shared_prefs", check=False)
            if len(data) < 1024 or data[257:262] != b"ustar":
                raise ShotError(f"couldn't copy the app's saved games and settings out with run-as "
                                f"({data[:120].decode('utf-8', 'replace').strip() or 'nothing came back'}); "
                                f"--no-app-data runs without them (the scenes' EpicReset clears them)")
            write_bytes(PREFS_BACKUP, data)
            state["prefs"] = rel(PREFS_BACKUP)
        elif "No such file" in there:
            state["prefs"] = "none"     # no saved games or settings yet: restore clears whatever the run made
        else:
            raise ShotError(f"run-as {package} didn't work ({there or 'no answer'}); --no-app-data runs without "
                            f"keeping the app's saved games and settings")
    write_json(STATE, state)
    return state


def restore_state(adb, state):
    """Puts back what save_state() recorded; returns the steps that failed (empty when all went back)."""
    failed = []
    package = state["package"]

    def attempt(what, fn):
        try:
            fn()
        except ShotError as e:
            failed.append(f"{what}: {e}")

    attempt("stop the app", lambda: adb.shell(f"am force-stop {package}"))
    prefs = state.get("prefs")
    if prefs == "none":
        attempt("the app's saved games and settings",
                lambda: adb.shell(f"run-as {package} rm -rf shared_prefs"))
    elif prefs:
        def put_prefs():
            tmp = "/data/local/tmp/eag-prefs.tar"
            adb.run("push", str(ROOT / prefs), tmp)
            adb.shell(f"run-as {package} rm -rf shared_prefs")
            adb.shell(f"cat {tmp} | run-as {package} tar -xf -")
            adb.shell(f"rm -f {tmp}", check=False)
        attempt("the app's saved games and settings", put_prefs)
    for permission, was in state.get("permissions", {}).items():
        def put_permission(permission=permission, was=was):
            adb.shell(f"pm {'grant' if was['granted'] else 'revoke'} {package} {permission}")
            adb.shell(f"pm clear-permission-flags {package} {permission} user-set user-fixed")
            back = [f.lower().replace("_", "-") for f in was["flags"] if f in ("USER_SET", "USER_FIXED")]
            if back:
                adb.shell(f"pm set-permission-flags {package} {permission} {' '.join(back)}")
        attempt(permission, put_permission)
    for name, value in state.get("settings", {}).items():
        if name == "global/sysui_demo_allowed":
            continue                    # last: leaving demo mode needs it
        namespace, key = name.split("/")
        attempt(f"setting {name}", lambda namespace=namespace, key=key, value=value:
                adb.put_setting(namespace, key, value))
    attempt("wm size", lambda: adb.shell(f"wm size {state['wmSize']}" if state.get("wmSize") else "wm size reset"))
    attempt("wm density", lambda: adb.shell(f"wm density {state['wmDensity']}" if state.get("wmDensity")
                                            else "wm density reset"))
    attempt("demo mode", lambda: demo_command(adb, "exit"))
    attempt("setting global/sysui_demo_allowed",
            lambda: adb.put_setting("global", "sysui_demo_allowed",
                                    state.get("settings", {}).get("global/sysui_demo_allowed")))
    return failed


def finish_restore(adb, state):
    failed = restore_state(adb, state)
    if failed:
        print("could not put everything back (run `py -3.13 tools/store_shots.py restore` to try again):")
        for f in failed:
            print(f"  {f}")
        return False
    for path in (STATE, PREFS_BACKUP):
        if path.exists():
            path.unlink()
    print("the emulator is back as it was")
    return True


# ----- Demo mode, targets, scenes -----

def demo_command(adb, command, **extras):
    args = " ".join(f"-e {k} {sh_quote(v)}" for k, v in extras.items())
    adb.shell(f"am broadcast -a com.android.systemui.demo -e command {command} {args}".strip())


def enter_demo(adb, demo):
    adb.put_setting("global", "sysui_demo_allowed", "1")
    demo_command(adb, "enter")
    demo_command(adb, "clock", hhmm=demo.get("clock", "0941"))
    demo_command(adb, "battery", level=str(demo.get("battery", 100)), plugged="false", powersave="false")
    demo_command(adb, "network", wifi="show", level=str(demo.get("wifi", 4)), fully="true")
    demo_command(adb, "network", mobile="hide")
    demo_command(adb, "notifications", visible="true" if demo.get("notifications") else "false")
    demo_command(adb, "status", **{k: "hide" for k in ("volume", "bluetooth", "location", "alarm", "zen", "mute",
                                                       "speakerphone", "sync", "tty", "eri", "cast", "hotspot")})


def apply_target(adb, target):
    w, h = target["size"]
    adb.shell(f"wm size {w}x{h}")
    adb.shell(f"wm density {target['density']}" if target.get("density") else "wm density reset")
    adb.put_setting("system", "accelerometer_rotation", "0")
    adb.put_setting("system", "user_rotation", str(target.get("rotation", 0)))
    if not adb.dry:
        time.sleep(2.0)                    # the launcher and SystemUI redraw at the new size


def grant(adb, package, sdk):
    adb.shell(f"pm grant {package} android.permission.RECORD_AUDIO")
    if sdk >= 33:
        adb.shell(f"pm grant {package} android.permission.POST_NOTIFICATIONS")


def tap_tag(adb, tag, package, tries=4):
    """Taps the middle of the element whose resource id is this test tag (uiautomator: TalkBack must be off)."""
    xml = ""
    for _ in range(1 if adb.dry else tries):
        said = adb.shell("uiautomator dump --compressed /sdcard/eag-ui.xml", check=False, timeout=30)
        if "dumped" in said.lower():
            xml = adb.exec_out("cat /sdcard/eag-ui.xml").decode("utf-8", "replace")
            break
        time.sleep(0.7)                    # "could not get idle state" while something animates
    adb.shell("rm -f /sdcard/eag-ui.xml", check=False)
    if adb.dry:
        print(f"  (tap the middle of {tag})")
        return
    if not xml:
        raise ShotError(f"uiautomator couldn't read the screen to find {tag}")
    for node in ET.fromstring(xml).iter("node"):
        if node.get("resource-id") in (tag, f"{package}:id/{tag}"):
            m = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
            if m:
                x1, y1, x2, y2 = map(int, m.groups())
                adb.shell(f"input tap {(x1 + x2) // 2} {(y1 + y2) // 2}")
                return
    raise ShotError(f"nothing on screen has the test tag {tag}")


def run_steps(adb, scene, reader, tag, pid, package, screen):
    """A scene's steps before its screencap; raises ShotError when one can't be done."""
    index = 0
    for step in scene_steps(scene):
        if "wait" in step:
            timeout = step.get("timeout", 30)
            if adb.dry:
                print(f"  (wait up to {timeout} s for an {tag} line matching {step['wait']!r})")
                continue
            found = reader.wait_for(step["wait"], index, timeout, tag=tag, pid=pid)
            if not found:
                seen = [line[3] for line in reader.lines if line[2] == tag and (pid is None or line[1] == pid)]
                raise ShotError(f"no {tag} line matching {step['wait']!r} in {timeout} s (it said: "
                                f"{'; '.join(seen[-6:]) or 'nothing'})")
            index = found[0] + 1
        elif "sleep" in step:
            if adb.dry:
                print(f"  (sleep {step['sleep']} s)")
            else:
                time.sleep(float(step["sleep"]))
        elif "tap" in step:
            tap_tag(adb, step["tap"], package)
        elif "swipe" in step:
            x1, y1, x2, y2 = step["swipe"]
            w, h = screen
            adb.shell(f"input swipe {round(x1 * w)} {round(y1 * h)} {round(x2 * w)} {round(y2 * h)} "
                      f"{int(step.get('ms', 400))}")
        elif "key" in step:
            adb.shell(f"input keyevent {step['key']}")


def capture(adb, data, target_name, scene, out=None, component=None, setup=None):
    """One scene: cold start, steps, screencap -> its raw PNG. Returns the file."""
    target = data["targets"][target_name]
    package = data["package"]
    tag = data["logTag"]
    types = data["extras"].get("types", {})
    if setup:
        setup()
    if target.get("device") != "wear":
        adb.put_setting("system", "font_scale", str(scene.get("fontScale", 1.0)))
    since = adb.device_time() - 0.5
    reader = LogReader(adb, since, [tag])
    try:
        said = adb.shell(am_start(component or component_of(data), scene_extras(data, scene), types), timeout=90)
        if "Error" in said or "Exception" in said:
            raise ShotError(f"am start: {said.strip()}")
        pid = None if adb.dry else adb.pid(package)
        if not adb.dry and pid is None:
            raise ShotError(f"{package} isn't running after the start (did it crash? adb logcat -b crash)")
        screen = target_size(target) if target.get("size") else (0, 0)
        run_steps(adb, scene, reader, tag, pid, package, screen)
        image = adb.exec_out("screencap -p", timeout=60)
    finally:
        reader.close()
    file = raw_path(data, target_name, scene["name"], out)
    if adb.dry:
        print(f"  -> {rel(file)}")
        return file
    size = png_size(image)
    if size is None:
        raise ShotError("screencap didn't give a PNG")
    if target.get("size") and size != target_size(target):
        print(f"  note: the capture is {size[0]}x{size[1]}, not {'x'.join(map(str, target_size(target)))}")
    write_bytes(file, image)
    return file


def chosen(data, targets=None, only=None, wear=False):
    """(target, scene) pairs to capture, in target order then scene order."""
    names = [t for t in data["targets"] if (not targets or t in targets)]
    if targets:
        unknown = [t for t in targets if t not in data["targets"]]
        if unknown:
            raise ShotError(f"no such target: {', '.join(unknown)} (brand/scenes.json has "
                            f"{', '.join(data['targets'])})")
    if not wear:
        if targets and any(data["targets"][t].get("device") == "wear" for t in targets):
            raise ShotError("the wear target's scenes need the watch: --wear SERIAL")
        names = [t for t in names if data["targets"][t].get("device") != "wear"]
    pairs = [(t, s) for t in names for s in data["scenes"] if t in s.get("targets", []) and
             (not only or s["name"] in only)]
    if only:
        found = {s["name"] for _, s in pairs}
        missing = [n for n in only if n not in found]
        if missing:
            raise ShotError(f"no scene called {', '.join(missing)} for {', '.join(names) or 'those targets'}")
    return pairs


def run_android(args):
    data = load_scenes(args.scenes)
    targets = [t for t in (args.targets or "").split(",") if t]
    only = [s for s in (args.only or "").split(",") if s]
    pairs = chosen(data, targets, only, wear=bool(args.wear))
    if not pairs:
        raise ShotError("no scenes to capture")
    package = data["package"]
    exe = "adb" if args.dry_run else find_adb()
    if args.dry_run:
        adb = Adb(exe, args.serial or "emulator-5554", dry=True)
    else:
        if STATE.exists():
            raise ShotError(f"a run didn't put the emulator back yet ({rel(STATE)}): "
                            f"py -3.13 tools/store_shots.py restore first")
        adb = pick_device(exe, args.serial, args.any_device)
    watch = None
    if args.wear:
        if data["targets"].get("wear", {}).get("component") is None:
            raise ShotError("brand/scenes.json's wear target has no component yet (the Wear OS app's activity)")
        watch = Adb(exe, args.wear, dry=True) if args.dry_run else pick_device(exe, args.wear, any_device=True)
    sdk = 35 if args.dry_run else int(adb.shell("getprop ro.build.version.sdk").strip() or 0)
    if not args.dry_run:
        dump = adb.shell(f"dumpsys package {package}")
        if f"Package [{package}]" not in dump:
            raise ShotError(f"{package} isn't installed: android\\gradlew.bat -p android :app:installDebug")
        if "DEBUGGABLE" not in dump:
            raise ShotError(f"{package} is a release build: the launch extras are in the debug build only")
    print(f"{adb.serial}: {len(pairs)} capture{'s' if len(pairs) != 1 else ''}")
    state = None if args.dry_run else save_state(adb, package, not args.no_app_data)
    made, failed = [], []
    try:
        enter_demo(adb, data.get("demo", {}))
        grant(adb, package, sdk)
        current = None
        for target_name, scene in pairs:
            target = data["targets"][target_name]
            device = watch if target.get("device") == "wear" else adb
            if target.get("device") != "wear" and target_name != current:
                print(f"{target_name}: {'x'.join(map(str, target['size']))}"
                      f"{' at ' + str(target['density']) + ' dpi' if target.get('density') else ''}"
                      f"{', turned' if target.get('rotation') else ''}")
                apply_target(adb, target)
                current = target_name
            print(f"  {target_name}/{scene['name']}")
            setup = None
            if scene.get("phone"):
                phone_scene = dict(scene["phone"], name=scene["name"], targets=["phone"])

                def setup(phone_scene=phone_scene):
                    say = adb.shell(am_start(component_of(data), scene_extras(data, phone_scene),
                                             data["extras"].get("types", {})), timeout=90)
                    if "Error" in say:
                        raise ShotError(f"the phone's am start: {say.strip()}")
                    if not adb.dry:
                        time.sleep(float(phone_scene.get("after", 3.0)))
            try:
                component = target.get("component") if target.get("device") == "wear" else None
                made.append(capture(device, data, target_name, scene, args.out, component, setup))
            except ShotError as e:
                failed.append(f"{target_name}/{scene['name']}: {e}")
                print(f"    failed: {e}")
                if args.stop_on_error:
                    break
    finally:
        if state is not None:
            finish_restore(adb, state)
        elif args.dry_run:
            print("  (then everything is put back as it was: the app's saved games and settings, the permissions, "
                  "the font scale, the rotation, wm size and density, demo mode)")
    if not args.dry_run:
        for f in made:
            print(f"  {rel(f)}")
        print(f"{len(made)} capture{'s' if len(made) != 1 else ''}, {len(failed)} failed")
        for f in failed:
            print(f"  {f}")
    return 1 if failed else 0


def run_restore(args):
    if not STATE.exists():
        print(f"nothing to put back ({rel(STATE)} isn't there)")
        return 0
    state = json.loads(STATE.read_text(encoding="utf-8"))
    if args.forget:
        STATE.unlink()
        print(f"forgot {rel(STATE)}")
        return 0
    adb = pick_device(find_adb(), args.serial or state["serial"], any_device=True)
    return 0 if finish_restore(adb, state) else 1


def run_list(args):
    data = load_scenes(args.scenes)
    types = data["extras"].get("types", {})
    print(f"{rel(args.scenes)}: {len(data['scenes'])} scenes, targets {', '.join(data['targets'])}")
    for target_name, target in data["targets"].items():
        if target.get("device") == "wear":
            print(f"\n{target_name}: the Wear OS device (--wear SERIAL), {target.get('component') or 'no component yet'}")
        else:
            print(f"\n{target_name}: wm size {target['size'][0]}x{target['size'][1]}, "
                  f"density {target.get('density') or 'the screen’s own'}, rotation {target.get('rotation', 0)}")
        for scene in data["scenes"]:
            if target_name not in scene.get("targets", []):
                continue
            print(f"  {scene['name']}  -> {rel(raw_path(data, target_name, scene['name'], args.out))}")
            if scene.get("about"):
                print(f"    {scene['about']}")
            component = target.get("component") if target.get("device") == "wear" else component_of(data)
            print(f"    font scale {scene.get('fontScale', 1.0)}; "
                  f"adb shell {am_start(component or '<wear component>', scene_extras(data, scene), types)}")
            for step in scene_steps(scene):
                kind = next(k for k in STEP_KINDS if k in step)
                more = f" (up to {step.get('timeout', 30)} s)" if kind == "wait" else ""
                print(f"    {kind} {step[kind]}{more}")
    return 0


# ----- Framing and checking the framed shots -----

def run_frame(args):
    sys.path.insert(0, str(ROOT / "tools"))
    from art.shots import run_shots
    sizes = [s for s in (args.sizes or "").split(",") if s]
    run_shots(args.platform, args.raw, [c for c in (args.claims or "").split(",") if c], sizes, args.out,
              args.replace)
    return 0


IOS_SIZES = {(1320, 2868), (1290, 2796), (1260, 2736), (1206, 2622), (1179, 2556), (1284, 2778), (1242, 2688),
             (2064, 2752), (2048, 2732)}


def png_info(path):
    """(width, height, colour type) of a PNG file, or None."""
    with open(path, "rb") as f:
        head = f.read(26)
    if len(head) < 26 or head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h = struct.unpack(">II", head[16:24])
    return w, h, head[25]


def run_check(args):
    """Every framed shot in the store folders (or --out) against brand/shots.json and the stores' rules."""
    spec = json.loads(SHOTS.read_text(encoding="utf-8"))
    root = Path(args.out) if args.out else ROOT
    root = root if root.is_absolute() else ROOT / root
    errors, warnings = [], []
    for platform in ("android", "ios"):
        p = spec[platform]
        folders = {}
        for name, layout in p["sizes"].items():
            folders.setdefault(root / layout.get("out", p["out"]), []).append((name, layout))
        for folder, layouts in folders.items():
            files = sorted(folder.glob("*.png")) if folder.exists() else []
            if not files:
                continue
            by_size = {}
            for path in files:
                info = png_info(path)
                if info is None:
                    errors.append(f"{rel(path)} isn't a PNG")
                    continue
                w, h, kind = info
                by_size.setdefault((w, h), []).append(path)
                if kind in (4, 6):
                    errors.append(f"{rel(path)} has an alpha channel; the stores want screenshots without")
                if path.stat().st_size > 8 * 1024 * 1024:
                    errors.append(f"{rel(path)} is over 8 MB")
                plain = [l for _, l in layouts if l.get("plain")]
                framed = [tuple(l["size"]) for _, l in layouts if not l.get("plain")]
                if plain:
                    if plain[0].get("square") and w != h:
                        errors.append(f"{rel(path)} is {w}x{h}; Wear OS screenshots are square")
                    if min(w, h) < plain[0].get("minSide", 0):
                        errors.append(f"{rel(path)} is {w}x{h}; at least {plain[0]['minSide']} a side")
                elif (w, h) not in framed:
                    errors.append(f"{rel(path)} is {w}x{h}; this folder's sizes are "
                                  f"{', '.join(f'{a}x{b}' for a, b in framed)}")
                if platform == "android":
                    if min(w, h) < 320 or max(w, h) > 3840 or max(w, h) > 2 * min(w, h):
                        errors.append(f"{rel(path)} is {w}x{h}: Play takes 320 to 3840 a side, the long side at "
                                      f"most twice the short")
                    elif not plain and w * 16 != h * 9 and w * 9 != h * 16:
                        warnings.append(f"{rel(path)} is {w}x{h}, not 9:16 or 16:9 (Play's promotion wants them)")
                elif (w, h) not in IOS_SIZES:
                    errors.append(f"{rel(path)} is {w}x{h}: not an App Store iPhone or 13-inch iPad size")
            if platform == "android":
                count = len(files)
                kind = folder.name
                if count > 8:
                    errors.append(f"{rel(folder)}: {count} screenshots; Play takes 8 at most")
                elif kind == "phoneScreenshots" and count < 2:
                    errors.append(f"{rel(folder)}: {count} screenshot; Play wants 2 to 8 for phones")
                elif kind in ("sevenInchScreenshots", "tenInchScreenshots") and count < 4:
                    warnings.append(f"{rel(folder)}: {count} screenshots; Play's large-screen promotion wants 4")
            else:
                for (w, h), paths in by_size.items():
                    if len(paths) > 10:
                        errors.append(f"{rel(folder)}: {len(paths)} screenshots at {w}x{h}; the App Store takes 10")
            print(f"  {rel(folder)}: {len(files)} file{'s' if len(files) != 1 else ''} "
                  f"({', '.join(f'{w}x{h}' for w, h in sorted(by_size))})")
    for w in warnings:
        print(f"  warning: {w}")
    for e in errors:
        print(f"  error: {e}")
    print(f"{len(errors)} error{'s' if len(errors) != 1 else ''}, {len(warnings)} warning"
          f"{'s' if len(warnings) != 1 else ''}")
    return 1 if errors else 0


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawTextHelpFormatter,
                                 epilog="\n\n".join(__doc__.split("\n\n")[1:]))
    sub = ap.add_subparsers(dest="command", required=True)

    p = sub.add_parser("list", help="the targets and scenes in brand/scenes.json, and the commands they make")
    p.add_argument("--scenes", type=Path, default=SCENES, help="the scenes file (default brand/scenes.json)")
    p.add_argument("--out", help="the raw captures' folder (default build/store-shots/android/raw)")

    p = sub.add_parser("android", help="capture the scenes on the emulator")
    p.add_argument("--scenes", type=Path, default=SCENES, help="the scenes file (default brand/scenes.json)")
    p.add_argument("--targets", help="only these targets, e.g. phone,tablet7 (default: all but wear)")
    p.add_argument("--only", help="only these scenes, e.g. 01_games,07_shop")
    p.add_argument("--serial", help="the emulator (default: the only one running)")
    p.add_argument("--wear", metavar="SERIAL", help="the Wear OS device for the wear target's scenes")
    p.add_argument("--out", help="the raw captures' folder (default build/store-shots/android/raw)")
    p.add_argument("--no-app-data", action="store_true",
                   help="don't copy the app's saved games and settings out and back (run-as)")
    p.add_argument("--stop-on-error", action="store_true", help="stop at the first scene that fails")
    p.add_argument("--any-device", action="store_true", help="allow a device that isn't an emulator")
    p.add_argument("--dry-run", action="store_true", help="print the adb commands; no device needed")

    p = sub.add_parser("restore", help="put the emulator back as device-state.json says it was")
    p.add_argument("--serial", help="the emulator (default: the one the run used)")
    p.add_argument("--forget", action="store_true", help="drop device-state.json without restoring")

    p = sub.add_parser("frame", help="frame raw captures with their captions (as make_art.py shots)")
    p.add_argument("platform", choices=["android", "ios"])
    p.add_argument("--sizes", help="brand/shots.json sizes: phone,7in,10in,10in-land,wear / 6.9,6.3,13 "
                                   "(default: the platform's default ones)")
    p.add_argument("--raw", help="the raw captures (default brand/shots.json's)")
    p.add_argument("--claims", default="", help="claims the device test has earned, e.g. voiceover,talkback")
    p.add_argument("--out", help="write under this folder instead of the store folders")
    p.add_argument("--replace", action="store_true", help="remove the folders' other screenshots (the old set)")

    p = sub.add_parser("check", help="the framed shots against brand/shots.json and the stores' rules")
    p.add_argument("--out", help="check a trial under this folder instead of the store folders")

    args = ap.parse_args(argv)
    try:
        return {"list": run_list, "android": run_android, "restore": run_restore, "frame": run_frame,
                "check": run_check}[args.command](args)
    except ShotError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("stopped", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
