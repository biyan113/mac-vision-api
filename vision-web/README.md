# Vision API Web Interface

基于 Vision API 的现代化 Web 界面，采用 Notion 风格设计，提供 OCR 文字识别和背景移除功能。

## 功能特性

### 🔍 OCR 文字识别
- 支持中文、英文等多种语言识别
- 可调节识别精度（精确模式/快速模式）
- 支持多种图片格式（PNG、JPG、JPEG、WebP、HEIC）
- 支持多种输入方式（文件上传、URL、Base64）
- 文本结果可复制、下载

### ✂️ 背景移除
- 智能识别图片主体
- 自动移除背景
- 输出透明背景的 PNG 图片
- 支持人物、物品等多种主体

### 🎨 界面特性
- Notion 风格设计
- 响应式布局，支持移动端
- 实时服务器状态监控
- Toast 通知系统
- 错误边界处理
- 加载状态反馈

## 技术栈

- **前端框架**: React 19 + TypeScript
- **构建工具**: Vite
- **样式**: Tailwind CSS
- **路由**: React Router
- **图标**: Lucide React
- **文件上传**: React Dropzone
- **动画**: Framer Motion
- **HTTP 客户端**: Axios

## 快速开始

### 前置条件

1. 确保 Vision API 服务已启动并运行在 `http://localhost:8080`
2. Node.js 18+ 和 npm

### 安装和运行

```bash
# 安装依赖
npm install

# 启动开发服务器
npm run dev

# 构建生产版本
npm run build

# 预览生产版本
npm run preview
```

### 配置

如果 Vision API 服务运行在其他地址，请修改 `src/services/api.ts` 中的 `API_BASE_URL` 配置：

```typescript
const API_BASE_URL = 'http://your-api-server:port'
```

## 项目结构

```
src/
├── components/           # React 组件
│   ├── layout/          # 布局组件（Header, Sidebar, Layout）
│   ├── ui/              # 通用 UI 组件（FileUpload, Toast, LoadingSpinner）
│   ├── ErrorBoundary.tsx
│   ├── HomePage.tsx
│   ├── OCRPage.tsx
│   └── BackgroundRemovalPage.tsx
├── services/            # API 服务
│   └── api.ts
├── lib/                 # 工具函数
│   └── utils.ts
├── App.tsx
└── main.tsx
```

## 使用方法

### OCR 文字识别

1. 访问 OCR 页面
2. 上传图片或提供图片 URL
3. 可选：配置识别语言和精度
4. 点击"开始识别"
5. 查看结果，支持复制和下载

### 背景移除

1. 访问背景移除页面
2. 上传图片
3. 点击"移除背景"
4. 查看处理结果
5. 下载透明背景的 PNG 图片

## 浏览器支持

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

## 开发

### 代码规范

项目使用 ESLint 进行代码检查：

```bash
npm run lint
```

### 构建

```bash
# 类型检查
npx tsc --noEmit

# 构建
npm run build
```

## API 文档

访问 Vision API 的 Swagger 文档：
http://localhost:8080/Swagger/index.html

## 许可证

本项目采用 MIT 许可证。详见 LICENSE 文件。
