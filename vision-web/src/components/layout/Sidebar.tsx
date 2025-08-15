import React from 'react'
import { NavLink } from 'react-router-dom'
import { FileText, Scissors, Home, ExternalLink, File } from 'lucide-react'
import { cn } from '../../lib/utils'

interface SidebarProps {
  isOpen: boolean
  onClose: () => void
}

const navigation = [
  {
    name: '首页',
    href: '/',
    icon: Home
  },
  {
    name: 'OCR 文字识别',
    href: '/ocr',
    icon: FileText
  },
  {
    name: '背景移除',
    href: '/background-removal',
    icon: Scissors
  },
  {
    name: 'PDF 处理',
    href: '/pdf',
    icon: File
  }
]

const Sidebar: React.FC<SidebarProps> = ({ isOpen, onClose }) => {
  return (
    <>
      {/* 移动端遮罩 */}
      {isOpen && (
        <div 
          className="fixed inset-0 bg-black bg-opacity-25 z-40 lg:hidden"
          onClick={onClose}
        />
      )}

      {/* 侧边栏 */}
      <div className={cn(
        'fixed inset-y-0 left-0 z-50 w-64 bg-notion-sidebar-bg border-r border-notion-border transform transition-transform duration-200 ease-in-out lg:translate-x-0 lg:static lg:inset-0',
        isOpen ? 'translate-x-0' : '-translate-x-full'
      )}>
        <div className="flex flex-col h-full">
          {/* 标题区域 */}
          <div className="flex items-center justify-between h-16 px-6 border-b border-notion-border">
            <div className="flex items-center space-x-3">
              <div className="w-8 h-8 bg-notion-blue rounded-notion-sm flex items-center justify-center">
                <span className="text-white font-bold text-sm">V</span>
              </div>
              <h1 className="text-lg font-semibold text-notion-text">Vision API</h1>
            </div>
          </div>

          {/* 导航菜单 */}
          <nav className="flex-1 px-4 py-6 space-y-1">
            {navigation.map((item) => (
              <NavLink
                key={item.name}
                to={item.href}
                onClick={onClose}
                className={({ isActive }) => cn(
                  'flex items-center px-3 py-2 text-sm font-medium rounded-notion-sm notion-transition',
                  isActive
                    ? 'bg-notion-blue text-white'
                    : 'text-notion-text-secondary hover:bg-notion-bg-hover hover:text-notion-text'
                )}
              >
                <item.icon className="w-5 h-5 mr-3" />
                {item.name}
              </NavLink>
            ))}
          </nav>

          {/* 底部信息 */}
          <div className="px-4 py-6 border-t border-notion-border">
            <div className="space-y-3">
              <a
                href="http://localhost:8080/Swagger/index.html"
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center px-3 py-2 text-sm text-notion-text-secondary hover:text-notion-text hover:bg-notion-bg-hover rounded-notion-sm notion-transition"
              >
                <ExternalLink className="w-4 h-4 mr-3" />
                API 文档
              </a>
              
              <div className="px-3 py-2">
                <p className="text-xs text-notion-text-light">
                  Vision API Web Interface
                </p>
                <p className="text-xs text-notion-text-light">
                  v1.0.0
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  )
}

export default Sidebar