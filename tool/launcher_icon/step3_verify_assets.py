# -*- coding: utf-8 -*-
"""核验 out/ 目录所有 PNG 尺寸与 alpha 通道。"""
from PIL import Image
import os

base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
legacy = {"mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
          "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192}
fg = {"mipmap-mdpi": 108, "mipmap-hdpi": 162, "mipmap-xhdpi": 216,
      "mipmap-xxhdpi": 324, "mipmap-xxxhdpi": 432}

ok = True
for d, s in legacy.items():
    p = os.path.join(base, d)
    checks = [
        ("ic_launcher.png", s, False),
        ("ic_launcher_round.png", s, True),
        ("ic_launcher_foreground.png", fg[d], True),
        ("ic_launcher_monochrome.png", fg[d], True),
    ]
    for name, exp, need_alpha in checks:
        fp = os.path.join(p, name)
        im = Image.open(fp)
        w, h = im.size
        amin, amax = im.getchannel("A").getextrema() if im.mode == "RGBA" else (255, 255)
        has_alpha = amin < 255
        good = (w == exp and h == exp and has_alpha == need_alpha)
        ok = ok and good
        print("%s/%s: %dx%d alpha=%s %s" % (d, name, w, h, has_alpha, "OK" if good else "FAIL"))

im = Image.open(os.path.join(base, "icon_512_play.png"))
good = im.size == (512, 512)
ok = ok and good
print("icon_512_play:", im.size, "OK" if good else "FAIL")

for xml in ["mipmap-anydpi-v26/ic_launcher.xml",
            "mipmap-anydpi-v26/ic_launcher_round.xml",
            "drawable/ic_launcher_background.xml"]:
    exists = os.path.exists(os.path.join(base, xml))
    ok = ok and exists
    print(xml, "OK" if exists else "MISSING")

print("ALL OK" if ok else "HAS FAILURES")
