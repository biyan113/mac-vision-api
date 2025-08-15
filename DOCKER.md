# Vision API Docker 部署指南

本文档介绍如何使用 Docker 运行 Vision API 服务和 Web 界面。

## 快速开始

### 方式一：使用便捷脚本（推荐）

```bash
# 给脚本执行权限
chmod +x docker-run.sh

# 运行完整应用（API + Web界面）
./docker-run.sh full

# 查看应用状态
./docker-run.sh status

# 查看帮助
./docker-run.sh help
```

### 方式二：使用 docker run --rm

```bash
# 仅运行 API 后端服务
docker run --rm -p 8080:8080 vision-api

# 仅运行 Web 前端界面（需要先构建镜像）
cd vision-web
docker build -t vision-web .
docker run --rm -p 3000:80 vision-web
```

## 详细使用说明

### 🚀 运行模式

#### 1. 完整模式 (推荐生产环境)
同时运行 API 后端和 Web 前端，通过 nginx 反向代理。

```bash
# 使用脚本
./docker-run.sh full

# 或使用 docker-compose
docker-compose -f docker-compose.full.yml up -d
```

**访问地址:**
- Web 界面: http://localhost:3000
- API 服务: http://localhost:8080
- API 文档: http://localhost:8080/Swagger/index.html

#### 2. 开发模式
仅运行 API 后端，前端使用本地开发服务器。

```bash
# 使用脚本
./docker-run.sh dev

# 然后在另一个终端启动前端
cd vision-web && npm run dev
```

**访问地址:**
- API 服务: http://localhost:8080
- 前端开发: http://localhost:5173

#### 3. 单独运行

##### 仅 API 服务
```bash
# 使用脚本
./docker-run.sh api

# 或使用原有配置
docker-compose up -d
```

##### 仅 Web 界面
```bash
# 使用脚本
./docker-run.sh web

# 或手动运行
cd vision-web
docker build -t vision-web .
docker run --rm -p 3000:80 --name vision-web-standalone vision-web
```

### 🔧 管理命令

#### 查看服务状态
```bash
./docker-run.sh status
```

#### 查看日志
```bash
./docker-run.sh logs
```

#### 停止所有服务
```bash
./docker-run.sh stop
```

#### 重新构建镜像
```bash
./docker-run.sh build
```

#### 清理 Docker 资源
```bash
./docker-run.sh clean
```

### 🐳 Docker 镜像说明

#### API 后端镜像
- 基于 Swift 官方镜像
- 包含 Apple Vision 框架依赖
- 暴露端口: 8080
- 健康检查: 30秒间隔

#### Web 前端镜像
- 基于 Node.js Alpine 构建，nginx Alpine 运行
- 包含优化的 nginx 配置
- 暴露端口: 80
- 支持 gzip 压缩和静态资源缓存

### 📝 配置说明

#### 环境变量
- `LOG_LEVEL`: 日志级别 (debug, info, warn, error)
- `NODE_ENV`: Node.js 环境 (development, production)

#### 网络配置
所有服务运行在自定义网络 `vision-network` 中，确保服务间通信。

#### 持久化存储
如需要持久化数据，可以在 docker-compose 中配置卷挂载。

### 🔍 故障排除

#### 常见问题

1. **端口被占用**
   ```bash
   # 检查端口占用
   lsof -i :8080
   lsof -i :3000
   
   # 停止占用端口的进程
   ./docker-run.sh stop
   ```

2. **macOS 版本不支持背景移除**
   ```bash
   # 检查 macOS 版本
   sw_vers
   
   # 背景移除功能需要 macOS 15.0+
   ```

3. **镜像构建失败**
   ```bash
   # 清理并重新构建
   ./docker-run.sh clean
   ./docker-run.sh build
   ```

4. **服务无法启动**
   ```bash
   # 查看详细日志
   ./docker-run.sh logs
   
   # 检查服务状态
   ./docker-run.sh status
   ```

#### 性能优化

1. **增加内存限制**
   ```yaml
   # 在 docker-compose 文件中添加
   deploy:
     resources:
       limits:
         memory: 2G
       reservations:
         memory: 1G
   ```

2. **启用 Docker BuildKit**
   ```bash
   export DOCKER_BUILDKIT=1
   ```

### 🏗️ 生产部署建议

1. **使用专用域名**
   - 配置反向代理 (nginx/Apache)
   - 启用 HTTPS (Let's Encrypt)

2. **监控和日志**
   - 集成日志聚合系统
   - 配置监控和告警

3. **安全配置**
   - 使用 Docker secrets 管理敏感信息
   - 限制容器权限
   - 定期更新镜像

4. **备份策略**
   - 定期备份数据卷
   - 导出镜像作为备份

### 📋 系统要求

- **操作系统**: macOS (推荐 macOS 15.0+ 完整功能)
- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **内存**: 最少 2GB 可用内存
- **磁盘**: 最少 5GB 可用空间

### 🔗 相关链接

- [Vision API 文档](./API_DOCUMENTATION.md)
- [Web 界面使用说明](./vision-web/README.md)
- [Swift 后端开发文档](./CLAUDE.md)