import React, { useState, useEffect } from 'react'
import { Settings, TestTube, CheckCircle, XCircle, Loader2 } from 'lucide-react'
import { setApiBaseUrl, getCurrentApiUrl, checkServerHealth } from '../services/api'
import { showToast } from './ui/Toast'

interface ApiConfigProps {
  onConfigChange?: () => void
}

const ApiConfig: React.FC<ApiConfigProps> = ({ onConfigChange }) => {
  const [isOpen, setIsOpen] = useState(false)
  const [apiUrl, setApiUrl] = useState('')
  const [isTesting, setIsTesting] = useState(false)
  const [testResult, setTestResult] = useState<{
    isHealthy: boolean
    message: string
    url: string
  } | null>(null)

  useEffect(() => {
    setApiUrl(getCurrentApiUrl())
  }, [])

  const handleSave = () => {
    if (!apiUrl.trim()) {
      showToast('error', '请输入有效的API地址')
      return
    }

    // 确保URL格式正确
    let formattedUrl = apiUrl.trim()
    if (!formattedUrl.startsWith('http://') && !formattedUrl.startsWith('https://')) {
      formattedUrl = 'http://' + formattedUrl
    }
    
    // 移除末尾的斜杠
    formattedUrl = formattedUrl.replace(/\/$/, '')

    setApiBaseUrl(formattedUrl)
    setApiUrl(formattedUrl)
    showToast('success', 'API地址已保存')
    setIsOpen(false)
    onConfigChange?.()
  }

  const handleTest = async () => {
    if (!apiUrl.trim()) {
      showToast('error', '请先输入API地址')
      return
    }

    setIsTesting(true)
    setTestResult(null)

    let testUrl = apiUrl.trim()
    if (!testUrl.startsWith('http://') && !testUrl.startsWith('https://')) {
      testUrl = 'http://' + testUrl
    }
    testUrl = testUrl.replace(/\/$/, '')

    try {
      const result = await checkServerHealth(testUrl)
      setTestResult(result)
      
      if (result.isHealthy) {
        showToast('success', '连接测试成功')
      } else {
        showToast('error', `连接测试失败: ${result.message}`)
      }
    } catch (error) {
      setTestResult({
        isHealthy: false,
        message: '测试失败',
        url: testUrl
      })
      showToast('error', '连接测试失败')
    } finally {
      setIsTesting(false)
    }
  }

  const handleReset = () => {
    const defaultUrl = process.env.NODE_ENV === 'production' ? '/api' : 'http://localhost:8080'
    setApiUrl(defaultUrl)
    setApiBaseUrl(defaultUrl)
    setTestResult(null)
    showToast('success', '已重置为默认地址')
    onConfigChange?.()
  }

  return (
    <div className="relative">
      {/* 配置按钮 */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
        title="API配置"
      >
        <Settings className="w-4 h-4" />
        API配置
      </button>

      {/* 配置面板 */}
      {isOpen && (
        <div className="absolute top-full right-0 mt-2 w-96 bg-white border border-gray-200 rounded-lg shadow-lg z-50">
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-medium text-gray-900">API接口配置</h3>
              <button
                onClick={() => setIsOpen(false)}
                className="text-gray-400 hover:text-gray-600"
              >
                ×
              </button>
            </div>

            <div className="space-y-4">
              {/* API地址输入 */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  后端API地址
                </label>
                <input
                  type="text"
                  value={apiUrl}
                  onChange={(e) => setApiUrl(e.target.value)}
                  placeholder="例如: http://localhost:8080"
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
                <p className="mt-1 text-xs text-gray-500">
                  输入后端服务的完整地址，包括协议和端口号
                </p>
              </div>

              {/* 测试结果 */}
              {testResult && (
                <div className={`p-3 rounded-md ${
                  testResult.isHealthy 
                    ? 'bg-green-50 border border-green-200' 
                    : 'bg-red-50 border border-red-200'
                }`}>
                  <div className="flex items-center gap-2">
                    {testResult.isHealthy ? (
                      <CheckCircle className="w-4 h-4 text-green-600" />
                    ) : (
                      <XCircle className="w-4 h-4 text-red-600" />
                    )}
                    <span className={`text-sm font-medium ${
                      testResult.isHealthy ? 'text-green-800' : 'text-red-800'
                    }`}>
                      {testResult.isHealthy ? '连接成功' : '连接失败'}
                    </span>
                  </div>
                  <p className={`mt-1 text-xs ${
                    testResult.isHealthy ? 'text-green-600' : 'text-red-600'
                  }`}>
                    {testResult.message}
                  </p>
                  <p className="mt-1 text-xs text-gray-500">
                    测试地址: {testResult.url}
                  </p>
                </div>
              )}

              {/* 操作按钮 */}
              <div className="flex gap-2">
                <button
                  onClick={handleTest}
                  disabled={isTesting}
                  className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-blue-700 bg-blue-50 border border-blue-200 rounded-md hover:bg-blue-100 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {isTesting ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <TestTube className="w-4 h-4" />
                  )}
                  {isTesting ? '测试中...' : '测试连接'}
                </button>

                <button
                  onClick={handleSave}
                  className="px-3 py-2 text-sm font-medium text-white bg-blue-600 border border-transparent rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
                  保存配置
                </button>

                <button
                  onClick={handleReset}
                  className="px-3 py-2 text-sm font-medium text-gray-700 bg-gray-100 border border-gray-300 rounded-md hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-500"
                >
                  重置默认
                </button>
              </div>

              {/* 当前配置显示 */}
              <div className="pt-3 border-t border-gray-200">
                <p className="text-xs text-gray-500">
                  当前API地址: <span className="font-mono">{getCurrentApiUrl()}</span>
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export default ApiConfig
