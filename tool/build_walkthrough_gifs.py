#!/usr/bin/env python3
"""Build silent, cursor-driven GIF walkthroughs from the rendered scenes.

The Flutter test `test/walkthrough_test.dart` renders the real application
offscreen and writes one PNG per scene plus a manifest describing where the
pointer went. This script turns that manifest into silent animated GIFs with a
visible mouse, a click ripple and a caption, so a reader can follow every
button without the video.

Nothing here is decorative fiction: the frames are the real UI, the clicks are
the real taps the test performed, and the numbers on screen are the numbers the
engine measured on the machine that rendered them.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FRAMES = ROOT / "docs" / "walkthrough" / "frames"
OUT = ROOT / "docs" / "walkthrough"

TARGET_WIDTH = 800
MOVE_FRAMES = 8      # frames the pointer travels
RIPPLE_FRAMES = 6    # frames of the click ripple
FADE_FRAMES = 2      # frames the pointer fades out at the end of a scene
HOLD_FRAMES = 18     # frames the scene rests on screen
PADDING = 44         # caption strip height at the bottom

CURSOR_SIZE = 26

CAPTIONS = {
    "01_dashboard_idle": "1. Dashboard - live CPU, memory and swap gauges",
    "02_dashboard_scanned": "2. Scan everything - every module is measured, nothing is touched",
    "03_cleaner_list": "3. Cleaner - click to open the review list",
    "04_confirm_dialog": "4. Clean selected - always confirms before moving a single byte",
    "05_cleaned": "5. Done - freed bytes reported, nothing is ever unlinked",
    "06_quarantine": "6. Quarantine - click to see every file still recoverable",
    "07_duplicates": "7. Duplicate finder - SHA-256, never file names",
    "08_duplicates_confirm": "8. Delete the rest - one original is always kept",
    "09_settings": "9. Settings - safety window, retention and diagnostics",
    "10_crimson_dashboard": "10. Theme switch - deep crimson for danger-heavy work",
    "11_arabic_dashboard": "11. Arabic - full right-to-left localisation",
    "12_arabic_cleaner": "12. Arabic cleaner - the whole interface, not a subset",
    "13_narrow_layout": "13. Phone layout - the same app on a narrow window",
}

GROUPS = [
    (
        "walkthrough-1-dashboard-and-cleaner.gif",
        ["01_dashboard_idle", "02_dashboard_scanned", "03_cleaner_list",
         "04_confirm_dialog", "05_cleaned"],
        "OmniClean Engine - dashboard and cleaner walkthrough",
    ),
    (
        "walkthrough-2-quarantine-and-duplicates.gif",
        ["06_quarantine", "07_duplicates", "08_duplicates_confirm"],
        "OmniClean Engine - quarantine and duplicate finder",
    ),
    (
        "walkthrough-3-settings-themes-languages.gif",
        ["09_settings", "10_crimson_dashboard", "11_arabic_dashboard",
         "12_arabic_cleaner", "13_narrow_layout"],
        "OmniClean Engine - settings, themes and languages",
    ),
]

ACCENT = (16, 185, 129)


@dataclass
class Scene:
    name: str
    image: Image.Image
    click: tuple[int, float] | None


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else ""),
        "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def load_scene(name: str, size: tuple[int, int]) -> Scene:
    path = FRAMES / f"{name}.png"
    if not path.exists():
        raise SystemExit(f"missing frame: {path}")
    image = Image.open(path).convert("RGB")
    width = TARGET_WIDTH
    height = round(image.height * width / image.width)
    image = image.resize((width, height), Image.LANCZOS)
    canvas = Image.new("RGB", (width, height + PADDING), (0, 0, 0))
    canvas.paste(image, (0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([0, height, width, height + PADDING], fill=(3, 10, 8))
    draw.line([0, height, width, height], fill=(14, 40, 32), width=1)
    return Scene(name=name, image=canvas, click=None)


def pointer_mask(size: int = CURSOR_SIZE) -> Image.Image:
    """A classic arrow pointer drawn on a transparent canvas."""
    pointer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pen = ImageDraw.Draw(pointer)
    outline = [
        (2, 0), (2, 1), (2, 2), (2, 3), (2, 4), (2, 5), (2, 6), (2, 7),
        (2, 8), (2, 9), (2, 10), (2, 11), (2, 12), (2, 13), (2, 14), (2, 15),
        (2, 16), (2, 17), (2, 18), (2, 19), (3, 20), (4, 19), (5, 18), (6, 17),
        (7, 16), (8, 15), (9, 14), (10, 13), (11, 12), (12, 11), (13, 10),
        (14, 9), (15, 8), (16, 7), (17, 6), (18, 5), (19, 4), (19, 3), (19, 2),
        (19, 1), (19, 0),
    ]
    pen.polygon(outline, fill=(255, 255, 255, 255), outline=(10, 10, 10, 255))
    pen.line([(2, 0), (2, 20), (19, 4), (2, 0)], fill=(12, 12, 12, 255))
    return pointer


def composite(scene: Scene, cursor: tuple[int, float] | None, opacity: int,
              ripple: float) -> Image.Image:
    frame = scene.image.copy()
    if ripple > 0:
        overlay = Image.new("RGBA", frame.size, (0, 0, 0, 0))
        pen = ImageDraw.Draw(overlay)
        cx, cy = scene.click
        radius = 10 + ripple * 34
        alpha = max(0, int(210 * (1 - ripple)))
        pen.ellipse(
            [cx - radius, cy - radius, cx + radius, cy + radius],
            outline=(ACCENT[0], ACCENT[1], ACCENT[2], alpha), width=3,
        )
        fill = max(0, int(120 * (1 - ripple)))
        pen.ellipse(
            [cx - radius * 0.45, cy - radius * 0.45,
             cx + radius * 0.45, cy + radius * 0.45],
            fill=(ACCENT[0], ACCENT[1], ACCENT[2], fill),
        )
        frame = Image.alpha_composite(frame.convert("RGBA"), overlay).convert("RGB")
    if cursor is not None and opacity > 0:
        mark = pointer_mask()
        if opacity < 255:
            alpha = mark.getchannel("A").point(lambda v: int(v * opacity / 255))
            mark.putalpha(alpha)
        frame_rgba = frame.convert("RGBA")
        frame_rgba.alpha_composite(mark, (int(cursor[0]), int(cursor[1])))
        frame = frame_rgba.convert("RGB")
    return frame


def scene_frames(scene: Scene, previous_click, index: int, first: bool):
    """Yields the frames that belong to one scene."""
    hold = HOLD_FRAMES
    if scene.click is None:
        for _ in range(hold):
            yield composite(scene, previous_click, 255, 0)
        return

    start = previous_click or (scene.click[0] - 240, scene.click[1] - 180)
    for step in range(MOVE_FRAMES):
        t = (step + 1) / MOVE_FRAMES
        eased = 1 - (1 - t) ** 3
        x = start[0] + (scene.click[0] - start[0]) * eased
        y = start[1] + (scene.click[1] - start[1]) * eased
        yield composite(scene, (x, y), 255, 0)
    for step in range(RIPPLE_FRAMES):
        yield composite(scene, scene.click, 255, (step + 1) / RIPPLE_FRAMES)
    for step in range(FADE_FRAMES):
        yield composite(scene, scene.click, int(255 * (1 - (step + 1) / FADE_FRAMES)), 0)
    for _ in range(hold):
        yield composite(scene, previous_click if first else scene.click, 255, 0)


def caption(frame: Image.Image, text: str, number: int) -> Image.Image:
    out = frame.copy()
    pen = ImageDraw.Draw(out)
    title_font = load_font(15, bold=True)
    sub_font = load_font(11)
    baseline = frame.height - PADDING
    right = f"OmniClean Engine  ·  {number}"
    right_width = pen.textlength(right, font=sub_font)
    room = frame.width - 28 - right_width - 16
    while pen.textlength(text, font=title_font) > room and len(text) > 8:
        text = text[:-2]
    pen.text((14, baseline + 7), text, font=title_font, fill=(226, 245, 239))
    pen.text(
        (frame.width - 14, baseline + 10),
        right,
        font=sub_font,
        fill=(104, 146, 134),
        anchor="ra",
    )
    return out


def build(name: str, scene_names: list[str], title: str) -> None:
    manifest = json.loads((OUT / "scenes.json").read_text())
    clicks = {}
    for entry in manifest["scenes"]:
        image = Path(entry["image"]).name
        clicks[image[:-4]] = tuple(entry["click"]) if entry.get("click") else None

    raw = [load_scene(scene, (TARGET_WIDTH, 0)) for scene in scene_names]
    order = {name: number for number, name in enumerate(scene_names, start=1)}
    global_order = {
        Path(entry["image"]).name[:-4]: number
        for number, entry in enumerate(manifest["scenes"], start=1)
    }
    frames = []
    cursor = None
    for index, scene in enumerate(raw):
        scene.click = clicks.get(scene.name)
        drawn = list(scene_frames(scene, cursor, index, index == 0))
        label = global_order.get(scene.name, order.get(scene.name, index + 1))
        for position, frame in enumerate(drawn):
            frames.append(
                caption(frame, CAPTIONS.get(scene.name, scene.name), label)
            )
        cursor = scene.click if scene.click else cursor

    # One shared palette for the whole clip: a per-frame palette would make the
    # dark background crawl between frames.
    samples = [frames[i] for i in range(0, len(frames), max(1, len(frames) // 6))][:6]
    strip = Image.new("RGB", (samples[0].width // 4, samples[0].height * len(samples) // 4))
    for position, sample in enumerate(samples):
        strip.paste(
            sample.resize((sample.width // 4, sample.height // 4), Image.BILINEAR),
            (0, position * sample.height // 4),
        )
    palette = strip.quantize(colors=200, method=Image.MEDIANCUT)

    indexed = [frame.quantize(palette=palette, dither=Image.FLOYDSTEINBERG)
               for frame in frames]

    duration = round(1000 * 6 / 100)
    indexed[0].save(
        OUT / name,
        save_all=True,
        append_images=indexed[1:],
        duration=duration,
        loop=0,
        optimize=False,
        disposal=1,
    )
    size = (OUT / name).stat().st_size / (1024 * 1024)
    print(f"{name}: {len(indexed)} frames, "
          f"{raw[0].image.width}x{raw[0].image.height}, {size:.1f} MB")


if __name__ == "__main__":
    if not (OUT / "scenes.json").exists():
        raise SystemExit("run test/walkthrough_test.dart first")
    OUT.mkdir(parents=True, exist_ok=True)
    for gif_name, scenes, _title in GROUPS:
        build(gif_name, scenes, _title)
