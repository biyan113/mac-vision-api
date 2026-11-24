# Vision API

把 macOS 自带的本地能力（Apple Vision、PDFKit、Speech、Translation）封装成 RESTful 接口的自托管服务。所有处理都在本机完成，不依赖云服务，也不需要 Apple Intelligence。

Self-hosted REST API that exposes on-device macOS capabilities: OCR, image analysis, background removal, PDF, speech-to-text and translation.

## 功能

| 能力 | 接口 | 最低系统 |
|---|---|---|
| 文本识别（OCR），可返回行级坐标 | `POST /text-detection/recognize-text` | macOS 13 |
| OCR 支持的语言 | `GET /text-detection/supported-languages` | macOS 13 |
| 文档结构识别（段落、表格、邮箱、电话） | `POST /text-detection/recognize-document` | macOS 26 |
| 图像分类 | `POST /vision/classify` | macOS 13 |
| 物体检测（动物、人脸、人体） | `POST /vision/detect-objects` | macOS 13 |
| 条码 / 二维码 | `POST /vision/scan-barcode` | macOS 13 |
| 人脸关键点 | `POST /vision/detect-faces` | macOS 13 |
| 人体姿态 | `POST /vision/detect-body-pose` | macOS 13 |
| 手部姿态 | `POST /vision/detect-hand-pose` | macOS 13 |
| 显著性区域 | `POST /vision/saliency` | macOS 13 |
| 矩形 / 文档边界 | `POST /vision/detect-rectangles` | macOS 13 |
| 地平线角度 | `POST /vision/detect-horizon` | macOS 13 |
| 美学评分 | `POST /vision/aesthetics` | macOS 15 |
| 镜头污渍检测 | `POST /vision/lens-smudge` | macOS 26 |
| 背景移除 | `POST /image-feature/background-removal` | macOS 14 |
| PDF 渲染为 PNG | `POST /pdf/render` | macOS 13 |
| PDF 文本抽取 | `POST /pdf/extract-text` | macOS 13 |
| 语音转文字 | `POST /speech/transcribe` | macOS 26 |
| 翻译 | `POST /translation/translate` | macOS 26 |
| 当前可用能力 | `GET /capabilities` | — |
| 健康检查 | `GET /health` | — |

服务启动时按系统版本注册接口，`GET /capabilities` 会告诉你当前机器上哪些可用。完整的参数和返回格式见 [API_DOCUMENTATION.md](API_DOCUMENTATION.md)，或启动后访问 `http://localhost:8080/Swagger/index.html`。

## 安装

本服务只能运行在 macOS 上。后端依赖的系统框架在 Linux 上不存在，所以没有后端的 Docker 镜像。

### 方式一：下载预编译版本（Apple 芯片）

```bash
curl -fsSL https://raw.githubusercontent.com/biyan113/mac-vision-api/master/scripts/install.sh | bash
cd ~/.vision-api && ./vision-api serve --env production --hostname 127.0.0.1 --port 8080
```

发布包里带有 [Web 界面](#web-界面)，启动后访问 `http://localhost:8080/`。也可以到 [Releases](https://github.com/biyan113/mac-vision-api/releases) 手动下载 `vision-api-macos-arm64.tar.gz`。

### 方式二：从源码运行

需要 Xcode 16 或更高版本（Swift 6.0+）。要使用 macOS 26 的能力，需要用 Xcode 26 编译。

```bash
git clone https://github.com/biyan113/mac-vision-api
cd mac-vision-api
swift run App serve --hostname 127.0.0.1 --port 8080
```

### 方式三：作为 Swift 包嵌入自己的 Vapor 应用

```swift
// Package.swift
.package(url: "https://github.com/biyan113/mac-vision-api.git", from: "1.0.0")
// target dependencies
.product(name: "VisionAPI", package: "mac-vision-api")
```

```swift
import Vapor
import VisionAPI

let app = try await Application.make(.detect())
try await VisionAPI.configure(app, config: ServiceConfig(apiKey: "secret"))
try await app.execute()
```

`configure` 会安装 CORS、静态文件和可选的鉴权中间件并注册全部路由。只想要路由时调用 `try VisionAPI.routes(app)`。

### Web 界面的 Docker 镜像

后端跑在 Mac 上，Web 界面可以单独用容器运行，由 nginx 把 `/api/` 代理到后端：

```bash
docker run -d -p 3000:80 \
  -e VISION_API_UPSTREAM=http://host.docker.internal:8080 \
  ghcr.io/biyan113/mac-vision-api-web:latest
```

或者 `docker compose up -d`，然后访问 `http://localhost:3000`。后端要让容器访问到，需要用 `--hostname 0.0.0.0` 启动。

## 配置

通过环境变量配置，默认值偏向安全。

| 环境变量 | 默认 | 说明 |
|---|---|---|
| `VISION_API_KEY` | 未设置 | 设置后，除 `/health` 和静态文件外的接口都需要 `Authorization: Bearer <key>` 或 `X-API-Key: <key>` |
| `VISION_ALLOW_LOCAL_FILES` | `false` | 是否允许 `imagePath` / `pdfPath` / `audioPath` 读取服务器本地文件 |
| `VISION_ALLOW_PRIVATE_URLS` | `false` | 是否允许 `imageURL` 等参数访问回环和内网地址 |
| `VISION_MAX_BODY_SIZE` | `50mb` | 请求体大小上限 |

```bash
VISION_API_KEY=secret VISION_ALLOW_LOCAL_FILES=true ./vision-api serve --hostname 0.0.0.0 --port 8080
```

把服务绑定到 `0.0.0.0` 时，建议设置 `VISION_API_KEY`。内网地址拦截只检查 URL 里的字面地址，不解析 DNS。

## 使用示例

```bash
# OCR
curl -X POST http://localhost:8080/text-detection/recognize-text \
  -F imageFile=@photo.png -F recognitionLanguages=zh-Hans,en-US -F includeLines=true

# 背景移除
curl -X POST http://localhost:8080/image-feature/background-removal \
  -F imageFile=@photo.jpg -o result.png

# 二维码
curl -X POST http://localhost:8080/vision/scan-barcode -F imageURL=https://example.com/qr.png

# 语音转写（macOS 26+）
curl -X POST http://localhost:8080/speech/transcribe -F audioFile=@meeting.m4a -F locale=en-US

# 翻译（macOS 26+）
curl -X POST http://localhost:8080/translation/translate \
  -H 'Content-Type: application/json' \
  -d '{"text": "Hello, world", "targetLanguage": "zh-Hans"}'
```

图片类接口都接受四种输入之一：`imageFile`（上传）、`imageURL`、`imageBase64`、`imagePath`。PDF 和音频接口把前缀换成 `pdf` 和 `audio`。

## Web 界面

发布包自带 Web 界面，启动后访问 `http://localhost:8080/`。页面包括：

| 页面 | 用途 |
|---|---|
| OCR 文字识别 | 上传图片提取文字，可切换到位置视图查看每行文字在图片上的位置和置信度 |
| 文档结构识别 | 提取段落和表格，表格可导出 CSV |
| 图像分析 | 分类、物体与人脸检测、条码、姿态、显著性、矩形、地平线、美学评分、镜头污渍；检测位置直接标注在图片上 |
| 背景移除 | 生成透明背景 PNG |
| PDF 处理 | 渲染页面、抽取文本 |
| 语音转写 | 带时间戳的转写结果，可导出 TXT 和 SRT 字幕 |
| 翻译 | 文本翻译，源语言可自动检测 |

右上角的“API配置”可以改后端地址，后端设置了 `VISION_API_KEY` 时在这里填写密钥。当前系统不支持的功能会在对应页面给出提示。

## 可以搭建的工作流

单个接口解决的是一步，把它们串起来才是完整的活。下面是几类实用的组合。

| 目标 | 接口组合 |
|---|---|
| 扫描版 PDF 转成可搜索文本 | `/pdf/render` → `/text-detection/recognize-text` |
| 票据、报表图片转成表格 | `/text-detection/recognize-document` → CSV |
| 会议录音生成文字稿和双语稿 | `/speech/transcribe` → `/translation/translate` |
| 外文图片、菜单、截图翻译 | `/text-detection/recognize-text` → `/translation/translate` |
| 商品图批量抠图并自动打标签 | `/image-feature/background-removal` + `/vision/classify` |
| 从一批照片里挑出好照片 | `/vision/aesthetics` + `/vision/lens-smudge` |
| 拍照文档自动裁边和校正 | `/vision/detect-rectangles` + `/vision/detect-horizon`，按返回的角点和角度在客户端裁剪 |
| 人脸打码 | `/vision/detect-faces`，按返回的人脸框在客户端模糊 |
| 条码、二维码批量录入 | `/vision/scan-barcode` → CSV |
| 自动生成缩略图的裁剪区域 | `/vision/saliency`，以最显著的区域为中心裁剪 |

这些都可以接到 macOS 快捷指令、文件夹监听脚本或 n8n 这类自动化工具里，因为每一步只是一个 HTTP 请求。

下面的脚本需要 `curl` 和 `jq`，并假设 `API=http://localhost:8080`。

### 扫描版 PDF 转文本

PDF 没有文本层时，逐页渲染成图片再做 OCR。

```bash
pages=$(curl -s -F pdfFile=@scan.pdf "$API/pdf/extract-text" | jq .totalPages)
for i in $(seq 0 $((pages - 1))); do
  curl -s -F pdfFile=@scan.pdf -F pageIndex=$i -F dpi=200 "$API/pdf/render" -o page.png
  curl -s -F imageFile=@page.png -F recognitionLanguages=zh-Hans,en-US \
    "$API/text-detection/recognize-text" | jq -r .text >> scan.txt
done
```

### 票据图片转 CSV（macOS 26+）

```bash
curl -s -F imageFile=@invoice.jpg "$API/text-detection/recognize-document" \
  | jq -r '.tables[0].rows[] | @csv' > invoice.csv
```

### 会议录音转文字稿并翻译（macOS 26+）

```bash
curl -s -F audioFile=@meeting.m4a -F locale=en-US "$API/speech/transcribe" > transcript.json
jq -r .text transcript.json > meeting.en.txt

jq '{texts: [.segments[].text], sourceLanguage: "en", targetLanguage: "zh-Hans"}' transcript.json \
  | curl -s -H 'Content-Type: application/json' -d @- "$API/translation/translate" \
  | jq -r '.translations[]' > meeting.zh.txt
```

译文与 `segments` 一一对应，配合每段的 `start` 和 `duration` 就能生成双语字幕。

### 图片里的外文翻译（macOS 26+）

```bash
curl -s -F imageFile=@menu.jpg "$API/text-detection/recognize-text" \
  | jq '{text: .text, targetLanguage: "zh-Hans"}' \
  | curl -s -H 'Content-Type: application/json' -d @- "$API/translation/translate" \
  | jq -r '.translations[]'
```

### 商品图批量抠图并打标签

```bash
mkdir -p out
for f in products/*.jpg; do
  name=$(basename "${f%.*}")
  curl -s -F imageFile=@"$f" "$API/image-feature/background-removal" -o "out/$name.png"
  curl -s -F imageFile=@"$f" -F maxResults=3 "$API/vision/classify" \
    | jq -r --arg name "$name" '[$name, .classifications[].identifier] | @csv' >> out/tags.csv
done
```

### 从一批照片里挑出好照片（macOS 15+）

```bash
for f in photos/*.jpg; do
  score=$(curl -s -F imageFile=@"$f" "$API/vision/aesthetics" | jq .overallScore)
  echo "$score,$f"
done | sort -t, -k1 -nr | head -20
```

## macOS 26 能力的前提

- **语音转写**：首次使用某种语言时，服务会自动下载系统语音模型，这次请求会比较慢。`GET /speech/supported-locales` 可查看支持和已安装的语言。
- **翻译**：语言包需要先在“系统设置 → 通用 → 语言与地区 → 翻译语言”里下载，否则接口返回 409。

## 开发

```bash
swift build          # 编译
swift test           # 运行测试
cd vision-web && npm install && npm run dev   # Web 界面开发服务器
```

## 发布

1. 更新 `Sources/VisionAPI/configure.swift` 里的 `version` 并合入 `master`。
2. 在 GitHub 的 Actions 页面选择 **Release** 工作流，点 **Run workflow**，填入同样的版本号（如 `1.0.0`）。也可以直接推送 `v1.0.0` 标签。

工作流会做这些事：

1. 校验版本号与代码中的 `version` 一致。
2. 在 macOS runner 上编译后端，连同 Web 界面打包成 `vision-api-macos-arm64.tar.gz`，启动一次做冒烟检查，然后创建标签并发布到 GitHub Releases。
3. 构建 Web 界面镜像并推送到 `ghcr.io/biyan113/mac-vision-api-web`。

每次推送和 PR 会运行 `.github/workflows/ci.yml`（后端编译与测试、前端构建）。

## 许可证

见 [LICENSE.txt](LICENSE.txt)。
