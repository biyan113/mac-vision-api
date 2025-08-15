import React, { useEffect, useState } from 'react'
import { CheckCircle, AlertCircle, X, Info } from 'lucide-react'
import { cn } from '../../lib/utils'

export type ToastType = 'success' | 'error' | 'info'

interface ToastProps {
  type: ToastType
  message: string
  duration?: number
  onClose: () => void
}

const Toast: React.FC<ToastProps> = ({ 
  type, 
  message, 
  duration = 3000, 
  onClose 
}) => {
  const [isVisible, setIsVisible] = useState(true)

  useEffect(() => {
    const timer = setTimeout(() => {
      setIsVisible(false)
      setTimeout(onClose, 150) // Allow time for fade out animation
    }, duration)

    return () => clearTimeout(timer)
  }, [duration, onClose])

  const getIcon = () => {
    switch (type) {
      case 'success':
        return <CheckCircle className="w-5 h-5" />
      case 'error':
        return <AlertCircle className="w-5 h-5" />
      case 'info':
        return <Info className="w-5 h-5" />
    }
  }

  const getStyles = () => {
    switch (type) {
      case 'success':
        return 'bg-green-50 border-green-200 text-green-800'
      case 'error':
        return 'bg-red-50 border-red-200 text-red-800'
      case 'info':
        return 'bg-blue-50 border-blue-200 text-blue-800'
    }
  }

  return (
    <div
      className={cn(
        'fixed top-4 right-4 z-50 max-w-sm w-full notion-shadow rounded-notion border p-4 notion-transition transform',
        getStyles(),
        isVisible ? 'translate-x-0 opacity-100' : 'translate-x-full opacity-0'
      )}
    >
      <div className="flex items-start space-x-3">
        <div className="flex-shrink-0">
          {getIcon()}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium">
            {message}
          </p>
        </div>
        <button
          onClick={() => {
            setIsVisible(false)
            setTimeout(onClose, 150)
          }}
          className="flex-shrink-0 p-0.5 hover:bg-black hover:bg-opacity-10 rounded-notion-sm notion-transition"
        >
          <X className="w-4 h-4" />
        </button>
      </div>
    </div>
  )
}

// Toast管理器
interface ToastItem {
  id: string
  type: ToastType
  message: string
  duration?: number
}

let toastId = 0
const toastListeners: ((toasts: ToastItem[]) => void)[] = []
let toasts: ToastItem[] = []

export const showToast = (type: ToastType, message: string, duration?: number) => {
  const id = (++toastId).toString()
  const toast: ToastItem = { id, type, message, duration }
  
  toasts = [...toasts, toast]
  toastListeners.forEach(listener => listener(toasts))
  
  return id
}

export const removeToast = (id: string) => {
  toasts = toasts.filter(toast => toast.id !== id)
  toastListeners.forEach(listener => listener(toasts))
}

export const useToasts = () => {
  const [toastList, setToastList] = useState<ToastItem[]>(toasts)

  useEffect(() => {
    const listener = (newToasts: ToastItem[]) => {
      setToastList(newToasts)
    }
    
    toastListeners.push(listener)
    
    return () => {
      const index = toastListeners.indexOf(listener)
      if (index > -1) {
        toastListeners.splice(index, 1)
      }
    }
  }, [])

  return toastList
}

// Toast容器组件
export const ToastContainer: React.FC = () => {
  const toasts = useToasts()

  return (
    <>
      {toasts.map(toast => (
        <Toast
          key={toast.id}
          type={toast.type}
          message={toast.message}
          duration={toast.duration}
          onClose={() => removeToast(toast.id)}
        />
      ))}
    </>
  )
}

export default Toast