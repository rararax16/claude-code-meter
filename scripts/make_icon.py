#!/usr/bin/env python3
"""
ClaudeCodeMeter のアプリアイコンを生成する。

デザイン:
  - macOS スクワークル背景 (Claude の暖色系オレンジ)
  - 中央に「減るリング」型のメーター (薄いトラック + 進捗弧)
  - 中央に小さな %記号もしくはミニドット

出力:
  scripts/build_icon/icon.iconset/  (Apple 規定のアイコンセット構造)
  Resources/AppIcon.icns            (iconutil で生成)
"""
import math
import os
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw

# Claude / Anthropic 系の暖色オレンジ
CLAUDE_ORANGE = (217, 119, 87, 255)        # #D97757 メイン
CLAUDE_ORANGE_DARK = (180, 88, 60, 255)    # 影/グラデ用
CREAM = (245, 240, 232, 255)               # 進捗弧
WHITE = (255, 255, 255, 255)
# トラック: 不透明の暗いオレンジ。半透明白だと PNG 保存時に alpha が残り
# 表示背景で見え方がブレるので、最初から不透明で「凹んだ溝」風の色にする。
TRACK = (165, 80, 55, 255)

BASE = 1024  # マスター解像度

def squircle_mask(size: int, radius_ratio: float = 0.225) -> Image.Image:
    """macOS 風の角丸正方形マスク。"""
    img = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(img)
    r = int(size * radius_ratio)
    draw.rounded_rectangle([(0, 0), (size - 1, size - 1)], radius=r, fill=255)
    return img

def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    """縦方向グラデーションを作って返す。"""
    img = Image.new("RGBA", (size, size), top)
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        r = int(top[0] * (1 - t) + bottom[0] * t)
        g = int(top[1] * (1 - t) + bottom[1] * t)
        b = int(top[2] * (1 - t) + bottom[2] * t)
        for x in range(size):
            px[x, y] = (r, g, b, 255)
    return img

def make_icon(size: int = BASE) -> Image.Image:
    # 1. スクワークル背景 + グラデ
    bg = vertical_gradient(size, CLAUDE_ORANGE, CLAUDE_ORANGE_DARK)
    mask = squircle_mask(size)
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(bg, (0, 0), mask)

    # 2. メーターのリング
    draw = ImageDraw.Draw(icon)
    cx = cy = size // 2
    # リング径とストローク幅は size に対する比率
    ring_diameter = int(size * 0.62)
    ring_stroke = int(size * 0.075)
    half = ring_diameter // 2
    bbox = [cx - half, cy - half, cx + half, cy + half]

    # 2a. 背景トラック (薄い白)
    draw.arc(bbox, start=0, end=360, fill=TRACK, width=ring_stroke)

    # 2b. 進捗 (使用量に応じて「増える」方向。アイコンでは 40% 使用済の表現に固定)
    # PIL の arc は 0° = 3時方向・時計回りに増加。
    # 12 時起点 (= 270°) から 時計回りに used*360°。360°ラップ時は 2 本に分けて描く
    # (PIL の arc は start>end を跨ぐと意図と逆の方向に描くケースがあるため)。
    used = 0.40
    sweep = 360 * used
    raw_end = 270 + sweep
    if raw_end <= 360:
        draw.arc(bbox, start=270, end=raw_end, fill=CREAM, width=ring_stroke)
    else:
        draw.arc(bbox, start=270, end=360, fill=CREAM, width=ring_stroke)
        draw.arc(bbox, start=0, end=raw_end - 360, fill=CREAM, width=ring_stroke)

    # 3. 中央のドット (リング中心を「焦点」にする小さなアクセント)
    dot_r = int(size * 0.06)
    draw.ellipse(
        [cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r],
        fill=CREAM,
    )

    # 4. 仕上げに角の柔らかい光沢 (左上から薄く)
    gloss = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(gloss)
    gdraw.ellipse(
        [int(size * -0.2), int(size * -0.4), int(size * 0.9), int(size * 0.5)],
        fill=(255, 255, 255, 18)
    )
    gloss.putalpha(Image.eval(gloss.split()[3], lambda a: a))
    gloss_masked = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gloss_masked.paste(gloss, (0, 0), mask)
    icon = Image.alpha_composite(icon, gloss_masked)

    return icon


def main():
    root = Path(__file__).resolve().parents[1]
    build = root / "scripts" / "build_icon"
    iconset = build / "AppIcon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)

    master = make_icon(BASE)

    # Apple 規定のサイズセット
    specs = [
        (16, "16x16", 1),
        (16, "16x16", 2),
        (32, "32x32", 1),
        (32, "32x32", 2),
        (128, "128x128", 1),
        (128, "128x128", 2),
        (256, "256x256", 1),
        (256, "256x256", 2),
        (512, "512x512", 1),
        (512, "512x512", 2),
    ]
    for size, name, scale in specs:
        px = size * scale
        suffix = "" if scale == 1 else "@2x"
        out = iconset / f"icon_{name}{suffix}.png"
        master.resize((px, px), Image.LANCZOS).save(out)
        print(f"  wrote {out.name}")

    # iconutil で .icns に固める
    icns = root / "Resources" / "AppIcon.icns"
    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset), "-o", str(icns)],
        check=True
    )
    print(f"\n✅ Generated: {icns}")

    # マスター 1024 PNG も保存 (Figma 等にエクスポートしたい時用)
    master_out = build / "icon-1024.png"
    master.save(master_out)
    print(f"   master: {master_out}")


if __name__ == "__main__":
    main()
