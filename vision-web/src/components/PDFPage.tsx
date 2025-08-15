import React, { useState, useCallback } from 'react'
import { FileText, Download, Loader2, AlertCircle, Image, Type } from 'lucide-react'
import FileUpload from './ui/FileUpload'
import { renderPDF, extractPDFText } from '../services/pdfApi'
import type { PDFRenderRequest, PDFTextRequest, PDFTextResponse } from '../services/pdfApi'
import { showToast } from './ui/Toast'
import { cn } from '../lib/utils'

const PDFPage: React.FC = () => {
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [activeTab, setActiveTab] = useState<'render' | 'extract'>('render')
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string>('')
  
  // 渲染相关状态
  const [renderedImage, setRenderedImage] = useState<string>('')
  const [renderSettings, setRenderSettings] = useState({
    pageIndex: 0,
    dpi: 150
  })
  
  // 文本抽取相关状态
  const [extractedText, setExtractedText] = useState<PDFTextResponse | null>(null)
  const [extractSettings, setExtractSettings] = useState({
    startPage: 0,
    endPage: undefined as number | undefined,
    mergePages: true
  })

  const handleFileSelect = useCallback((file: File | null) => {
    setSelectedFile(file)
    setError('')
    setRenderedImage('')
    setExtractedText(null)
  }, [])

  const handleRenderPDF = async () => {
    if (!selectedFile) {
      showToast('error', '请先选择PDF文件')
      return
    }

    setIsLoading(true)
    setError('')
    setRenderedImage('')

    try {
      const request: PDFRenderRequest = {
        pdfFile: selectedFile,
        pageIndex: renderSettings.pageIndex,
        dpi: renderSettings.dpi
      }

      const blob = await renderPDF(request)
      const imageUrl = URL.createObjectURL(blob)
      setRenderedImage(imageUrl)
      showToast('success', 'PDF渲染成功')
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : '渲染失败'
      setError(errorMessage)
      showToast('error', `渲染失败: ${errorMessage}`)
    } finally {
      setIsLoading(false)
    }
  }

  const handleExtractText = async () => {
    if (!selectedFile) {
      showToast('error', '请先选择PDF文件')
      return
    }

    setIsLoading(true)
    setError('')
    setExtractedText(null)

    try {
      const request: PDFTextRequest = {
        pdfFile: selectedFile,
        startPage: extractSettings.startPage,
        endPage: extractSettings.endPage,
        mergePages: extractSettings.mergePages
      }

      const result = await extractPDFText(request)
      setExtractedText(result)
      showToast('success', `成功抽取${result.extractedPages.length}页文本`)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : '文本抽取失败'
      setError(errorMessage)
      showToast('error', `文本抽取失败: ${errorMessage}`)
    } finally {
      setIsLoading(false)
    }
  }

  const downloadRenderedImage = () => {
    if (!renderedImage) return
    
    const link = document.createElement('a')
    link.href = renderedImage
    link.download = `pdf_page_${renderSettings.pageIndex + 1}.png`
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
  }

  const downloadExtractedText = () => {
    if (!extractedText) return
    
    const text = extractSettings.mergePages ? 
      extractedText.allText || '' : 
      extractedText.extractedPages.map(page => 
        `=== 第${page.pageNumber}页 ===\n${page.text}`
      ).join('\n\n')
    
    const blob = new Blob([text], { type: 'text/plain;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = 'extracted_text.txt'
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    URL.revokeObjectURL(url)
  }

  const copyToClipboard = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text)
      showToast('success', '文本已复制到剪贴板')
    } catch (error) {
      showToast('error', '复制失败')
    }
  }

  return (
    <div className="max-w-6xl mx-auto p-6 space-y-6">
      {/* 页面标题 */}
      <div className="text-center space-y-2">
        <div className="flex items-center justify-center space-x-3">
          <div className="w-12 h-12 bg-red-100 rounded-xl flex items-center justify-center">
            <FileText className="w-6 h-6 text-red-600" />
          </div>
          <div>
            <h1 className="text-3xl font-bold text-gray-900">PDF处理</h1>
            <p className="text-gray-600">PDF渲染为位图和原生文本层抽取</p>
          </div>
        </div>
      </div>

      {/* 文件上传区域 */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">选择PDF文件</h2>
        <FileUpload
          selectedFile={selectedFile}
          onFileSelect={handleFileSelect}
          onClear={() => handleFileSelect(null)}
          accept={{'.pdf': ['application/pdf']}}
          maxSize={50 * 1024 * 1024} // 50MB
          className="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center hover:border-red-400 transition-colors"
        />
        {selectedFile && (
          <div className="mt-4 p-3 bg-gray-50 rounded-lg">
            <p className="text-sm text-gray-600">
              已选择: <span className="font-medium">{selectedFile.name}</span>
              <span className="ml-2 text-gray-400">
                ({(selectedFile.size / (1024 * 1024)).toFixed(2)} MB)
              </span>
            </p>
          </div>
        )}
      </div>

      {/* 功能选项卡 */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
        <div className="border-b border-gray-200">
          <nav className="flex">
            <button
              onClick={() => setActiveTab('render')}
              className={cn(
                'flex items-center gap-2 px-6 py-4 text-sm font-medium border-b-2 transition-colors',
                activeTab === 'render'
                  ? 'border-red-500 text-red-600 bg-red-50'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:bg-gray-50'
              )}
            >
              <Image className="w-4 h-4" />
              PDF渲染为位图
            </button>
            <button
              onClick={() => setActiveTab('extract')}
              className={cn(
                'flex items-center gap-2 px-6 py-4 text-sm font-medium border-b-2 transition-colors',
                activeTab === 'extract'
                  ? 'border-red-500 text-red-600 bg-red-50'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:bg-gray-50'
              )}
            >
              <Type className="w-4 h-4" />
              文本层抽取
            </button>
          </nav>
        </div>

        <div className="p-6">
          {activeTab === 'render' && (
            <div className="space-y-6">
              {/* 渲染设置 */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    页面索引（从0开始）
                  </label>
                  <input
                    type="number"
                    min="0"
                    value={renderSettings.pageIndex}
                    onChange={(e) => setRenderSettings(prev => ({
                      ...prev,
                      pageIndex: parseInt(e.target.value) || 0
                    }))}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-red-500"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    输出DPI
                  </label>
                  <select
                    value={renderSettings.dpi}
                    onChange={(e) => setRenderSettings(prev => ({
                      ...prev,
                      dpi: parseInt(e.target.value)
                    }))}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-red-500"
                  >
                    <option value={72}>72 DPI (低质量)</option>
                    <option value={150}>150 DPI (标准)</option>
                    <option value={300}>300 DPI (高质量)</option>
                    <option value={600}>600 DPI (超高质量)</option>
                  </select>
                </div>
              </div>

              {/* 渲染按钮 */}
              <button
                onClick={handleRenderPDF}
                disabled={!selectedFile || isLoading}
                className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-red-600 text-white font-medium rounded-lg hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                {isLoading ? (
                  <Loader2 className="w-5 h-5 animate-spin" />
                ) : (
                  <Image className="w-5 h-5" />
                )}
                {isLoading ? '渲染中...' : '渲染PDF'}
              </button>

              {/* 渲染结果 */}
              {renderedImage && (
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <h3 className="text-lg font-medium text-gray-900">渲染结果</h3>
                    <button
                      onClick={downloadRenderedImage}
                      className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-red-600 bg-red-50 border border-red-200 rounded-md hover:bg-red-100 transition-colors"
                    >
                      <Download className="w-4 h-4" />
                      下载图片
                    </button>
                  </div>
                  <div className="border border-gray-200 rounded-lg overflow-hidden">
                    <img
                      src={renderedImage}
                      alt="渲染结果"
                      className="w-full h-auto max-h-96 object-contain bg-gray-50"
                    />
                  </div>
                </div>
              )}
            </div>
          )}

          {activeTab === 'extract' && (
            <div className="space-y-6">
              {/* 抽取设置 */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    起始页面（从0开始）
                  </label>
                  <input
                    type="number"
                    min="0"
                    value={extractSettings.startPage}
                    onChange={(e) => setExtractSettings(prev => ({
                      ...prev,
                      startPage: parseInt(e.target.value) || 0
                    }))}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-red-500"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    结束页面（可选）
                  </label>
                  <input
                    type="number"
                    min="0"
                    value={extractSettings.endPage || ''}
                    onChange={(e) => setExtractSettings(prev => ({
                      ...prev,
                      endPage: e.target.value ? parseInt(e.target.value) : undefined
                    }))}
                    placeholder="留空表示到最后一页"
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-red-500"
                  />
                </div>
                <div className="flex items-center">
                  <label className="flex items-center space-x-2">
                    <input
                      type="checkbox"
                      checked={extractSettings.mergePages}
                      onChange={(e) => setExtractSettings(prev => ({
                        ...prev,
                        mergePages: e.target.checked
                      }))}
                      className="w-4 h-4 text-red-600 border-gray-300 rounded focus:ring-red-500"
                    />
                    <span className="text-sm font-medium text-gray-700">合并页面文本</span>
                  </label>
                </div>
              </div>

              {/* 抽取按钮 */}
              <button
                onClick={handleExtractText}
                disabled={!selectedFile || isLoading}
                className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-red-600 text-white font-medium rounded-lg hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                {isLoading ? (
                  <Loader2 className="w-5 h-5 animate-spin" />
                ) : (
                  <Type className="w-5 h-5" />
                )}
                {isLoading ? '抽取中...' : '抽取文本'}
              </button>

              {/* 抽取结果 */}
              {extractedText && (
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <h3 className="text-lg font-medium text-gray-900">
                      抽取结果 (共{extractedText.totalPages}页)
                    </h3>
                    <button
                      onClick={downloadExtractedText}
                      className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-red-600 bg-red-50 border border-red-200 rounded-md hover:bg-red-100 transition-colors"
                    >
                      <Download className="w-4 h-4" />
                      下载文本
                    </button>
                  </div>

                  {extractSettings.mergePages && extractedText.allText ? (
                    <div className="border border-gray-200 rounded-lg">
                      <div className="flex items-center justify-between p-3 bg-gray-50 border-b border-gray-200">
                        <span className="text-sm font-medium text-gray-700">合并文本</span>
                        <button
                          onClick={() => copyToClipboard(extractedText.allText || '')}
                          className="text-xs text-red-600 hover:text-red-700"
                        >
                          复制
                        </button>
                      </div>
                      <div className="p-4 max-h-96 overflow-y-auto">
                        <pre className="text-sm text-gray-800 whitespace-pre-wrap font-mono">
                          {extractedText.allText}
                        </pre>
                      </div>
                    </div>
                  ) : (
                    <div className="space-y-3">
                      {extractedText.extractedPages.map((page) => (
                        <div key={page.pageNumber} className="border border-gray-200 rounded-lg">
                          <div className="flex items-center justify-between p-3 bg-gray-50 border-b border-gray-200">
                            <span className="text-sm font-medium text-gray-700">
                              第{page.pageNumber}页
                            </span>
                            <button
                              onClick={() => copyToClipboard(page.text)}
                              className="text-xs text-red-600 hover:text-red-700"
                            >
                              复制
                            </button>
                          </div>
                          <div className="p-4 max-h-48 overflow-y-auto">
                            <pre className="text-sm text-gray-800 whitespace-pre-wrap font-mono">
                              {page.text || '(此页面无文本内容)'}
                            </pre>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {/* 错误显示 */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4">
          <div className="flex items-start space-x-3">
            <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
            <div>
              <h3 className="text-sm font-medium text-red-800">处理失败</h3>
              <p className="text-sm text-red-700 mt-1">{error}</p>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export default PDFPage
