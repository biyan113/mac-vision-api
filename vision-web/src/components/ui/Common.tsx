import React from 'react'
import { AlertCircle, AlertTriangle, Loader2 } from 'lucide-react'
import { cn } from '../../lib/utils'
import type { Capabilities } from '../../services/api'

export const PageHeader: React.FC<{
  icon: React.ComponentType<{ className?: string }>
  title: string
  description: string
}> = ({ icon: Icon, title, description }) => (
  <div className="mb-8">
    <div className="flex items-center space-x-3 mb-2">
      <div className="p-2 bg-notion-blue-light rounded-notion">
        <Icon className="w-6 h-6 text-notion-blue" />
      </div>
      <h1 className="text-3xl font-bold text-notion-text">{title}</h1>
    </div>
    <p className="text-notion-text-secondary">{description}</p>
  </div>
)

export const RunButton: React.FC<{
  onClick: () => void
  disabled?: boolean
  loading?: boolean
  label: string
  loadingLabel: string
}> = ({ onClick, disabled, loading, label, loadingLabel }) => (
  <button
    onClick={onClick}
    disabled={disabled || loading}
    className={cn(
      'w-full py-3 px-4 rounded-notion font-medium notion-transition',
      'bg-notion-blue text-white hover:bg-blue-600',
      'disabled:opacity-50 disabled:cursor-not-allowed',
      'flex items-center justify-center space-x-2'
    )}
  >
    {loading && <Loader2 className="w-4 h-4 animate-spin" />}
    <span>{loading ? loadingLabel : label}</span>
  </button>
)

export const ErrorBox: React.FC<{ title?: string; message: string }> = ({ title = '处理失败', message }) => (
  <div className="flex items-start space-x-2 text-red-600 bg-red-50 p-3 rounded-notion">
    <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
    <div>
      <p className="font-medium">{title}</p>
      <p className="text-sm">{message}</p>
    </div>
  </div>
)

/** 后端明确报告某项能力不可用时显示的提示 */
export const CapabilityNotice: React.FC<{
  capabilities: Capabilities | null
  need: keyof Capabilities
  requirement: string
}> = ({ capabilities, need, requirement }) => {
  if (!capabilities || capabilities[need]) return null
  return (
    <div className="mb-6 flex items-start space-x-2 text-yellow-800 bg-yellow-50 border border-yellow-200 p-3 rounded-notion">
      <AlertTriangle className="w-5 h-5 flex-shrink-0 mt-0.5" />
      <p className="text-sm">当前后端不支持此功能：需要 {requirement}。</p>
    </div>
  )
}

export const EmptyState: React.FC<{
  icon: React.ComponentType<{ className?: string }>
  text: string
}> = ({ icon: Icon, text }) => (
  <div className="flex items-center justify-center min-h-[240px] text-notion-text-secondary">
    <div className="text-center">
      <Icon className="w-12 h-12 mx-auto mb-2 opacity-50" />
      <p>{text}</p>
    </div>
  </div>
)

export const LoadingState: React.FC<{ text: string }> = ({ text }) => (
  <div className="flex items-center justify-center min-h-[240px] text-notion-text-secondary">
    <div className="text-center">
      <Loader2 className="w-8 h-8 mx-auto mb-2 animate-spin" />
      <p>{text}</p>
    </div>
  </div>
)
