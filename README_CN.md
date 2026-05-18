# cloakFetch — 让 Claude Code 穿透 Cloudflare 的网页抓取兜底 🛡️

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/Agents365-ai/cloakFetch?style=flat&logo=github)](https://github.com/Agents365-ai/cloakFetch/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/Agents365-ai/cloakFetch?style=flat&logo=github)](https://github.com/Agents365-ai/cloakFetch/network/members)
[![Latest Release](https://img.shields.io/github/v/release/Agents365-ai/cloakFetch?logo=github)](https://github.com/Agents365-ai/cloakFetch/releases/latest)
[![Last Commit](https://img.shields.io/github/last-commit/Agents365-ai/cloakFetch?logo=github)](https://github.com/Agents365-ai/cloakFetch/commits/main)

[![Claude Code Hook](https://img.shields.io/badge/Claude%20Code-PostToolUse%20hook-8a2be2)](https://docs.claude.com/en/docs/claude-code/hooks)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-compatible-2ea44f)](https://agentskills.io)
[![Discord](https://img.shields.io/badge/Discord-加入-5865F2?logo=discord&logoColor=white)](https://discord.gg/79JF5Atuk)

[English](README.md) · **中文**

外部参考:[CloakBrowser](https://github.com/CloakHQ/CloakBrowser) · [defuddle](https://github.com/kepano/defuddle) · [Claude Code hooks](https://docs.claude.com/en/docs/claude-code/hooks)

同一个思路、两条路径:当网页抓取被 [Cloudflare](https://www.cloudflare.com/)(或类似的 bot 防护)拦截时,把 URL 路由到 [CloakBrowser](https://github.com/CloakHQ/CloakBrowser) —— 一个能通过 JS 挑战的隐身 Chromium —— 再通过 [defuddle](https://github.com/kepano/defuddle) 输出干净的 markdown。

- **[路径 A:PostToolUse 钩子](#路径-a--claude-code-posttooluse-钩子)** —— Claude Code 全自动。每一次被拦截的 `WebFetch` 都会静默回退,agent 完全看不到失败。
- **[路径 B:SKILL.md 技能](#路径-b--skillmd-技能用于不支持钩子的-agent)** —— 任意支持 SKILL.md 的 agent(Codex、OpenCode、OpenClaw、SkillsMP)都能用的反应式兜底。agent 在看到 403/CF 模式后自己选择调用。

## 为什么需要它

Claude Code 内置的 `WebFetch`(以及 `curl`、`requests`、绝大多数 HTTP 客户端)都过不了 Cloudflare 的 JS 挑战 —— 任何对 CF 保护站点(`science.org`、大量出版商、很多新闻站)的请求都会返回:

```
The server returned HTTP 403 Forbidden.
```

CloakBrowser 是一个在 C++ 层就打了反 bot 补丁的真实 Chromium,**能**通过那些挑战。cloakFetch 把 CloakBrowser + defuddle 接入 Claude Code(和其它 agent),让 agent 永远不必告诉用户"这页抓不下来"。

## 两条激活路径

|  | 路径 A:钩子 | 路径 B:技能 |
|---|---|---|
| **触发方式** | 自动 —— 每次 WebFetch 结果都会过一遍 | 反应式 —— agent 看到失败后自己决定 |
| **Agent 认知成本** | 零 —— 隐形升级 | 必须识别 403/CF 模式并记得这个技能 |
| **运行时支持** | 仅 Claude Code(需要 `PostToolUse` 钩子机制) | 任何支持 SKILL.md 的 agent:Claude Code、OpenClaw、Codex、OpenCode、SkillsMP |
| **命中时延迟** | ~25–40 秒 | ~25–40 秒 |
| **未命中时延迟** | ~毫秒级(正则检查,不启动浏览器) | 无(技能未被调用) |
| **安装** | 复制 2 个脚本 + 改 `~/.claude/settings.json` | 把技能目录扔进 agent 的 skills 目录 |
| **文件** | `hooks/cloak_fetch.py` + `hooks/webfetch_cloak_fallback.sh` | `skills/cloak-fetch/SKILL.md` + `cloak_fetch.py` + `cloak_fetch.sh` |

两条路径底层都用同一份 `cloak_fetch.py` —— 区别只是*激活方式*。

## 仓库结构

```
cloakFetch/
├── hooks/                          # 路径 A —— Claude Code PostToolUse
│   ├── cloak_fetch.py              #   无头 CloakBrowser → 渲染后的 HTML
│   └── webfetch_cloak_fallback.sh  #   payload 匹配器 + 编排器
├── skills/cloak-fetch/             # 路径 B —— SKILL.md 技能
│   ├── SKILL.md                    #   强势的描述 + 触发启发式
│   ├── cloak_fetch.py              #   (同一份脚本,env-python shebang)
│   └── cloak_fetch.sh              #   wrapper:定位 python、抓取、defuddle
├── settings.snippet.json           #   贴进 ~/.claude/settings.json 的 PostToolUse JSON 片段
└── README.md
```

---

## 路径 A —— Claude Code PostToolUse 钩子

### 架构

```
┌───────────────────┐    失败(CF 403)
│  WebFetch(Claude │ ─────────────────┐
│  内置工具)        │                  │
└───────────────────┘                  ▼
                          ┌──────────────────────────────┐
                          │ webfetch_cloak_fallback.sh   │
                          │ (PostToolUse 钩子)           │
                          │                              │
                          │ 1. 从 stdin 读 payload       │
                          │ 2. 正则匹配失败模式          │
                          │ 3. 提取 tool_input.url       │
                          │ 4. 调用 cloak_fetch.py       │
                          │ 5. defuddle → markdown       │
                          │ 6. 输出 additionalContext    │
                          └──────────────────────────────┘
                                         │
                                         ▼
                          ┌──────────────────────────────┐
                          │ cloak_fetch.py               │
                          │ (CloakBrowser 无头)          │
                          │                              │
                          │ 启动 → goto → 等 CF 放行     │
                          │ → 等内容渲染                  │
                          │ → 把 DOM 输出到 stdout       │
                          └──────────────────────────────┘
```

两个独立文件,失败检测正则(bash)和浏览器逻辑(Python)可以独立演进。

### 安装(钩子)

```bash
# 1. 把钩子脚本复制到 Claude Code 的钩子目录
mkdir -p ~/.claude/hooks
cp hooks/cloak_fetch.py hooks/webfetch_cloak_fallback.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/cloak_fetch.py ~/.claude/hooks/webfetch_cloak_fallback.sh

# 2. 告诉钩子你的 CloakBrowser Python 在哪。加进 shell 启动文件
#    (~/.zshrc、~/.bashrc 等):
#      export CLOAKBROWSER_PYTHON="$HOME/path/to/CloakBrowser/.venv/bin/python"
#    钩子也会自动尝试 $HOME/github/CloakBrowser/.venv/bin/python 和
#    `python3`,所以如果默认能用,这一步可跳过。

# 3. 在 ~/.claude/settings.json 中注册钩子 —— 把
#    settings.snippet.json 的内容作为新条目加进 "PostToolUse" 数组。
#    最终结构示例:
```

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "WebFetch",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/webfetch_cloak_fallback.sh"
          }
        ]
      }
    ]
  }
}
```

钩子在下一次工具调用时就会生效 —— 不用重启 Claude Code。

#### 小技巧 —— 用 symlink 代替复制

如果你把这个仓库当 git checkout 来维护(推荐),把钩子文件 symlink 到 `~/.claude/hooks/`,而不是复制。这样仓库里的修改立即生效,`git pull` 就等于更新钩子:

```bash
mkdir -p ~/.claude/hooks
ln -sf "$(pwd)/hooks/cloak_fetch.py"             ~/.claude/hooks/cloak_fetch.py
ln -sf "$(pwd)/hooks/webfetch_cloak_fallback.sh" ~/.claude/hooks/webfetch_cloak_fallback.sh
```

代价:如果你把仓库挪走或删了,钩子会静默停止生效(脚本里的 `[ ! -f "$CLOAK_FETCH" ]` 检查会触发并以 0 退出)。如果你的仓库在 `~/github/` 下稳定存在,这是个不错的取舍。

### 测试(钩子)

把一段伪造的 WebFetch 失败 payload 通过管道喂给钩子,模拟 harness:

```bash
echo '{
  "tool_name": "WebFetch",
  "tool_input": {"url": "https://www.science.org/content/page/information-authors-research-articles", "prompt": "x"},
  "tool_response": "The server returned HTTP 403 Forbidden."
}' | ~/.claude/hooks/webfetch_cloak_fallback.sh
```

预期:stdout 输出 `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "WebFetch was blocked... <markdown>"}}`,退出码 0。

实际测试就让 Claude Code 会话里的 Claude 去抓任意一个 Cloudflare 保护的 URL。你应该会先看到 `WebFetch` 的 403,紧接着是对话里的 `PostToolUse:WebFetch hook additional context: ...` 块。

### 可配置项(钩子)

在 `hooks/webfetch_cloak_fallback.sh` 中:

| 变量 | 默认值 | 作用 |
|---|---|---|
| `CLOAK_FETCH` | `$HOME/.claude/hooks/cloak_fetch.py` | Python 抓取脚本路径。可用同名环境变量覆盖。 |
| `CLOAKBROWSER_PYTHON` | `$HOME/github/CloakBrowser/.venv/bin/python` → `python3` | 跑抓取脚本的 Python 解释器。必须能 import `cloakbrowser`。 |
| `FAILURE_REGEX` | `403\|forbidden\|cloudflare\|just a moment\|resource was not loaded\|access denied\|blocked` | 大小写不敏感、针对 `tool_response` 的正则。按需放宽或收紧。 |

---

## 路径 B —— SKILL.md 技能(用于不支持钩子的 agent)

钩子方式只能用在 Claude Code 上。对于没有 `PostToolUse` 机制的 agent —— Codex CLI、OpenCode、OpenClaw、SkillsMP —— 把 cloakFetch 装成 SKILL.md 格式的技能。Agent 在相关场景下读取 SKILL.md,识别到 Cloudflare 失败模式后调用 wrapper 脚本。

### 安装(技能)

| Agent | 安装路径 |
|---|---|
| **Claude Code**(全局) | `cp -r skills/cloak-fetch ~/.claude/skills/cloak-fetch` |
| **Claude Code**(项目级) | `cp -r skills/cloak-fetch .claude/skills/cloak-fetch` |
| **OpenClaw**(全局) | `cp -r skills/cloak-fetch ~/.openclaw/skills/cloak-fetch` |
| **OpenClaw**(项目级) | `cp -r skills/cloak-fetch skills/cloak-fetch` |
| **SkillsMP** | 在 [skillsmp.com](https://skillsmp.com) 搜索 `cloak-fetch` |

如果 CloakBrowser 的 venv 不在默认路径,设置环境变量(可写在 shell rc,也可单次调用时传入):

```bash
export CLOAKBROWSER_PYTHON=/path/to/your/cloakbrowser/.venv/bin/python
```

### 调用(技能)

Agent 在普通抓取返回 403/CF 模式后,执行这条命令即可:

```bash
~/.claude/skills/cloak-fetch/cloak_fetch.sh "<URL>"
```

wrapper 会处理所有事:找到能 import `cloakbrowser` 的 Python、启动无头浏览器、跑 defuddle、把干净的 markdown 输出到 stdout。stderr 输出进度信息;任何失败都以非零状态码退出。

### 测试(技能)

```bash
~/.claude/skills/cloak-fetch/cloak_fetch.sh "https://www.science.org/content/page/information-authors-research-articles"
```

预期:大约 20–40 秒后,stdout 输出约 25 KB 的干净 markdown(页面标题是 "Information for Authors-Research Articles")。

非 Cloudflare 网站的健全性检查:

```bash
~/.claude/skills/cloak-fetch/cloak_fetch.sh "https://example.com"
# → "This domain is for use in documentation examples..."
```

### 可配置项(技能)

| 环境变量 | 默认值 | 作用 |
|---|---|---|
| `CLOAKBROWSER_PYTHON` | (自动探测:`~/github/CloakBrowser/.venv/bin/python`,然后 `python3`) | 能 import `cloakbrowser` 的 Python 解释器 |

在 `skills/cloak-fetch/cloak_fetch.py` 中:

| 旋钮 | 默认值 | 作用 |
|---|---|---|
| `headless=True` | `True` | 改成 `False` 可以看到浏览器窗口,便于调试 |
| 选择器等待列表 | `main, article, .article__body, .core-container, .pb-page-body` | 标志 SPA 内容已渲染完毕的选择器。目标站点有特殊需求时可扩充。 |
| `time.sleep(2)` 缓冲 | 2 秒 | 给晚加载 JS 的额外等待时间。 |

---

## 前置条件(两条路径都需要)

- 安装 [CloakBrowser](https://github.com/CloakHQ/CloakBrowser),`cloakbrowser` Python 包可 import(`pip install cloakbrowser` 的 venv 即可)
- `npx`(按需调用 `defuddle` —— 不需要全局安装)
- 仅路径 A:`jq`(用于解析钩子 payload)

## 行为与安全

- **失败即闭。** 如果 cloakFetch 内部出问题(没装 cloakbrowser、断网、CloakBrowser 也过不了挑战),两条路径都保留原始失败状态。Agent 永远不会被骗以为抓取成功。
- **顺利路径完全静默。** 正则不匹配时钩子什么都不做;没有失败需要补救时技能根本不会被触发。
- **成本。** 一次触发的兜底是真启动一个浏览器 —— 墙钟约 20–40 秒,内存非平凡。顺利路径上钩子的正则检查代价是 ~毫秒级。
- **信任边界。** 两条路径都只对 agent 已经主动选择交给抓取工具的 URL 起作用。它们不会引入新的访问互联网的方式 —— URL 面相同,只是后端能力更强。

## 限制

- Cloudflare 最难的挑战(交互式 Turnstile 等)在无头模式下可能仍然过不去 —— 需要全 CF 覆盖时把 `cloak_fetch.py` 中的 `headless` 设为 `False`。
- 钩子把 `tool_response` 当字符串做正则匹配。如果未来 Claude Code 改了 payload 结构,匹配器的 `jq` 选择器需要同步更新。
- `additionalContext` 大小受 Claude Code 钩子输出处理的上限约束 —— 过大的页面会被落盘,内联只显示预览(脚本会输出落盘文件路径,agent 可用 `Read` 读取)。
- 技能是**反应式**的:只有 agent 识别到失败并记得调用技能时才有效。如果 agent 一看到 403 就放弃、不再尝试,这个技能帮不上忙。SKILL.md 的描述刻意写得很"强势",就是为了对抗 agent 不主动触发的问题 —— 实际使用中如果 agent 触发不够积极,review 一下并按需调整。

## 💬 社区

- **Discord:** https://discord.gg/79JF5Atuk
- **微信:** 扫描下方二维码

<p align="center">
  <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/agents365ai_wechat_1.png" width="200" alt="微信交流群">
</p>

## ❤️ 支持

如果 cloakFetch 帮你少看了一次 "HTTP 403 Forbidden",欢迎打赏支持作者:

<table>
  <tr>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/wechat-pay.png" width="180" alt="微信支付">
      <br>
      <b>微信支付</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/alipay.png" width="180" alt="支付宝">
      <br>
      <b>支付宝</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/buymeacoffee.png" width="180" alt="Buy Me a Coffee">
      <br>
      <b>Buy Me a Coffee</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/awarding/award.gif" width="180" alt="打赏">
      <br>
      <b>打赏</b>
    </td>
  </tr>
</table>

## 👤 作者

**Agents365-ai**

- GitHub: https://github.com/Agents365-ai
- Bilibili: https://space.bilibili.com/441831884

## 📄 License

[MIT](LICENSE)
