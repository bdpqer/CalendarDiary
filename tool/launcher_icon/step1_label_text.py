# -*- coding: utf-8 -*-
"""
Step 1: 在抠好的透明前景上定位白色标签，绘制 Calendar / DIARY 两行文字。
输出:
  foreground_text.png  2048 透明前景（带文字）
  preview_label.png    标签定位核验图
"""
import os
from PIL import Image, ImageDraw, ImageFont
import numpy as np

BASE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BASE, "foreground_cut.png")
OUT_FG = os.path.join(BASE, "foreground_text.png")
OUT_PREVIEW = os.path.join(BASE, "preview_label.png")

FONT_BOLD = r"C:\Windows\Fonts\arialbd.ttf"
TEXT_COLOR = (26, 26, 26, 255)  # 近黑，比纯黑柔和


def find_components(mask):
    """两遍扫描 + union-find，返回 (labels, parent_count)。mask: bool HxW"""
    h, w = mask.shape
    labels = np.zeros((h, w), dtype=np.int32)
    parent = [0]

    def find(x):
        root = x
        while parent[root] != root:
            root = parent[root]
        while parent[x] != root:
            parent[x], x = root, parent[x]
        return root

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)

    next_id = 1
    ys, xs = np.nonzero(mask)
    for y, x in zip(ys.tolist(), xs.tolist()):
        up = labels[y - 1, x] if y > 0 else 0
        left = labels[y, x - 1] if x > 0 else 0
        if up and left:
            m = min(up, left)
            labels[y, x] = m
            union(up, left)
        elif up:
            labels[y, x] = up
        elif left:
            labels[y, x] = left
        else:
            labels[y, x] = next_id
            parent.append(next_id)
            next_id += 1
    # 扁平化
    flat = np.zeros(next_id, dtype=np.int32)
    for i in range(1, next_id):
        flat[i] = find(i)
    return labels, flat


def detect_label(im):
    """返回标签在原图坐标系中的 bbox (x0,y0,x1,y1)"""
    rgba = np.array(im)
    # 在 1/2 尺度上做连通域，加速
    scale = 2
    small = im.resize((im.width // scale, im.height // scale), Image.LANCZOS)
    a = np.array(small)
    white = (a[..., 0] > 238) & (a[..., 1] > 238) & (a[..., 2] > 238) & (a[..., 3] > 180)
    labels, flat = find_components(white)
    # 统计每个连通块面积与 bbox
    stats = {}
    ys, xs = np.nonzero(labels)
    for lab, y, x in zip(flat[labels[ys, xs]].tolist(), ys.tolist(), xs.tolist()):
        s = stats.get(lab)
        if s is None:
            stats[lab] = [1, x, y, x, y]
        else:
            s[0] += 1
            s[1] = min(s[1], x); s[2] = min(s[2], y)
            s[3] = max(s[3], x); s[4] = max(s[4], y)
    candidates = []
    for lab, (area, x0, y0, x1, y1) in stats.items():
        w, h = x1 - x0 + 1, y1 - y0 + 1
        fill = area / (w * h)
        candidates.append((area, w, h, fill, x0, y0, x1, y1))
    candidates.sort(reverse=True)
    print("白色连通块 Top 8 (small-coords):")
    for c in candidates[:8]:
        print("  area=%d w=%d h=%d fill=%.2f bbox=(%d,%d,%d,%d)" % c)
    # 标签：面积大、宽>150、高>150、填充率>0.8、横向偏宽
    label = None
    for c in candidates:
        area, w, h, fill, x0, y0, x1, y1 = c
        if w > 150 and h > 150 and fill > 0.80 and 0.7 < w / h < 2.0:
            label = c
            break
    if label is None:
        raise RuntimeError("未检测到标签白色区域")
    _, _, _, _, x0, y0, x1, y1 = label
    # 映射回原图
    box = (x0 * scale, y0 * scale, (x1 + 1) * scale, (y1 + 1) * scale)
    print("检测到标签 bbox (full):", box)
    return box


def fit_font(text, max_w, max_h, start_ratio=1.0):
    """按高度上限和宽度上限自适应字号，返回 (font, size)"""
    size = int(max_h * start_ratio)
    while size > 6:
        f = ImageFont.truetype(FONT_BOLD, size)
        tb = f.getbbox(text)
        w = tb[2] - tb[0]
        h = tb[3] - tb[1]
        if w <= max_w and h <= max_h:
            return f, size, tb
        size -= 2
    raise RuntimeError("字号收敛失败: " + text)


def draw_text_centered(draw, cx, cy, text, font, tbbox, fill):
    """以几何中心居中绘制（getbbox 有偏移，需补偿）"""
    w = tbbox[2] - tbbox[0]
    h = tbbox[3] - tbbox[1]
    x = cx - w / 2 - tbbox[0]
    y = cy - h / 2 - tbbox[1]
    draw.text((x, y), text, font=font, fill=fill)


def main():
    im = Image.open(SRC).convert("RGBA")
    print("源图:", im.size)
    box = detect_label(im)
    x0, y0, x1, y1 = box
    bw, bh = x1 - x0, y1 - y0

    # ---- 定位核验预览 ----
    preview = im.copy()
    d = ImageDraw.Draw(preview)
    d.rectangle(box, outline=(255, 0, 0, 255), width=8)
    preview.resize((512, 512), Image.LANCZOS).save(OUT_PREVIEW)

    # ---- 绘制两行文字 ----
    canvas = im.copy()
    draw = ImageDraw.Draw(canvas)

    pad_x = bw * 0.10
    pad_y = bh * 0.10
    inner_w = bw - 2 * pad_x
    inner_h = bh - 2 * pad_y
    # 下行 DIARY 大、上行 Calendar 小；行距约为内高 8%
    gap = inner_h * 0.10
    h_cal = inner_h * 0.32
    h_diary = inner_h * 0.52
    f_cal, s_cal, tb_cal = fit_font("Calendar", inner_w * 0.92, h_cal)
    f_diary, s_diary, tb_diary = fit_font("DIARY", inner_w * 0.95, h_diary)
    print("字号 Calendar=%d  DIARY=%d" % (s_cal, s_diary))

    cx = (x0 + x1) / 2
    cy_cal = y0 + pad_y + h_cal / 2
    cy_diary = y0 + pad_y + h_cal + gap + h_diary / 2
    draw_text_centered(draw, cx, cy_cal, "Calendar", f_cal, tb_cal, TEXT_COLOR)
    draw_text_centered(draw, cx, cy_diary, "DIARY", f_diary, tb_diary, TEXT_COLOR)

    canvas.save(OUT_FG)
    print("已保存:", OUT_FG)
    # 文字效果预览（512）
    canvas.resize((512, 512), Image.LANCZOS).save(os.path.join(BASE, "preview_text.png"))
    print("已保存预览: preview_text.png / preview_label.png")


if __name__ == "__main__":
    main()
