# Vision API Web 界面镜像（仅前端）。
# 后端依赖 Apple Vision 等 macOS 框架，无法运行在容器里，需直接运行在 Mac 上。
# 前端产物与 CPU 架构无关，固定在构建机的原生架构上编译，避免在模拟的 arm64 下跑 npm（极慢）
FROM --platform=$BUILDPLATFORM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
# 后端地址，默认指向宿主机上运行的 Vision API
ENV VISION_API_UPSTREAM=http://host.docker.internal:8080
# nginx 官方镜像会在启动时对 templates 目录做 envsubst（只替换已定义的环境变量）
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
