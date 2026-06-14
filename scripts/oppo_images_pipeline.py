#!/usr/bin/env python3
import argparse
import csv
import json
import re
import shutil
import struct
import sys
import time
from pathlib import Path
from urllib.error import URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen


CATEGORY_API_URL = "https://www.opposhop.cn/cn/oapi/goods-business/category/goods"
DETAIL_API_URL = "https://store.oppo.com/cn/oapi/cms-business/goods/switch"
IMAGE_PATTERN = re.compile(r"https?://[^\s\"'<>]+?\.(?:png|jpe?g|webp|gif)(?:\?[^\s\"'<>]*)?", re.I)
TARGET_SIZES = {(1440, 1440)}
SUPPORTED_SUFFIXES = {".png", ".webp", ".gif", ".jpg", ".jpeg"}
METADATA_FILE_NAME = "image_metadata.json"
DEVICE_MARKERS = (
    "真无线降噪蓝牙耳机",
    "真无线蓝牙耳机",
    "真无线降噪耳机",
    "真无线耳机",
    "蓝牙耳机",
    "耳机",
)


class ImageInfoError(Exception):
    pass


def request_json(url: str, timeout: int = 20) -> dict:
    request = Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/json,text/plain,*/*",
            "Connection": "close",
        },
    )
    with urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def request_bytes(url: str, timeout: int = 30, retries: int = 3) -> bytes:
    last_error = None
    for attempt in range(1, retries + 1):
        try:
            request = Request(
                url,
                headers={
                    "User-Agent": "Mozilla/5.0",
                    "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
                    "Connection": "close",
                },
            )
            with urlopen(request, timeout=timeout) as response:
                return response.read()
        except URLError as error:
            last_error = error
            time.sleep(min(attempt, 3))
    raise last_error


def fetch_goods(category_code: str, page_size: int) -> list[dict]:
    query = urlencode(
        {
            "scene": "mall",
            "categoryCode": category_code,
            "pageIndex": 1,
            "pageSize": page_size,
        }
    )
    payload = request_json(f"{CATEGORY_API_URL}?{query}")
    if payload.get("code") != 200:
        raise RuntimeError(payload.get("message") or payload)
    return payload.get("data", [])


def goods_name_map(goods: list[dict]) -> dict[str, str]:
    result = {}
    for item in goods:
        sku_id = str(item.get("skuId") or "")
        sku_name = item.get("skuName") or item.get("spuName") or sku_id
        if sku_id:
            result[sku_id] = sku_name
    return result


def fetch_detail_payload(sku_id: str) -> dict:
    query = urlencode(
        {
            "interfaceVersion": "v2",
            "pageCode": "skuDetail",
            "skuId": sku_id,
        }
    )
    payload = request_json(f"{DETAIL_API_URL}?{query}")
    if payload.get("code") != 200:
        raise RuntimeError(f"{sku_id}: {payload.get('message') or payload}")
    return payload


def collect_images(value) -> list[str]:
    result = []

    def walk(node):
        if isinstance(node, dict):
            for item in node.values():
                walk(item)
            return
        if isinstance(node, list):
            for item in node:
                walk(item)
            return
        if isinstance(node, str):
            result.extend(match.group(0) for match in IMAGE_PATTERN.finditer(node))

    walk(value)
    return list(dict.fromkeys(result))


def source_key_from_url(url: str) -> str:
    return Path(urlparse(url).path).stem


def source_key_from_path(path: Path) -> str:
    return re.sub(r"^\d+_", "", path.stem)


def file_name_for(index: int, url: str) -> str:
    path = urlparse(url).path
    suffix = Path(path).suffix or ".jpg"
    stem = Path(path).stem or "image"
    return f"{index:03d}_{stem[:80]}{suffix}"


def download_sku_images(sku_id: str, payload: dict, raw_dir: Path, overwrite: bool) -> tuple[int, list[str]]:
    urls = collect_images(payload)
    sku_dir = raw_dir / sku_id
    sku_dir.mkdir(parents=True, exist_ok=True)

    failed = []
    downloaded = 0
    for index, url in enumerate(urls, 1):
        target = sku_dir / file_name_for(index, url)
        if target.exists() and not overwrite:
            continue
        try:
            target.write_bytes(request_bytes(url))
            downloaded += 1
        except Exception as error:
            failed.append(url)
            print(f"[warn] {sku_id}: 下载失败 {url} ({error})", file=sys.stderr)

    return downloaded, failed


def add_image_metadata(
    metadata: dict[tuple[str, str], list[dict[str, str]]],
    sku_id: str,
    url,
    device: str,
    color,
    variant_sku_id=None,
    source: str = "",
) -> None:
    if not url or not color:
        return
    key = (sku_id, source_key_from_url(url))
    metadata.setdefault(key, []).append(
        {
            "skuId": sku_id,
            "variantSkuId": variant_sku_id or "",
            "device": device,
            "color": color,
            "source": source,
            "sourceUrl": url,
        }
    )


def build_detail_metadata(sku_id: str, payload: dict, device: str) -> dict[tuple[str, str], dict[str, str]]:
    data = payload.get("data", {}).get("_$data", {})
    candidates: dict[tuple[str, str], list[dict[str, str]]] = {}
    sku_colors = {}

    for item in data.get("attributeList", []) or []:
        variant_sku_id = item.get("skuId")
        attributes = item.get("attributes") or {}
        color = attributes.get("key1") or next(iter(attributes.values()), "")
        if variant_sku_id and color:
            variant_sku_id = str(variant_sku_id)
            sku_colors[variant_sku_id] = color
            add_image_metadata(candidates, sku_id, item.get("spuImageUrl"), device, color, variant_sku_id, "attribute.spuImageUrl")
            add_image_metadata(candidates, sku_id, item.get("skuImageUrl"), device, color, variant_sku_id, "attribute.skuImageUrl")

        for group in item.get("value") or []:
            for option in group.get("list") or []:
                option_color = option.get("_$text1") or option.get("_$text")
                add_image_metadata(candidates, sku_id, option.get("imageUrl"), device, option_color, None, "attribute.option.imageUrl")
            for option in group.get("preList") or []:
                option_color = option.get("_$text") or option.get("_$text1")
                add_image_metadata(candidates, sku_id, option.get("_$url"), device, option_color, None, "attribute.preList.url")

    for item in data.get("showcaseList", []) or []:
        variant_sku_id = str(item.get("skuId") or "")
        color = sku_colors.get(variant_sku_id)
        for image in item.get("list") or []:
            add_image_metadata(
                candidates,
                sku_id,
                image.get("_$url") or image.get("imageUrl"),
                device,
                color,
                variant_sku_id,
                "showcaseList",
            )

    result = {}
    for key, items in candidates.items():
        colors = {item["color"] for item in items if item.get("color")}
        if len(colors) == 1:
            result[key] = items[0]
    return result


def write_image_metadata(raw_dir: Path, metadata: dict[tuple[str, str], dict[str, str]]) -> None:
    output = {}
    for (sku_id, source_key), value in sorted(metadata.items()):
        output.setdefault(sku_id, {})[source_key] = value
    target = raw_dir / METADATA_FILE_NAME
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")


def read_png_info(data: bytes) -> tuple[int, int, bool]:
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ImageInfoError("不是 PNG 文件")

    offset = 8
    width = height = None
    has_alpha = False

    while offset + 8 <= len(data):
        length = int.from_bytes(data[offset : offset + 4], "big")
        chunk_type = data[offset + 4 : offset + 8]
        chunk_data_start = offset + 8
        chunk_data_end = chunk_data_start + length
        if chunk_data_end + 4 > len(data):
            raise ImageInfoError("PNG 数据不完整")

        chunk_data = data[chunk_data_start:chunk_data_end]
        if chunk_type == b"IHDR":
            if len(chunk_data) < 13:
                raise ImageInfoError("PNG IHDR 不完整")
            width, height = struct.unpack(">II", chunk_data[:8])
            color_type = chunk_data[9]
            has_alpha = color_type in (4, 6)
        elif chunk_type == b"tRNS":
            has_alpha = True
        elif chunk_type == b"IDAT":
            break

        offset = chunk_data_end + 4

    if width is None or height is None:
        raise ImageInfoError("未找到 PNG 尺寸")
    return width, height, has_alpha


def read_webp_info(data: bytes) -> tuple[int, int, bool]:
    if len(data) < 16 or data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        raise ImageInfoError("不是 WebP 文件")

    offset = 12
    width = height = None
    has_alpha = False

    while offset + 8 <= len(data):
        chunk_type = data[offset : offset + 4]
        chunk_size = int.from_bytes(data[offset + 4 : offset + 8], "little")
        chunk_data_start = offset + 8
        chunk_data_end = chunk_data_start + chunk_size
        chunk_data = data[chunk_data_start:chunk_data_end]
        if chunk_data_end > len(data):
            raise ImageInfoError("WebP 数据不完整")

        if chunk_type == b"VP8X":
            if len(chunk_data) < 10:
                raise ImageInfoError("WebP VP8X 不完整")
            has_alpha = bool(chunk_data[0] & 0x10)
            width = int.from_bytes(chunk_data[4:7], "little") + 1
            height = int.from_bytes(chunk_data[7:10], "little") + 1
        elif chunk_type == b"ALPH":
            has_alpha = True
        elif chunk_type == b"VP8 ":
            if len(chunk_data) < 10:
                raise ImageInfoError("WebP VP8 不完整")
            width = int.from_bytes(chunk_data[6:8], "little") & 0x3FFF
            height = int.from_bytes(chunk_data[8:10], "little") & 0x3FFF
        elif chunk_type == b"VP8L":
            if len(chunk_data) < 5 or chunk_data[0] != 0x2F:
                raise ImageInfoError("WebP VP8L 不完整")
            bits = int.from_bytes(chunk_data[1:5], "little")
            width = (bits & 0x3FFF) + 1
            height = ((bits >> 14) & 0x3FFF) + 1
            has_alpha = True

        offset = chunk_data_end + (chunk_size % 2)

    if width is None or height is None:
        raise ImageInfoError("未找到 WebP 尺寸")
    return width, height, has_alpha


def read_gif_info(data: bytes) -> tuple[int, int, bool]:
    if not (data.startswith(b"GIF87a") or data.startswith(b"GIF89a")):
        raise ImageInfoError("不是 GIF 文件")
    if len(data) < 10:
        raise ImageInfoError("GIF 数据不完整")
    width, height = struct.unpack("<HH", data[6:10])
    return width, height, b"\x21\xf9\x04" in data


def read_jpeg_info(data: bytes) -> tuple[int, int, bool]:
    if not data.startswith(b"\xff\xd8"):
        raise ImageInfoError("不是 JPEG 文件")

    offset = 2
    while offset + 9 <= len(data):
        if data[offset] != 0xFF:
            offset += 1
            continue
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            break

        marker = data[offset]
        offset += 1
        if marker in (0xD8, 0xD9):
            continue
        if offset + 2 > len(data):
            break

        segment_length = int.from_bytes(data[offset : offset + 2], "big")
        if segment_length < 2 or offset + segment_length > len(data):
            break
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            if segment_length < 7:
                raise ImageInfoError("JPEG SOF 不完整")
            height = int.from_bytes(data[offset + 3 : offset + 5], "big")
            width = int.from_bytes(data[offset + 5 : offset + 7], "big")
            return width, height, False
        offset += segment_length

    raise ImageInfoError("未找到 JPEG 尺寸")


def read_image_info(path: Path) -> tuple[int, int, bool]:
    data = path.read_bytes()
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return read_png_info(data)
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return read_webp_info(data)
    if data.startswith(b"GIF87a") or data.startswith(b"GIF89a"):
        return read_gif_info(data)
    if data.startswith(b"\xff\xd8"):
        return read_jpeg_info(data)
    raise ImageInfoError("不支持的图片格式")


def image_suffix(path: Path) -> str:
    data = path.read_bytes()[:16]
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return ".webp"
    if data.startswith(b"GIF87a") or data.startswith(b"GIF89a"):
        return ".gif"
    if data.startswith(b"\xff\xd8"):
        return ".jpg"
    return path.suffix.lower()


def filter_alpha_images(
    raw_dir: Path,
    alpha_dir: Path,
    metadata=None,
    require_metadata: bool = False,
) -> tuple[int, int, int, int]:
    copied = 0
    skipped = 0
    failed = 0
    missing_metadata = 0

    for source in sorted(raw_dir.rglob("*")):
        if not source.is_file() or source.suffix.lower() not in SUPPORTED_SUFFIXES:
            continue

        try:
            width, height, has_alpha = read_image_info(source)
        except Exception as error:
            failed += 1
            print(f"[warn] 跳过无法识别的图片: {source} ({error})", file=sys.stderr)
            continue

        if (width, height) not in TARGET_SIZES or not has_alpha:
            skipped += 1
            continue

        source_key = (source.parent.name, source_key_from_path(source))
        if require_metadata and (not metadata or source_key not in metadata):
            missing_metadata += 1
            continue

        target = alpha_dir / source.relative_to(raw_dir)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        copied += 1

    return copied, skipped, failed, missing_metadata


def clear_images(directory: Path) -> None:
    if not directory.exists():
        return
    for path in directory.rglob("*"):
        if path.is_file() and path.suffix.lower() in SUPPORTED_SUFFIXES:
            path.unlink()


def safe_name(value: str) -> str:
    value = re.sub(r"[\\/:*?\"<>|]", " ", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value or "未命名商品"


def flatten_named_images(
    alpha_dir: Path,
    named_dir: Path,
    metadata: dict[tuple[str, str], dict[str, str]],
    names: dict[str, str],
) -> tuple[int, list[str], int]:
    copied = 0
    missing_names = []
    skipped = 0
    counters: dict[tuple[str, str], int] = {}

    for sku_dir in sorted(path for path in alpha_dir.iterdir() if path.is_dir()):
        sku_id = sku_dir.name
        if sku_id not in names:
            missing_names.append(sku_id)

        files = sorted(
            path
            for path in sku_dir.iterdir()
            if path.is_file() and path.suffix.lower() in SUPPORTED_SUFFIXES
        )
        for source in files:
            info = metadata.get((sku_id, source_key_from_path(source)))
            if not info:
                skipped += 1
                continue
            device = safe_name(info["device"])
            color = safe_name(info["color"])
            key = (device, color)
            counters[key] = counters.get(key, 0) + 1
            target_name = f"{device}__{color}_{counters[key]:03d}{image_suffix(source)}"
            target = named_dir / target_name
            named_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            copied += 1

    return copied, missing_names, skipped


def product_name_from_image(path: Path) -> str:
    return re.sub(r"_\d+\.[^.]+$", "", path.name)


def split_device_color(product_name: str) -> tuple[str, str]:
    value = re.sub(r"\s+", " ", product_name).strip()
    value = re.sub(r"\s*官方标配$", "", value).strip()
    if "__" in value:
        device, color = value.split("__", 1)
        return device.strip(), color.strip()

    for marker in DEVICE_MARKERS:
        token = f" {marker} "
        if token in value:
            device, color = value.split(token, 1)
            return device.strip(), color.strip()

    parts = value.rsplit(" ", 1)
    if len(parts) == 2:
        return parts[0].strip(), parts[1].strip()
    return value, ""


def device_color_rows(image_dir: Path) -> list[dict[str, object]]:
    groups = {}
    for source in sorted(image_dir.iterdir()):
        if not source.is_file() or source.suffix.lower() not in SUPPORTED_SUFFIXES:
            continue

        product_name = product_name_from_image(source)
        device, color = split_device_color(product_name)
        key = (product_name, device, color)
        if key not in groups:
            groups[key] = {
                "productName": product_name,
                "device": device,
                "color": color,
                "imageCount": 0,
                "files": [],
            }
        groups[key]["imageCount"] += 1
        groups[key]["files"].append(source.name)

    return list(groups.values())


def resolve_map_path(image_dir: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return image_dir / path


def write_device_color_map(image_dir: Path, csv_path: Path, json_path: Path) -> int:
    rows = device_color_rows(image_dir)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.parent.mkdir(parents=True, exist_ok=True)

    with csv_path.open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=["productName", "device", "color", "imageCount"])
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    "productName": row["productName"],
                    "device": row["device"],
                    "color": row["color"],
                    "imageCount": row["imageCount"],
                }
            )

    json_path.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    return len(rows)


def resolve_sku_ids(args, goods: list[dict]) -> list[str]:
    if args.sku_ids:
        return args.sku_ids
    return [str(item["skuId"]) for item in goods if item.get("skuId")]


def goods_device_map(goods: list[dict]) -> dict[str, str]:
    result = {}
    for item in goods:
        sku_id = str(item.get("skuId") or "")
        sku_name = item.get("skuName") or item.get("spuName") or sku_id
        if sku_id:
            device, _ = split_device_color(sku_name)
            result[sku_id] = device
    return result


def write_failed_downloads(raw_dir: Path, failed_downloads: dict[str, list[str]]) -> None:
    if not failed_downloads:
        return
    failed_file = raw_dir / "failed_downloads.json"
    failed_file.parent.mkdir(parents=True, exist_ok=True)
    failed_file.write_text(json.dumps(failed_downloads, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[warn] 部分图片下载失败，已写入 {failed_file}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("sku_ids", nargs="*", help="不传则自动使用分类接口返回的全部 SKU")
    parser.add_argument("--target", choices=("raw", "alpha", "named", "map"), default="named")
    parser.add_argument("--category-code", default="003925")
    parser.add_argument("--page-size", type=int, default=50)
    parser.add_argument("--raw-dir", default="oppo_images")
    parser.add_argument("--alpha-dir", default="oppo_alpha_images")
    parser.add_argument("--named-dir", default="oppo_alpha_images_named")
    parser.add_argument("--map-source-dir", default="")
    parser.add_argument("--map-csv", default="device_color_map.csv")
    parser.add_argument("--map-json", default="device_color_map.json")
    parser.add_argument("--no-download", action="store_true", help="跳过下载，直接使用 raw-dir 里的已有图片")
    parser.add_argument("--overwrite", action="store_true", help="重新下载并覆盖 raw-dir 里已有的同名图片")
    args = parser.parse_args()

    raw_dir = Path(args.raw_dir)
    alpha_dir = Path(args.alpha_dir)
    named_dir = Path(args.named_dir)

    if args.target == "map":
        map_source_dir = Path(args.map_source_dir) if args.map_source_dir else named_dir
        row_count = write_device_color_map(
            map_source_dir,
            resolve_map_path(map_source_dir, args.map_csv),
            resolve_map_path(map_source_dir, args.map_json),
        )
        print(f"设备颜色记录: {row_count}")
        print(f"输出目录: {map_source_dir}")
        return 0

    goods = fetch_goods(args.category_code, args.page_size)
    names = goods_name_map(goods)
    devices = goods_device_map(goods)
    sku_ids = resolve_sku_ids(args, goods)
    if not sku_ids:
        raise SystemExit("没有可处理的 SKU")

    if args.no_download and not raw_dir.is_dir():
        raise SystemExit(f"输入原图目录不存在: {raw_dir}")

    total_downloaded = 0
    failed_downloads = {}
    detail_payloads = {}
    metadata = {}
    for sku_id in sku_ids:
        payload = fetch_detail_payload(sku_id)
        detail_payloads[sku_id] = payload
        metadata.update(build_detail_metadata(sku_id, payload, devices.get(sku_id) or split_device_color(names.get(sku_id, sku_id))[0]))
    if raw_dir.is_dir():
        write_image_metadata(raw_dir, metadata)

    if not args.no_download:
        for sku_id in sku_ids:
            downloaded, failed = download_sku_images(sku_id, detail_payloads[sku_id], raw_dir, args.overwrite)
            total_downloaded += downloaded
            if failed:
                failed_downloads[sku_id] = failed
        write_failed_downloads(raw_dir, failed_downloads)
        print(f"下载新增图片: {total_downloaded}")

    if args.target == "raw":
        print(f"输出目录: {raw_dir}")
        return 0

    clear_images(alpha_dir)
    copied, skipped, failed, missing_metadata = filter_alpha_images(
        raw_dir,
        alpha_dir,
        metadata,
        require_metadata=args.target == "named",
    )
    print(f"Alpha 图片: {copied}")
    print(f"已跳过: {skipped}")
    print(f"识别失败: {failed}")
    print(f"无颜色映射: {missing_metadata}")

    if args.target == "alpha":
        print(f"输出目录: {alpha_dir}")
        return 0

    if not alpha_dir.is_dir():
        raise SystemExit(f"Alpha 目录不存在: {alpha_dir}")

    clear_images(named_dir)
    named_count, missing_names, skipped_named = flatten_named_images(alpha_dir, named_dir, metadata, names)
    print(f"已复制并重命名: {named_count}")
    print(f"命名阶段跳过: {skipped_named}")
    print(f"输出目录: {named_dir}")
    if missing_names:
        print(f"[warn] 以下 SKU 未在分类接口中找到名称: {', '.join(missing_names)}", file=sys.stderr)
    row_count = write_device_color_map(
        named_dir,
        resolve_map_path(named_dir, args.map_csv),
        resolve_map_path(named_dir, args.map_json),
    )
    print(f"设备颜色记录: {row_count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
