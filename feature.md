# PPTX 媒体压缩功能方案

## 背景

PPTX 文件经常因为直接粘贴超大图片、截图、设计稿或高清视频而迅速膨胀。用户在页面上看到的图片可能只有几百像素宽，但 PPTX 里保留的仍是原始大图，甚至还保留了被裁剪掉的区域；视频也可能以 4K、高码率或低压缩格式嵌入，成为文件体积的主要来源。Microsoft 官方的图片压缩入口主要围绕两件事：对图片降采样，以及删除裁剪区域。

本功能目标是在不改变幻灯片视觉布局的前提下，提供一个自动化压缩流程，把 PPTX 中过大的图片、视频和音频资源压到适合演示、分享或归档的体积。

## 调研结论

1. PPTX 可以作为 ZIP 包处理，内部图片、视频和音频通常存放在 `ppt/media/*`。因此压缩功能可以解包、识别媒体文件、重编码图片或转码音视频，再重新打包。
2. 仅调整 PowerPoint 中图片显示尺寸不会减少文件体积。真正减少体积需要替换嵌入的图片数据。
3. PowerPoint 的“Compress Pictures”功能支持应用到全文件、删除裁剪区域、选择目标分辨率；这是产品行为上的参考基准。
4. 裁剪后的图片默认仍保留隐藏区域，删除裁剪区域会进一步减小体积，但会牺牲后续恢复裁剪的能力。
5. 视频压缩应优先采用通用兼容的 MP4/H.264 输出，默认限制为不超过 `1080p`、视频码率不超过 `4 Mbps`，音频按 `128 Kbps`、`44.1 kHz` 转码，避免 4K 或高码率素材直接嵌入 PPTX。
6. 自动化压缩最稳妥的 MVP 是“按显示尺寸推算图片所需像素上限，对视频和音频按固定上限转码，然后替换 `ppt/media` 中的媒体文件”。高级版本再支持读取每个图片实例的裁剪参数，生成只保留可见区域的新图。

## 目标

- 显著降低由大图、高码率视频和高码率音频导致的 PPTX 文件体积。
- 默认不改变幻灯片上的图片位置、大小、层级、裁剪外观。
- 将嵌入视频压缩到不超过 `1080p`、视频码率不超过 `4 Mbps`。
- 将音频压缩到 `128 Kbps`、`44.1 kHz`。这里按常见音频采样率理解用户输入的 `44hz` 为 `44.1 kHz`，即 `44100 Hz`。
- 生成压缩报告，说明每个媒体文件的压缩前后大小、尺寸变化、格式变化和跳过原因。
- 支持安全回退：保留原文件，输出新文件。

## 非目标

- 不处理嵌入文件、OLE 对象的压缩。
- 不尝试重新设计幻灯片布局。
- MVP 不强制实现肉眼无损，只提供可配置质量档位。
- MVP 不处理 SVG、EMF、WMF 等矢量资源的栅格化压缩。

## 用户场景

### 场景 1：分享前一键瘦身

用户有一个几十到几百 MB 的 PPTX，希望压缩到适合邮件、飞书、微信或网盘预览的大小。

### 场景 2：批量处理生成结果

项目生成的多个 PPTX 都包含大图、视频或音频，发布前需要自动压缩。

### 场景 3：排查体积来源

用户想知道哪个图片、视频或音频导致文件巨大，并决定是否进一步压缩或替换。

## 推荐方案

采用“PPTX 包级媒体压缩器”：

```text
输入 PPTX
  -> 解包到临时目录
  -> 扫描 ppt/media 中的图片、视频和音频
  -> 解析 slide XML 和 relationship，建立媒体使用关系
  -> 计算每张图片的目标像素尺寸
  -> 使用 Pillow 降采样和重编码图片
  -> 使用 ffmpeg 转码视频到 1080p/4Mbps 上限
  -> 使用 ffmpeg 转码音频到 128Kbps/44.1kHz
  -> 替换媒体文件
  -> 更新必要的 Content Types
  -> 重新打包为新 PPTX
  -> 输出压缩报告
```

### 为什么不用只调用 PowerPoint

PowerPoint 自带压缩适合人工操作，但不适合服务端或批量自动化：依赖 Office 桌面环境，难以稳定集成到生成链路，也不方便产出结构化报告。包级处理可以跨平台运行，并能纳入 CLI、CI 或后处理流水线。

## 压缩策略

### 1. 图片识别

扫描 `ppt/media/*` 中的位图资源：

- 支持：JPEG、PNG、BMP、TIFF、GIF 首帧或静态 GIF。
- 默认跳过：SVG、EMF、WMF、ICO、未知格式。
- 对小图跳过：例如小于 `120 KB` 或原始尺寸低于目标尺寸。

### 2. 目标尺寸计算

按图片在幻灯片中的显示尺寸估算所需像素：

```text
target_px = displayed_inches * target_ppi * retina_factor
```

建议档位：

| 档位 | target_ppi | 适用场景 |
|---|---:|---|
| email | 96 | 邮件、聊天转发、快速预览 |
| screen | 150 | 普通投屏、线上会议 |
| hd | 220 | 高清屏展示、保留较好细节 |
| print | 300 | 打印或高质量归档 |

默认使用 `screen`，并设置 `retina_factor = 1.25`，避免细线截图和 UI 截图明显发虚。

如果同一媒体文件被多处引用，取所有引用中最大的目标尺寸，避免压缩后影响其他页面。

### 3. 格式选择

| 原格式/内容 | 推荐输出 | 原因 |
|---|---|---|
| 照片、复杂截图、无透明通道 PNG | JPEG | 体积通常明显小于 PNG |
| 有透明通道 PNG | PNG 优化，必要时保留原图 | JPEG 会丢透明 |
| BMP/TIFF | JPEG 或 PNG | Office 中常见体积浪费来源 |
| 已经很小的 JPEG | 保留 | 避免重复有损压缩 |
| 线稿、图标、少色块 UI | PNG | 避免 JPEG 边缘噪点 |

JPEG 质量建议：

- `email`: 72
- `screen`: 80
- `hd`: 86
- `print`: 92

PNG 使用优化保存；如后续引入 `pngquant` 或 `oxipng`，可作为可选增强。

### 4. 裁剪区域处理

MVP：

- 不改变 XML 裁剪参数。
- 只按图片最大显示尺寸降采样。
- 即使图片被裁剪，也先保留完整画面比例，确保视觉不变。

增强版：

- 解析 `a:srcRect` 中的 `l/t/r/b` 裁剪比例。
- 对仅被单一形状引用的图片，可以物理裁掉不可见区域，并清空或重写裁剪参数。
- 对被多处引用且裁剪不同的图片，复制生成多个媒体文件，并分别更新 relationship。

增强版收益更高，但会触碰 XML 结构和关系更新，建议放在第二阶段。

### 5. 视频压缩

扫描 `ppt/media/*` 中的视频资源：

- 支持：MP4、MOV、M4V、AVI、WMV、MKV 等常见容器。
- 推荐输出：MP4 容器、H.264 视频编码、AAC 音频编码。
- 默认分辨率上限：长边不超过 `1920`、短边不超过 `1080`，保持原始宽高比，不放大小视频。
- 默认视频码率上限：`4 Mbps`。
- 默认音频码率：`128 Kbps`，采样率 `44.1 kHz`，双声道。
- 已低于 `1080p` 且码率不高于 `4 Mbps` 的 MP4/H.264 视频可跳过。

ffmpeg 推荐参数：

```bash
ffmpeg -i input.mov \
  -vf "scale='min(1920,iw)':-2:force_original_aspect_ratio=decrease" \
  -c:v libx264 \
  -b:v 4M \
  -maxrate 4M \
  -bufsize 8M \
  -preset medium \
  -movflags +faststart \
  -c:a aac \
  -b:a 128k \
  -ar 44100 \
  -ac 2 \
  output.mp4
```

如果源视频是竖屏或其他比例，需要保证输出不超过 `1080 x 1920` 的等价上限。实现时应根据源宽高选择横屏或竖屏 scale 规则，避免竖屏视频被错误压到过宽。

### 6. 音频压缩

扫描 `ppt/media/*` 中的独立音频资源：

- 支持：MP3、M4A、WAV、AAC、AIFF、WMA 等常见音频格式。
- 推荐输出：M4A/AAC，优先保证 Office 兼容性；对已经兼容且低码率的 MP3 可保留原格式。
- 默认音频码率：`128 Kbps`。
- 默认采样率：`44.1 kHz`，即 `44100 Hz`。
- 默认声道：双声道；如果源文件是单声道，可保留单声道以进一步减小体积。
- 已低于 `128 Kbps` 且采样率不高于 `44.1 kHz` 的音频可跳过。

ffmpeg 推荐参数：

```bash
ffmpeg -i input.wav \
  -c:a aac \
  -b:a 128k \
  -ar 44100 \
  -ac 2 \
  output.m4a
```

### 7. 安全边界

- 不覆盖原文件，默认输出 `xxx.compressed.pptx`。
- 单张图片压缩后如果体积未减少至少 `5%`，保留原图。
- 单个视频压缩后如果体积未减少至少 `5%`，保留原视频。
- 单个音频压缩后如果体积未减少至少 `5%`，保留原音频。
- 保留 EXIF 方向处理，保存前应用正确旋转，避免方向错乱。
- 对 CMYK、调色板、带 alpha 图片做明确转换策略。
- 所有异常媒体只跳过并记录，不中断全文件压缩。
- 音视频转码失败、缺少 ffmpeg、编码格式不支持时只跳过并记录，不中断全文件压缩。

## CLI 设计

```bash
pptx-compress input.pptx \
  --output input.compressed.pptx \
  --profile screen \
  --video-max-short-edge 1080 \
  --video-bitrate 4M \
  --audio-bitrate 128k \
  --audio-sample-rate 44100 \
  --min-saving-ratio 0.05 \
  --report input.compression.json
```

参数：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `input` | 必填 | 输入 PPTX |
| `--output` | 自动生成 | 输出 PPTX |
| `--profile` | `screen` | `email/screen/hd/print` |
| `--target-ppi` | 跟随 profile | 手动覆盖目标 PPI |
| `--jpeg-quality` | 跟随 profile | 手动覆盖 JPEG 质量 |
| `--keep-alpha` | true | 透明图默认不转 JPEG |
| `--compress-video` | true | 是否压缩嵌入视频 |
| `--video-max-long-edge` | `1920` | 视频长边上限 |
| `--video-max-short-edge` | `1080` | 视频短边上限，即横屏不超过 1080p、竖屏不超过 1080x1920 |
| `--video-bitrate` | `4M` | 视频码率上限 |
| `--audio-bitrate` | `128k` | 音频码率 |
| `--audio-sample-rate` | `44100` | 音频采样率，单位 Hz |
| `--audio-channels` | `2` | 默认双声道 |
| `--video-codec` | `libx264` | 视频编码器 |
| `--audio-codec` | `aac` | 音频编码器 |
| `--delete-cropped-areas` | false | 第二阶段能力 |
| `--report` | 可选 | 输出 JSON 报告 |
| `--dry-run` | false | 只分析不写文件 |

## 报告格式

```json
{
  "input": "demo.pptx",
  "output": "demo.compressed.pptx",
  "original_bytes": 128430112,
  "compressed_bytes": 24899120,
  "saved_bytes": 103530992,
  "saved_ratio": 0.806,
  "images": [
    {
      "path": "ppt/media/image12.png",
      "action": "converted",
      "format_before": "PNG",
      "format_after": "JPEG",
      "size_before": 18432000,
      "size_after": 1320042,
      "dimensions_before": [6000, 4000],
      "dimensions_after": [2200, 1467],
      "max_display_inches": [11.0, 7.33],
      "reason": "downsampled_to_screen_profile"
    }
  ],
  "videos": [
    {
      "path": "ppt/media/media1.mov",
      "action": "transcoded",
      "format_before": "MOV",
      "format_after": "MP4",
      "codec_before": "prores",
      "codec_after": "h264",
      "size_before": 84233120,
      "size_after": 16341220,
      "dimensions_before": [3840, 2160],
      "dimensions_after": [1920, 1080],
      "video_bitrate_after": "4M",
      "audio_bitrate_after": "128k",
      "audio_sample_rate_after": 44100,
      "reason": "downsampled_to_1080p_4mbps"
    }
  ],
  "audios": [
    {
      "path": "ppt/media/media2.wav",
      "action": "transcoded",
      "format_before": "WAV",
      "format_after": "M4A",
      "codec_before": "pcm_s16le",
      "codec_after": "aac",
      "size_before": 24833120,
      "size_after": 2164020,
      "bitrate_before": "1411k",
      "bitrate_after": "128k",
      "sample_rate_before": 48000,
      "sample_rate_after": 44100,
      "channels_after": 2,
      "reason": "downsampled_to_128k_44100hz"
    }
  ],
  "skipped": [
    {
      "path": "ppt/media/image3.svg",
      "reason": "vector_format"
    }
  ]
}
```

## 实现要点

### 包处理

- 使用 Python 标准库 `zipfile` 读取和重新写入 PPTX。
- 只重写发生变化的媒体文件，其余文件原样复制。
- 重新打包时使用 `ZIP_DEFLATED`。

### XML 解析

需要读取：

- `ppt/slides/slide*.xml`
- `ppt/slides/_rels/slide*.xml.rels`
- `ppt/slideMasters/*` 和对应 `_rels`，用于母版媒体
- `ppt/slideLayouts/*` 和对应 `_rels`，用于版式媒体

核心关系：

- 在 slide XML 中找 `a:blip` 的 `r:embed`。
- 在 rels 中把图片 `rId` 映射到 `../media/imageX.ext`。
- 对视频，读取 `p:pic` 下的视频关系和 `ppt/media/mediaX.ext` 目标文件。
- 从媒体所在 shape 的 `a:xfrm/a:ext` 读取显示尺寸 EMU。

EMU 换算：

```text
1 inch = 914400 EMU
displayed_inches = emu / 914400
```

### 图片处理

- 使用 Pillow 打开图片。
- 根据目标像素上限等比缩小，不放大小图。
- JPEG 保存时使用 `quality`、`optimize=True`、`progressive=True`。
- PNG 保存时使用 `optimize=True`。
- 透明 PNG 只有在用户允许扁平化背景时才转 JPEG。

### 视频处理

- 使用 `ffprobe` 读取视频分辨率、时长、编码格式、码率、音频信息。
- 使用 `ffmpeg` 转码超过上限的视频。
- 输出固定为 MP4/H.264/AAC，视频不超过 `1080p/4Mbps`，音频按 `128k/44100Hz`，优先保证 PowerPoint、Keynote、WPS 的兼容性。
- 转码后需要更新 relationship 指向的新扩展名，并更新 `[Content_Types].xml` 中的 MIME 类型。
- 对已有 MP4/H.264 且不超过 `1080p/4Mbps` 的视频跳过。

### 音频处理

- 使用 `ffprobe` 读取音频格式、时长、编码格式、码率、采样率、声道数。
- 使用 `ffmpeg` 转码超过上限的独立音频文件。
- 默认输出 M4A/AAC，码率 `128k`，采样率 `44100 Hz`。
- 转码后需要更新 relationship 指向的新扩展名，并更新 `[Content_Types].xml` 中的 MIME 类型。
- 对已有兼容格式且不超过 `128k/44100Hz` 的音频跳过。

## 阶段计划

### Phase 1：分析与基础压缩

- 扫描 `ppt/media`。
- 解析图片、视频引用和显示尺寸。
- 支持 JPEG、PNG、BMP、TIFF 的降采样和重编码。
- 支持视频转码为不超过 `1080p`、`4 Mbps` 的 MP4/H.264。
- 支持音频转码为 `128 Kbps`、`44.1 kHz` 的 AAC/M4A。
- 输出新 PPTX 和 JSON 报告。
- 不删除裁剪区域。

验收标准：

- 对包含大图的 PPTX，文件体积可明显下降。
- 对包含 4K 或高码率视频的 PPTX，视频被压缩到不超过 `1080p/4Mbps`。
- 对包含高码率音频的 PPTX，音频被压缩到 `128k/44100Hz`。
- 幻灯片打开无报错。
- 图片位置、大小、裁剪外观不变。
- 视频位置、封面、播放行为不变。
- 音频播放触发方式和播放行为不变。
- 同一图片多处引用时按最大显示尺寸保真。

### Phase 2：裁剪区域物理删除

- 解析 `a:srcRect`。
- 支持单引用图片删除隐藏区域。
- 支持多引用图片拆分媒体文件。
- 更新 relationship 和 `[Content_Types].xml`。

验收标准：

- 被大幅裁剪的图片体积继续下降。
- 压缩后 PowerPoint 中图片视觉与压缩前一致。
- 报告能标记裁剪收益。

### Phase 3：质量评估与批量处理

- 支持目录批量压缩。
- 输出 Markdown/HTML 汇总报告。
- 增加图片前后视觉差异抽检、视频抽帧对比和音频播放抽检。
- 可配置最大输出文件大小，自动选择压缩档位。

## 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 透明 PNG 转 JPEG 后背景错误 | 视觉错误 | 默认保留透明 PNG |
| 图片被多处引用 | 某些页面变糊 | 取最大显示尺寸作为目标 |
| 裁剪 XML 复杂 | 压缩后画面错位 | 裁剪物理删除放到 Phase 2 |
| 视频转码后无法播放 | 演示中断 | 固定 MP4/H.264/AAC，增加压缩后播放兼容校验 |
| 视频封面或 poster 丢失 | 页面预览变化 | 只替换媒体文件，保留原 shape 和 poster 关系 |
| 音频转码后无法播放 | 演示中断 | 固定 AAC/M4A，增加压缩后播放兼容校验 |
| 音频采样率理解错误 | 音质异常 | 将用户的 `44hz` 解释为常见 `44.1 kHz/44100 Hz`，不使用不可用的 `44 Hz` |
| ffmpeg 不可用 | 视频无法压缩 | 启动时检测依赖，缺失时跳过视频并记录 |
| 4 Mbps 对细节运动不够 | 视频出现压缩块 | 允许 `--video-bitrate` 覆盖，默认满足文件体积优先 |
| 128 Kbps 对音乐细节不够 | 音质下降 | 允许 `--audio-bitrate` 覆盖，默认满足体积优先 |
| PowerPoint 兼容性 | 文件无法打开 | 保持包结构，增加压缩后打开校验 |
| 过度压缩截图 | 文字发虚 | 默认 `screen=150ppi` 加 1.25 系数，UI 图可保 PNG |
| 已压缩图片二次压缩 | 质量下降但收益小 | 小于最小收益阈值时回退原图 |

## 验收测试建议

准备 8 类样本：

1. 多张 4K/8K 照片粘贴的 PPTX。
2. 大尺寸 PNG 截图缩小显示的 PPTX。
3. 带透明 logo 和图标的 PPTX。
4. 同一图片在多页复用且显示尺寸不同的 PPTX。
5. 含裁剪图片的 PPTX。
6. 含 4K、高码率 MP4/MOV 视频的 PPTX。
7. 含竖屏视频和低码率视频的 PPTX。
8. 含 WAV、高码率 MP3/M4A、视频内音轨的 PPTX。

测试项：

- 输出文件能被 PowerPoint、Keynote、WPS 打开。
- 总体积、每张图片体积符合报告。
- 视频输出不超过 `1080p/4Mbps`，且能正常播放。
- 音频输出为 `128k/44100Hz`，且能正常播放。
- 页面截图对比无明显错位。
- `dry-run` 不产生输出文件。
- 异常图片或视频不会中断处理。

## 参考资料

- Microsoft Support: [Reduce the file size of your PowerPoint presentations](https://support.microsoft.com/en-us/office/reduce-the-file-size-of-your-powerpoint-presentations-9548ffd4-d853-41e7-8e40-b606bca036b4)
- Microsoft Support: [Crop a picture in Office](https://support.microsoft.com/en-us/office/crop-a-picture-in-office-14d69647-bc93-4f06-9528-df95103aa1e6)
- Microsoft Support: [PowerPoint Options Advanced](https://support.microsoft.com/en-au/office/powerpoint-options-advanced-bdbee278-4984-4c7d-88ad-6f493bd18343)
- Python docs: [zipfile - Work with ZIP archives](https://docs.python.org/3/library/zipfile.html)
- Pillow docs: [Image module](https://pillow.readthedocs.io/en/stable/reference/Image.html)
- FFmpeg docs: [ffmpeg Documentation](https://ffmpeg.org/ffmpeg.html)
- FFmpeg docs: [ffprobe Documentation](https://ffmpeg.org/ffprobe.html)
- python-pptx docs: [Working with images](https://scanny-python-pptx.mintlify.app/guides/images)
