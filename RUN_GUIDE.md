# Vision API 运行指南

## 概述

Vision API 是一个基于 Apple Vision 框架的图像处理服务，提供文本识别（OCR）和背景移除功能。本指南将帮助您在本地环境中运行完整的应用程序。

## 系统要求

### 硬件要求
- **操作系统**: macOS 13.0 或更高版本
- **处理器**: Apple Silicon (M1/M2/M3) 或 Intel x64
- **内存**: 至少 8GB RAM
- **存储**: 至少 2GB 可用空间

### 软件依赖

#### 必需组件
1. **Swift 6.0+**
   ```bash
   # 检查 Swift 版本
   swift --version
   ```

2. **Node.js 18+**
   ```bash
   # 检查 Node.js 版本
   node --version
   npm --version
   ```

3. **Xcode Command Line Tools**
   ```bash
   # 安装命令行工具
   xcode-select --install
   ```

## 快速开始

### 1. 克隆项目
```bash
git clone https://github.com/tdawn0-0/vision-api
cd vision-api
```

### 2. 安装后端依赖
```bash
# 解析 Swift 包依赖
swift package resolve

# 编译项目（可选，运行时会自动编译）
swift build
```

### 3. 安装前端依赖
```bash
cd vision-web
npm install
cd ..
```

### 4. 启动应用

#### 方法一：分别启动（推荐用于开发）

**启动后端服务：**

选项A - 直接运行（开发模式）：
```bash
# 在项目根目录，默认端口 8080
swift run App

# 指定端口号
swift run App serve --port 8081

# 指定主机和端口
swift run App serve --hostname 0.0.0.0 --port 8081
```

选项B - 编译后运行（生产模式）：
```bash
# 编译项目
swift build -c release

# 运行编译后的二进制文件
./.build/release/App

# 指定端口运行
./.build/release/App serve --port 8081

# 后台运行
nohup ./.build/release/App serve --port 8081 > app.log 2>&1 &
```

后端服务默认在 `http://localhost:8080` 启动

**启动前端开发服务器：**
```bash
# 新开终端窗口，进入前端目录
cd vision-web
npm run dev
```
前端服务将在 `http://localhost:5173` 启动

#### 方法二：使用脚本启动
```bash
# 创建启动脚本（支持端口参数）
cat > start.sh << 'EOF'
#!/bin/bash

# 默认端口
BACKEND_PORT=${1:-8080}
FRONTEND_PORT=${2:-5173}

echo "🚀 启动 Vision API..."
echo "后端端口: $BACKEND_PORT"
echo "前端端口: $FRONTEND_PORT"

# 检查端口是否被占用
check_port() {
    if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null ; then
        echo "❌ 端口 $1 已被占用，请使用其他端口或终止占用进程："
        echo "   lsof -ti:$1 | xargs kill -9"
        exit 1
    fi
}

check_port $BACKEND_PORT
check_port $FRONTEND_PORT

# 选择启动方式
if [ "$3" = "--binary" ]; then
    echo "📡 使用编译后二进制启动后端服务..."
    # 确保已编译
    swift build -c release
    ./.build/release/App serve --port $BACKEND_PORT &
else
    echo "📡 使用开发模式启动后端服务..."
    swift run App serve --port $BACKEND_PORT &
fi

BACKEND_PID=$!

# 等待后端启动
sleep 3

# 启动前端
echo "🌐 启动前端服务..."
cd vision-web
VITE_PORT=$FRONTEND_PORT npm run dev &
FRONTEND_PID=$!

echo "✅ 应用启动完成！"
echo "前端地址: http://localhost:$FRONTEND_PORT"
echo "后端地址: http://localhost:$BACKEND_PORT"
echo "API文档: http://localhost:$BACKEND_PORT/Swagger/index.html"
echo ""
echo "停止服务: Ctrl+C"
echo "后台进程ID: 后端=$BACKEND_PID, 前端=$FRONTEND_PID"

# 清理函数
cleanup() {
    echo "\n🛑 正在停止服务..."
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    exit 0
}

trap cleanup INT TERM

# 等待用户中断
wait
EOF

chmod +x start.sh

# 使用示例：
# ./start.sh                    # 默认端口 8080, 5173
# ./start.sh 8081 5174          # 自定义端口
# ./start.sh 8081 5174 --binary # 使用编译后二进制
./start.sh
```

## 访问应用

启动成功后，您可以通过以下地址访问：

- **前端界面**: http://localhost:5173
- **后端API**: http://localhost:8080
- **Swagger文档**: http://localhost:8080/Swagger/index.html
- **Stoplight文档**: http://localhost:8080/stoplight

## 功能验证

### 1. 验证后端服务
```bash
# 测试API健康状态
curl http://localhost:8080/

# 查看OpenAPI规范
curl http://localhost:8080/Swagger/swagger.json
```

### 2. 测试文本识别功能
```bash
# 使用示例图片测试OCR
curl -X POST http://localhost:8080/text-detection/recognize-text \
  -F "imageURL=https://via.placeholder.com/300x100/000000/FFFFFF?text=Hello+World"
```

### 3. 测试背景移除功能
```bash
# 上传本地图片测试背景移除
curl -X POST http://localhost:8080/image-feature/background-removal \
  -F "imageFile=@/path/to/your/image.jpg" \
  --output result.png
```

## 开发模式

### 前端热重载
前端使用 Vite 开发服务器，支持热重载：
- 修改 `vision-web/src/` 下的文件会自动刷新浏览器
- TypeScript 类型检查实时进行
- CSS 样式变更即时生效

### 后端调试
```bash
# 使用调试模式运行
swift run App --env development

# 查看详细日志
LOG_LEVEL=debug swift run App
```

## 生产部署

### 构建生产版本

**前端构建：**
```bash
cd vision-web
npm run build
# 构建产物在 dist/ 目录
```

**后端优化构建：**
```bash
# Release 模式编译（推荐生产环境）
swift build -c release

# 编译后的二进制文件位置
ls -la ./.build/release/App

# 运行编译后的应用
./.build/release/App serve --env production --port 8080

# 后台运行并记录日志
nohup ./.build/release/App serve --env production --port 8080 > app.log 2>&1 &

# 查看运行状态
ps aux | grep App
tail -f app.log
```

### Docker 部署（可选）
```bash
# 构建镜像
docker build -t vision-api:latest .

# 运行容器
docker run -p 8080:8080 vision-api:latest
```

## 故障排除

### 常见问题

#### 1. Swift 编译错误
```
错误: Swift compiler not found
解决: 确保安装了 Xcode Command Line Tools
xcode-select --install
```

#### 2. Node.js 依赖冲突
```
错误: ERESOLVE unable to resolve dependency tree
解决: 清理缓存并重新安装
rm -rf node_modules package-lock.json
npm install
```

#### 3. 端口占用
```
错误: Address already in use
解决方案：

# 方法1: 终止占用端口的进程
lsof -ti:8080 | xargs kill -9  # 后端端口
lsof -ti:5173 | xargs kill -9  # 前端端口

# 方法2: 使用不同端口启动
swift run App serve --port 8081
# 或
./.build/release/App serve --port 8081

# 方法3: 查看端口占用详情
lsof -i :8080
ps aux | grep App
```

#### 4. Vision 框架不可用
```
错误: Vision framework not available
解决: 确保运行在 macOS 13.0+ 系统上
```

### 日志查看

**后端日志：**
- 控制台直接显示
- 可通过 `LOG_LEVEL` 环境变量调整日志级别

**前端日志：**
- 浏览器开发者工具 Console 面板
- Vite 开发服务器控制台

### 性能优化

1. **内存使用**
   - 大图片处理可能消耗较多内存
   - 建议限制上传文件大小（默认20MB）

2. **处理速度**
   - OCR 识别速度取决于图片大小和复杂度
   - 背景移除需要 macOS 15.0+ 获得最佳性能

## 停止应用

### 优雅停止
```bash
# 如果使用 Ctrl+C 停止，服务会优雅关闭
# 或者找到进程ID并终止
ps aux | grep App
kill <PID>

# 停止前端开发服务器
# 在前端终端按 Ctrl+C
```

### 强制停止
```bash
# 强制终止所有相关进程
pkill -f "swift run App"
pkill -f "npm run dev"
```

## 更多信息

- **API 文档**: 参考 `API_DOCUMENTATION.md`
- **功能说明**: 参考 `FEASIBILITY_VISION_CAPABILITIES_CN.md`
- **Docker 部署**: 参考 `DOCKER.md`

## 技术支持

如果遇到问题，请检查：
1. 系统要求是否满足
2. 依赖是否正确安装
3. 端口是否被占用
4. 日志中的错误信息

更多技术细节请参考项目的其他文档文件。
