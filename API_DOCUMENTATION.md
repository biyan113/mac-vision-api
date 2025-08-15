# Vision API 中文文档

## 概述

Vision API 是一个自托管的 RESTful 服务，将 Apple 的 Vision 框架能力通过 HTTP 接口对外提供。它支持常见的视觉任务，例如：
- 文本识别（OCR）
- 背景移除（前景分割）

适合在本地或私有环境中部署，无需依赖第三方云服务。

基础地址（默认）：`http://localhost:8080`

## 接口列表

### 1. 文本识别（OCR）

从图片中识别并提取文本内容。

- 接口地址：`POST /text-detection/recognize-text`
- 功能说明：识别图像中的文本，支持多语言（含中文、英文等）。

请求参数（表单 multipart/form-data）：

| 参数名 | 类型 | 必填 | 说明 |
|---|---|---|---|
| imageFile | File | 否* | 待识别的图片文件（PNG、JPEG 等常见格式） |
| imagePath | String | 否* | 本地图片文件路径 |
| imageURL | String | 否* | 远程图片 URL |
| imageBase64 | String | 否* | Base64 编码的图片数据 |
| recognitionLanguages | String | 否 | 逗号分隔的 ISO 语言代码（如：`zh,en`）。不提供则自动检测语言 |
| recognitionLevel | Integer | 否 | 识别精度级别：`0` = 精确（默认），`1` = 快速 |

注：带星号（*）的图片来源参数需至少提供其中之一。

成功响应（200）：

```json
{
  "text": "从图片中提取的文本内容"
}
```

错误响应示例：

```json
{
  "error": true,
  "reason": "请提供图片文件、本地路径、远程URL或Base64编码数据其中之一"
}
```

示例（curl）：

```bash
# 使用本地文件
curl -X POST http://localhost:8080/text-detection/recognize-text \
  -F "imageFile=@/path/to/your/image.jpg"

# 使用远程 URL
curl -X POST http://localhost:8080/text-detection/recognize-text \
  -F "imageURL=https://example.com/image.jpg"

# 使用 Base64 图片
curl -X POST http://localhost:8080/text-detection/recognize-text \
  -F "imageBase64=data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAIBAQIB..."

# 搭配可选参数
curl -X POST http://localhost:8080/text-detection/recognize-text \
  -F "imageFile=@/path/to/your/image.jpg" \
  -F "recognitionLanguages=en,zh" \
  -F "recognitionLevel=0"
```

### 2. 背景移除

移除图片背景，仅保留前景主体。

- 接口地址：`POST /image-feature/background-removal`
- 功能说明：对传入图片执行前景分割并输出去背景 PNG 图像。

请求参数（表单 multipart/form-data）：

| 参数名 | 类型 | 必填 | 说明 |
|---|---|---|---|
| imageFile | File | 是 | 待处理的图片文件（PNG、JPEG 等常见格式） |

成功响应（200）：返回 PNG 图片二进制流，响应头包含：
- `Content-Type: image/png`
- `Content-Disposition: attachment; filename="image.png"`

错误响应示例：

```json
{
  "error": true,
  "reason": "未找到前景实例。"
}
```

示例（curl）：

```bash
curl -X POST http://localhost:8080/image-feature/background-removal \
  -F "imageFile=@/path/to/your/image.jpg" \
  --output background_removed.png
```

## 错误与状态码

- 400 Bad Request：请求参数无效或缺失（如未提供任何图片来源）。
- 500 Internal Server Error：服务端处理失败（如图像转换失败、未找到前景实例）。

返回的错误内容通常包含 `reason` 字段说明失败原因。

## 其他说明

1. 请求体最大默认 20MB，适用于大多数图像处理场景。
2. 背景移除接口需要 macOS 15.0 及以上环境。
3. 运行服务后可访问 Swagger UI：`http://localhost:8080/Swagger/index.html`。
4. 也可访问交互式文档（Stoplight）：`http://localhost:8080/stoplight`，OpenAPI JSON：`http://localhost:8080/Swagger/swagger.json`。

## 运行服务

### 使用 Swift 运行

```bash
# 克隆项目
git clone https://github.com/tdawn0-0/vision-api
cd vision-api

# 解析依赖
swift package resolve

# 启动服务
swift run App
```

### 使用 Docker 运行

```bash
# 构建镜像
docker-compose build

# 启动服务
docker-compose up app

# 停止服务
docker-compose down
```

服务启动后默认监听：`http://localhost:8080`。

