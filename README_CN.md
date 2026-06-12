# cloakFetch — AI Agent 网页抓取兜底  🛡️

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/Agents365-ai/cloakFetch?style=flat&logo=github)](https://github.com/Agents365-ai/cloakFetch/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/Agents365-ai/cloakFetch?style=flat&logo=github)](https://github.com/Agents365-ai/cloakFetch/network/members)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-compatible-2ea44f)](https://agentskills.io)
[![Discord](https://img.shields.io/badge/Discord-加入-5865F2?logo=discord&logoColor=white)](https://discord.gg/79JF5Atuk)

[English](README.md) · **中文**

外部参考：[CloakBrowser](https://github.com/CloakHQ/CloakBrowser) · [trafilatura](https://github.com/adbar/trafilatura)

当 `WebFetch` / `curl` 遇到 Cloudflare（或任何 WAF）拦截时，cloakFetch 把 URL 路由到 [CloakBrowser](https://github.com/CloakHQ/CloakBrowser) —— 一个在 C++ 层打了反 bot 补丁的真实 Chromium —— 再通过 [trafilatura](https://github.com/adbar/trafilatura) 输出干净的 markdown。Agent 永远不必告诉用户"这页抓不下来"。

支持所有 SKILL.md 兼容的 agent：Claude Code、Codex CLI、OpenCode、OpenClaw、SkillsMP。

## 为什么需要

```
WebFetch → science.org    → 403 Forbidden
         → nytimes.com    → 空 body
         → datanexus.qq.com → SPA 空壳（无 JS）
```

`WebFetch`、`curl`、`requests` —— 它们都不执行 JavaScript。CloakBrowser 能。它是一个打过补丁的 Chromium，能通过指纹检测、JS 挑战和被动 bot 识别。cloakFetch 就是把它接入 agent 的那一层薄封装。

## 安装

把技能目录放到 agent 的 skills 路径下：

| Agent | 路径 |
|---|---|
| Claude Code（全局） | `~/.claude/skills/cloak-fetch/` |
| Claude Code（项目） | `.claude/skills/cloak-fetch/` |
| OpenClaw（全局） | `~/.openclaw/skills/cloak-fetch/` |
| OpenClaw（项目） | `skills/cloak-fetch/` |
| Codex CLI | `~/.codex/skills/cloak-fetch/` |
| SkillsMP | 在 [skillsmp.com](https://skillsmp.com) 搜索 `cloak-fetch` |

## 前置条件

```bash
pip install cloakbrowser trafilatura
```

就这些。技能会自动发现 Python 解释器（详见[配置](#配置)）。

## 使用

```bash
<skill目录>/cloak_fetch.sh "https://example.com"
```

stdout 输出干净的 markdown，stderr 输出进度信息。成功退出码 0，失败非零。

**在 agent 的 CLAUDE.md 中**（可选但推荐）：

> 当需要获取网页内容时，必须使用 cloak-fetch 技能。禁止使用 WebFetch 或 curl —— 它们不执行 JavaScript，对任何受保护页面都只会返回空壳或 403。

这样能省掉 WebFetch → 403 → 再重试的浪费。

## 配置

三种方式告诉技能哪个 Python 能 `import cloakbrowser`，按优先级从高到低：

### 1. 环境变量

```bash
export CLOAKBROWSER_PYTHON=/你的/venv/bin/python
```

最高优先级。写入 `~/.zshrc` 或 `~/.bashrc`。

### 2. 配置文件（`cloak_fetch.conf`）

编辑 `cloak_fetch.sh` 旁边的这个文件。一行一个路径，`#` 开头为注释。从上到下尝试：

```ini
# 我的 CloakBrowser venv
/home/alice/CloakBrowser/.venv/bin/python
/opt/CloakBrowser/.venv/bin/python
```

### 3. PATH 兜底

以上都不设置时，直接使用 PATH 上的 `python3`。当你通过 `pip install cloakbrowser` 安装到系统 Python 时，零配置即可用。

## 调优

编辑 `cloak_fetch.py`：

| 参数 | 默认值 | 作用 |
|---|---|---|
| `launch(headless=)` | `True` | 改为 `False` 可看到浏览器窗口（调试用） |
| `page.goto(… timeout=)` | `90000` | 页面加载超时（毫秒） |
| `page.wait_for_selector(… timeout=)` | `15000` | SPA 内容容器最长等待时间 |
| `time.sleep(2)` | 2 秒 | JS 延迟加载的额外缓冲 |
| 选择器列表 | `main, article, .article__body, .core-container, .pb-page-body` | 按需添加站点特定选择器以加速检测 |

## 架构

```
cloak_fetch.sh <url>                 ← 一条命令
   │
   ├─ 1. 发现 Python（环境变量 → conf → PATH）
   ├─ 2. arch -arm64（仅 macOS，防止 Rosetta x86_64 架构错配）
   └─ 3. exec cloak_fetch.py <url>
         │
         ├─ launch(headless=True)    ← CloakBrowser，Playwright 兼容 API
         ├─ page.goto(url)
         ├─ 轮询真实标题              ← "Just a moment…" → 等 CF 放行
         ├─ wait_for_selector()      ← SPA 内容渲染完毕？
         ├─ time.sleep(2)            ← 晚加载 JS 缓冲
         ├─ page.evaluate(outerHTML) ← 获取完整 DOM
         └─ trafilatura.extract()    ← HTML → 干净 markdown
```

## 行为

- **无头运行** — 无浏览器窗口。
- **延迟** — ~20–40 秒（浏览器启动 + 渲染 + 缓冲）。
- **输出** — trafilatura markdown：保留标题、列表、链接、代码块。去掉广告、导航、cookie 横幅。
- **兜底** — 如果 trafilatura 找不到正文，输出原始 HTML，确保 agent 至少有点东西可读。
- **失败即报** — 任何环节出错都以非零码退出，stderr 输出清晰错误信息。绝不静默返回空内容。

## 局限

- **交互式验证码**（Turnstile 复选框、reCAPTCHA 图片网格、hCaptcha 滑块）需要人工或付费打码服务。CloakBrowser 通过被动指纹检测，但不解决交互式挑战。
- **无头模式**能应付大多数保护，但最强 CF 挑战可能需要 `headless=False`。
- **被动触发** — agent 必须记得用这个技能。在 CLAUDE.md 加规则（见[使用](#使用)）可变为主动。
- **跨平台** — 支持 macOS（ARM/Intel）、Linux。`arch -arm64` 仅在 macOS ARM 下启用，Linux 直接跳过。

## 仓库结构

```
cloakFetch/
├── skills/cloak-fetch/
│   ├── SKILL.md              ← Agent 读取 — 触发启发式、厂商特征
│   ├── cloak_fetch.sh        ← 入口：发现 Python、跨平台 exec
│   ├── cloak_fetch.py        ← 浏览器启动 + trafilatura 提取
│   └── cloak_fetch.conf      ← 用户自定义 Python 路径（可选）
├── LICENSE
├── .gitignore
├── README.md
└── README_CN.md
```

## 💬 社区

- **Discord:** https://discord.gg/79JF5Atuk
- **微信:** 扫描下方二维码

<p align="center">
  <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/agents365ai_wechat_1.png" width="200" alt="微信交流群">
</p>

## ❤️ 支持

如果 cloakFetch 帮你少看了一次 "HTTP 403 Forbidden"，欢迎打赏支持作者：

<table>
  <tr>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/wechat-pay.png" width="180" alt="微信支付">
      <br><b>微信支付</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/alipay.png" width="180" alt="支付宝">
      <br><b>支付宝</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/buymeacoffee.png" width="180" alt="Buy Me a Coffee">
      <br><b>Buy Me a Coffee</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/awarding/award.gif" width="180" alt="打赏">
      <br><b>打赏</b>
    </td>
  </tr>
</table>

## 👤 作者

**Agents365-ai**

- GitHub: https://github.com/Agents365-ai
- Bilibili: https://space.bilibili.com/441831884

## 📄 License

[MIT](LICENSE)
