+# macOS 原生能力扩展可行性报告（不含 Vision）
+
+## 目标与范围
+
+- 目标：在不依赖 Vision SDK 的前提下，评估可集成的 macOS 原生框架能力，给出可行的 REST API 设计、风险与实施建议。
+- 环境：Swift + Vapor 服务，运行于 macOS（Apple Silicon 优先）。
+- 输入输出：图片/音频/文本作为输入，输出 JSON 或二进制（PNG/JPEG/音频片段等）。
+- 版本声明：不同能力对系统版本有要求，正式落地前需以 Xcode SDK 文档为准做运行时可用性判断。
+
+## 能力清单与建议接口
+
+1) NaturalLanguage（NLP 自然语言处理）
+- 能力：语言检测、分词、词性标注、命名实体识别、情感分析、文本嵌入。
+- 建议接口：
+  - `POST /nlp/detect-language` → `{ languageCode, confidence }`
+  - `POST /nlp/tokenize` → `{ tokens: [string] }`
+  - `POST /nlp/pos` → `{ tokens: [{ text, tag, range }] }`
+  - `POST /nlp/ner` → `{ entities: [{ text, type, range, confidence }] }`
+  - `POST /nlp/sentiment` → `{ score: [-1..1], confidence }`
+  - `POST /nlp/embedding` → `{ vector: [Float], dimension }`
+- 备注：对中文分词和实体识别可提供语言提示 `locale` 以提升效果。
+
+2) Speech（语音转写）
+- 能力：离线/在线语音识别（依赖已安装的语言包和系统权限）。
+- 建议接口：
+  - `POST /speech/recognize` → 输入音频（WAV/MP4/M4A 等），输出 `{ text, segments: [{ start, end, text, confidence }] }`
+- 风险：
+  - 需确保服务器具有麦克风/语音识别权限或使用文件识别模式。
+  - 长音频需分段或流式；不同语言的模型可用性需运行时检查。
+
+3) SoundAnalysis（音频分类）
+- 能力：使用系统内置或自带模型对音频进行分类（环境音、事件等）。
+- 建议接口：
+  - `POST /audio/classify` → `{ results: [{ label, confidence, timeRange }] }`
+- 备注：对持续音频可返回时间分段的标签序列。
+
+4) Core Image（图像滤镜与几何变换）
+- 能力：丰富的 CIFilter 管线（裁剪、缩放、旋转、锐化、降噪、色彩调整等）。
+- 建议接口：
+  - `POST /image/filter`（按白名单传入 `filterName` 与参数）→ 返回 PNG/JPEG
+  - `POST /image/resize`（`width/height/fit`）→ 返回 PNG/JPEG
+  - `POST /image/crop`（`x,y,width,height`）→ 返回 PNG/JPEG
+  - `POST /image/rotate`（`angle`）→ 返回 PNG/JPEG
+  - `POST /image/denoise|sharpen|exposure|contrast` → 返回 PNG/JPEG
+- 风险：
+  - 过滤器与参数需白名单以防滥用；注意色彩空间与元数据处理。
+
+5) ImageIO / CoreGraphics / Accelerate(vImage)（编解码与高性能像素处理）
+- 能力：读取/写入多种图像格式（PNG/JPEG/HEIC 等）、提取与清理 EXIF、色彩空间变换、快速缩放。
+- 建议接口：
+  - `POST /image/convert?format=png|jpeg|heic` → 返回目标格式二进制
+  - `POST /image/metadata/extract` → `{ exif, tiff, gps, iccProfile... }`
+  - `POST /image/metadata/strip` → 去除敏感元数据并输出
+  - `POST /image/colorspace/convert?to=sRGB|DisplayP3` → 返回转换后图片
+- 风险：HEIC 写入依赖系统编解码支持；注意内存峰值与色彩配置。
+
+6) PDFKit（PDF 渲染与文本抽取）
+- 能力：将 PDF 页渲染为位图、提取可选文本层内容。
+- 建议接口：
+  - `POST /pdf/render`（`page=1&scale=2.0&bg=white`）→ 返回 PNG
+  - `POST /pdf/extract-text` → `{ pages: [{ index, text }] }`
+- 备注：若 PDF 无文本层，需结合 OCR；但本报告不依赖 Vision，可仅提供原生文本层抽取与渲染。
+
+7) QuickLookThumbnailing（通用缩略图）
+- 能力：为多种文件类型生成缩略图（办公文档、图像、视频等）。
+- 建议接口：
+  - `POST /file/thumbnail`（上传文件或 URL，传入尺寸 `width/height`）→ 返回 PNG
+- 风险：在无界面环境下可用性需验证；个别类型需相应扩展支持。
+
+8) Core ML（自定义模型推理，非 Vision 绑定）
+- 能力：载入 `.mlmodel`/`.mlmodelc` 并在后端执行推理（可用于文本/音频/图像等任务）。
+- 建议接口：
+  - `POST /ml/predict`（`modelName`、输入张量/图像/文本）→ 返回模型原生输出
+  - `POST /ml/models`（列举/热加载/卸载模型）
+- 风险：
+  - 模型管理与安全（来源、版本、资源配额）；首次加载的 warm-up 延迟。
+
+9) Foundation NSDataDetector（数据模式识别）
+- 能力：对纯文本识别 URL、邮箱、电话、地址、日期等结构化信息。
+- 建议接口：
+  - `POST /text/datadetect` → `{ matches: [{ type, value, range }] }`
+- 价值：结合 OCR/ASR 结果进行二次结构化（不依赖 Vision 也可用于纯文本管线）。
+
+10) CryptoKit（内容摘要与完整性）
+- 能力：SHA-256/SHA-512 等摘要，辅助去重、缓存与校验。
+- 建议接口：
+  - `POST /util/hash?algo=sha256` → `{ hashHex }`
+- 备注：非核心识别能力，但对平台稳定性有价值。
+
+## 通用设计与返回规范
+
+- 入参：保持与现有风格一致（`imageFile|imageURL|imageBase64`、`text`、`audioFile` 等）。
+- 出参：JSON 结果结构稳定且字段含义清晰；二进制返回设置合适的 `Content-Type` 与 `Content-Disposition`。
+- 错误：统一 `reason` 与可选 `code` 字段；对不支持的系统能力返回明确提示。
+- 文档：继续使用 OpenAPI 生成 Swagger/Stoplight；为每个路由标注参数与示例。
+
+## 风险与限制
+
+- 系统可用性：不同 macOS 版本能力差异大，需运行时 `@available` 检查并降级。
+- 隐私与权限：语音识别、文件缩略图等可能触发权限或沙箱限制；需在部署前验证。
+- 性能与内存：图像高分辨率/长音频需切片与流式，限制请求体大小与并发。
+- 安全：
+  - 过滤器/模型/目标格式使用白名单；
+  - `imageURL` 建议采用域名白名单或中转下载；
+  - 严控 PDF/Office 解析带来的潜在复杂性与资源消耗。
+
+## 实施建议与排期（人日，粗估）
+
+- Phase A（3–5 人日）：NLP（语言检测/分词/情感）、图像转换与元数据、基础滤镜/resize。
+- Phase B（4–6 人日）：PDF 渲染/文本抽取、QuickLook 缩略图、音频分类（SoundAnalysis）。
+- Phase C（5–7 人日）：语音转写（分片/拼接）、Core ML 推理接口与模型管理雏形。
+
+## 里程碑与验收
+
+- 里程碑 1：A 完成，Swagger/Stoplight 可验证示例；对 10–20 张图片/文本通过冒烟测试。
+- 里程碑 2：B 完成，文件类型覆盖增加；提供压力测试报告与资源占用指标。
+- 里程碑 3：C 完成，ASR 与自定义模型可跑通 Demo；提供失败回退与错误分类。
+
+---
+
+如需，我可以先落地 Phase A：
+- `/nlp/detect-language`、`/nlp/sentiment`、`/nlp/tokenize`
+- `/image/convert`、`/image/metadata/extract|strip`、`/image/resize`
+并同步补充 OpenAPI 文档与 curl 示例。
