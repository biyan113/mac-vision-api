#!/bin/bash
# Vision API 安装脚本：下载最新发布的 macOS 可执行文件到 ~/.vision-api
#
#   curl -fsSL https://raw.githubusercontent.com/biyan113/mac-vision-api/master/scripts/install.sh | bash
#
# 可用环境变量：
#   VISION_API_VERSION   指定版本标签（如 v1.0.0），默认 latest
#   VISION_API_HOME      安装目录，默认 ~/.vision-api
set -euo pipefail

REPO="biyan113/mac-vision-api"
ASSET="vision-api-macos-arm64"
VERSION="${VISION_API_VERSION:-latest}"
INSTALL_DIR="${VISION_API_HOME:-$HOME/.vision-api}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "错误：Vision API 依赖 Apple 的系统框架，只能运行在 macOS 上。" >&2
  exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
  echo "错误：预编译版本仅支持 Apple 芯片。Intel Mac 请从源码构建：swift build -c release" >&2
  exit 1
fi

if [ "$VERSION" = "latest" ]; then
  URL="https://github.com/$REPO/releases/latest/download/$ASSET.tar.gz"
else
  URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET.tar.gz"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "下载 $URL"
curl -fL --progress-bar "$URL" -o "$TMP/$ASSET.tar.gz"

if curl -fsL "$URL.sha256" -o "$TMP/$ASSET.tar.gz.sha256"; then
  (cd "$TMP" && shasum -a 256 -c "$ASSET.tar.gz.sha256")
fi

tar -xzf "$TMP/$ASSET.tar.gz" -C "$TMP"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/Public"
cp -R "$TMP/$ASSET/." "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/vision-api"

cat <<MSG

已安装到 $INSTALL_DIR

启动服务（必须在安装目录下运行，以便找到 Public/ 静态文件）：

  cd "$INSTALL_DIR" && ./vision-api serve --env production --hostname 127.0.0.1 --port 8080

然后访问：
  Web 界面  http://localhost:8080/
  API 文档  http://localhost:8080/Swagger/index.html
MSG
