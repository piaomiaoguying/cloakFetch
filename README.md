# cloakFetch — AI Agent 网页抓取  🛡️

[English](README_EN.md) · **中文**

cloakFetch 是 AI Agent 的首选网页抓取技能。它通过 [CloakBrowser](https://github.com/CloakHQ/CloakBrowser)（打过反 bot 补丁的真实 Chromium）+ [trafilatura](https://github.com/adbar/trafilatura) 输出干净的 markdown，能通过 SPA 渲染和 WAF/CDN 反爬保护。

## 核心原则

**优先使用 cloakFetch，不要用 WebFetch 或 curl 抓取网页正文。**

`WebFetch` 和 `curl` 不执行 JavaScript，无法渲染 SPA 页面，也无法通过反爬保护。`WebFetch` 仅适用于检查 meta 标签、验证链接或获取纯静态 API 响应。若返回空或 <500 字符，立即用 cloakFetch 重试。

## 初始化

**一键安装：**

```bash
curl -sSL https://raw.githubusercontent.com/piaomiaoguying/cloakFetch/main/init.sh | bash
```

脚本执行过程中会询问安装方式：

| 选项 | 说明 |
|---|---|
| **系统默认** | `pip3 install` 到当前 Python 环境，零配置 |
| **隔离 venv** | 创建独立虚拟环境，~300MB，不污染系统。可指定路径，默认 `~/clkbrowser-venv` |

其余步骤全自动：拉取技能文件 → `pip install` 依赖 → 放置到 `~/.claude/skills/cloak-fetch/` → 配置 Python 解释器 → 追加 CLAUDE.md 规范。

> **网络问题**：`git clone` 和 `pip3 install` 在大陆网络可能较慢或超时，可先设置代理后执行。

## 使用

```bash
# 基础用法：读取网页正文
cloak_fetch.sh "https://example.com"

# 提取页面中所有链接（用于 SPA 页面丢失 href 的场景）
cloak_fetch.sh "https://example.com" --links
```

### `--links` 参数

SPA 页面（React/Vue 渲染）中，trafilatura 提取正文时可能丢失 `<a>` 标签的 `href` 属性。加上 `--links` 后，输出末尾会追加一个「页面链接」节，列出渲染 DOM 中所有链接。支持三种提取策略：

1. 标准 `<a href>` 标签
2. `data-href`、`data-url`、`data-link` 属性
3. `onclick` 中的 `window.open` / `location.href` 跳转

正文中出现的链接会自动排到前面。

**适用场景**：飞书文档表单链接、SPA 文档站导航链接、需精准获取目标 URL 等。

## 局限

- 交互式验证码（Turnstile 复选框、reCAPTCHA 图片等）需人工处理
- 极少数强 CF 挑战可能需要关闭无头模式

## License

[MIT](LICENSE)
