#!/usr/bin/env python3
"""Package a Flutter Linux release into distributable artifacts.

Flutter itself only produces a raw folder (`flutter build linux --release`), so
the three formats users actually download have to be assembled here:

    tar      portable folder, works on any distro with no install step
    deb      Debian/Ubuntu/Kali package (dpkg-deb, the same tool the distro uses)
    appimage single self-mounting executable that runs on any glibc distro

Usage:
    flutter build linux --release
    python3 tool/packaging/linux_packaging.py deb
    python3 tool/packaging/linux_packaging.py all --out dist
"""

from __future__ import annotations

import argparse
import os
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

APP_NAME = "OmniClean Engine"
BINARY = "omni_clean_engine"
DESKTOP_ID = "dev.omniclean.OmniCleanEngine"
DEFAULT_ICON = "resources/icon/omniclean-engine.png"
BUNDLE = Path("build/linux/x64/release/bundle")
DIST = Path("dist")

# Everything the Flutter GTK runner links against at load time. `dpkg-shlibdeps`
# is deliberately not used: it needs a built .so tree to walk, and the GTK
# runner links straight into system libraries, so this explicit list is both
# sufficient and reviewable.
RUNTIME_DEPENDS = [
    "libgtk-3-0 | libgtk-3-0t64",
    "libgdk-pixbuf-2.0-0",
    "libgl1",
    "libstdc++6",
]


def run(args: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=cwd, check=True)


def read_version() -> str:
    """Reads the version out of pubspec.yaml without needing a YAML parser."""
    for line in Path("pubspec.yaml").read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            raw = line.split(":", 1)[1].strip()
            return raw.split("+", 1)[0]
    raise SystemExit("pubspec.yaml has no version field")


def bundle_path() -> Path:
    if not (BUNDLE / BINARY).exists():
        raise SystemExit(
            f"{BUNDLE / BINARY} is missing - run `flutter build linux --release` first"
        )
    return BUNDLE


def install_prefix() -> str:
    return "/opt/omniclean-engine"


def desktop_entry(version: str) -> str:
    return (
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Version=1.5\n"
        f"Name={APP_NAME}\n"
        "GenericName=System cleaner\n"
        "Comment=Reclaim disk space and find duplicate files safely.\n"
        f'Exec="{install_prefix()}/{BINARY}" %U\n'
        f"Icon={DESKTOP_ID}\n"
        "Terminal=false\n"
        "Categories=Utility;\n"
        f"X-AppVersion={version}\n"
        "StartupWMClass=omni_clean_engine\n"
    )


def control_file(version: str) -> str:
    installed_kb = int(
        sum(f.stat().st_size for f in bundle_path().rglob("*") if f.is_file()) / 1024
    )
    depends = ", ".join(RUNTIME_DEPENDS)
    return (
        "Package: omniclean-engine\n"
        f"Version: {version}\n"
        "Section: utils\n"
        "Priority: optional\n"
        "Architecture: amd64\n"
        "Maintainer: OmniClean Engine <maintainers@omniclean.dev>\n"
        f"Installed-Size: {max(installed_kb, 1)}\n"
        f"Depends: {depends}\n"
        "Homepage: https://github.com/aihams21/OmniClean-Engine\n"
        f"Description: {APP_NAME}\n"
        " A cross-platform disk cleaner and duplicate finder for Linux.\n"
        " Every file is quarantined instead of deleted, so anything it removes\n"
        " can be restored with one click.\n"
    )


def stage_icon(stage_icon: Path) -> None:
    source = Path(DEFAULT_ICON)
    if not source.exists():
        print(f"! icon {source} missing, skipping icon install", flush=True)
        return
    stage_icon.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, stage_icon)


def write_deb_tree(root: Path, version: str) -> Path:
    """Lays out a complete .deb payload and returns its staging directory."""
    payload = root / "omniclean-engine"
    target = payload / install_prefix().lstrip("/")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(bundle_path(), target, symlinks=True)

    bin_dir = payload / "usr" / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    launcher = bin_dir / BINARY
    launcher.write_text(
        "#!/bin/sh\n"
        f'exec "{install_prefix()}/{BINARY}" "$@"\n',
        encoding="utf-8",
    )
    launcher.chmod(0o755)

    applications = payload / "usr" / "share" / "applications"
    applications.mkdir(parents=True, exist_ok=True)
    (applications / f"{DESKTOP_ID}.desktop").write_text(
        desktop_entry(version), encoding="utf-8"
    )
    stage_icon(payload / "usr" / "share" / "icons" / "hicolor" / "512x512" / "apps" / f"{DESKTOP_ID}.png")

    control = payload / "DEBIAN"
    control.mkdir(parents=True, exist_ok=True)
    (control / "control").write_text(control_file(version), encoding="utf-8")
    (control / "conffiles").write_text(
        f"/usr/share/applications/{DESKTOP_ID}.desktop\n", encoding="utf-8"
    )
    (control / "postinst").write_text(
        "#!/bin/sh\n"
        "set -e\n"
        "if command -v update-desktop-database >/dev/null 2>&1; then\n"
        "  update-desktop-database -q /usr/share/applications || true\n"
        "fi\n"
        "if command -v gtk-update-icon-cache >/dev/null 2>&1; then\n"
        "  gtk-update-icon-cache -q -f -t /usr/share/icons/hicolor || true\n"
        "fi\n"
        "exit 0\n",
        encoding="utf-8",
    )
    (control / "prerm").write_text(
        "#!/bin/sh\n"
        "set -e\n"
        "if command -v update-desktop-database >/dev/null 2>&1; then\n"
        "  update-desktop-database -q /usr/share/applications || true\n"
        "fi\n"
        "exit 0\n",
        encoding="utf-8",
    )
    for script in ("postinst", "prerm"):
        (control / script).chmod(0o755)
    return payload


def build_deb(out: Path) -> Path:
    version = read_version()
    out.mkdir(parents=True, exist_ok=True)
    target = out / f"omniclean-engine_{version}_amd64.deb"
    with tempfile.TemporaryDirectory() as tmp:
        payload = write_deb_tree(Path(tmp), version)
        run(
            [
                "dpkg-deb",
                "--root-owner-group",
                "--build",
                str(payload),
                str(target),
            ]
        )
    print(f"built {target} ({target.stat().st_size // 1024} KiB)")
    return target


def build_tar(out: Path) -> Path:
    version = read_version()
    out.mkdir(parents=True, exist_ok=True)
    target = out / f"omniclean-engine_{version}_linux-x64-portable.tar.gz"
    with tempfile.TemporaryDirectory() as tmp:
        staging = Path(tmp) / f"omni-clean-engine-{version}"
        staging.mkdir()
        shutil.copytree(bundle_path(), staging / APP_NAME, symlinks=True)
        readme = staging / "RUN-ME.txt"
        readme.write_text(
            f"{APP_NAME} {version} - portable build\n"
            "==========================================\n\n"
            f"1. Unpack this archive anywhere you like.\n"
            f"2. Double-click, or run:  ./{APP_NAME}/{BINARY}\n\n"
            "No installation and no root are required for the user cache, temp\n"
            "file and thumbnail modules. Modules marked with a lock badge ask for\n"
            "administrator rights when you run them.\n",
            encoding="utf-8",
        )
        with tarfile.open(target, "w:gz") as tar:
            tar.add(staging, arcname=staging.name)
    print(f"built {target} ({target.stat().st_size // 1024} KiB)")
    return target


def appdir_tree(root: Path, version: str) -> Path:
    # appimagetool requires the desktop entry to be named after the AppDir.
    appdir = root / "OmniCleanEngine.AppDir"
    shutil.copytree(bundle_path(), appdir, symlinks=True)
    (appdir / "AppRun").write_text(
        "#!/bin/sh\n"
        'HERE="$(dirname "$(readlink -f "$0")")"\n'
        f'exec "$HERE/{BINARY}" "$@"\n',
        encoding="utf-8",
    )
    (appdir / "AppRun").chmod(0o755)
    # The desktop entry inside an AppDir must launch through AppRun: the spec
    # forbids `$` in Exec unless it is escaped as `\\$`, and appimagetool puts
    # the AppDir on PATH, so AppRun resolves to this very bundle.
    entry = desktop_entry(version).replace(
        f'Exec="{install_prefix()}/{BINARY}" %U\n', "Exec=AppRun %U\n"
    )
    (appdir / "OmniCleanEngine.desktop").write_text(entry, encoding="utf-8")
    icons = appdir / "usr" / "share" / "icons" / "hicolor"
    stage_icon(icons / "512x512" / "apps" / f"{DESKTOP_ID}.png")
    stage_icon(appdir / f"{DESKTOP_ID}.png")
    stage_icon(appdir / ".DirIcon")
    (appdir / "version").write_text(version + "\n", encoding="utf-8")
    with zipfile.ZipFile(appdir / f"{DESKTOP_ID}.metainfo.xml", "w") as zf:
        zf.writestr(
            "metainfo.xml",
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            "<component type=\"desktop-application\">\n"
            f"  <id>{DESKTOP_ID}</id>\n"
            f"  <name>{APP_NAME}</name>\n"
            "  <summary>Cross-platform disk cleaner and duplicate finder</summary>\n"
            '  <metadata_license>CC0-1.0</metadata_license>\n'
            "  <project_license>MIT</project_license>\n"
            f'  <description><p>{APP_NAME} reclaims disk space safely.</p>'
            "<p>Nothing is deleted: every file moves to a restorable quarantine.</p>"
            "</description>\n"
            f'  <launchable type="desktop-id">{DESKTOP_ID}.desktop</launchable>\n'
            '  <releases><release version="' + version + '"/></releases>\n'
            "</component>\n",
        )
    return appdir


def build_appimage(out: Path, tool: Path | None) -> Path:
    version = read_version()
    if tool is None:
        tool = Path(os.environ.get("APPIMAGETOOL", "appimagetool"))
    if not (tool.exists() or shutil.which(str(tool))):
        raise SystemExit(
            "appimagetool not found. Download AppImageKit or set APPIMAGETOOL."
        )
    # An absolute path matters: `subprocess` resolves a bare name against PATH,
    # never against the working directory, so `./appimagetool.AppImage` would
    # work on a developer's shell and fail on a CI runner.
    tool = tool.resolve()
    out.mkdir(parents=True, exist_ok=True)
    target = out / f"omniclean-engine_{version}_amd64.AppImage"
    with tempfile.TemporaryDirectory() as tmp:
        appdir = appdir_tree(Path(tmp), version)
        env = dict(os.environ, ARCH="x86_64")
        print("+", str(tool), "--no-appstream", str(appdir), str(target), flush=True)
        subprocess.run(
            [str(tool), "--no-appstream", str(appdir), str(target)],
            check=True,
            env=env,
        )
    target.chmod(target.stat().st_mode | stat.S_IEXEC)
    print(f"built {target} ({target.stat().st_size // 1024} KiB)")
    return target


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "formats",
        nargs="+",
        choices=["deb", "tar", "appimage", "all"],
        help="which artifacts to produce",
    )
    parser.add_argument("--out", default=str(DIST), help="output directory")
    parser.add_argument("--appimagetool", default=None)
    args = parser.parse_args(argv)

    out = Path(args.out)
    wanted = {"deb", "tar", "appimage"} if "all" in args.formats else set(args.formats)
    bundle_path()

    if "tar" in wanted:
        build_tar(out)
    if "deb" in wanted:
        build_deb(out)
    if "appimage" in wanted:
        build_appimage(
            out,
            Path(args.appimagetool) if args.appimagetool else None,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
