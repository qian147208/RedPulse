# 灵芯官网 (灵芯 Website)

> 灵芯 App 的官方网站，用于 App Store 审核的技术支持 URL 和隐私政策 URL。

## 📂 文件结构

```
website/
├── index.html          ← 首页（简介 + 功能 + 截屏 + 下载引导）
├── support.html        ← 技术支持（FAQ + 联系方式）
├── privacy.html        ← 隐私政策（App Store 审核必需）
├── screenshots/        ← 应用截屏
│   ├── 01-generate.jpg
│   ├── 02-products.jpg
│   ├── 03-result.jpg
│   ├── 04-history.jpg
│   └── 05-ai-assistant.jpg
├── deploy.sh           ← 一键部署脚本
└── README.md           ← 本文件
```

## 🚀 部署到 GitHub Pages

### 第 1 步：创建 GitHub 仓库

1. 打开 [github.com/new](https://github.com/new)
2. 仓库名：`redbookrefill-website`（或你想用的名字）
3. 设为 Public
4. 点击 "Create repository"

### 第 2 步：初始化并推送

```bash
cd /Users/mac/Desktop/灵芯/RedbookRefill/website

# 初始化 git
git init

# 添加远程仓库（替换为你的用户名和仓库名）
git remote add origin https://github.com/<你的用户名>/redbookrefill-website.git

# 添加所有文件
git add .

# 提交
git commit -m "Initial website for 灵芯"

# 重命名分支为 main
git branch -M main

# 推送
git push -u origin main
```

### 第 3 步：开启 GitHub Pages

1. 打开你的 GitHub 仓库页面
2. 点击 **Settings** → **Pages**
3. **Source** 选择 `main branch`，根目录
4. 等待 1-2 分钟，网站即可访问

### 第 4 步：获取 URL

部署成功后，你的 URL 格式为：

| 页面 | URL |
|------|-----|
| 首页 | `https://<你的用户名>.github.io/redbookrefill-website/` |
| 技术支持 | `https://<你的用户名>.github.io/redbookrefill-website/support.html` |
| 隐私政策 | `https://<你的用户名>.github.io/redbookrefill-website/privacy.html` |

## 🔧 可选：使用自动部署脚本

```bash
cd /Users/mac/Desktop/灵芯/RedbookRefill/website
bash deploy.sh
```

## 📝 需要修改的地方

在 `index.html` 和 `support.html` 中搜索以下占位符并替换：

- `https://apps.apple.com/app/你的appid` → 你的 App Store 链接
- `support@redpulse.app` → 你的实际联系邮箱

## 📱 在 App Store Connect 中使用

填写 App Store Connect 时：

- **技术支持 URL**：填写你的首页 URL（如 `https://username.github.io/redbookrefill-website/`）
- **隐私政策 URL**：填写 `https://username.github.io/redbookrefill-website/privacy.html`

---

© 2026 灵芯 (灵芯). 保留所有权利。
