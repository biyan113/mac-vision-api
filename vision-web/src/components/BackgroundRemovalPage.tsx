import React, { useState, useCallback } from 'react'
import { Scissors, Download, Loader2, AlertCircle, ImageIcon, RefreshCw } from 'lucide-react'
import FileUpload from './ui/FileUpload'
import { removeBackground } from '../services/api'
import { showToast } from './ui/Toast'
import { cn } from '../lib/utils'

const BackgroundRemovalPage: React.FC = () => {
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [processedImage, setProcessedImage] = useState<string | null>(null)
  const [error, setError] = useState<string>('')

  const handleFileSelect = useCallback((file: File) => {
    setSelectedFile(file)
    setProcessedImage(null)
    setError('')
  }, [])

  const handleClearFile = useCallback(() => {
    setSelectedFile(null)
    setProcessedImage(null)
    setError('')
  }, [])

  const handleRemoveBackground = async () => {
    if (!selectedFile) return

    setIsLoading(true)
    setError('')
    setProcessedImage(null)

    try {
      const resultBlob = await removeBackground({ imageFile: selectedFile })
      const imageUrl = URL.createObjectURL(resultBlob)
      setProcessedImage(imageUrl)
      showToast('success', '背景移除完成！')
    } catch (err: any) {
      let errorMessage = '背景移除失败，请稍后重试'
      if (err.response?.status === 404) {
        errorMessage = '背景移除功能需要 macOS 15.0 或更高版本'
      } else {
        errorMessage = err.response?.data?.message || err.message || errorMessage
      }
      setError(errorMessage)
      showToast('error', errorMessage)
    } finally {
      setIsLoading(false)
    }
  }

  const handleDownloadImage = () => {
    if (!processedImage) return

    const a = document.createElement('a')
    a.href = processedImage
    a.download = `background-removed-${Date.now()}.png`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    showToast('success', 'PNG 图片已下载')
  }

  const handleTryAgain = () => {
    setError('')
    setProcessedImage(null)
  }

  return (
    <div className="max-w-6xl mx-auto p-6 space-y-6">
      {/* 页面标题 */}
      <div className="space-y-2">
        <div className="flex items-center space-x-3">
          <Scissors className="w-8 h-8 text-notion-blue" />
          <h1 className="text-3xl font-bold text-notion-text">背景移除</h1>
        </div>
        <p className="text-notion-text-secondary">
          自动识别图片主体，移除背景，生成透明背景的 PNG 图片。
        </p>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        {/* 左侧：文件上传 */}
        <div className="space-y-4">
          <div>
            <h3 className="font-medium text-notion-text mb-3">上传图片</h3>
            <FileUpload
              onFileSelect={handleFileSelect}
              selectedFile={selectedFile}
              onClear={handleClearFile}
              disabled={isLoading}
            />
          </div>

          {/* 处理按钮 */}
          <button
            onClick={handleRemoveBackground}
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
                <span>处理中...</span>
              </>
            ) : (
              <>
                <Scissors className="w-4 h-4" />
                <span>移除背景</span>
              </>
            )}
          </button>

          {/* 功能说明 */}
          <div className="bg-notion-blue-light/20 border border-notion-blue/20 rounded-notion p-4">
            <h4 className="font-medium text-notion-text mb-2">功能特点</h4>
            <ul className="text-notion-text-secondary text-sm space-y-1">
              <li>• 自动识别主体对象</li>
              <li>• 智能边缘处理</li>
              <li>• 输出透明背景 PNG</li>
              <li>• 支持人物、物品等</li>
            </ul>
          </div>

          {/* 系统要求 */}
          <div className="bg-notion-bg-secondary rounded-notion p-4">
            <h4 className="font-medium text-notion-text mb-2">系统要求</h4>
            <p className="text-notion-text-secondary text-sm">
              此功能需要运行在 macOS 15.0 或更高版本的服务器上。
            </p>
          </div>
        </div>

        {/* 中间：原图预览 */}
        <div className="space-y-4">
          <h3 className="font-medium text-notion-text">原图</h3>
          <div className="bg-notion-bg-secondary rounded-notion p-4 min-h-[400px] flex items-center justify-center">
            {selectedFile ? (
              <div className="max-w-full max-h-96">
                <img
                  src={URL.createObjectURL(selectedFile)}
                  alt="Original"
                  className="max-w-full max-h-full object-contain rounded-notion-sm border border-notion-border"
                />
              </div>
            ) : (
              <div className="text-center text-notion-text-secondary">
                <ImageIcon className="w-12 h-12 mx-auto mb-2 opacity-50" />
                <p>请上传图片</p>
              </div>
            )}
          </div>
        </div>

        {/* 右侧：处理结果 */}
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="font-medium text-notion-text">处理结果</h3>
            {processedImage && (
              <button
                onClick={handleDownloadImage}
                className="flex items-center space-x-1 px-3 py-2 bg-notion-blue text-white rounded-notion-sm hover:bg-blue-600 notion-transition"
              >
                <Download className="w-4 h-4" />
                <span>下载</span>
              </button>
            )}
          </div>

          <div className="bg-notion-bg-secondary rounded-notion p-4 min-h-[400px] flex items-center justify-center">
            {error && (
              <div className="text-center">
                <div className="flex items-start space-x-2 text-red-600 bg-red-50 p-4 rounded-notion mb-4">
                  <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
                  <div className="text-left">
                    <p className="font-medium">处理失败</p>
                    <p className="text-sm">{error}</p>
                  </div>
                </div>
                <button
                  onClick={handleTryAgain}
                  className="flex items-center space-x-2 px-4 py-2 bg-notion-gray text-white rounded-notion-sm hover:bg-gray-600 notion-transition mx-auto"
                >
                  <RefreshCw className="w-4 h-4" />
                  <span>重试</span>
                </button>
              </div>
            )}

            {processedImage && (
              <div className="max-w-full max-h-96">
                {/* 棋盘格背景显示透明效果 */}
                <div 
                  className="rounded-notion-sm border border-notion-border p-2"
                  style={{
                    backgroundImage: `
                      linear-gradient(45deg, #f0f0f0 25%, transparent 25%),
                      linear-gradient(-45deg, #f0f0f0 25%, transparent 25%),
                      linear-gradient(45deg, transparent 75%, #f0f0f0 75%),
                      linear-gradient(-45deg, transparent 75%, #f0f0f0 75%)
                    `,
                    backgroundSize: '20px 20px',
                    backgroundPosition: '0 0, 0 10px, 10px -10px, -10px 0px'
                  }}
                >
                  <img
                    src={processedImage}
                    alt="Background Removed"
                    className="max-w-full max-h-full object-contain"
                  />
                </div>
              </div>
            )}

            {!processedImage && !error && !isLoading && (
              <div className="text-center text-notion-text-secondary">
                <Scissors className="w-12 h-12 mx-auto mb-2 opacity-50" />
                <p>处理结果将显示在这里</p>
              </div>
            )}

            {isLoading && (
              <div className="text-center text-notion-text-secondary">
                <Loader2 className="w-8 h-8 mx-auto mb-2 animate-spin" />
                <p>正在移除背景...</p>
                <p className="text-xs mt-2">这可能需要几秒钟</p>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

export default BackgroundRemovalPage