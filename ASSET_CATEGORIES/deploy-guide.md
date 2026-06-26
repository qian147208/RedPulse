# 隐私政策部署指南

## 目标
将 `4-privacy-policy.html` 部署到 GitHub Pages，获取公开的隐私政策 URL。

## 步骤

### 1. 创建 GitHub 仓库
```bash
cd ~/Desktop/灵芯/RedbookRefill/ASSET_CATEGORIES/

# 如果还没有专用仓库，可以创建一个名为 redbookrefill-privacy 的 GitHub 仓库
# 在 GitHub 上创建新仓库，设置名为 public（或你想用的名字）
# 然后将 HTML 文件推上去

# 或者直接在现有项目中加一个 pages 配置
```

### 2. 简单部署方式（推荐）

#### 方式 A：用现有项目启用 GitHub Pages
```bash
cd ~/Desktop/灵芯/RedbookRefill

# 确保项目已推送到 GitHub
git remote -v

# 在项目设置中：
# Settings > Pages > Source 选择 main branch / /docs 文件夹
# 将 4-privacy-policy.html 放到 docs/ 文件夹下
mkdir -p docs
cp ASSET_CATEGORIES/4-privacy-policy.html docs/privacy.html
git add docs/privacy.html
git commit -m "Add privacy policy page"
git push
```

#### 方式 B：用 Netlify Drop（无需 GitHub）
```bash
# 1. 打开 https://app.netlify.com/drop
# 2. 将包含 4-privacy-policy.html 的文件夹拖入上传区域
# 3. 获得一个公开的 HTTPS URL
# 4. 在 App Store Connect 中填写该 URL
```

#### 方式 C：用 GitHub Pages（最标准）
```bash
cd ~/Desktop/灵芯/RedbookRefill

# 创建 docs 目录并放隐私政策
mkdir -p docs
cp ASSET_CATEGORIES/4-privacy-policy.html docs/privacy.html

# 提交并推送
git add docs/
git commit -m "Add privacy policy for App Store submission"
git push origin main

# 然后在 GitHub 项目页面：
# Settings → Pages → Source 选择 main branch，根目录
# 等待部署完成后，URL 通常为：
# https://<your-username>.github.io/<repo-name>/privacy.html
```

### 3. 获取 URL 后更新以下文件

更新 `ASSET_CATEGORIES/5-privacy-policy-url.md`：
```
https://<your-username>.github.io/<repo-name>/privacy.html
```

更新 `ASSET_CATEGORIES/0-app-store-metadata.md` 第 6 节。

### 4. 技术支持网址

同样方式部署支持页面（`ASSET_CATEGORIES/3-tech-support-url.md` 中的内容）。

---

## ⚠️ 注意事项
- 隐私政策必须是 HTTPS 链接
- URL 必须公开可访问（不能需要登录）
- 所有 App Store 提交都需要隐私政策 URL
- 建议尽早部署，在提交 App Store Connect 前完成
