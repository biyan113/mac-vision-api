# Vision API 接口文档

基础地址默认为 `http://localhost:8080`。交互式文档在 `/Swagger/index.html`，OpenAPI 规范在 `/Swagger/swagger.json`。

## 通用约定

### 输入

图片接口接受下列字段之一，按顺序取第一个存在的：

| 字段 | 说明 |
|---|---|
| `imageFile` | multipart 上传的文件 |
| `imagePath` | 服务器本地路径，需要 `VISION_ALLOW_LOCAL_FILES=true` |
| `imageURL` | http/https 地址；默认拒绝回环和内网地址 |
| `imageBase64` | Base64 字符串，可带 `data:image/png;base64,` 前缀 |

PDF 接口使用 `pdfFile` / `pdfPath` / `pdfURL` / `pdfBase64`，音频接口使用 `audioFile` / `audioPath` / `audioURL` / `audioBase64`。

请求体可以是 `multipart/form-data`，不上传文件时也可以是 JSON。

### 坐标

所有 `boundingBox` 和点坐标都是 0~1 的归一化值，原点在图像**左下角**（Vision 框架的约定）。人脸关键点的坐标相对于该人脸的 `boundingBox`。

### 鉴权

设置了 `VISION_API_KEY` 后，除 `/health` 外的接口需要 `Authorization: Bearer <key>` 或 `X-API-Key: <key>`。

### 错误

错误响应为 `{"error": true, "reason": "..."}`。

| 状态码 | 含义 |
|---|---|
| 400 | 缺少输入、参数无效、Base64 或 URL 无效 |
| 401 | 缺少或错误的 API Key |
| 403 | 本地路径或内网 URL 未开启 |
| 409 | 翻译语言包未下载 |
| 413 | 请求体超过 `VISION_MAX_BODY_SIZE` |
| 422 | 文件无法解析，或图片中没有可处理的内容 |

## 服务信息

### `GET /health`
```json
{"status": "healthy", "version": "1.0.0", "timestamp": "2026-01-01T00:00:00Z"}
```

### `GET /capabilities`
返回当前系统上可用的能力，每项为布尔值：`textRecognition`、`pdf`、`imageAnalysis`、`backgroundRemoval`、`aesthetics`、`documentRecognition`、`lensSmudge`、`speechTranscription`、`translation`。

## 文本识别

### `POST /text-detection/recognize-text`

| 参数 | 类型 | 说明 |
|---|---|---|
| 图片输入 | — | 见通用约定 |
| `recognitionLanguages` | String | 逗号分隔的语言代码，如 `zh-Hans,en-US`。省略则自动检测。只填一个中文代码时会自动加上 `en-US`。常见简写会被换成完整标识，如 `zh` → `zh-Hans`、`en` → `en-US` |
| `recognitionLevel` | Int | `0` 精确（默认），`1` 快速 |
| `includeLines` | Bool | 为 `true` 时返回 `lines` |

```json
{
  "text": "第一行\n第二行",
  "lines": [
    {"text": "第一行", "confidence": 0.98, "boundingBox": {"x": 0.1, "y": 0.8, "width": 0.5, "height": 0.05}}
  ]
}
```

### `GET /text-detection/supported-languages?recognitionLevel=0`
```json
{"languages": ["en-US", "zh-Hans", "zh-Hant", "ja-JP"]}
```

### `POST /text-detection/recognize-document`（macOS 26+）
识别文档结构。
```json
{
  "text": "全文",
  "paragraphs": ["段落一", "段落二"],
  "tables": [{"rows": [["姓名", "电话"], ["张三", "123456"]]}],
  "emails": ["a@example.com"],
  "phoneNumbers": ["123456"]
}
```

## 图像分析

以下接口的输入都是图片输入。

| 接口 | 额外参数 | 返回 |
|---|---|---|
| `POST /vision/classify` | `maxResults`（默认 10） | `{"classifications": [{"identifier", "confidence"}]}` |
| `POST /vision/detect-objects` | — | `{"objects": [{"label", "confidence", "boundingBox"}]}`，`label` 为动物类别、`face` 或 `human` |
| `POST /vision/scan-barcode` | — | `{"barcodes": [{"payload", "symbology", "boundingBox"}]}` |
| `POST /vision/detect-faces` | — | `{"faces": [{"boundingBox", "confidence", "roll", "yaw", "pitch", "landmarks"}]}` |
| `POST /vision/detect-body-pose` | — | `{"poses": [{"confidence", "joints"}]}` |
| `POST /vision/detect-hand-pose` | `maxHands`（默认 2） | `{"poses": [{"confidence", "chirality", "joints"}]}` |
| `POST /vision/saliency` | `type`：`attention`（默认）或 `objectness` | `{"type", "regions": [{"boundingBox", "confidence"}]}` |
| `POST /vision/detect-rectangles` | `maxResults`（默认 10） | `{"rectangles": [{"confidence", "boundingBox", "topLeft", "topRight", "bottomLeft", "bottomRight"}]}` |
| `POST /vision/detect-horizon` | — | `{"detected", "angleRadians", "angleDegrees"}` |
| `POST /vision/aesthetics`（macOS 15+） | — | `{"overallScore", "isUtility"}`，分数范围 -1~1 |
| `POST /vision/lens-smudge`（macOS 26+） | — | `{"confidence"}`，越接近 1 越可能有污渍 |

`landmarks` 是区域名到点数组的映射，区域包括 `faceContour`、`leftEye`、`rightEye`、`leftEyebrow`、`rightEyebrow`、`nose`、`noseCrest`、`medianLine`、`outerLips`、`innerLips`、`leftPupil`、`rightPupil`。

`joints` 是关节名到 `{"x", "y", "confidence"}` 的映射，关节名使用 Vision 框架的原始标识。

## 背景移除

### `POST /image-feature/background-removal`（macOS 14+）

| 参数 | 类型 | 说明 |
|---|---|---|
| 图片输入 | — | 见通用约定 |
| `crop` | Bool | 是否裁剪到主体范围，默认 `true` |

返回 `image/png`，背景透明。图片中没有前景主体时返回 422。

## PDF

### `POST /pdf/render`

| 参数 | 类型 | 说明 |
|---|---|---|
| PDF 输入 | — | `pdfFile` / `pdfPath` / `pdfURL` / `pdfBase64` |
| `pageIndex` | Int | 页码，从 0 开始，默认 0 |
| `dpi` | Double | 36~600，默认 150，超出范围会被截断 |

返回 `image/png`。

### `POST /pdf/extract-text`

| 参数 | 类型 | 说明 |
|---|---|---|
| PDF 输入 | — | 同上 |
| `startPage` / `endPage` | Int | 从 0 开始，默认全部页 |
| `mergePages` | Bool | 为 `true` 时返回 `allText` |

```json
{
  "totalPages": 3,
  "extractedPages": [{"pageNumber": 1, "text": "..."}],
  "allText": "..."
}
```

只抽取 PDF 的文本层。扫描件请先用 `/pdf/render` 渲染，再调用 OCR。

## 语音转写（macOS 26+）

### `POST /speech/transcribe`

| 参数 | 类型 | 说明 |
|---|---|---|
| 音频输入 | — | `audioFile` / `audioPath` / `audioURL` / `audioBase64`，支持 m4a、mp3、wav、caf 等 |
| `locale` | String | 如 `en-US`、`zh-CN`，默认 `en-US` |

```json
{
  "locale": "en-US",
  "text": "Hello world.",
  "segments": [{"text": "Hello world.", "start": 0.0, "duration": 1.2}]
}
```

首次使用某种语言时会自动下载系统语音模型。通过 `audioBase64` 或没有文件名的方式提交时，服务按 m4a 处理。

### `GET /speech/supported-locales`
```json
{"supported": ["en-US", "zh-CN"], "installed": ["en-US"]}
```

## 翻译（macOS 26+）

### `POST /translation/translate`

请求体为 JSON 或表单。

| 参数 | 类型 | 说明 |
|---|---|---|
| `text` | String | 待翻译文本 |
| `texts` | [String] | 批量文本，可与 `text` 同时提供 |
| `sourceLanguage` | String | 源语言，省略则自动检测 |
| `targetLanguage` | String | 目标语言，必填，如 `zh-Hans` |

```json
{"sourceLanguage": "en", "targetLanguage": "zh", "translations": ["你好，世界"]}
```

语言包未下载时返回 409，需要在“系统设置 → 通用 → 语言与地区 → 翻译语言”中下载。

### `GET /translation/supported-languages`
```json
{"languages": ["en", "ja", "zh"]}
```
