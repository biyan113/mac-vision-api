import React, { Component } from 'react'
import type { ReactNode } from 'react'
import { AlertTriangle, RefreshCw } from 'lucide-react'

interface Props {
  children: ReactNode
}

interface State {
  hasError: boolean
  error?: Error
}

class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props)
    this.state = { hasError: false }
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('Error Boundary caught an error:', error, errorInfo)
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: undefined })
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen flex items-center justify-center bg-notion-bg p-4">
          <div className="max-w-md w-full bg-white rounded-notion notion-shadow p-8 text-center">
            <div className="w-16 h-16 bg-red-50 rounded-notion flex items-center justify-center mx-auto mb-4">
              <AlertTriangle className="w-8 h-8 text-red-600" />
            </div>
            
            <h1 className="text-xl font-semibold text-notion-text mb-2">
              出错了
            </h1>
            
            <p className="text-notion-text-secondary mb-6">
              应用程序遇到了一个错误。请尝试刷新页面或联系技术支持。
            </p>
            
            {this.state.error && (
              <details className="mb-6 text-left">
                <summary className="cursor-pointer text-notion-text-secondary text-sm mb-2">
                  错误详情
                </summary>
                <div className="bg-notion-bg-secondary rounded-notion-sm p-3 text-xs font-mono text-notion-text break-all">
                  {this.state.error.message}
                </div>
              </details>
            )}
            
            <div className="space-y-3">
              <button
                onClick={this.handleRetry}
                className="w-full flex items-center justify-center space-x-2 bg-notion-blue text-white py-2 px-4 rounded-notion hover:bg-blue-600 notion-transition"
              >
                <RefreshCw className="w-4 h-4" />
                <span>重试</span>
              </button>
              
              <button
                onClick={() => window.location.reload()}
                className="w-full py-2 px-4 border border-notion-border text-notion-text rounded-notion hover:bg-notion-bg-hover notion-transition"
              >
                刷新页面
              </button>
            </div>
          </div>
        </div>
      )
    }

    return this.props.children
  }
}

export default ErrorBoundary