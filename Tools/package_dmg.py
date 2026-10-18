#!/usr/bin/env python3
"""Build Tidepool.app for release and pack it into a drag-to-install DMG.

    dist/PibbosTidepool-<version>.dmg
        Tidepool.app        universal (Apple silicon + Intel), macOS 13+
        Applications ->     drop target
        First launch.txt    what to do if macOS blocks the app

Signing:
    Without a Developer ID the app stays ad-hoc signed: it runs, but macOS
    blocks the first launch of a downloaded copy until the user allows it
    (see "First launch.txt"). With a Developer ID certificate in the keychain:

        SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \\
        NOTARY_PROFILE=tidepool python3 Tools/package_dmg.py

    signs app + DMG with the hardened runtime and a timestamp, notarizes the
    DMG with `xcrun notarytool` (profile saved once with
    `xcrun notarytool store-credentials tidepool`) and staples the ticket.

Usage:
    python3 Tools/package_dmg.py

Requires: Python 3.10+, Xcode command line tools, xcodegen, hdiutil (macOS).
"""
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
DERIVED = ROOT / "build/package"
VOLUME_NAME = "Pibbo's Tidepool"

FIRST_LAUNCH_ADHOC = """Hi! 🦦

1. Drag Tidepool into Applications.
2. Open it from Applications.

This build isn't signed with an Apple Developer ID yet, so the first time
macOS will say it can't check Tidepool for malware. To allow it:

    System Settings → Privacy & Security → scroll down →
    "Tidepool was blocked…" → Open Anyway → enter your password

You only need to do this once. After that Pibbo starts by himself every
time you log in (macOS shows a one-time "Login Item Added" note).

To quit: click Pibbo → Swim away.
Tidepool is open source (GPL-3.0): https://github.com/Eric031212/pibbos-tidepool
"""

FIRST_LAUNCH_SIGNED = """Hi! 🦦

1. Drag Tidepool into Applications.
2. Open it from Applications.

After that Pibbo starts by himself every time you log in (macOS shows a
one-time "Login Item Added" note).

To quit: click Pibbo → Swim away.
Tidepool is open source (GPL-3.0): https://github.com/Eric031212/pibbos-tidepool
"""


def run(*args, **kwargs):
    print("$", " ".join(str(a) for a in args))
    subprocess.run([str(a) for a in args], check=True, **kwargs)


def version():
    match = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', (ROOT / "project.yml").read_text())
    if not match:
        raise SystemExit("MARKETING_VERSION not found in project.yml")
    return match.group(1)


def build_app():
    run("xcodegen", "generate", cwd=ROOT)
    run("xcodebuild", "-scheme", "Tidepool", "-configuration", "Release",
        "-derivedDataPath", DERIVED, "-destination", "generic/platform=macOS", "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO",
        "clean", "build", cwd=ROOT, stdout=subprocess.DEVNULL)
    app = DERIVED / "Build/Products/Release/Tidepool.app"
    archs = subprocess.run(["lipo", "-archs", app / "Contents/MacOS/Tidepool"],
                           capture_output=True, text=True, check=True).stdout.split()
    if sorted(archs) != ["arm64", "x86_64"]:
        raise SystemExit(f"expected a universal binary, got {archs}")
    return app


def sign(path, identity):
    run("codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity, path)


def main():
    identity = os.environ.get("SIGN_IDENTITY")
    notary = os.environ.get("NOTARY_PROFILE")
    if notary and not identity:
        raise SystemExit("NOTARY_PROFILE needs SIGN_IDENTITY (notarization requires a Developer ID)")

    app = build_app()
    if identity:
        sign(app, identity)
    run("codesign", "--verify", "--strict", app)

    DIST.mkdir(exist_ok=True)
    dmg = DIST / f"PibbosTidepool-{version()}.dmg"
    dmg.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        stage = Path(tmp) / "stage"
        stage.mkdir()
        run("ditto", app, stage / "Tidepool.app")
        (stage / "Applications").symlink_to("/Applications")
        (stage / "First launch.txt").write_text(FIRST_LAUNCH_SIGNED if identity else FIRST_LAUNCH_ADHOC)
        run("hdiutil", "create", "-volname", VOLUME_NAME, "-srcfolder", stage,
            "-fs", "HFS+", "-format", "UDZO", "-imagekey", "zlib-level=9", "-ov", dmg,
            stdout=subprocess.DEVNULL)

    if identity:
        run("codesign", "--force", "--timestamp", "--sign", identity, dmg)
    if notary:
        run("xcrun", "notarytool", "submit", dmg, "--keychain-profile", notary, "--wait")
        run("xcrun", "stapler", "staple", dmg)

    size = dmg.stat().st_size / 1_000_000
    kind = "notarized" if notary else "Developer ID signed" if identity else "ad-hoc signed"
    print(f"wrote {dmg.relative_to(ROOT)} ({size:.0f} MB, {kind})")


if __name__ == "__main__":
    main()
