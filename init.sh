#!/usr/bin/env bash
# cloakFetch 一键初始化脚本
# 本地:  ./init.sh
# 远程:  curl -sSL https://raw.githubusercontent.com/piaomiaoguying/cloakFetch/main/init.sh | bash
set -uo pipefail

REPO_URL="https://github.com/piaomiaoguying/cloakFetch.git"
SKILL_NAME="cloak-fetch"
TARGET_DIR="${HOME}/.claude/skills/${SKILL_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="${SCRIPT_DIR}/skills/${SKILL_NAME}"

echo "=== cloakFetch 初始化 ==="
echo ""

# ── 0. 获取技能文件 ──────────────────────────────────────────
if [ ! -d "${SKILL_SRC}" ]; then
  echo ">>> 0. 获取技能文件"
  TMPDIR="$(mktemp -d)"
  if git clone --depth 1 "${REPO_URL}" "${TMPDIR}" 2>&1; then
    SKILL_SRC="${TMPDIR}/skills/${SKILL_NAME}"
    echo "    ✓ 已 clone 仓库"
  else
    echo "    ✗ clone 失败，请手动下载: ${REPO_URL}"
    exit 1
  fi
  echo ""
fi

# ── 1. 安装依赖 ──────────────────────────────────────────────
echo ">>> 1. 安装 Python 依赖 (cloakbrowser + trafilatura)"
if pip3 install cloakbrowser trafilatura 2>&1; then
  echo "    ✓ 安装完成"
else
  echo "    ✗ pip3 install 失败，请确认 Python 3 和 pip 已正确安装"
  exit 1
fi
echo ""

# ── 2. 放置技能目录 ──────────────────────────────────────────
echo ">>> 2. 放置技能到 ${TARGET_DIR}"
mkdir -p "$(dirname "${TARGET_DIR}")"
if [ -d "${TARGET_DIR}" ] || [ -L "${TARGET_DIR}" ]; then
  echo "    ! 目标已存在，跳过复制"
else
  cp -r "${SKILL_SRC}" "${TARGET_DIR}"
  echo "    ✓ 已复制到 ${TARGET_DIR}"
fi
echo ""

# ── 3. 配置 Python 解释器 ────────────────────────────────────
echo ">>> 3. 配置 Python 解释器"
PY3="$(command -v python3 2>/dev/null || echo "")"
if [ -n "${PY3}" ] && "${PY3}" -c "import cloakbrowser" 2>/dev/null; then
  echo "    ✓ 系统 python3 可直接 import cloakbrowser，无需额外配置"
else
  GUESSED_VENV=""
  for candidate in \
    "${HOME}/CloakBrowser/.venv/bin/python" \
    "${HOME}/CloakBrowser/.venv/bin/python3" \
    ; do
    if [ -x "${candidate}" ] && "${candidate}" -c "import cloakbrowser" 2>/dev/null; then
      GUESSED_VENV="${candidate}"
      break
    fi
  done

  if [ -n "${GUESSED_VENV}" ]; then
    echo "    检测到 ${GUESSED_VENV}"
    echo "    → 已写入 ${TARGET_DIR}/cloak_fetch.conf"
    echo "${GUESSED_VENV}" > "${TARGET_DIR}/cloak_fetch.conf"
    echo ""
    echo "    推荐同时设置环境变量（可选）:"
    echo "      export CLOAKBROWSER_PYTHON=${GUESSED_VENV}"
    echo "    将上面这行加入 ~/.zshrc 或 ~/.bashrc"
  else
    echo "    ! 未自动检测到可 import cloakbrowser 的 Python"
    echo "    ! 请手动设置 CLOAKBROWSER_PYTHON 环境变量，或编辑"
    echo "    ! ${TARGET_DIR}/cloak_fetch.conf"
  fi
fi
echo ""

# ── 4. 验证 ──────────────────────────────────────────────────
echo ">>> 4. 验证"
if [ -x "${TARGET_DIR}/cloak_fetch.sh" ]; then
  echo "    ✓ cloak_fetch.sh 就绪"
else
  echo "    ✗ cloak_fetch.sh 不可执行"
fi
echo ""

# ── 5. CLAUDE.md 配置 ────────────────────────────────────────
echo ">>> 5. CLAUDE.md 配置"
CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
if [ -f "${CLAUDE_MD}" ]; then
  if grep -q "网页内容读取规范" "${CLAUDE_MD}" 2>/dev/null; then
    echo "    ✓ 已配置网页内容读取规范，跳过"
  else
    cat >> "${CLAUDE_MD}" << 'EOF'

## 网页内容读取规范
当用户要求查看、读取、或获取网页的实际正文内容时（如"看一下这个页面""读取内容""获取文章"），必须优先使用 cloak-fetch skill，**禁止使用 WebFetch 或 curl 直接抓取**。原因：WebFetch 和 curl 不执行 JavaScript，无法渲染 SPA 页面（如支付宝/微信文档中心等）；也无法通过 WAF/CDN 反爬保护。
WebFetch 仅在以下场景可使用：检查 meta 标签、验证链接是否有效、获取纯静态 API 响应。
在使用 WebFetch 后若返回内容为空或极短（<500字符），必须立即用 cloak-fetch skill 重试。
EOF
    echo "    ✓ 已追加到 ${CLAUDE_MD}"
  fi
else
  echo "    ! ~/.claude/CLAUDE.md 不存在，跳过"
fi

echo ""
echo "=== 初始化完成 ==="
