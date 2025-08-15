import React, { useState } from 'react'
import Header from './Header'
import Sidebar from './Sidebar'

interface LayoutProps {
  children: React.ReactNode
}

const Layout: React.FC<LayoutProps> = ({ children }) => {
  const [sidebarOpen, setSidebarOpen] = useState(false)

  const handleToggleSidebar = () => {
    setSidebarOpen(!sidebarOpen)
  }

  const handleCloseSidebar = () => {
    setSidebarOpen(false)
  }

  return (
    <div className="flex h-screen bg-notion-bg">
      {/* 侧边栏 */}
      <Sidebar isOpen={sidebarOpen} onClose={handleCloseSidebar} />

      {/* 主内容区域 */}
      <div className="flex-1 flex flex-col lg:pl-64">
        {/* 顶部导航 */}
        <Header onMenuToggle={handleToggleSidebar} />

        {/* 页面内容 */}
        <main className="flex-1 overflow-auto">
          <div className="min-h-full">
            {children}
          </div>
        </main>
      </div>
    </div>
  )
}

export default Layout