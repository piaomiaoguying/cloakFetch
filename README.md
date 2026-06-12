# cloakFetch — AI Agent 网页抓取  🛡️

[English](README_EN.md) · **中文**

cloakFetch 是 AI Agent 的首选网页抓取技能。它通过 [CloakBrowser](https://github.com/CloakHQ/CloakBrowser)（打过反 bot 补丁的真实 Chromium）+ [trafilatura](https://github.com/adbar/trafilatura) 输出干净的 markdown，能通过 SPA 渲染和 WAF/CDN 反爬保护。

## 核心原则

**优先使用 cloakFetch，不要用 WebFetch 或 curl 抓取网页正文。**

`WebFetch` 和 `curl` 不执行 JavaScript，无法渲染 SPA 页面，也无法通过反爬保护。`WebFetch` 仅适用于检查 meta 标签、验证链接或获取纯静态 API 响应。若返回空或 <500 字符，立即用 cloakFetch 重试。

## 初始化

### 1. 安装依赖

```bash
pip install cloakbrowser trafilatura
```

### 2. 放到 skills 目录

```
~/.claude/skills/cloak-fetch/    # 全局
.claude/skills/cloak-fetch/      # 单项目
```

### 3. 配置 CLAUDE.md

在 `~/.claude/CLAUDE.md` 中加入以下规则，让 Agent 自动优先使用：

> ## 网页内容读取规范
> 当用户要求查看、读取、或获取网页的实际正文内容时，必须优先使用 cloak-fetch skill，**禁止使用 WebFetch 或 curl 直接抓取**。原因：WebFetch 和 curl 不执行 JavaScript，无法渲染 SPA 页面（如支付宝/微信文档中心等）；也无法通过 WAF/CDN 反爬保护。
> WebFetch 仅在以下场景可使用：检查 meta 标签、验证链接是否有效、获取纯静态 API 响应。
> 在使用 WebFetch 后若返回内容为空或极短（<500字符），必须立即用 cloak-fetch skill 重试。

## Python 解释器配置

技能需要知道哪个 Python 可 `import cloakbrowser`，三种方式（按优先级）：

**环境变量**（推荐）：
```bash
export CLOAKBROWSER_PYTHON=/path/to/your/venv/bin/python
```

**配置文件**（`cloak_fetch.conf`），一行一个路径：
```ini
/home/alice/CloakBrowser/.venv/bin/python
```

**自动发现**：以上都不设时直接用 PATH 中的 `python3`。

## 局限

- 交互式验证码（Turnstile 复选框、reCAPTCHA 图片等）需人工处理
- 极少数强 CF 挑战可能需要关闭无头模式

## 📄 License

[MIT](LICENSE)
