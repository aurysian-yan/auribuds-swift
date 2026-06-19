<div align="center">

<picture>
  <source
    media="(prefers-color-scheme: dark)"
    srcset="./assets/dark-mode-image.png"
  >
  <source
    media="(prefers-color-scheme: light)"
    srcset="./assets/light-mode-image.png"
  >
  <img
    alt="AuriBuds App Icon"
    src="./assets/default-image.png"
    width="456"
  >
</picture>

**swiftUI 轻量级耳机控制工具**

无需官方 App，在你的 Apple 设备上上查看 OPPO / OnePlus / realme / 小米 等品牌蓝牙耳机的电量、控制降噪模式。

</div>

---

## 功能特性

- **电池监控** — 实时显示左耳、右耳及充电盒电量，支持充电状态检测
- **降噪控制** — 切换 关闭 / 通透 / 降噪 三种模式
- **自动发现** — 蓝牙连接时自动识别耳机，无需手动配置 (only macOS)
- **菜单栏组件** — 常驻菜单栏，随时查看状态和控制降噪
- **连接弹窗** — 耳机连接时弹出半透明通知，3 秒自动消失 (only macOS)

## 支持的设备

| 品牌 | 协议 |
|------|------|
| OPPO / OnePlus / realme / Enco | RFCOMM 经典蓝牙协议 |
| 小米 / Redmi / POCO / MiBuds | BLE GATT + SPP 协议 |

## 系统要求

- macOS 26+ (Tahoe)
- iOS 26+
- Xcode 26+
- 蓝牙适配器（Mac 内置蓝牙即可）

## 安装

### 从源码构建

```bash
git clone https://github.com/aurysian/AuriBuds.git
cd AuriBuds
open AuriBuds.xcodeproj
```

在 Xcode 中选择 `AuriBuds` scheme，设置开发团队后 Build (⌘B) 并 Run (⌘R)。

<details>

<summary>

## 项目结构

</summary>

```
AuriBuds/
├── Core/                               # 核心业务逻辑
│   ├── BluetoothMonitor.swift            蓝牙设备扫描与监控
│   ├── BluetoothHybridTransport.swift    混合传输层 (RFCOMM + BLE)
│   ├── OppoProtocol.swift                OPPO 耳机协议
│   ├── XiaomiProtocol.swift              小米耳机协议
│   ├── HeadphoneAdapter.swift            协议适配器注册
│   ├── EarbudsState.swift                耳机状态模型
│   ├── DeviceImageProvider.swift         设备图片匹配
│   └── ...                               更多核心模块
├── Views/                              # SwiftUI 视图
│   ├── MainWindowView.swift              主窗口 (NavigationSplitView)
│   ├── MenuBarContentView.swift          菜单栏下拉面板
│   ├── ANCModeSelector.swift             降噪模式选择器
│   ├── BatteryCardView.swift             电池卡片
│   ├── FindDeviceView.swift              设备查找页面
│   └── ...                               更多视图
├── ViewModels/
│   └── EarbudsViewModel.swift          # 主视图模型
├── Assets.xcassets/                    # 图片资源
└── AppIcon.icon/                       # App 图标

AuriBudsIOS/                            # iOS / iPadOS 配套应用
AuriBudsWidget/                         # WidgetKit 桌面小组件
Phase1RfcommPoC/                        # RFCOMM 协议验证原型
scripts/                                # 设备图片处理流水线
Release/                                # 发布相关文件
```

</details>

## 技术架构

- **UI 框架**: SwiftUI + AppKit (macOS) / UIKit (iOS)
- **蓝牙通信**: IOBluetooth (RFCOMM 经典蓝牙) + CoreBluetooth (BLE GATT)
- **响应式状态**: Combine + async/await
- **小组件**: WidgetKit + AppIntents
- **架构模式**: MVVM

## 致谢

OPPO 耳机部分逻辑基于[1812z/OppoPods](https://github.com/1812z/OppoPods)
- [Art-Chen/HyperPods](https://github.com/Art-Chen/HyperPods) — OppoPods 原始灵感项目
- [Leaf-lsgtky/OppoPods](https://github.com/Leaf-lsgtky/OppoPods) — OppoPods 协议参考

小米耳机部分感谢[leset0ng](https://github.com/leset0ng)和[Searchstars](https://github.com/Searchstars)
