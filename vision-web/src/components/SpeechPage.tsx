import React, { useEffect, useState } from 'react'
import { Copy, Download, Mic } from 'lucide-react'
import FileUpload from './ui/FileUpload'
import { showToast } from './ui/Toast'
import {
  CapabilityNotice, EmptyState, ErrorBox, LoadingState, PageHeader, RunButton,
} from './ui/Common'
import { copyWithToast, downloadText } from '../lib/clipboard'
import { errorMessage, getSpeechLocales, transcribeAudio } from '../services/api'
import type { SpeechLocales, TranscribeResponse, TranscriptSegment } from '../services/api'
import { useCapabilities } from '../hooks/useCapabilities'

const AUDIO_ACCEPT = {
  'audio/*': ['.m4a', '.mp3', '.wav', '.caf', '.aac', '.aiff', '.flac'],
  'video/mp4': ['.mp4'],
  'video/quicktime': ['.mov'],
}

const pad = (value: number, length = 2) => String(value).padStart(length, '0')

const formatClock = (seconds: number) => {
  const total = Math.max(0, Math.floor(seconds))
  return `${pad(Math.floor(total / 60))}:${pad(total % 60)}`
}

const srtTime = (seconds: number) => {
  const ms = Math.max(0, Math.round(seconds * 1000))
  return `${pad(Math.floor(ms / 3600000))}:${pad(Math.floor(ms / 60000) % 60)}:${pad(Math.floor(ms / 1000) % 60)},${pad(ms % 1000, 3)}`
}

const toSRT = (segments: TranscriptSegment[]) =>
  segments
    .map((segment, index) =>
      `${index + 1}\n${srtTime(segment.start)} --> ${srtTime(segment.start + segment.duration)}\n${segment.text.trim()}\n`
    )
    .join('\n')

const SpeechPage: React.FC = () => {
  const capabilities = useCapabilities()
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [locales, setLocales] = useState<SpeechLocales | null>(null)
  const [locale, setLocale] = useState('en-US')
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState('')
  const [result, setResult] = useState<TranscribeResponse | null>(null)

  useEffect(() => {
    getSpeechLocales()
      .then(setLocales)
      .catch(() => {
        // 后端不支持或未启动时，保留手动输入
      })
  }, [])

  const reset = () => {
    setError('')
    setResult(null)
  }

  const handleRun = async () => {
    if (!selectedFile) return
    setIsLoading(true)
    reset()
    try {
      setResult(await transcribeAudio(selectedFile, locale.trim() || 'en-US'))
      showToast('success', '转写完成')
    } catch (err) {
      const message = errorMessage(err, '转写失败，请稍后重试')
      setError(message)
      showToast('error', message)
    } finally {
      setIsLoading(false)
    }
  }

  const baseName = selectedFile?.name.replace(/\.[^.]+$/, '') || 'transcript'
  const needsDownload = locales !== null && !locales.installed.includes(locale)

  return (
    <div className="max-w-6xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
      <PageHeader
        icon={Mic}
        title="语音转写"
        description="把音频文件转成带时间戳的文字，全程在本机处理。可导出为纯文本或 SRT 字幕。"
      />

      <CapabilityNotice capabilities={capabilities} need="speechTranscription" requirement="macOS 26 或更高版本" />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="space-y-4">
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
            accept={AUDIO_ACCEPT}
            maxSize={50 * 1024 * 1024}
            label="点击上传或拖拽音频文件"
            hint="支持 M4A、MP3、WAV、CAF、AAC、MP4、MOV 等格式"
            disabled={isLoading}
          />

          <div className="bg-notion-bg-secondary rounded-notion p-4">
            <label className="block text-sm font-medium text-notion-text mb-2">语言</label>
            {locales ? (
              <select
                value={locale}
                onChange={(e) => setLocale(e.target.value)}
                disabled={isLoading}
                className="w-full p-2 border border-notion-border rounded-notion-sm focus:outline-none focus:ring-2 focus:ring-notion-blue focus:border-transparent"
              >
                {!locales.supported.includes(locale) && <option value={locale}>{locale}</option>}
                {locales.supported.map((item) => (
                  <option key={item} value={item}>
                    {item}{locales.installed.includes(item) ? '（已安装）' : ''}
                  </option>
                ))}
              </select>
            ) : (
              <input
                type="text"
                value={locale}
                onChange={(e) => setLocale(e.target.value)}
                placeholder="例如 en-US、zh-CN"
                disabled={isLoading}
                className="w-full p-2 border border-notion-border rounded-notion-sm focus:outline-none focus:ring-2 focus:ring-notion-blue focus:border-transparent"
              />
            )}
            {needsDownload && (
              <p className="mt-2 text-xs text-notion-text-secondary">
                该语言的语音模型尚未安装，首次转写时会自动下载，耗时会更长。
              </p>
            )}
          </div>

          <RunButton
            onClick={handleRun}
            disabled={!selectedFile}
            loading={isLoading}
            label="开始转写"
            loadingLabel="转写中..."
          />
        </div>

        <div className="bg-notion-bg-secondary rounded-notion p-4 min-h-[400px]">
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-medium text-notion-text">转写结果</h3>
            {result && (
              <div className="flex items-center space-x-3 text-sm">
                <button
                  onClick={() => copyWithToast(result.text)}
                  className="flex items-center space-x-1 text-notion-blue hover:underline"
                >
                  <Copy className="w-4 h-4" />
                  <span>复制</span>
                </button>
                <button
                  onClick={() => downloadText(result.text, `${baseName}.txt`)}
                  className="flex items-center space-x-1 text-notion-blue hover:underline"
                >
                  <Download className="w-4 h-4" />
                  <span>TXT</span>
                </button>
                <button
                  onClick={() => downloadText(toSRT(result.segments), `${baseName}.srt`)}
                  className="flex items-center space-x-1 text-notion-blue hover:underline"
                >
                  <Download className="w-4 h-4" />
                  <span>SRT</span>
                </button>
              </div>
            )}
          </div>

          {error && <ErrorBox title="转写失败" message={error} />}
          {isLoading && <LoadingState text="正在转写，长音频需要一些时间..." />}
          {!result && !error && !isLoading && <EmptyState icon={Mic} text="上传音频并点击开始转写" />}

          {result && (
            <div className="bg-white border border-notion-border rounded-notion p-4 max-h-[560px] overflow-auto">
              {result.segments.length > 0 ? (
                <div className="space-y-2 text-sm">
                  {result.segments.map((segment, i) => (
                    <div key={i} className="flex space-x-3">
                      <span className="flex-shrink-0 font-mono text-notion-text-light">{formatClock(segment.start)}</span>
                      <span className="text-notion-text leading-relaxed">{segment.text}</span>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-notion-text-secondary">没有识别到语音内容</p>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

export default SpeechPage
