#!/bin/sh
# ============================================================================
# luci-app-openclaw v2026.6.10 — 全局环境变量
# 仅在 Node.js 已安装时生效，为 SSH 登录用户提供正确的运行环境
# 解决 Issue #42: 统一配置文件路径，避免 /root/.openclaw 与安装路径混乱
# v2026.6.10: install_path 直接是 state dir 自身,无 /data 包装
# ============================================================================

# 从 UCI 配置读取自定义安装路径。
# 注意:这里不能修改全局 HOME。profile 会被 SSH shell、zsh/oh-my-zsh 等加载,
# 全局改 HOME 会让 cd ~、插件缓存、历史文件全部跑到 OpenClaw 数据目录。
# OpenClaw CLI 需要的 HOME 只在 openclaw 命令包装器里单独注入。
[ -r /usr/libexec/openclaw-paths.sh ] && . /usr/libexec/openclaw-paths.sh
OC_CONFIGURED_PATH="$(uci -q get openclaw.main.install_path 2>/dev/null || echo '/root/.openclaw')"
if command -v oc_load_paths >/dev/null 2>&1; then
	oc_load_paths "$OC_CONFIGURED_PATH" || return 0
	OC_INSTALL_PATH="$STATE_DIR"
else
	# 兜底:paths.sh 不可用时手写
	OC_INSTALL_PATH="$OC_CONFIGURED_PATH"
	NODE_BASE="${OC_INSTALL_PATH}/node"
	NPM_LIB="${NODE_BASE}/lib/node_modules"
	CONFIG_FILE="${OC_INSTALL_PATH}/openclaw.json"
fi

# v2026.6.10 修正: 加空值守卫,防止 OC_INSTALL_PATH / NODE_BASE 为空时
# 后续 PATH / case 匹配产生误判(例如变成 "*:/bin:*")
[ -n "${OC_INSTALL_PATH:-}" ] || return 0
[ -n "${NODE_BASE:-}" ] || return 0

# 检查 Node.js 是否已安装
[ -x "${NODE_BASE}/bin/node" ] || return 0

# 添加 Node.js 和 OpenClaw 到 PATH (非侵入式，检查是否已存在)
case ":$PATH:" in
  *":${NODE_BASE}/bin:"*) ;;
  *) export PATH="${NODE_BASE}/bin:${NPM_LIB}/bin:$PATH" ;;
esac

# 设置 Node.js ICU 数据路径
export NODE_ICU_DATA="${NODE_BASE}/share/icu"

# 设置 OpenClaw 核心环境变量
# v2026.6.10: 扁平化,所有 env var 都指向 install_path 自身
export OPENCLAW_HOME="$OC_INSTALL_PATH"
export OPENCLAW_STATE_DIR="$OC_INSTALL_PATH"
export OPENCLAW_CONFIG_PATH="$CONFIG_FILE"

# 创建便捷包装器:只给 openclaw 命令单独注入 HOME,避免污染用户 shell
_oc_cli=""
if [ -x "${NPM_LIB}/openclaw" ] || [ -f "${NPM_LIB}/openclaw/openclaw.mjs" ]; then
	if [ -x "${NODE_BASE}/bin/openclaw" ]; then
		_oc_cli="${NODE_BASE}/bin/openclaw"
	else
		_oc_cli="${NODE_BASE}/bin/node ${NPM_LIB}/openclaw/openclaw.mjs"
	fi
else
	for _oc_dir in "${NPM_LIB}/openclaw" "${NPM_LIB}/*/openclaw" "${NODE_BASE}/lib/node_modules/openclaw"; do
		case "$_oc_dir" in
			*"*"*) continue ;;
		esac
		if [ -f "${_oc_dir}/openclaw.mjs" ]; then
			_oc_cli="${NODE_BASE}/bin/node ${_oc_dir}/openclaw.mjs"
			break
		elif [ -f "${_oc_dir}/dist/cli.js" ]; then
			_oc_cli="${NODE_BASE}/bin/node ${_oc_dir}/dist/cli.js"
			break
		fi
	done
fi

if [ -n "$_oc_cli" ]; then
	openclaw() {
		# v2026.6.10: 路径扁平化,所有 env var 都指向 install_path 自身
		HOME="$OC_INSTALL_PATH" \
		OPENCLAW_HOME="$OC_INSTALL_PATH" \
		OPENCLAW_STATE_DIR="$OC_INSTALL_PATH" \
		OPENCLAW_CONFIG_PATH="$CONFIG_FILE" \
		sh -c 'exec "$@"' openclaw $_oc_cli "$@"
	}
fi
