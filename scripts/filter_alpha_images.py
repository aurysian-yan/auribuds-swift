#!/usr/bin/env python3
import argparse
import shutil
import struct
import sys
from pathlib import Path


TARGET_SIZES = {(1440, 1440)}
SUPPORTED_SUFFIXES = {".png", ".webp", ".gif", ".jpg", ".jpeg"}


class ImageInfoError(Exception):
    pass


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


def unique_target_path(path: Path) -> Path:
    if not path.exists():
        return path

    for index in range(1, 10000):
        target = path.with_name(f"{path.stem}_{index}{path.suffix}")
        if not target.exists():
            return target
    raise RuntimeError(f"无法生成唯一文件名: {path}")


def filter_images(input_dir: Path, output_dir: Path, flat: bool) -> tuple[int, int, int]:
    copied = 0
    skipped = 0
    failed = 0

    for source in sorted(input_dir.rglob("*")):
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

        if flat:
            relative_name = "__".join(source.relative_to(input_dir).parts)
            target = unique_target_path(output_dir / relative_name)
        else:
            target = output_dir / source.relative_to(input_dir)

        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        copied += 1

    return copied, skipped, failed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", nargs="?", default="oppo_images")
    parser.add_argument("output_dir", nargs="?", default="oppo_alpha_images")
    parser.add_argument("--flat", action="store_true", help="复制到单层目录，并用原路径拼接文件名")
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    if not input_dir.is_dir():
        raise SystemExit(f"输入目录不存在: {input_dir}")

    copied, skipped, failed = filter_images(input_dir, output_dir, args.flat)
    print(f"已复制: {copied}")
    print(f"已跳过: {skipped}")
    print(f"识别失败: {failed}")
    print(f"输出目录: {output_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
