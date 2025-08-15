#!/bin/bash

# Vision API Docker 运行脚本
# 提供多种运行模式的便捷命令

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=================================${NC}"
    echo -e "${BLUE} Vision API Docker Manager${NC}"
    echo -e "${BLUE}=================================${NC}"
}

# 显示帮助信息
show_help() {
    print_header
    echo ""
    echo "用法: ./docker-run.sh [命令]"
    echo ""
    echo "可用命令:"
    echo "  full      - 运行完整应用 (API + Web界面)"
    echo "  api       - 仅运行 API 后端服务"
    echo "  web       - 仅运行 Web 前端界面"
    echo "  dev       - 开发模式 (仅API，前端使用本地开发服务器)"
    echo "  stop      - 停止所有服务"
    echo "  logs      - 查看服务日志"
    echo "  status    - 查看服务状态"
    echo "  clean     - 清理 Docker 镜像和容器"
    echo "  build     - 重新构建镜像"
    echo "  help      - 显示此帮助信息"
    echo ""
    echo "快速开始:"
    echo "  ./docker-run.sh full    # 运行完整应用"
    echo "  ./docker-run.sh dev     # 开发模式"
    echo ""
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
}

# 运行完整应用
run_full() {
    print_message "启动完整 Vision API 应用..."
    print_message "这将启动 API 后端 (端口 8080) 和 Web 界面 (端口 3000)"
    
    docker-compose -f docker-compose.full.yml up --build -d
    
    print_message "应用已启动！"
    print_message "API 服务: http://localhost:8080"
    print_message "Web 界面: http://localhost:3000"
    print_message "API 文档: http://localhost:8080/Swagger/index.html"
}

# 仅运行 API
run_api() {
    print_message "启动 Vision API 后端服务..."
    
    docker-compose -f docker-compose.yml up --build -d
    
    print_message "API 服务已启动！"
    print_message "API 服务: http://localhost:8080"
    print_message "API 文档: http://localhost:8080/Swagger/index.html"
}

# 仅运行 Web 界面
run_web() {
    print_message "启动 Vision Web 界面..."
    print_warning "注意: 请确保 API 服务已在运行"
    
    cd vision-web && docker build -t vision-web . && cd ..
    docker run --rm -d -p 3000:80 --name vision-web-standalone vision-web
    
    print_message "Web 界面已启动！"
    print_message "Web 界面: http://localhost:3000"
}

# 开发模式
run_dev() {
    print_message "启动开发模式..."
    print_message "API 将在端口 8080 运行"
    print_message "请在另一个终端中运行前端开发服务器："
    print_message "  cd vision-web && npm run dev"
    
    docker-compose -f docker-compose.dev.yml up --build -d
    
    print_message "开发环境已启动！"
    print_message "API 服务: http://localhost:8080"
    print_message "前端开发: http://localhost:5173 (需手动启动)"
}

# 停止所有服务
stop_services() {
    print_message "停止所有 Vision API 服务..."
    
    docker-compose -f docker-compose.full.yml down 2>/dev/null || true
    docker-compose -f docker-compose.dev.yml down 2>/dev/null || true
    docker-compose -f docker-compose.yml down 2>/dev/null || true
    docker stop vision-web-standalone 2>/dev/null || true
    
    print_message "所有服务已停止"
}

# 查看日志
show_logs() {
    print_message "显示服务日志..."
    
    if docker-compose -f docker-compose.full.yml ps -q | grep -q .; then
        docker-compose -f docker-compose.full.yml logs -f
    elif docker-compose -f docker-compose.dev.yml ps -q | grep -q .; then
        docker-compose -f docker-compose.dev.yml logs -f
    elif docker-compose ps -q | grep -q .; then
        docker-compose logs -f
    else
        print_warning "没有找到运行中的服务"
    fi
}

# 查看状态
show_status() {
    print_message "服务运行状态:"
    echo ""
    
    echo "完整应用模式:"
    docker-compose -f docker-compose.full.yml ps
    echo ""
    
    echo "开发模式:"
    docker-compose -f docker-compose.dev.yml ps
    echo ""
    
    echo "API 服务:"
    docker-compose ps
    echo ""
    
    echo "独立 Web 服务:"
    docker ps --filter "name=vision-web-standalone" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# 清理资源
clean_docker() {
    print_warning "这将删除所有 Vision API 相关的 Docker 镜像和容器"
    read -p "确定要继续吗? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_message "停止所有服务..."
        stop_services
        
        print_message "删除容器和镜像..."
        docker system prune -f
        docker image prune -a -f
        
        print_message "清理完成"
    else
        print_message "已取消清理操作"
    fi
}

# 重新构建镜像
rebuild() {
    print_message "重新构建所有镜像..."
    
    docker-compose -f docker-compose.full.yml build --no-cache
    docker-compose -f docker-compose.dev.yml build --no-cache
    docker-compose build --no-cache
    
    print_message "镜像重新构建完成"
}

# 主函数
main() {
    check_docker
    
    case "${1:-help}" in
        "full")
            run_full
            ;;
        "api")
            run_api
            ;;
        "web")
            run_web
            ;;
        "dev")
            run_dev
            ;;
        "stop")
            stop_services
            ;;
        "logs")
            show_logs
            ;;
        "status")
            show_status
            ;;
        "clean")
            clean_docker
            ;;
        "build")
            rebuild
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# 运行主函数
main "$@"