# -*- coding: utf-8 -*-
"""检查构建出的 APK 中图标资源是否齐全。"""
import zipfile
import os

apk = r"D:\project\CalendarDiary\build\app\outputs\flutter-apk\app-debug.apk"
print("APK:", apk, "exists:", os.path.exists(apk),
      "size:", os.path.getsize(apk) if os.path.exists(apk) else "-")

need = ["ic_launcher.xml", "ic_launcher_round.xml", "ic_launcher_foreground",
        "ic_launcher_monochrome", "ic_launcher_background", "ic_launcher.png"]
with zipfile.ZipFile(apk) as z:
    names = z.namelist()
    hits = [n for n in names if "ic_launcher" in n or "ic_launcher_background" in n]
    for h in sorted(hits):
        print(" ", h)
    print("---")
    missing = [k for k in need if not any(k in h for h in hits)]
    print("缺失:", missing if missing else "无，全部图标资源已打包")

    # 检查 Manifest 中是否有 roundIcon（二进制 XML，直接看字节特征）
    manifest = z.read("AndroidManifest.xml")
    print("AndroidManifest 含 roundIcon 字符串:", b"roundIcon" in manifest)
