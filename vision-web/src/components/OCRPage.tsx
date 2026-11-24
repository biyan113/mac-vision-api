import React, { useState, useCallback, useEffect, useMemo } from 'react'
import { FileText, Settings, Copy, Download, Loader2, AlertCircle, CheckCircle } from 'lucide-react'
import FileUpload from './ui/FileUpload'
import { recognizeText } from '../services/api'
import type { OCRLine, OCRRequest, OCRResponse } from '../services/api'
import { showToast } from './ui/Toast'
import { cn } from '../lib/utils'

const OCRPage: React.FC = () => {
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [result, setResult] = useState<string>('')
  const [lines, setLines] = useState<OCRLine[]>([])
  const [view, setView] = useState<'text' | 'boxes'>('text')
  const [activeLine, setActiveLine] = useState<number | null>(null)
  const [error, setError] = useState<string>('')
  const [showSettings, setShowSettings] = useState(false)
  const [settings, setSettings] = useState({
    recognitionLanguages: 'zh-Hans,en-US',
    recognitionLevel: 0
  })
  const [copySuccess, setCopySuccess] = useState(false)

  const previewUrl = useMemo(() => (selectedFile ? URL.createObjectURL(selectedFile) : ''), [selectedFile])
  useEffect(() => () => {
    if (previewUrl) URL.revokeObjectURL(previewUrl)
  }, [previewUrl])

  const handleFileSelect = useCallback((file: File) => {
    setSelectedFile(file)
    setResult('')
    setLines([])
    setActiveLine(null)
    setError('')
  }, [])

  const handleClearFile = useCallback(() => {
    setSelectedFile(null)
    setResult('')
    setLines([])
    setActiveLine(null)
    setError('')
  }, [])

  const handleRecognizeText = async () => {
    if (!selectedFile) return

    setIsLoading(true)
    setError('')
    setResult('')
    setLines([])
    setActiveLine(null)

    try {
      const request: OCRRequest = {
        imageFile: selectedFile,
        recognitionLanguages: settings.recognitionLanguages || undefined,
        recognitionLevel: settings.recognitionLevel,
        includeLines: true
      }

      const response: OCRResponse = await recognizeText(request)
      setResult(response.text)
      setLines(response.lines ?? [])
      showToast('success', '文字识别完成！')
    } catch (err: any) {
      const errorMessage = err.response?.data?.reason || err.response?.data?.message || err.message || '识别失败，请稍后重试'
      setError(errorMessage)
      showToast('error', errorMessage)
    } finally {
      setIsLoading(false)
    }
  }

  const handleCopyText = async () => {
    if (!result) return
    
    try {
      await navigator.clipboard.writeText(result)
      setCopySuccess(true)
      showToast('success', '文本已复制到剪贴板')
      setTimeout(() => setCopySuccess(false), 2000)
    } catch (err) {
      console.error('复制失败:', err)
      showToast('error', '复制失败')
    }
  }

  const handleDownloadText = () => {
    if (!result) return

    const blob = new Blob([result], { type: 'text/plain;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `ocr-result-${Date.now()}.txt`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
    showToast('success', '文本文件已下载')
  }

  return (
    <div className="max-w-4xl mx-auto p-6 space-y-6">
      {/* 页面标题 */}
      <div className="space-y-2">
        <div className="flex items-center space-x-3">
          <FileText className="w-8 h-8 text-notion-blue" />
          <h1 className="text-3xl font-bold text-notion-text">OCR 文字识别</h1>
        </div>
        <p className="text-notion-text-secondary">
          上传图片，自动识别并提取图片中的文字内容，支持中文、英文等多种语言。
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* 左侧：文件上传和设置 */}
        <div className="space-y-4">
          <FileUpload
            onFileSelect={handleFileSelect}
            selectedFile={selectedFile}
            onClear={handleClearFile}
            disabled={isLoading}
          />

          {/* 设置面板 */}
          <div className="bg-notion-bg-secondary rounded-notion p-4">
            <button
              onClick={() => setShowSettings(!showSettings)}
              className="flex items-center justify-between w-full text-left"
            >
              <div className="flex items-center space-x-2">
                <Settings className="w-4 h-4 text-notion-text-secondary" />
                <span className="text-notion-text font-medium">识别设置</span>
              </div>
              <div className={cn(
                'transform transition-transform',
                showSettings && 'rotate-180'
              )}>
                ▼
              </div>
            </button>

            {showSettings && (
              <div className="mt-4 space-y-4">
                <div>
                  <label className="block text-sm font-medium text-notion-text mb-2">
                    识别语言
                  </label>
                  <select
                    value={settings.recognitionLanguages}
                    onChange={(e) => setSettings(prev => ({
                      ...prev,
                      recognitionLanguages: e.target.value
                    }))}
                    className="w-full p-2 border border-notion-border rounded-notion-sm focus:outline-none focus:ring-2 focus:ring-notion-blue focus:border-transparent"
                  >
                    <option value="zh-Hans,en-US">简体中文 + 英文</option>
                    <option value="zh-Hant,en-US">繁体中文 + 英文</option>
                    <option value="zh-Hans">仅简体中文</option>
                    <option value="en-US">仅英文</option>
                    <option value="">自动检测</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-notion-text mb-2">
                    识别精度
                  </label>
                  <select
                    value={settings.recognitionLevel}
                    onChange={(e) => setSettings(prev => ({
                      ...prev,
                      recognitionLevel: parseInt(e.target.value)
                    }))}
                    className="w-full p-2 border border-notion-border rounded-notion-sm focus:outline-none focus:ring-2 focus:ring-notion-blue focus:border-transparent"
                  >
                    <option value={0}>精确模式（推荐）</option>
                    <option value={1}>快速模式</option>
                  </select>
                </div>
              </div>
            )}
          </div>

          {/* 识别按钮 */}
          <button
            onClick={handleRecognizeText}
            disabled={!selectedFile || isLoading}
            className={cn(
              'w-full py-3 px-4 rounded-notion font-medium notion-transition',
              'bg-notion-blue text-white hover:bg-blue-600',
              'disabled:opacity-50 disabled:cursor-not-allowed',
              'flex items-center justify-center space-x-2'
            )}
          >
            {isLoading ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" />
                <span>识别中...</span>
              </>
            ) : (
              <>
                <FileText className="w-4 h-4" />
                <span>开始识别</span>
              </>
            )}
          </button>
        </div>

        {/* 右侧：识别结果 */}
        <div className="space-y-4">
          <div className="bg-notion-bg-secondary rounded-notion p-4 min-h-[400px]">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-medium text-notion-text">识别结果</h3>
              {result && (
                <div className="flex space-x-2">
                  <button
                    onClick={handleCopyText}
                    className={cn(
                      'p-2 rounded-notion-sm notion-transition',
                      'hover:bg-notion-bg-hover',
                      copySuccess && 'text-green-600'
                    )}
                    title="复制文本"
                  >
                    {copySuccess ? <CheckCircle className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
                  </button>
                  <button
                    onClick={handleDownloadText}
                    className="p-2 hover:bg-notion-bg-hover rounded-notion-sm notion-transition"
                    title="下载文本"
                  >
                    <Download className="w-4 h-4" />
                  </button>
                </div>
              )}
            </div>

            {/* 结果内容 */}
            <div className="min-h-[300px]">
              {error && (
                <div className="flex items-start space-x-2 text-red-600 bg-red-50 p-3 rounded-notion">
                  <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
                  <div>
                    <p className="font-medium">识别失败</p>
                    <p className="text-sm">{error}</p>
                  </div>
                </div>
              )}

              {result && lines.length > 0 && (
                <div className="inline-flex p-1 mb-3 rounded-notion-sm bg-white border border-notion-border text-sm">
                  <button
                    onClick={() => setView('text')}
                    aria-pressed={view === 'text'}
                    className={cn(
                      'px-3 py-1 rounded-notion-sm notion-transition',
                      view === 'text' ? 'bg-notion-blue text-white' : 'text-notion-text-secondary hover:text-notion-text'
                    )}
                  >
                    文本
                  </button>
                  <button
                    onClick={() => setView('boxes')}
                    aria-pressed={view === 'boxes'}
                    className={cn(
                      'px-3 py-1 rounded-notion-sm notion-transition',
                      view === 'boxes' ? 'bg-notion-blue text-white' : 'text-notion-text-secondary hover:text-notion-text'
                    )}
                  >
                    位置（{lines.length} 行）
                  </button>
                </div>
              )}

              {result && view === 'text' && (
                <div className="bg-white border border-notion-border rounded-notion p-4">
                  <pre className="whitespace-pre-wrap text-notion-text font-mono text-sm leading-relaxed">
                    {result}
                  </pre>
                </div>
              )}

              {result && view === 'boxes' && lines.length > 0 && (
                <div className="space-y-3">
                  {previewUrl && (
                    <div className="relative inline-block max-w-full border border-notion-border rounded-notion-sm overflow-hidden bg-white">
                      <img src={previewUrl} alt="识别位置" className="block max-w-full max-h-[420px]" />
                      {lines.map((line, index) => (
                        <button
                          key={index}
                          type="button"
                          aria-label={`第 ${index + 1} 行：${line.text}`}
                          title={line.text}
                          onMouseEnter={() => setActiveLine(index)}
                          onMouseLeave={() => setActiveLine(null)}
                          onFocus={() => setActiveLine(index)}
                          onBlur={() => setActiveLine(null)}
                          className={cn(
                            'absolute border-2 notion-transition',
                            activeLine === index
                              ? 'border-orange-500 bg-orange-400/30'
                              : 'border-blue-600 bg-blue-500/10'
                          )}
                          style={{
                            left: `${line.boundingBox.x * 100}%`,
                            top: `${(1 - line.boundingBox.y - line.boundingBox.height) * 100}%`,
                            width: `${line.boundingBox.width * 100}%`,
                            height: `${line.boundingBox.height * 100}%`
                          }}
                        />
                      ))}
                    </div>
                  )}
                  <ul className="bg-white border border-notion-border rounded-notion divide-y divide-notion-border max-h-64 overflow-auto">
                    {lines.map((line, index) => (
                      <li
                        key={index}
                        onMouseEnter={() => setActiveLine(index)}
                        onMouseLeave={() => setActiveLine(null)}
                        className={cn(
                          'flex items-start justify-between gap-3 px-3 py-2 text-sm',
                          activeLine === index && 'bg-orange-50'
                        )}
                      >
                        <span className="text-notion-text break-all">{line.text}</span>
                        <span className="flex-shrink-0 font-mono text-xs text-notion-text-secondary">
                          {(line.confidence * 100).toFixed(0)}%
                        </span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {!result && !error && !isLoading && (
                <div className="flex items-center justify-center h-full text-notion-text-secondary">
                  <div className="text-center">
                    <FileText className="w-12 h-12 mx-auto mb-2 opacity-50" />
                    <p>上传图片并点击识别按钮开始</p>
                  </div>
                </div>
              )}

              {isLoading && (
                <div className="flex items-center justify-center h-full text-notion-text-secondary">
                  <div className="text-center">
                    <Loader2 className="w-8 h-8 mx-auto mb-2 animate-spin" />
                    <p>正在识别图片中的文字...</p>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default OCRPage