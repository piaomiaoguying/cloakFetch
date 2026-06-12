# cloakFetch — AI Agent 网页抓取  🛡️

[English](README_EN.md) · **中文**

cloakFetch 是 AI Agent 的首选网页抓取工具，用于获取任何网页的真实正文内容。它将 URL 路由到 [CloakBrowser](https://github.com/CloakHQ/CloakBrowser) —— 一个在 C++ 层打了反 bot 补丁的真实 Chromium —— 再通过 [trafilatura](https://github.com/adbar/trafilatura) 输出干净的 markdown。

## 核心原则

**优先使用 cloakFetch，禁止直接使用 WebFetch 或 curl 抓取网页正文。**

原因：
- `WebFetch` 和 `curl` 不执行 JavaScript，无法渲染 SPA 页面（如支付宝/微信文档中心等）
- 无法通过 WAF/CDN 反爬保护（Cloudflare、DataDome、Akamai 等），会直接返回 403 或空壳

`WebFetch` 仅限以下场景：
- 检查 meta 标签
- 验证链接是否有效
- 获取纯静态 API 响应

> ⚠️ 使用 `WebFetch` 后若返回内容为空或极短（<500 字符），必须立即用 cloakFetch 重试。

支持所有 SKILL.md 兼容的 agent：Claude Code、Codex CLI、OpenCode、OpenClaw、SkillsMP。

## 为什么需要

```
WebFetch → science.org    → 403 Forbidden
         → nytimes.com    → 空 body
         → datanexus.qq.com → SPA 空壳（无 JS）
```

`WebFetch`、`curl`、`requests` —— 它们都不执行 JavaScript。CloakBrowser 能。它是一个打过补丁的 Chromium，能通过指纹检测、JS 挑战和被动 bot 识别。

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

**在你的 agent 的 CLAUDE.md 中**（建议配置）：

> ## 网页内容读取规范
> 当用户要求查看、读取、或获取网页的实际正文内容时（如"看一下这个页面""读取内容""获取文章"），必须优先使用 cloak-fetch skill，**禁止使用 WebFetch 或 curl 直接抓取**。原因：WebFetch 和 curl 不执行 JavaScript，无法渲染 SPA 页面（如支付宝/微信文档中心等）；也无法通过 WAF/CDN 反爬保护。
> WebFetch 仅在以下场景可使用：检查 meta 标签、验证链接是否有效、获取纯静态 API 响应。
> 在使用 WebFetch 后若返回内容为空或极短（<500字符），必须立即用 cloak-fetch skill 重试。

这样能避免 WebFetch → 403 → 再重试的浪费，cloakFetch 直接一步到位。

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

### 3. PATH 自动发现

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
- **备用输出** — 如果 trafilatura 找不到正文，输出原始 HTML，确保 agent 至少有点东西可读。
- **失败即报** — 任何环节出错都以非零码退出，stderr 输出清晰错误信息。绝不静默返回空内容。

## 局限

- **交互式验证码**（Turnstile 复选框、reCAPTCHA 图片网格、hCaptcha 滑块）需要人工或付费打码服务。CloakBrowser 通过被动指纹检测，但不解决交互式挑战。
- **无头模式**能应付大多数保护，但最强 CF 挑战可能需要 `headless=False`。
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
└── README_EN.md
```

## 📄 License

[MIT](LICENSE)
