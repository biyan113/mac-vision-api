# Vision 与 macOS 自带能力扩展可行性报告

## 背景与目标

现有服务已提供 OCR 与背景移除两项能力。本文评估可进一步集成的 Apple Vision 与 macOS 自带能力，提出可行的 API 设计、系统需求、风险与实施计划，帮助确定优先级与排期。

## 技术假设与边界

- 运行环境：macOS（Apple Silicon 优先），Swift + Vapor，已集成 Vision、CoreImage、ImageIO 等框架。
- 调用模式：以 REST 接口（主要处理单张图片）为主；视频/序列帧类能力作为后续扩展。
- 数据形态：`multipart/form-data` 上传图片或 `imageURL/imageBase64`；输出 JSON 或图片二进制。
- 版本要求：不同能力在不同 macOS 版本可用，文内会标注最低版本要求（以官方文档为准）。

## 可集成能力清单与可行性

以下均为「单张图片输入」的优先方案，便于与现有 API 风格一致。

1) 条形码/二维码识别（VNDetectBarcodesRequest）
- 用途：识别一维/二维条码（QR、EAN、Code128 等）。
- 版本：macOS 10.13+（覆盖面广，适合集成）。
- 输出：条码类型、内容、置信度、位置框。
- API 草案：
  - `POST /barcode/recognize`
  - 入参：`imageFile | imageURL | imageBase64`
  - 出参：`{ barcodes: [{ symbology, payloadStringValue, boundingBox, confidence }] }`
- 风险：不同码制兼容度与容错（旋转、遮挡、低清晰度）。
- 复杂度：低（1 天内）。

2) 人脸检测与关键点（VNDetectFaceRectanglesRequest / VNDetectFaceLandmarksRequest）
- 用途：检测人脸位置，返回五官关键点（眼、鼻、嘴、轮廓）。
- 版本：macOS 10.13+。
- 输出：人脸框、关键点（可选）、置信度。
- API 草案：
  - `POST /face/detect`
  - 入参：`image*`，可选 `returnLandmarks=true|false`
  - 出参：`{ faces: [{ boundingBox, landmarks?: {...} }] }`
- 风险：隐私与合规（仅做检测不做识别）。
- 复杂度：低（1–2 天）。

3) 人体检测/姿态估计（VNDetectHumanRectanglesRequest / VNDetectHumanBodyPoseRequest）
- 用途：识别人体框、关节点（头肩肘腕髋膝踝等）。
- 版本：人体框 macOS 10.15+；人体姿态 macOS 11+。
- API 草案：
  - `POST /human/pose`
  - 出参：`{ persons: [{ boundingBox, joints: { jointName: {x,y,confidence} } }] }`
- 风险：多人人群场景与遮挡；性能随分辨率敏感。
- 复杂度：中（2–3 天）。

4) 手部关键点（VNDetectHumanHandPoseRequest）
- 用途：检测手部并返回 21 点关键点，手势理解的基础。
- 版本：macOS 12+。
- API 草案：
  - `POST /hand/pose`
  - 出参：`{ hands: [{ joints: { jointName: {x,y,confidence} } }] }`
- 风险：低光、模糊、遮挡导致关键点缺失。
- 复杂度：中（2 天）。

5) 图像分类（VNClassifyImageRequest）
- 用途：通用图像语义分类（无需自定义模型）。
- 版本：macOS 12+（不同系统模型版本可能不同）。
- API 草案：
  - `POST /vision/classify-image`
  - 入参：`topK`（默认 5）
  - 出参：`{ labels: [{ identifier, confidence }] }`
- 风险：类别集合不可控、语义泛化；需清晰声明适用性。
- 复杂度：低（1–2 天）。

6) 显著性/注意力图（VNGenerateAttentionBasedSaliencyImageRequest / VNGenerateObjectnessBasedSaliencyImageRequest）
- 用途：返回显著区域热力图或显著框，辅助裁剪与聚焦。
- 版本：macOS 10.15+。
- API 草案：
  - `POST /image/saliency`
  - 出参：`{ saliencyMap: <PNG Base64> , salientRegions: [{ boundingBox, confidence }] }` 或直接输出 PNG。
- 风险：结果用于自动裁剪需人工验证策略。
- 复杂度：中（2 天）。

7) 轮廓/边缘检测（VNDetectContoursRequest）
- 用途：提取物体轮廓，多用于矢量化、测量与拼接。
- 版本：macOS 10.15+。
- API 草案：
  - `POST /image/contours`
  - 入参：阈值、对比度等可选参数
  - 出参：`{ contours: [{ points: [{x,y}], childContours: [...] }] }` 或导出 SVG。
- 风险：点集较大；JSON 体积控制与下采样策略。
- 复杂度：中（2–3 天）。

8) 矩形/文档边界检测（VNDetectRectanglesRequest）
- 用途：检测规则矩形（文档、白板、屏幕等），可配合透视矫正。
- 版本：macOS 10.13+。
- API 草案：
  - `POST /image/detect-rectangles`
  - 出参：`{ rectangles: [{ topLeft, topRight, bottomLeft, bottomRight, confidence }] }`
- 风险：极端透视/反光影响；与 OCR 联动时注意顺序。
- 复杂度：低（1–2 天）。

9) 地平线检测（VNDetectHorizonRequest）
- 用途：返回相机倾斜角，辅助自动旋转与纠偏。
- 版本：macOS 10.15+。
- API 草案：
  - `POST /image/horizon`
  - 出参：`{ angle: number, transform: [ [a,b,c], [d,e,f], [g,h,i] ] }`（或直接给出旋转角度）。
- 风险：非风景/非水平场景效果一般。
- 复杂度：低（1 天）。

10) OCR 版面位置信息增强（基于 VNRecognizeTextRequest）
- 用途：在现有 OCR 上返回每行/每块的边框与置信度，支持版面重建。
- 版本：macOS 10.15+。
- API 草案：
  - `POST /text-detection/recognize-text` 增加 `includeBoxes=true|false`
  - 出参：`{ text, blocks: [{ text, boundingBox, confidence }] }`
- 风险：坐标体系（归一化/像素）需要统一文档说明。
- 复杂度：低（0.5–1 天）。

11) 后续（视频/序列帧）：追踪/光流/轨迹（VNTrackObjectRequest / VNDetectTrajectoriesRequest 等）
- 用途：对象跟踪、运动分析（需要连续帧）。
- 版本：多为 macOS 10.15+；需流式或批量接口设计。
- 风险：状态管理、会话粘性与资源占用；暂不纳入首期。
- 复杂度：高（单项 3–5 天+）。

## macOS 其他原生框架能力（扩展项）

- Core ML：加载自定义 `.mlmodel` 进行分类/检测/分割。
  - API 草案：`POST /ml/predict`（入参：模型名、输入图像；出参：模型原生输出）
  - 风险：动态加载模型的安全与资源配额；模型版本管理。
- NaturalLanguage：语言检测、分词、词性标注、命名实体、情感、文本嵌入。
  - 文本类 REST：`/nlp/detect-language`、`/nlp/sentiment` 等。
  - 价值：补齐多模态（图像+文本）场景。
- Speech：离线/在线语音转写（SFSpeechRecognizer + URL 识别）。
  - API 草案：`POST /speech/recognize`（入参音频文件；出参转写文本）
  - 风险：语言包安装、并发许可、长音频切分。
- Core Image：图像滤镜/几何变换/去噪/锐化，配合 Vision 进行后处理。
  - API 草案：`POST /image/filter?filter=CISepiaTone&intensity=...`
- PDFKit：PDF 页渲染 + OCR（配合 Vision），实现 PDF 批量文本提取。
  - API 草案：`POST /pdf/ocr`（入参 PDF；出参每页文本 + 位置）。

## 性能与资源评估（定性）

- 分辨率：多数请求在 1080p–4K 内有较好平衡；建议后端统一下采样至最长边（如 2048–3072px）以控时与内存。
- 并发：每路请求 1–2 个 Vision 请求（几十毫秒到数百毫秒级，依能力而异）；限制并发队列与请求超时（如 30s）。
- 加速：部分能力可受益于 Metal/GPU；Vapor 侧避免阻塞主线程，使用 async/await。
- 体积：保持默认 20MB 限制；对极大图像进行预缩放以避免 OOM。

## 安全与合规

- 输入校验：严格限制 `imageURL` 域名白名单与内容类型；本地路径禁止越权访问。
- 速率与配额：按路由限流，避免 DoS；限制每 IP 并发。
- 隐私：不做身份识别/比对，仅提供检测/关键点；必要时在文档标注用途边界。
- 依赖与许可：避免引入非系统依赖；Core ML 模型需明确授权来源与用途。

## API 设计与返回规范建议

- 路径风格：延续当前分组，如 `/text-detection`、`/image-feature`、新增 `/barcode`、`/face`、`/human`、`/vision` 等。
- 入参：统一 `imageFile | imageURL | imageBase64` 三选一；必要时增设可选参数（阈值、topK、是否返回关键点）。
- 出参：
  - JSON：使用归一化坐标（0–1）与像素坐标并存，便于前端叠加。
  - 图片：返回 PNG（二进制）或 Base64（配合 JSON）。
- 错误：沿用 `reason` 字段；补充错误码枚举（如 `InvalidImage`, `NoResult`, `ModelUnavailable`）。
- 文档：继续使用 SwiftOpenAPI/VaporToOpenAPI 生成 Swagger/Stoplight。

## 实施计划与工期预估（人日）

- Phase 1（基础，优先上线，3–5 人日）
  - 条码识别、矩形检测、人脸检测（含可选关键点）、OCR 位置增强。
- Phase 2（进阶，5–7 人日）
  - 人体姿态、手部姿态、轮廓检测、显著性图。
- Phase 3（补充，3–5 人日）
  - 图像分类、地平线检测、若干图像滤镜（Core Image）。
- Phase 4（扩展，>7 人日）
  - Core ML 自定义模型推理、PDF OCR 管线、语音转写、NLP 文本分析。

说明：工期含接口实现、OpenAPI 文档、示例与基础测试；不含大规模性能压测与生产化运维。

## 优先级建议（MoSCoW）

- Must-have：条形码识别、矩形检测、人脸检测、OCR 位置增强。
- Should-have：人体姿态、手部姿态、轮廓检测、显著性图。
- Could-have：图像分类、地平线检测、部分滤镜后处理。
- Won’t (first)：视频序列类追踪/光流、语音转写、NLP、Core ML 动态模型管理。

## 里程碑与验收

- 里程碑 A：Phase 1 完成，可在 Swagger/Stoplight 验证全部示例通过。
- 里程碑 B：Phase 2 完成，新增关键点/热力图结果的可视化示例页（可选）。
- 里程碑 C：Phase 3 完成，分类/地平线能力联动裁剪/自动旋转 Demo。
- 验收：功能接口返回正确、OpenAPI 准确、在 1080p 图片下 P50 延迟 < 400ms（以 M1/M2 单机为参考，不做性能承诺）。

## 风险与缓解

- 系统版本碎片化：为不同接口标注最低系统版本，运行时判定可用性并返回友好错误。
- 资源占用：限制图片分辨率与请求并发；错误恢复与超时控制。
- 质量稳定性：对低光/模糊/遮挡场景设定预期与置信度阈值；必要时提供结果降级策略。
- 部署限制：容器化在 macOS 上的限制与授权需评估（现有 Docker 方案以 Swift 为主，访问硬件加速需实测）。

---

如需，我可以按上述清单先落地 Phase 1 的 3–4 个接口（条码、人脸、矩形、OCR 增强），并补充对应的 OpenAPI 文档与 curl 示例。

