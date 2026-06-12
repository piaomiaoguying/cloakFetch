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

脚本会自动完成：安装 Python 依赖 → 放置技能到 `~/.claude/skills/cloak-fetch/` → 检测 Python 解释器 → 追加 CLAUDE.md 配置规则。

## 局限

- 交互式验证码（Turnstile 复选框、reCAPTCHA 图片等）需人工处理
- 极少数强 CF 挑战可能需要关闭无头模式

## License

[MIT](LICENSE)
