import React, { useEffect, useState } from 'react'
import { ArrowRight, Copy, Languages } from 'lucide-react'
import { showToast } from './ui/Toast'
import {
  CapabilityNotice, EmptyState, ErrorBox, LoadingState, PageHeader, RunButton,
} from './ui/Common'
import { copyWithToast } from '../lib/clipboard'
import { errorMessage, getTranslationLanguages, translateText } from '../services/api'
import type { TranslateResponse } from '../services/api'
import { useCapabilities } from '../hooks/useCapabilities'

const FALLBACK_LANGUAGES = ['en', 'zh', 'zh-TW', 'ja', 'ko', 'fr', 'de', 'es', 'ms', 'id', 'th', 'vi']

const selectClass =
  'w-full p-2 border border-notion-border rounded-notion-sm bg-white focus:outline-none focus:ring-2 focus:ring-notion-blue focus:border-transparent'

const TranslationPage: React.FC = () => {
  const capabilities = useCapabilities()
  const [languages, setLanguages] = useState<string[]>(FALLBACK_LANGUAGES)
  const [source, setSource] = useState('')
  const [target, setTarget] = useState('zh')
  const [text, setText] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState('')
  const [result, setResult] = useState<TranslateResponse | null>(null)

  useEffect(() => {
    getTranslationLanguages()
      .then((list) => {
        if (list.length > 0) {
          setLanguages(list)
          setTarget((current) => (list.includes(current) ? current : list[0]))
        }
      })
      .catch(() => {
        // 后端不支持或未启动时使用内置列表
      })
  }, [])

  const handleRun = async () => {
    if (!text.trim()) return
    setIsLoading(true)
    setError('')
    setResult(null)
    try {
      setResult(await translateText(text, target, source || undefined))
    } catch (err) {
      const message = errorMessage(err, '翻译失败，请稍后重试')
      setError(message)
      showToast('error', message)
    } finally {
      setIsLoading(false)
    }
  }

  const translated = result?.translations.join('\n') ?? ''

  return (
    <div className="max-w-6xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
      <PageHeader
        icon={Languages}
        title="翻译"
        description="使用系统翻译语言包在本机翻译文本。语言包需要先在“系统设置 → 通用 → 语言与地区 → 翻译语言”中下载。"
      />

      <CapabilityNotice capabilities={capabilities} need="translation" requirement="macOS 26 或更高版本" />

      <div className="bg-notion-bg-secondary rounded-notion p-4 mb-6">
        <div className="flex items-end space-x-3">
          <div className="flex-1">
            <label className="block text-sm font-medium text-notion-text mb-2">源语言</label>
            <select value={source} onChange={(e) => setSource(e.target.value)} disabled={isLoading} className={selectClass}>
              <option value="">自动检测</option>
              {languages.map((item) => (
                <option key={item} value={item}>{item}</option>
              ))}
            </select>
          </div>
          <ArrowRight className="w-5 h-5 mb-3 text-notion-text-secondary flex-shrink-0" />
          <div className="flex-1">
            <label className="block text-sm font-medium text-notion-text mb-2">目标语言</label>
            <select value={target} onChange={(e) => setTarget(e.target.value)} disabled={isLoading} className={selectClass}>
              {languages.map((item) => (
                <option key={item} value={item}>{item}</option>
              ))}
            </select>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="space-y-4">
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="输入或粘贴要翻译的文本"
            disabled={isLoading}
            className="w-full h-80 p-4 border border-notion-border rounded-notion text-sm text-notion-text leading-relaxed resize-none focus:outline-none focus:ring-2 focus:ring-notion-blue focus:border-transparent"
          />
          <RunButton
            onClick={handleRun}
            disabled={!text.trim()}
            loading={isLoading}
            label="翻译"
            loadingLabel="翻译中..."
          />
        </div>

        <div className="bg-notion-bg-secondary rounded-notion p-4 min-h-[400px]">
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-medium text-notion-text">
              译文{result ? `（${result.sourceLanguage} → ${result.targetLanguage}）` : ''}
            </h3>
            {result && (
              <button
                onClick={() => copyWithToast(translated)}
                className="flex items-center space-x-1 text-sm text-notion-blue hover:underline"
              >
                <Copy className="w-4 h-4" />
                <span>复制</span>
              </button>
            )}
          </div>

          {error && <ErrorBox title="翻译失败" message={error} />}
          {isLoading && <LoadingState text="正在翻译..." />}
          {!result && !error && !isLoading && <EmptyState icon={Languages} text="输入文本并点击翻译" />}

          {result && (
            <div className="bg-white border border-notion-border rounded-notion p-4">
              <pre className="whitespace-pre-wrap text-sm text-notion-text leading-relaxed font-sans">{translated}</pre>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

export default TranslationPage
