#!/usr/bin/env bash
# cloakFetch 一键初始化脚本
# 本地:  ./init.sh                      # 交互选择
#        ./init.sh --system              # 系统默认
#        ./init.sh --venv /path/to/venv  # 指定 venv
# 远程:  curl -sSL https://raw.githubusercontent.com/piaomiaoguying/cloakFetch/main/init.sh | bash
set -uo pipefail

REPO_URL="https://github.com/piaomiaoguying/cloakFetch.git"
SKILL_NAME="cloak-fetch"
TARGET_DIR="${HOME}/.claude/skills/${SKILL_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="${SCRIPT_DIR}/skills/${SKILL_NAME}"

# ── 解析参数 ──────────────────────────────────────────────────
INSTALL_MODE=""       # system | venv
VENV_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --system) INSTALL_MODE="system" ;;
    --venv)
      if [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
        echo "用法: $0 --venv <路径>" >&2; exit 2
      fi
      INSTALL_MODE="venv"; VENV_PATH="$2"; shift
      ;;
    *) echo "未知参数: $1"; echo "用法: $0 [--system | --venv <路径>]"; exit 2 ;;
  esac
  shift
done

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

# ── 1. 选择安装位置 ──────────────────────────────────────────
echo ">>> 1. 安装位置"
echo "    cloakbrowser 含完整 Chromium (~300MB)，请选择安装方式:"

if [ -z "${INSTALL_MODE}" ]; then
  # 未通过参数指定，交互询问
  if [ -t 0 ]; then
    echo ""
    echo "  1) 系统默认      — pip3 install 到当前 Python 环境"
    echo "  2) 隔离 venv     — 创建独立虚拟环境 (~300MB)"
    echo ""
    read -r -p "  请选择 [1/2] (默认 1): " CHOICE
    CHOICE="${CHOICE:-1}"
  else
    echo "    非交互模式，默认使用系统安装"
    CHOICE="1"
  fi

  case "${CHOICE}" in
    1) INSTALL_MODE="system" ;;
    2)
      INSTALL_MODE="venv"
      read -r -p "    venv 路径 (默认 ~/clkbrowser-venv，直接回车即可): " VENV_PATH
      VENV_PATH="${VENV_PATH:-${HOME}/clkbrowser-venv}"
      ;;
    *) echo "    ✗ 无效选择"; exit 1 ;;
  esac
fi

if [ "${INSTALL_MODE}" = "venv" ] && [ -z "${VENV_PATH}" ]; then
  VENV_PATH="${HOME}/clkbrowser-venv"
  echo "    使用默认路径: ${VENV_PATH}"
fi

echo ""

# ── 2. 安装依赖 ──────────────────────────────────────────────
echo ">>> 2. 安装 Python 依赖"

if [ "${INSTALL_MODE}" = "venv" ]; then
  # venv 模式
  if [ ! -f "${VENV_PATH}/bin/python" ]; then
    echo "    创建 venv: ${VENV_PATH}"
    python3 -m venv "${VENV_PATH}" 2>&1 || {
      echo "    ✗ 创建 venv 失败"; exit 1
    }
    echo "    ✓ venv 已创建"
  else
    echo "    使用已有 venv: ${VENV_PATH}"
  fi
  PYTHON="${VENV_PATH}/bin/python"
  echo "    安装 cloakbrowser + trafilatura 到 venv ..."
  "${PYTHON}" -m pip install --quiet cloakbrowser trafilatura 2>&1 || {
    echo "    ✗ pip install 失败"; exit 1
  }
  echo "    ✓ 已安装到 ${VENV_PATH}"
  echo "    占用估算: $(du -sh "${VENV_PATH}" 2>/dev/null | awk '{print $1}')"
else
  # system 模式
  echo "    安装到系统 Python (pip3 install cloakbrowser trafilatura)"
  pip3 install cloakbrowser trafilatura 2>&1 || {
    echo "    ✗ pip3 install 失败，请确认 Python 3 和 pip 已正确安装"
    exit 1
  }
  PYTHON="$(command -v python3)"
  echo "    ✓ 已安装到系统 Python"
fi

echo ""

# ── 3. 放置技能目录 ──────────────────────────────────────────
echo ">>> 3. 放置技能到 ${TARGET_DIR}"
mkdir -p "$(dirname "${TARGET_DIR}")"
if [ -d "${TARGET_DIR}" ] || [ -L "${TARGET_DIR}" ]; then
  echo "    ! 目标已存在，跳过复制"
else
  cp -r "${SKILL_SRC}" "${TARGET_DIR}"
  echo "    ✓ 已复制到 ${TARGET_DIR}"
fi
echo ""

# ── 4. 配置 Python 解释器 ────────────────────────────────────
echo ">>> 4. 配置 Python 解释器"
if "${PYTHON}" -c "import cloakbrowser" 2>/dev/null; then
  if [ "${INSTALL_MODE}" = "venv" ]; then
    echo "    ✓ venv python 可 import cloakbrowser"
    echo "    → 写入 ${TARGET_DIR}/cloak_fetch.conf"
    echo "${PYTHON}" > "${TARGET_DIR}/cloak_fetch.conf"
  else
    echo "    ✓ 系统 python3 可直接 import cloakbrowser，无需额外配置"
  fi
else
  echo "    ! ${PYTHON} 无法 import cloakbrowser"
  echo "    ! 请手动编辑 ${TARGET_DIR}/cloak_fetch.conf"
fi
echo ""

# ── 5. 验证 ──────────────────────────────────────────────────
echo ">>> 5. 验证"
if [ -x "${TARGET_DIR}/cloak_fetch.sh" ]; then
  echo "    ✓ cloak_fetch.sh 就绪"
else
  echo "    ✗ cloak_fetch.sh 不可执行"
fi
echo ""

# ── 6. CLAUDE.md 配置 ────────────────────────────────────────
echo ">>> 6. CLAUDE.md 配置"
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
