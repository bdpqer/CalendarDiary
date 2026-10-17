# -*- coding: utf-8 -*-
"""
Step 2: 由带文字的透明前景生成全套 Android 启动图标资源。
输出到 tool/launcher_icon/out/（核验后再复制进工程）。

资源:
  mipmap-<dpi>/ic_launcher.png            方形 legacy 48/72/96/144/192
  mipmap-<dpi>/ic_launcher_round.png      圆形 legacy 同尺寸
  mipmap-<dpi>/ic_launcher_foreground.png 自适应前景 108/162/216/324/432
  mipmap-<dpi>/ic_launcher_monochrome.png Android13 主题图标剪影 同前景尺寸
  mipmap-anydpi-v26/ic_launcher{,_round}.xml
  drawable/ic_launcher_background.xml
  icon_512_play.png                       Play 商店 512x512
  preview_adaptive_masks.png / preview_legacy.png  核验图
"""
import os
import math
from PIL import Image, ImageDraw, ImageFont
import numpy as np

BASE = os.path.dirname(os.path.abspath(__file__))
FG = os.path.join(BASE, "foreground_text.png")
OUT = os.path.join(BASE, "out")

# 暖橙渐变背景（左上 -> 右下）
BG_TOP = (255, 247, 236)   # #FFF7EC
BG_BOTTOM = (255, 214, 168)  # #FFD6A8

DPI = {
    "mdpi": 1,
    "hdpi": 1.5,
    "xhdpi": 2,
    "xxhdpi": 3,
    "xxxhdpi": 4,
}
LEGACY_BASE = 48
FG_BASE = 108

# 几何参数（以 108dp 自适应画布为基准）
SAFE_DIAMETER_DP = 66          # 核心内容安全圈
CORE_MAX_RATIO = 0.58          # 核心主体略小于 66dp 安全圈(0.611)，留少量余量
LEGACY_SQUARE_RATIO = 0.82     # 方形 legacy 主体占画布比例（按较大边）
LEGACY_ROUND_RATIO = 0.70      # 圆形 legacy 主体高度占比（避免角部被裁）
STORE_RATIO = 0.80


def ensure_dir(p):
    os.makedirs(p, exist_ok=True)


def make_bg(size):
    """对角线（左上到右下）暖橙渐变位图。"""
    w = h = size
    c0 = np.array(BG_TOP, dtype=np.float32)
    c1 = np.array(BG_BOTTOM, dtype=np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = (xx + yy) / (w + h - 2)
    grad = c0[None, None, :] * (1 - t[..., None]) + c1[None, None, :] * t[..., None]
    return Image.fromarray(grad.astype(np.uint8), "RGB")


def alpha_bbox(im, threshold=200):
    a = np.array(im.getchannel("A"))
    ys, xs = np.where(a >= threshold)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def alpha_bbox_soft(im, threshold=16):
    a = np.array(im.getchannel("A"))
    ys, xs = np.where(a >= threshold)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def fit_subject(im, canvas_px, subject_ratio, soft_bbox=None, core_bbox=None):
    """把主体等比缩放到画布中心。
    subject_ratio: 核心 bbox 较大边占画布边长比例。
    以核心 bbox 定缩放，软 bbox（含阴影）跟随，可能超出（允许）。
    返回新 RGBA 画布。
    """
    canvas = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
    cx0, cy0, cx1, cy1 = core_bbox
    cw, ch = cx1 - cx0, cy0 - cy0
    scale = canvas_px * subject_ratio / max(cw, ch)
    new_w = int(round(im.width * scale))
    new_h = int(round(im.height * scale))
    big = im.resize((new_w, new_h), Image.LANCZOS)
    # 核心 bbox 缩放后中心与画布中心对齐
    core_cx = ((cx0 + cx1) / 2) * scale
    core_cy = ((cy0 + cy1) / 2) * scale
    pos = (int(round(canvas_px / 2 - core_cx)), int(round(canvas_px / 2 - core_cy)))
    canvas.alpha_composite(big, pos)
    return canvas


def apply_circle_mask(im, diameter_ratio=1.0, bg=None):
    """圆形 mask：diameter_ratio 为圆直径占画布边长比例。"""
    size = im.width
    base = bg.convert("RGBA") if bg is not None else Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if bg is not None:
        base.alpha_composite(im)
    else:
        base = im.copy()
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    r = size * diameter_ratio / 2
    d.ellipse((size / 2 - r, size / 2 - r, size / 2 + r, size / 2 + r), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)
    return out


def make_foreground(size, fg, core_bbox, ratio=CORE_MAX_RATIO, soft_bbox=None):
    return fit_subject(fg, size, ratio, soft_bbox=soft_bbox, core_bbox=core_bbox)


def make_monochrome(fg_canvas):
    """alpha 通道 -> 白色剪影。"""
    a = fg_canvas.getchannel("A")
    mono = Image.new("RGBA", fg_canvas.size, (255, 255, 255, 0))
    mono.putalpha(a)
    return mono


def rounded_rect_mask(size, radius_ratio=0.22):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    r = int(size * radius_ratio)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return mask


def squircle_mask(size):
    """近似水滴/超椭圆 mask（用四次超椭圆）。"""
    w = h = size
    n = 5
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx - (w - 1) / 2) / ((w - 1) / 2)
    ny = (yy - (h - 1) / 2) / ((h - 1) / 2)
    inside = (np.abs(nx) ** n + np.abs(ny) ** n) <= 1.0
    return Image.fromarray((inside * 255).astype(np.uint8), "L")


def main():
    fg = Image.open(FG).convert("RGBA")
    print("前景源:", fg.size)
    core = alpha_bbox(fg, 200)
    soft = alpha_bbox_soft(fg, 16)
    print("核心 bbox(alpha>=200):", core, " 尺寸:", (core[2] - core[0], core[3] - core[1]))
    print("软 bbox(alpha>=16):", soft, " 尺寸:", (soft[2] - soft[0], soft[3] - soft[1]))

    # 取封面主色（用于核对背景协调性）
    arr = np.array(fg)
    orange = (arr[..., 0] > 180) & (arr[..., 0] < 235) & (arr[..., 1] > 90) & (arr[..., 1] < 160) & (arr[..., 2] < 90) & (arr[..., 3] > 200)
    if orange.any():
        sample = arr[orange][:, :3].mean(axis=0).astype(int)
        print("封面主色采样 RGB:", tuple(sample.tolist()))

    for dpi, mult in DPI.items():
        d = os.path.join(OUT, "mipmap-" + dpi)
        ensure_dir(d)
        legacy_px = int(LEGACY_BASE * mult)
        fg_px = int(FG_BASE * mult)

        # 自适应前景（核心内容入 66dp 安全圈）
        fg_canvas = make_foreground(fg_px, fg, core, soft_bbox=soft)
        fg_canvas.save(os.path.join(d, "ic_launcher_foreground.png"))

        # monochrome 剪影
        make_monochrome(fg_canvas).save(os.path.join(d, "ic_launcher_monochrome.png"))

        # 方形 legacy：渐变底 + 主体 90%
        bg = make_bg(legacy_px)
        sq = fit_subject(fg, legacy_px, LEGACY_SQUARE_RATIO, core_bbox=core)
        bg.paste(sq, (0, 0), sq)
        bg.save(os.path.join(d, "ic_launcher.png"))

        # 圆形 legacy：渐变底 + 主体 78%，再裁圆
        bg2 = make_bg(legacy_px)
        rd = fit_subject(fg, legacy_px, LEGACY_ROUND_RATIO, core_bbox=core)
        bg2.paste(rd, (0, 0), rd)
        circle = apply_circle_mask(bg2.convert("RGBA"), 1.0)
        circle.save(os.path.join(d, "ic_launcher_round.png"))

    # Play 商店 512
    bg512 = make_bg(512)
    s512 = fit_subject(fg, 512, STORE_RATIO, core_bbox=core)
    bg512.paste(s512, (0, 0), s512)
    bg512.save(os.path.join(OUT, "icon_512_play.png"))

    # ---- 自适应图标多蒙版预览（432 画布）----
    fg432 = make_foreground(432, fg, core, soft_bbox=soft)
    bg432 = make_bg(432).convert("RGBA")
    composited = Image.alpha_composite(bg432, fg432)
    circle_mask = Image.new("L", (432, 432), 0)
    ImageDraw.Draw(circle_mask).ellipse((0, 0, 431, 431), fill=255)
    masks = [
        ("square", Image.new("L", (432, 432), 255)),
        ("circle", circle_mask),
        ("rounded", rounded_rect_mask(432, 0.22)),
        ("squircle", squircle_mask(432)),
    ]
    preview = Image.new("RGBA", (432 * 4 + 40 * 5, 432 + 80), (235, 235, 235, 255))
    draw = ImageDraw.Draw(preview)
    try:
        f = ImageFont.truetype(r"C:\Windows\Fonts\arialbd.ttf", 26)
    except Exception:
        f = ImageFont.load_default()
    names = ["Square", "Circle", "RoundedSquare", "Squircle"]
    for i, (name, mask) in enumerate(masks):
        x = 40 + i * (432 + 40)
        tile = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
        tile.paste(composited, (0, 0), mask)
        preview.alpha_composite(tile, (x, 40))
        tb = draw.textbbox((0, 0), names[i], font=f)
        draw.text((x + 216 - (tb[2] - tb[0]) / 2, 4), names[i], font=f, fill=(40, 40, 40, 255))
    preview.convert("RGB").save(os.path.join(BASE, "preview_adaptive_masks.png"))

    # ---- legacy 预览（xxxhdpi 192 方形/圆形 + 安全区叠加）----
    prev2 = Image.new("RGBA", (192 * 3 + 40 * 4, 192 + 40), (235, 235, 235, 255))
    sq192 = Image.open(os.path.join(OUT, "mipmap-xxxhdpi", "ic_launcher.png")).convert("RGBA")
    rd192 = Image.open(os.path.join(OUT, "mipmap-xxxhdpi", "ic_launcher_round.png")).convert("RGBA")
    fg192 = make_foreground(192, fg, core, soft_bbox=soft)
    bg192 = make_bg(192).convert("RGBA")
    ad192 = Image.alpha_composite(bg192, fg192)
    d2 = ImageDraw.Draw(ad192)
    d2.ellipse((192 / 2 - 192 * 0.611 / 2, 192 / 2 - 192 * 0.611 / 2,
                192 / 2 + 192 * 0.611 / 2, 192 / 2 + 192 * 0.611 / 2),
               outline=(255, 0, 0, 200), width=2)
    prev2.alpha_composite(sq192, (40, 20))
    prev2.alpha_composite(rd192, (40 * 2 + 192, 20))
    prev2.alpha_composite(ad192, (40 * 3 + 192 * 2, 20))
    prev2.convert("RGB").save(os.path.join(BASE, "preview_legacy.png"))

    print("全部资源已输出到:", OUT)


if __name__ == "__main__":
    main()
