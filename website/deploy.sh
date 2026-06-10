#!/bin/bash
# ============================================================
# 红书笔芯官网 — GitHub Pages 一键部署脚本
# ============================================================

set -euo pipefail

# ============ 配置 ============
SITE_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE_NAME="${GITHUB_REMOTE:-origin}"
BRANCH="${GITHUB_BRANCH:-main}"

echo "=========================================="
echo "  红书笔芯官网部署工具"
echo "=========================================="
echo ""

# 检查 git
if ! command -v git &>/dev/null; then
    echo "❌ 未找到 git，请先安装 git"
    exit 1
fi

# 检查目录
if [ ! -f "$SITE_DIR/index.html" ]; then
    echo "❌ 未找到 index.html，请确认在当前目录"
    exit 1
fi

# 检查是否已推送过
if ! git ls-remote "$REMOTE_NAME" 2>/dev/null | grep -q "$BRANCH"; then
    echo "⚠️  远程仓库 '$REMOTE_NAME/$BRANCH' 可能不存在"
    echo ""
    echo "请先在 GitHub 创建一个新仓库，然后将本地仓库推送到远程。"
    echo ""
    echo "操作步骤："
    echo "  1. 在 GitHub 创建新仓库（如 redbookrefill-website）"
    echo "  2. 运行："
    echo "     cd $SITE_DIR"
    echo "     git init"
    echo "     git remote add origin https://github.com/<你的用户名>/<仓库名>.git"
    echo "     git add . && git commit -m 'Initial website'"
    echo "     git branch -M main"
    echo "     git push -u origin main"
    echo ""
    echo "  3. 开启 GitHub Pages:"
    echo "     Settings → Pages → Source: main branch / /docs"
    echo ""
    read -p "是否继续？(y/N) " -r answer
    if [[ ! "$answer" =~ ^[Yy] ]]; then
        echo "已取消"
        exit 0
    fi
fi

# 检查是否包含截图
if [ ! -d "$SITE_DIR/screenshots" ] || [ -z "$(ls "$SITE_DIR/screenshots/"*.jpg 2>/dev/null)" ]; then
    echo "⚠️  未找到截图文件"
    echo "    请将截屏放入: $SITE_DIR/screenshots/"
    echo "    从 ../SCREENSHOTS/ 复制: cp ../SCREENSHOTS/*.jpg screenshots/"
    echo ""
    read -p "是否继续？(y/N) " -r answer
    if [[ ! "$answer" =~ ^[Yy] ]]; then
        echo "已取消"
        exit 0
    fi
fi

echo "→ 部署中..."
echo ""

# 添加文件
git add -A

# 检查是否有变化
if git diff --cached --quiet; then
    echo "ℹ️  没有检测到文件变化，跳过部署"
else
    git commit -m "Update website [skip ci]" --allow-empty || true
    echo "→ 提交成功"
    echo "→ 推送到远程..."
    git push origin "$BRANCH" 2>&1 || echo "⚠️  推送失败，请检查网络连接和远程仓库权限"
fi

echo ""
echo "=========================================="
echo "  ✅ 部署完成！"
echo "=========================================="
echo ""
echo "你的网站文件："
echo "  index.html     → 首页"
echo "  support.html   → 技术支持"
echo "  privacy.html   → 隐私政策"
echo "  screenshots/   → 截屏图片"
echo ""
echo "GitHub Pages 配置："
echo "  1. 打开 https://github.com/<你的用户名>/<仓库名>/settings/pages"
echo "  2. Source 选择: main branch / (root)"
echo "  3. 等待 1-2 分钟生效"
echo ""
echo "生效后 URL："
echo "  首页:   https://<你的用户名>.github.io/<仓库名>/"
echo "  支持:   https://<你的用户名>.github.io/<仓库名>/support.html"
echo "  隐私:   https://<你的用户名>.github.io/<仓库名>/privacy.html"
echo ""
