import React from 'react'
import { Link } from 'react-router-dom'
import { FileText, Scissors, Eye, Zap, Shield, Globe } from 'lucide-react'

const HomePage: React.FC = () => {
  const features = [
    {
      title: 'OCR 文字识别',
      description: '强大的光学字符识别功能，支持中文、英文等多种语言，精确提取图片中的文字内容。',
      icon: FileText,
      href: '/ocr',
      color: 'bg-blue-50 text-blue-600 border-blue-200'
    },
    {
      title: '背景移除',
      description: '智能识别图片主体，自动移除背景，生成透明背景的 PNG 图片，完美适用于设计工作。',
      icon: Scissors,
      href: '/background-removal',
      color: 'bg-purple-50 text-purple-600 border-purple-200'
    }
  ]

  const advantages = [
    {
      title: '自托管解决方案',
      description: '无需依赖第三方云服务，保护数据隐私，完全掌控处理流程。',
      icon: Shield
    },
    {
      title: '基于 Apple Vision',
      description: '利用 Apple Vision 框架的先进机器学习技术，提供高质量的图像处理能力。',
      icon: Eye
    },
    {
      title: '高性能处理',
      description: '原生 Swift 实现，充分利用系统资源，快速处理各种图像任务。',
      icon: Zap
    },
    {
      title: '多语言支持',
      description: '支持中文、英文等多种语言的文字识别，满足不同地区用户需求。',
      icon: Globe
    }
  ]

  return (
    <div className="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
      {/* 标题区域 */}
      <div className="text-center mb-12">
        <div className="flex items-center justify-center mb-6">
          <div className="w-16 h-16 bg-notion-blue rounded-notion flex items-center justify-center">
            <span className="text-white font-bold text-2xl">V</span>
          </div>
        </div>
        <h1 className="text-4xl font-bold text-notion-text mb-4">
          Vision API
        </h1>
        <p className="text-xl text-notion-text-secondary max-w-3xl mx-auto leading-relaxed">
          基于 Apple Vision 框架的自托管图像处理 API 服务，提供 OCR 文字识别和背景移除等强大功能
        </p>
      </div>

      {/* 功能卡片 */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-8 mb-16">
        {features.map((feature) => (
          <Link
            key={feature.title}
            to={feature.href}
            className="block bg-white rounded-notion notion-shadow hover:notion-shadow-hover notion-transition p-6 border border-notion-border"
          >
            <div className="flex items-start space-x-4">
              <div className={`p-3 rounded-notion border ${feature.color}`}>
                <feature.icon className="w-6 h-6" />
              </div>
              <div className="flex-1">
                <h3 className="text-lg font-semibold text-notion-text mb-2">
                  {feature.title}
                </h3>
                <p className="text-notion-text-secondary leading-relaxed">
                  {feature.description}
                </p>
                <div className="mt-4">
                  <span className="inline-flex items-center text-notion-blue font-medium text-sm">
                    立即使用 →
                  </span>
                </div>
              </div>
            </div>
          </Link>
        ))}
      </div>

      {/* 优势特点 */}
      <div className="mb-16">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold text-notion-text mb-4">
            为什么选择 Vision API？
          </h2>
          <p className="text-notion-text-secondary max-w-2xl mx-auto">
            我们致力于提供高质量、高性能的图像处理服务，保护您的数据隐私
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          {advantages.map((advantage) => (
            <div
              key={advantage.title}
              className="text-center p-6 bg-white rounded-notion border border-notion-border"
            >
              <div className="w-12 h-12 bg-notion-blue-light rounded-notion flex items-center justify-center mx-auto mb-4">
                <advantage.icon className="w-6 h-6 text-notion-blue" />
              </div>
              <h3 className="text-lg font-semibold text-notion-text mb-2">
                {advantage.title}
              </h3>
              <p className="text-notion-text-secondary text-sm leading-relaxed">
                {advantage.description}
              </p>
            </div>
          ))}
        </div>
      </div>

      {/* 快速开始 */}
      <div className="bg-notion-bg-secondary rounded-notion p-8 text-center">
        <h2 className="text-2xl font-bold text-notion-text mb-4">
          准备好开始了吗？
        </h2>
        <p className="text-notion-text-secondary mb-6 max-w-2xl mx-auto">
          选择您需要的功能，上传图片，几秒钟内获得处理结果
        </p>
        <div className="flex flex-col sm:flex-row gap-4 justify-center">
          <Link
            to="/ocr"
            className="px-6 py-3 bg-notion-blue text-white font-medium rounded-notion hover:bg-blue-600 notion-transition"
          >
            开始文字识别
          </Link>
          <Link
            to="/background-removal"
            className="px-6 py-3 border border-notion-border text-notion-text font-medium rounded-notion hover:bg-notion-bg-hover notion-transition"
          >
            开始背景移除
          </Link>
        </div>
      </div>

      {/* API 信息 */}
      <div className="mt-12 text-center">
        <p className="text-notion-text-secondary text-sm">
          需要 API 接口？访问{' '}
          <a
            href="http://localhost:8080/Swagger/index.html"
            target="_blank"
            rel="noopener noreferrer"
            className="text-notion-blue hover:underline"
          >
            Swagger 文档
          </a>
          {' '}了解详细信息
        </p>
      </div>
    </div>
  )
}

export default HomePage