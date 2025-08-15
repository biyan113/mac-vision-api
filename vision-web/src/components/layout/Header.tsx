import React, { useState, useEffect } from 'react'
import { Menu, Wifi, WifiOff, Activity } from 'lucide-react'
import { checkServerHealth } from '../../services/api'
import { cn } from '../../lib/utils'
import ApiConfig from '../ApiConfig'

interface HeaderProps {
  onMenuToggle: () => void
}

const Header: React.FC<HeaderProps> = ({ onMenuToggle }) => {
  const [serverStatus, setServerStatus] = useState<'checking' | 'online' | 'offline'>('checking')

  const checkHealth = async () => {
    setServerStatus('checking')
    const result = await checkServerHealth()
    setServerStatus(result.isHealthy ? 'online' : 'offline')
  }

  useEffect(() => {
    checkHealth()
    
    // 每30秒检查一次服务器状态
    const interval = setInterval(checkHealth, 30000)
    
    return () => clearInterval(interval)
  }, [])

  const handleConfigChange = () => {
    // API配置更改后重新检查服务器状态
    checkHealth()
  }

  const getStatusColor = () => {
    switch (serverStatus) {
      case 'online':
        return 'text-green-600'
      case 'offline':
        return 'text-red-600'
      default:
        return 'text-yellow-600'
    }
  }

  const getStatusText = () => {
    switch (serverStatus) {
      case 'online':
        return '服务正常'
      case 'offline':
        return '服务离线'
      default:
        return '检查中'
    }
  }

  const getStatusIcon = () => {
    switch (serverStatus) {
      case 'online':
        return <Wifi className="w-4 h-4" />
      case 'offline':
        return <WifiOff className="w-4 h-4" />
      default:
        return <Activity className="w-4 h-4 animate-pulse" />
    }
  }

  return (
    <header className="bg-white border-b border-notion-border">
      <div className="flex items-center justify-between h-16 px-4 lg:px-6">
        {/* 左侧：菜单按钮 */}
        <div className="flex items-center">
          <button
            onClick={onMenuToggle}
            className="p-2 rounded-notion-sm hover:bg-notion-bg-hover notion-transition lg:hidden"
          >
            <Menu className="w-5 h-5 text-notion-text" />
          </button>

          {/* 桌面端标题 */}
          <div className="hidden lg:block">
            <div className="flex items-center space-x-3">
              <div className="w-6 h-6 bg-notion-blue rounded-notion-sm flex items-center justify-center">
                <span className="text-white font-bold text-xs">V</span>
              </div>
              <h1 className="text-lg font-semibold text-notion-text">Vision API</h1>
            </div>
          </div>
        </div>

        {/* 右侧：API配置和服务器状态 */}
        <div className="flex items-center space-x-4">
          <ApiConfig onConfigChange={handleConfigChange} />
          <div className={cn(
            'flex items-center space-x-2 px-3 py-1.5 rounded-notion text-sm',
            'bg-notion-bg-secondary border border-notion-border',
            getStatusColor()
          )}>
            {getStatusIcon()}
            <span className="hidden sm:inline">{getStatusText()}</span>
          </div>
        </div>
      </div>
    </header>
  )
}

export default Header