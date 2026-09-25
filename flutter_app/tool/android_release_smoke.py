#!/usr/bin/env python3
import argparse
import pathlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET

PACKAGE = "it.notes.ecosystem.lymlyc"
ACTIVITY = "it.notes.ecosystem.notes_ecosistema.MainActivity"
CRASH_PATTERNS = (
    "FATAL EXCEPTION",
    f"ANR in {PACKAGE}",
    f"Process: {PACKAGE}",
    f"am_crash.*{PACKAGE}",
)

def run(*args, check=True, capture=True):
    result = subprocess.run(
        list(args),
        check=False,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(args)}\n"
            f"{result.stdout or ''}"
        )
    return result.stdout or ""

def adb(*args, check=True):
    return run("adb", *args, check=check)

def dump_ui():
    adb("shell", "uiautomator", "dump", "/sdcard/window.xml")
    raw = adb("shell", "cat", "/sdcard/window.xml")
    return ET.fromstring(raw)

def bounds_center(value):
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", value or "")
    if not match:
        raise RuntimeError(f"Invalid bounds: {value}")
    x1, y1, x2, y2 = map(int, match.groups())
    return (x1 + x2) // 2, (y1 + y2) // 2

def _dismiss_launcher_anr(nodes):
    title = next(
        (
            n
            for n in nodes
            if "Pixel Launcher isn't responding" in n.attrib.get("text", "")
        ),
        None,
    )
    if title is None:
        return False

    close = next(
        (n for n in nodes if n.attrib.get("text") == "Close app"),
        None,
    )
    if close is None:
        return False

    x, y = bounds_center(close.attrib.get("bounds", ""))
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(1)
    return True

def find_node(text, timeout=20):
    deadline = time.time() + timeout
    last = []
    while time.time() < deadline:
        try:
            root = dump_ui()
            nodes = list(root.iter("node"))
            if _dismiss_launcher_anr(nodes):
                continue
            last = [
                (n.attrib.get("text", ""), n.attrib.get("content-desc", ""))
                for n in nodes
                if n.attrib.get("text") or n.attrib.get("content-desc")
            ]
            for node in nodes:
                values = (
                    node.attrib.get("text", ""),
                    node.attrib.get("content-desc", ""),
                )
                if any(
                    text == value.strip()
                    or text in [line.strip() for line in value.splitlines()]
                    for value in values
                    if value
                ):
                    return node
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError(f"UI node not found: {text}. Visible sample: {last[:80]}")

def tap_text(text, timeout=20):
    node = find_node(text, timeout=timeout)
    x, y = bounds_center(node.attrib.get("bounds", ""))
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(1)

def assert_text(text, timeout=20):
    find_node(text, timeout=timeout)

def screenshot(path):
    data = subprocess.run(
        ["adb", "exec-out", "screencap", "-p"],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    pathlib.Path(path).write_bytes(data)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", required=True)
    parser.add_argument("--out", default="build/smoke")
    args = parser.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    apk = pathlib.Path(args.apk)
    if not apk.is_file():
        raise RuntimeError(f"APK not found: {apk}")

    adb("wait-for-device")
    try:
        adb("install", "-r", str(apk))
        adb("shell", "pm", "clear", PACKAGE)
        adb("logcat", "-c")

        # The Google APIs image can occasionally surface a launcher-only
        # ANR during cold boot under CI load. It is unrelated to Notes, so
        # force-stop the launcher before explicitly starting our activity.
        adb(
            "shell",
            "am",
            "force-stop",
            "com.google.android.apps.nexuslauncher",
            check=False,
        )
        launch = adb(
            "shell",
            "am",
            "start",
            "-W",
            "-n",
            f"{PACKAGE}/{ACTIVITY}",
        )
        (out / "launch.txt").write_text(launch, encoding="utf-8")
        time.sleep(4)

        pid = adb("shell", "pidof", PACKAGE).strip()
        if not pid:
            raise RuntimeError("Notes process is not running after launch.")

        # Home boot + primary navigation.
        assert_text("Oggi, nel tuo spazio.")
        assert_text("Crea")
        tap_text("Spazi")
        # Unique Shared Spaces content. The screen title itself is merged by
        # Flutter into a multiline semantics node and the bottom nav also
        # contains "Spazi", so it is not a reliable navigation assertion.
        assert_text("PRIVATE BY DEFAULT")
        tap_text("Home")
        assert_text("Oggi, nel tuo spazio.")

        # Real functional persistence path: create and save one note.
        tap_text("Crea")
        tap_text("Nuova nota")
        assert_text("La tua pagina")
        tap_text("Titolo")
        adb("shell", "input", "text", "SmokeTest032")
        tap_text("Comincia da un pensiero…")
        adb("shell", "input", "text", "ReleaseSmokeBody")
        tap_text("Salva")
        assert_text("Oggi, nel tuo spazio.")

        tap_text("Note")
        assert_text("SmokeTest032")

        if not adb("shell", "pidof", PACKAGE).strip():
            raise RuntimeError("Notes process died during smoke test.")
    finally:
        try:
            screenshot(out / "notes-smoke.png")
        except Exception as error:
            (out / "screenshot-error.txt").write_text(str(error), encoding="utf-8")
        try:
            adb("shell", "uiautomator", "dump", "/sdcard/window.xml", check=False)
            ui = adb("shell", "cat", "/sdcard/window.xml", check=False)
            (out / "last-window.xml").write_text(ui, encoding="utf-8")
        except Exception as error:
            (out / "ui-error.txt").write_text(str(error), encoding="utf-8")
        try:
            logcat = adb("logcat", "-d", "-v", "threadtime", check=False)
            (out / "logcat.txt").write_text(logcat, encoding="utf-8")
        except Exception as error:
            logcat = ""
            (out / "logcat-error.txt").write_text(str(error), encoding="utf-8")

    for pattern in CRASH_PATTERNS:
        if re.search(pattern, logcat, flags=re.IGNORECASE):
            raise RuntimeError(f"Crash/ANR signature found in logcat: {pattern}")

    print("Android release smoke test passed.")

if __name__ == "__main__":
    main()
