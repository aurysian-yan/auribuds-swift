# OPPO 图片提取脚本

## 主脚本

使用 `oppo_images_pipeline.py` 完成下载、筛选、按真实颜色重命名和生成设备颜色表。

```bash
cd scripts
python3 oppo_images_pipeline.py --target named --raw-dir oppo_images --alpha-dir oppo_alpha_images --named-dir output-images
```

## 输出规则

`output-images` 只保留满足以下条件的图片：

- 分辨率为 `1440x1440`
- 包含 Alpha 通道
- 能从商品详情接口明确映射到设备颜色

无法明确映射到颜色的图片会被跳过，避免文件名颜色和实际机身颜色不一致。

文件名格式：

```text
设备__颜色_序号.png
```

示例：

```text
OPPO Enco Air5s__月光白_001.png
OPPO Enco Air5s__暗夜黑_001.png
OPPO Enco Air5s__星光版 星光紫_001.png
```

## 重新生成设备颜色表

手动调整 `output-images` 后，只重新生成表：

```bash
python3 oppo_images_pipeline.py --target map --map-source-dir output-images
```

生成文件：

```text
output-images/device_color_map.csv
output-images/device_color_map.json
```

## 生成状态文件名和状态表

使用 macOS Vision 的图像特征模型对图片状态聚类，并输出带状态名的文件：

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/oppo_state_module_cache swift classify_image_states.swift --input-dir output-images --output-dir output-images-stated --clusters 4
```

输出文件名格式：

```text
设备__颜色__状态_序号.png
```

当前默认状态：

- `open_case`
- `earbuds_with_case`
- `closed_case`
- `earbuds_pair`

生成文件：

```text
output-images-stated/device_color_state_map.csv
output-images-stated/device_color_state_map.json
```

说明：Vision/Core ML 会由系统选择 CPU/GPU/Neural Engine 等执行路径；脚本不下载第三方模型。

如果 Vision 状态识别有误，编辑 `state_overrides.json`。Key 使用 `output-images` 里的原始文件名，Value 使用目标状态名：

```json
{
  "OPPO Enco Air4 新声版__冰透绿_003.png": "closed_case"
}
```

然后重新运行状态脚本和裁切脚本。

## 裁切透明边缘并统一尺寸

对带状态名的图片裁切透明边缘，输出 1:1 PNG。同一设备下相同状态会使用统一正方形边长。

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/oppo_trim_module_cache swift trim_square_images.swift --input-dir output-images-stated --output-dir output-images-trimmed
```

处理规则：

- 通过 Alpha 通道计算耳机主体边界
- 如果图片 Alpha 覆盖整张画布，会按四角背景色继续识别背景并裁切
- 正方形边长优先取主体宽度
- 如果主体高度大于宽度，则按高度取边长
- 同一 `设备 + 状态` 分组取组内最大边长，保证渲染尺寸统一

可调整纯色背景识别容差：

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/oppo_trim_module_cache swift trim_square_images.swift --input-dir output-images-stated --output-dir output-images-trimmed --background-tolerance 12
```

生成文件：

```text
output-images-trimmed/trim_report.csv
output-images-trimmed/trim_report.json
output-images-trimmed/device_color_state_map.csv
output-images-trimmed/device_color_state_map.json
```

## 常用参数

只下载原图：

```bash
python3 oppo_images_pipeline.py --target raw
```

只筛选 Alpha 图：

```bash
python3 oppo_images_pipeline.py --target alpha
```

使用已有原图，不重新下载：

```bash
python3 oppo_images_pipeline.py --no-download --target named --raw-dir oppo_images --alpha-dir oppo_alpha_images --named-dir output-images
```

重新下载并覆盖已有原图：

```bash
python3 oppo_images_pipeline.py --target named --raw-dir oppo_images --alpha-dir oppo_alpha_images --named-dir output-images --overwrite
```
