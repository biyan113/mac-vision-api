import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { ScanSearch } from 'lucide-react'
import FileUpload from './ui/FileUpload'
import { showToast } from './ui/Toast'
import { CapabilityNotice, EmptyState, ErrorBox, LoadingState, PageHeader, RunButton } from './ui/Common'
import { errorMessage, postImage } from '../services/api'
import type { Capabilities } from '../services/api'
import { useCapabilities } from '../hooks/useCapabilities'
import { cn } from '../lib/utils'

// 后端返回的归一化坐标，原点在左下角
interface Box {
  x: number
  y: number
  width: number
  height: number
}

interface Point {
  x: number
  y: number
}

interface Overlay {
  boxes: { box: Box; label?: string }[]
  points: Point[]
  polygons: Point[][]
  summary: string[]
}

interface Mode {
  id: string
  name: string
  path: string
  description: string
  capability?: keyof Capabilities
  requirement?: string
  params?: Record<string, string | number>
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  toOverlay: (data: any) => Overlay
}

const percent = (value: number) => `${(value * 100).toFixed(1)}%`
const empty = (): Overlay => ({ boxes: [], points: [], polygons: [], summary: [] })

const MODES: Mode[] = [
  {
    id: 'classify',
    name: '图像分类',
    path: '/vision/classify',
    description: '识别图片内容所属的类别',
    toOverlay: (data) => ({
      ...empty(),
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      summary: (data.classifications ?? []).map((c: any) => `${c.identifier} · ${percent(c.confidence)}`),
    }),
  },
  {
    id: 'objects',
    name: '物体检测',
    path: '/vision/detect-objects',
    description: '检测动物、人脸和人体',
    toOverlay: (data) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const objects: any[] = data.objects ?? []
      return {
        ...empty(),
        boxes: objects.map((o) => ({ box: o.boundingBox, label: o.label })),
        summary: objects.map((o) => `${o.label} · ${percent(o.confidence)}`),
      }
    },
  },
  {
    id: 'barcode',
    name: '条码 / 二维码',
    path: '/vision/scan-barcode',
    description: '扫描并解码条形码和二维码',
    toOverlay: (data) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const barcodes: any[] = data.barcodes ?? []
      return {
        ...empty(),
        boxes: barcodes.map((b, i) => ({ box: b.boundingBox, label: `#${i + 1}` })),
        summary: barcodes.map((b, i) => `#${i + 1} · ${b.symbology} · ${b.payload}`),
      }
    },
  },
  {
    id: 'faces',
    name: '人脸关键点',
    path: '/vision/detect-faces',
    description: '检测人脸位置与五官关键点',
    toOverlay: (data) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const faces: any[] = data.faces ?? []
      const points: Point[] = []
      faces.forEach((face) => {
        const box: Box = face.boundingBox
        Object.values((face.landmarks ?? {}) as Record<string, Point[]>).forEach((region) => {
          region.forEach((p) => {
            // 关键点坐标相对于人脸框
            points.push({ x: box.x + p.x * box.width, y: box.y + p.y * box.height })
          })
        })
      })
      return {
        ...empty(),
        boxes: faces.map((f, i) => ({ box: f.boundingBox, label: `#${i + 1}` })),
        points,
        summary: faces.map((f, i) => `人脸 #${i + 1} · 置信度 ${percent(f.confidence)}`),
      }
    },
  },
  {
    id: 'body',
    name: '人体姿态',
    path: '/vision/detect-body-pose',
    description: '估计人体关节点位置',
    toOverlay: (data) => poseOverlay(data, '人体'),
  },
  {
    id: 'hand',
    name: '手部姿态',
    path: '/vision/detect-hand-pose',
    description: '估计手部关节点位置',
    params: { maxHands: 4 },
    toOverlay: (data) => poseOverlay(data, '手'),
  },
  {
    id: 'saliency',
    name: '显著性区域',
    path: '/vision/saliency',
    description: '找出最吸引注意力的区域',
    toOverlay: (data) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const regions: any[] = data.regions ?? []
      return {
        ...empty(),
        boxes: regions.map((r, i) => ({ box: r.boundingBox, label: `#${i + 1}` })),
        summary: regions.map((r, i) => `区域 #${i + 1} · ${percent(r.confidence)}`),
      }
    },
  },
  {
    id: 'rectangles',
    name: '矩形检测',
    path: '/vision/detect-rectangles',
    description: '检测文档、卡片等矩形的四个角',
    toOverlay: (data) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const rectangles: any[] = data.rectangles ?? []
      return {
        ...empty(),
        polygons: rectangles.map((r) => [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]),
        summary: rectangles.map((r, i) => `矩形 #${i + 1} · ${percent(r.confidence)}`),
      }
    },
  },
  {
    id: 'horizon',
    name: '地平线',
    path: '/vision/detect-horizon',
    description: '检测画面倾斜角度',
    toOverlay: (data) => ({
      ...empty(),
      summary: data.detected ? [`倾斜角度 · ${Number(data.angleDegrees).toFixed(2)}°`] : ['未检测到地平线'],
    }),
  },
  {
    id: 'aesthetics',
    name: '美学评分',
    path: '/vision/aesthetics',
    description: '评估图片的整体美感',
    capability: 'aesthetics',
    requirement: 'macOS 15 或更高版本',
    toOverlay: (data) => ({
      ...empty(),
      summary: [
        `综合评分 · ${Number(data.overallScore).toFixed(3)}（范围 -1 ~ 1）`,
        data.isUtility ? '工具类图片（截图、票据等）' : '非工具类图片',
      ],
    }),
  },
  {
    id: 'smudge',
    name: '镜头污渍',
    path: '/vision/lens-smudge',
    description: '判断模糊是否由镜头脏污造成',
    capability: 'lensSmudge',
    requirement: 'macOS 26 或更高版本',
    toOverlay: (data) => ({
      ...empty(),
      summary: [`污渍可能性 · ${percent(data.confidence)}`],
    }),
  },
]

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function poseOverlay(data: any, noun: string): Overlay {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const poses: any[] = data.poses ?? []
  const points: Point[] = []
  poses.forEach((pose) => {
    Object.values((pose.joints ?? {}) as Record<string, Point>).forEach((joint) => points.push(joint))
  })
  return {
    ...empty(),
    points,
    summary: poses.map((pose, i) => {
      const side = pose.chirality === 'left' ? '（左）' : pose.chirality === 'right' ? '（右）' : ''
      return `${noun} #${i + 1}${side} · ${Object.keys(pose.joints ?? {}).length} 个关节点`
    }),
  }
}

const VisionAnalysisPage: React.FC = () => {
  const capabilities = useCapabilities()
  const [modeId, setModeId] = useState(MODES[0].id)
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState('')
  const [raw, setRaw] = useState<unknown>(null)
  const [overlay, setOverlay] = useState<Overlay | null>(null)
  const [showRaw, setShowRaw] = useState(false)

  const mode = MODES.find((m) => m.id === modeId) ?? MODES[0]

  const previewUrl = useMemo(() => (selectedFile ? URL.createObjectURL(selectedFile) : ''), [selectedFile])
  useEffect(() => () => {
    if (previewUrl) URL.revokeObjectURL(previewUrl)
  }, [previewUrl])

  const reset = useCallback(() => {
    setError('')
    setRaw(null)
    setOverlay(null)
  }, [])

  const handleRun = async () => {
    if (!selectedFile) return
    setIsLoading(true)
    reset()
    try {
      const data = await postImage<unknown>(mode.path, selectedFile, mode.params)
      setRaw(data)
      setOverlay(mode.toOverlay(data))
      showToast('success', '分析完成')
    } catch (err) {
      const message = errorMessage(err, '分析失败，请稍后重试')
      setError(message)
      showToast('error', message)
    } finally {
      setIsLoading(false)
    }
  }

  const hasGraphics = overlay && (overlay.boxes.length > 0 || overlay.points.length > 0 || overlay.polygons.length > 0)

  return (
    <div className="max-w-6xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
      <PageHeader
        icon={ScanSearch}
        title="图像分析"
        description="选择一种分析方式，上传图片后查看结果。检测到的位置会直接标注在图片上。"
      />

      {mode.capability && mode.requirement && (
        <CapabilityNotice capabilities={capabilities} need={mode.capability} requirement={mode.requirement} />
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="space-y-4">
          <div className="bg-notion-bg-secondary rounded-notion p-4">
            <h3 className="font-medium text-notion-text mb-3">分析方式</h3>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
              {MODES.map((item) => (
                <button
                  key={item.id}
                  onClick={() => {
                    setModeId(item.id)
                    reset()
                  }}
                  disabled={isLoading}
                  title={item.description}
                  className={cn(
                    'px-3 py-2 text-sm rounded-notion-sm border notion-transition',
                    item.id === modeId
                      ? 'bg-notion-blue text-white border-notion-blue'
                      : 'bg-white text-notion-text border-notion-border hover:bg-notion-bg-hover'
                  )}
                >
                  {item.name}
                </button>
              ))}
            </div>
            <p className="mt-3 text-sm text-notion-text-secondary">{mode.description}</p>
          </div>

          <FileUpload
            onFileSelect={(file) => {
              setSelectedFile(file)
              reset()
            }}
            selectedFile={selectedFile}
            onClear={() => {
              setSelectedFile(null)
              reset()
            }}
            disabled={isLoading}
          />

          <RunButton
            onClick={handleRun}
            disabled={!selectedFile}
            loading={isLoading}
            label="开始分析"
            loadingLabel="分析中..."
          />
        </div>

        <div className="bg-notion-bg-secondary rounded-notion p-4 min-h-[400px]">
          <h3 className="font-medium text-notion-text mb-4">分析结果</h3>

          {error && <ErrorBox title="分析失败" message={error} />}
          {isLoading && <LoadingState text="正在分析图片..." />}
          {!overlay && !error && !isLoading && <EmptyState icon={ScanSearch} text="上传图片并点击开始分析" />}

          {overlay && (
            <div className="space-y-4">
              {hasGraphics && previewUrl && (
                <div className="relative inline-block max-w-full border border-notion-border rounded-notion-sm overflow-hidden bg-white">
                  <img src={previewUrl} alt="分析结果" className="block max-w-full max-h-[480px]" />
                  <svg
                    className="absolute inset-0 w-full h-full pointer-events-none"
                    viewBox="0 0 1 1"
                    preserveAspectRatio="none"
                  >
                    {overlay.boxes.map(({ box }, i) => (
                      <rect
                        key={`box-${i}`}
                        x={box.x}
                        y={1 - box.y - box.height}
                        width={box.width}
                        height={box.height}
                        fill="rgba(37, 99, 235, 0.12)"
                        stroke="#2563eb"
                        strokeWidth={2}
                        vectorEffect="non-scaling-stroke"
                      />
                    ))}
                    {overlay.polygons.map((polygon, i) => (
                      <polygon
                        key={`polygon-${i}`}
                        points={polygon.map((p) => `${p.x},${1 - p.y}`).join(' ')}
                        fill="rgba(22, 163, 74, 0.15)"
                        stroke="#16a34a"
                        strokeWidth={2}
                        vectorEffect="non-scaling-stroke"
                      />
                    ))}
                    {overlay.points.map((p, i) => (
                      <ellipse key={`point-${i}`} cx={p.x} cy={1 - p.y} rx={0.005} ry={0.005} fill="#dc2626" />
                    ))}
                  </svg>
                  {overlay.boxes.map(({ box, label }, i) =>
                    label ? (
                      <span
                        key={`label-${i}`}
                        className="absolute px-1 text-xs text-white bg-blue-600 rounded-sm pointer-events-none"
                        style={{ left: `${box.x * 100}%`, top: `${(1 - box.y - box.height) * 100}%` }}
                      >
                        {label}
                      </span>
                    ) : null
                  )}
                </div>
              )}

              <div className="bg-white border border-notion-border rounded-notion p-4">
                {overlay.summary.length > 0 ? (
                  <ul className="space-y-1 text-sm text-notion-text">
                    {overlay.summary.map((line, i) => (
                      <li key={i} className="break-all">{line}</li>
                    ))}
                  </ul>
                ) : (
                  <p className="text-sm text-notion-text-secondary">没有检测到内容</p>
                )}
              </div>

              <div>
                <button
                  onClick={() => setShowRaw((value) => !value)}
                  className="text-sm text-notion-blue hover:underline"
                >
                  {showRaw ? '隐藏原始 JSON' : '查看原始 JSON'}
                </button>
                {showRaw && (
                  <pre className="mt-2 max-h-80 overflow-auto bg-white border border-notion-border rounded-notion p-3 text-xs font-mono text-notion-text">
                    {JSON.stringify(raw, null, 2)}
                  </pre>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

export default VisionAnalysisPage
