#!/usr/bin/env python3
"""
用英文设备名+颜色+状态 替代所有 Hash 文件名
命名规则: oppo_device_<model>_<color>_<state>.png
"""
import csv, json, os, shutil, re
from pathlib import Path

ASSETS = Path("AuriBuds/Assets.xcassets")
TRIMMED = Path("scripts/output-images-trimmed")
CATALOG_PATH = Path("AuriBuds/Core/DeviceImageCatalog.generated.swift")

# ========== 设备名映射 ==========
DEVICE_MAP = {
    "OPPO Enco Air4": "enco_air4",
    "OPPO Enco Air4 Pro": "enco_air4_pro",
    "OPPO Enco Air4 新声版": "enco_air4_new",
    "OPPO Enco Air4i": "enco_air4i",
    "OPPO Enco Air5": "enco_air5",
    "OPPO Enco Air5 Pro": "enco_air5_pro",
    "OPPO Enco Air5s": "enco_air5s",
    "OPPO Enco Clip2 开放式耳机": "enco_clip2",
    "OPPO Enco Free4": "enco_free4",
    "OPPO Enco R3 Pro": "enco_r3_pro",
    "OPPO Enco R4": "enco_r4",
    "OPPO Enco R5": "enco_r5",
    "OPPO Enco X3": "enco_x3",
    "一加 Buds 3V": "oneplus_buds_3v",
    "一加 Buds 4": "oneplus_buds_4",
    "一加 Buds Ace 2": "oneplus_buds_ace2",
    "一加 Buds Ace 3": "oneplus_buds_ace3",
}

# ========== 颜色名映射 ==========
COLOR_MAP = {
    "春绿": "spring_green",
    "霜白": "frost_white",
    "夜影灰": "night_gray",
    "晨曦白": "dawn_white",
    "云雾黑": "mist_black",
    "云雾白": "mist_white",
    "冰透绿": "ice_green",
    "排球少年!! 联名耳机": "haikyu_collab",
    "润玉白": "jade_white",
    "玄岩黑": "obsidian_black",
    "玉瓷白": "porcelain_white",
    "星釉白": "star_glaze_white",
    "暮云紫": "dusk_purple",
    "月珀白": "moon_amber_white",
    "雾夜黑": "fog_night_black",
    "星光版 星光紫": "starlight_purple",
    "暗夜黑": "dark_night_black",
    "月光白": "moonlight_white",
    "深空灰": "deep_space_gray",
    "高光金": "highlight_gold",
    "丹拿版 星瀚银": "dynaudio_star_silver",
    "水漾蓝": "water_blue",
    "珠光白": "pearl_white",
    "星闪白": "star_flash_white",
    "霜月白": "frost_moon_white",
    "米白": "cream_white",
    "雅黑": "elegant_black",
    "晨雾蓝": "morning_mist_blue",
    "极夜黑": "polar_night_black",
    "松影绿": "pine_green",
    "潜航黑": "deep_sea_black",
    "瞬影青": "flash_cyan",
    "星际黑": "interstellar_black",
    "钛空银": "titanium_silver",
}

# ========== 1. 删掉所有旧的 oppo_device_* 资产 ==========
print("🗑️  删除旧资产...")
deleted = 0
for entry in sorted(ASSETS.iterdir()):
    if entry.is_dir() and entry.name.endswith(".imageset") and entry.name.startswith("oppo_device_"):
        shutil.rmtree(entry)
        deleted += 1
        if deleted <= 5 or deleted % 20 == 0:
            print(f"  ✕ {entry.name}")
print(f"  删除 {deleted} 个旧资产\n")

# ========== 2. 读取 CSV, 复制图片到 Assets ==========
print("📁 复制图片到 Assets 并创建 .imageset...")

with open(TRIMMED / "device_color_state_map.csv", encoding="utf-8-sig") as f:
    rows = list(csv.DictReader(f))

catalog_entries = {}  # key: (device_cn, color_cn) -> info
copied = 0

for row in rows:
    device_cn = row["device"]
    color_cn = row["color"]
    state = row["state"]
    files = row["files"].split("|")

    model_en = DEVICE_MAP.get(device_cn)
    color_en = COLOR_MAP.get(color_cn)
    if not model_en or not color_en:
        print(f"  ⚠️  缺少映射: {device_cn} / {color_cn}")
        continue

    key = (device_cn, color_cn)
    for filename in files:
        filename = filename.strip()
        src = TRIMMED / filename
        if not src.exists():
            print(f"  ⚠️  文件不存在: {filename}")
            continue

        asset_name = f"oppo_device_{model_en}_{color_en}_{state}"
        imageset_dir = ASSETS / f"{asset_name}.imageset"
        imageset_dir.mkdir(parents=True, exist_ok=True)

        # 复制 PNG
        dst = imageset_dir / f"{asset_name}.png"
        shutil.copy2(src, dst)

        # 写 Contents.json
        contents = {
            "images": [
                {"filename": f"{asset_name}.png", "idiom": "universal", "scale": "1x"},
                {"idiom": "universal", "scale": "2x"},
                {"idiom": "universal", "scale": "3x"},
            ],
            "info": {"author": "xcode", "version": 1},
        }
        with open(imageset_dir / "Contents.json", "w") as cj:
            json.dump(contents, cj, indent=2)

        # 记录 catalog 信息
        if key not in catalog_entries:
            catalog_entries[key] = {
                "device_cn": device_cn,
                "color_cn": color_cn,
                "states": {},
            }
        # 只保留每个状态的第一个文件（就是 _001）
        if state not in catalog_entries[key]["states"]:
            catalog_entries[key]["states"][state] = asset_name

        copied += 1

print(f"  复制 {copied} 张图片\n")

# ========== 3. 生成新 Catalog ==========
print("📝 生成新 Catalog...")

# 按 device 分组排序
sorted_entries = sorted(catalog_entries.items(), key=lambda x: (
    list(DEVICE_MAP.keys()).index(x[0][0]) if x[0][0] in DEVICE_MAP else 999,
    x[0][1]
))

lines = [
    'import Foundation\n',
    '',
    'extension DeviceImageDescriptor {',
    '    static let generatedCatalog: [DeviceImageDescriptor] = [',
]

for (device_cn, color_cn), entry in sorted_entries:
    states = entry["states"]
    model_en = DEVICE_MAP.get(device_cn, device_cn)
    color_en = COLOR_MAP.get(color_cn, color_cn)

    primary = (
        states.get("open_case")
        or states.get("earbuds_with_case")
        or next(iter(states.values()), "unknown")
    )
    case = states.get("closed_case") or states.get("open_case") or primary
    pair = states.get("earbuds_pair")
    pair_str = f'"{pair}"' if pair else "nil"

    lines.append(f'''        DeviceImageDescriptor(
            productId: "{device_cn}",
            colorId: "{color_cn}",
            modelName: "{device_cn}",
            displayTitle: "{color_cn}",
            imageSet: DeviceImageSet(
                primary: "{primary}",
                caseImage: "{case}",
                leftBud: nil,
                rightBud: nil,
                pairImage: {pair_str}
            )
        ),''')

lines.append('    ]')
lines.append('}')
lines.append('')

with open(CATALOG_PATH, "w", encoding="utf-8") as f:
    f.write('\n'.join(lines))

print(f"  {len(catalog_entries)} 个设备色系写入 Catalog\n")

# ========== 4. 统计 ==========
total_assets = len([d for d in ASSETS.iterdir() if d.is_dir() and d.name.endswith(".imageset")])
print(f"✅ 完成! Assets 总数: {total_assets} 个")
