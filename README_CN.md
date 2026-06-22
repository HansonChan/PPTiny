# PPTiny

[下载App](https://github.com/HansonChan/PPTiny/raw/main/dist/PPTiny-1.0.0-arm64.zip)

PPTiny 是一个用于一键压缩 PowerPoint 文件的轻量 macOS 应用。

当前版本：`1.0.0`

它支持通过拖拽或文件选择器导入一个或多个 `.pptx` 文件，并按队列顺序逐个压缩。压缩后的文件会保留原文件名，原始文件会自动改名为 `.old.pptx` 后缀。

## 功能特性

- 支持拖入一个或多个 PPTX 文件。
- 压缩前可查看文件队列。
- 支持从队列中移除文件。
- 多文件按顺序逐个压缩。
- 压缩后的文件保留原路径和原文件名。
- 原始文件会改名为 `name.old.pptx`，如有冲突则使用 `name.old-1.pptx`。
- 图片会缩放到 1080p 等价尺寸：
  - 横图：最高 `1920x1080`
  - 竖图：最高 `1080x1920`
- 非透明 PNG/BMP/TIFF 图片会转为 JPEG。
- 使用 macOS 原生 `AVFoundation` 压缩音视频，不依赖 `ffmpeg`。
- 移除 PowerPoint 内嵌字体以减小文件体积。
- 可识别云端占位文件，并提示用户先下载到本机。

## 环境要求

- Apple Silicon Mac
- macOS 14 或更高版本
- 不需要安装 `ffmpeg` 或 Homebrew

当前应用仅构建 `arm64` 版本，未包含 Intel Mac 支持。

## 构建

```bash
swift build
```

应用版本号由 `VERSION` 文件统一管理。构建脚本会把该值写入 `CFBundleShortVersionString`；`CFBundleVersion` 默认是 `1`，可通过 `BUILD_NUMBER` 覆盖。

## 运行

```bash
./script/build_and_run.sh
```

该脚本会构建 SwiftPM 应用，生成 `dist/PPTiny.app`，复制应用图标，执行 ad-hoc 签名，并启动应用。

## 应用包

运行构建脚本后，应用包位于：

```text
dist/PPTiny.app
```

应用包只包含应用可执行文件和图标。运行时的媒体压缩能力来自 macOS 系统框架。

## CLI 测试工具

项目包含一个 CLI target，可用于测试压缩核心逻辑：

```bash
swift run PPTinyCLI /path/to/file.pptx
```

CLI 与 macOS 应用使用同一套压缩器，并执行相同的原地替换逻辑。

## 隐私与 Git 维护

本仓库会刻意忽略本地文档、生成的演示文件、Office 文件、媒体文件、构建产物、应用包、本地 Codex 状态和签名材料。

请不要提交真实客户文档、云盘文件、压缩输出文件或签名凭据。

## 项目结构

```text
Sources/PPTiny/       SwiftUI macOS 应用
Sources/PPTinyCore/   PPTX 压缩核心
Sources/PPTinyCLI/    CLI 测试封装
Assets/AppIcon/       应用图标资源
script/               构建和运行脚本
tools/                图标生成工具
```
