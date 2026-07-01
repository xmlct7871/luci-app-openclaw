#!/bin/sh
# luci-app-openclaw v2026.6.10 — 路径解析工具
#
# 设计原则 (v2026.6.10):
#   - install_path 直接就是 OpenClaw 的 state dir(类比上游 ~/.openclaw/)
#   - 默认 install_path = /root/.openclaw,与 OpenClaw 上游在 root 用户下的默认路径完全一致
#   - 不再有 /opt/openclaw/{node,global,data} 包装层
#   - Node.js 运行时和 OpenClaw 包都装在 ${install_path}/node/ 下
#   - 数据/配置/工作区/扩展直接展开在 ${install_path}/ 根(与 upstream 平铺布局一致)
#
# OpenClaw 进程环境变量(本文件末尾设置):
#   HOME=${STATE_DIR}                  # 让 ~ 解析到 install_path
#   OPENCLAW_STATE_DIR=${STATE_DIR}     # 上游 env var 优先
#   OPENCLAW_CONFIG_PATH=${STATE_DIR}/openclaw.json
#   NPM_CONFIG_CACHE=${STATE_DIR}/.npm
#   TMPDIR=${STATE_DIR}/.tmp
#   XDG_CACHE_HOME=${STATE_DIR}/.cache

# ─── 默认 state dir ───
# 与上游 OpenClaw 在 root 用户的默认位置一致,零配置即可用
OC_DEFAULT_STATE_DIR="/root/.openclaw"

# ─── 路径规范化 ───
# 输入:用户配置的 install_path(state dir 路径)
# 输出:规范化后的绝对路径(失败返回 1)
oc_normalize_install_path() {
	local raw="${1:-}"

	# 空值统一回到 upstream 默认
	[ -n "$raw" ] || raw="$OC_DEFAULT_STATE_DIR"

	# 去掉首尾空白和末尾斜杠。OpenWrt busybox sed 支持基础表达式。
	raw=$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s:/*$::')
	[ -n "$raw" ] || raw="$OC_DEFAULT_STATE_DIR"

	case "$raw" in
		/*) ;;
		*) return 1 ;;
	esac

	# 拒绝 shell 特殊字符(防命令注入)
	# 注意: 不能用 *[\ \t]* 配 [ ] 转义字符类,bash 在 case 模式里
	# 跟 | 后续 pattern 组合时会报 syntax error near ']*'
	# 改用 POSIX 标准字符类 [[:space:]] 代替
	case "$raw" in
		*[[:space:]]*|*\'*|*\"*|*\`*|*\$*|*\;*|*\&*|*\|*|*\<*|*\>*|*\(*|*\)*)
			return 1
			;;
	esac

	# 拒绝危险根目录(只读/系统目录)
	case "$raw" in
		/|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/tmp|/tmp/*|/var|/var/*|/etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|/rom|/rom/*|/overlay|/overlay/*)
			return 1
			;;
	esac

	printf '%s\n' "$raw"
}

# ─── POSIX 单引号转义 ───
oc_quote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# ─── 加载所有路径,设置到 env var ───
# 输入:install_path(state dir)
# 输出:设置 STATE_DIR / NODE_BASE / CONFIG_FILE / 等所有路径,export
oc_load_paths() {
	local input="${1:-}"
	local normalized

	normalized=$(oc_normalize_install_path "$input") || return 1

	# ── 状态层(state dir 内容,匹配 upstream 平铺布局) ──
	STATE_DIR="$normalized"
	CONFIG_FILE="${STATE_DIR}/openclaw.json"
	WORKSPACE_DIR="${STATE_DIR}/workspace"
	EXT_DIR="${STATE_DIR}/extensions"
	HOOKS_DIR="${STATE_DIR}/hooks"
	LOGS_DIR="${STATE_DIR}/logs"
	AGENTS_DIR="${STATE_DIR}/agents"
	BACKUPS_DIR="${STATE_DIR}/backups"
	SECRETS_FILE="${STATE_DIR}/secrets.json"
	NPM_PROJECTS_DIR="${EXT_DIR}/npm/projects"

	# ── 运行时层(Node.js + OpenClaw npm 包) ──
	NODE_BASE="${STATE_DIR}/node"
	NODE_BIN="${NODE_BASE}/bin/node"
	NPM_BIN="${NODE_BASE}/bin/npm"
	PNP_BIN="${NODE_BASE}/bin/pnpm"
	NPM_LIB="${NODE_BASE}/lib/node_modules"
	# OpenClaw 入口(pnpm 版本化目录优先)
	OC_ENTRY_DEFAULT="${NPM_LIB}/openclaw/openclaw.mjs"
	OC_ENTRY_FALLBACK="${NPM_LIB}/openclaw/dist/cli.js"

	# ── 隔离目录(避免污染系统其它用户) ──
	NPM_CACHE_DIR="${STATE_DIR}/.npm"
	TMP_DIR="${STATE_DIR}/.tmp"
	CACHE_DIR="${STATE_DIR}/.cache"
	JITI_CACHE_DIR="${CACHE_DIR}/jiti"

	# ── OpenClaw 上游 env var(env var 优先于 ~/.openclaw/ 解析) ──
	OPENCLAW_STATE_DIR="$STATE_DIR"
	OPENCLAW_CONFIG_PATH="$CONFIG_FILE"
	OPENCLAW_HOME="$STATE_DIR"

	export STATE_DIR CONFIG_FILE WORKSPACE_DIR EXT_DIR HOOKS_DIR LOGS_DIR \
	       AGENTS_DIR BACKUPS_DIR SECRETS_FILE NPM_PROJECTS_DIR \
	       NODE_BASE NODE_BIN NPM_BIN PNP_BIN NPM_LIB \
	       OC_ENTRY_DEFAULT OC_ENTRY_FALLBACK \
	       NPM_CACHE_DIR TMP_DIR CACHE_DIR JITI_CACHE_DIR \
	       OPENCLAW_STATE_DIR OPENCLAW_CONFIG_PATH OPENCLAW_HOME
}

# ─── 向上回溯找到已存在的路径 ───
oc_find_existing_path() {
	local path="$1"
	while [ -n "$path" ] && [ "$path" != "/" ]; do
		[ -e "$path" ] && { printf '%s\n' "$path"; return 0; }
		path=${path%/*}
	done
	printf '/\n'
}

# ─── 探针:检查 install_path 是否可写 ───
oc_probe_writable_root() {
	local base="$1"
	local probe_parent
	local probe_dir

	probe_parent=$(oc_find_existing_path "$base")
	[ -d "$probe_parent" ] || return 1
	[ -w "$probe_parent" ] || return 1

	probe_dir="${probe_parent}/.openclaw-write-test-$$"
	if mkdir "$probe_dir" 2>/dev/null; then
		rmdir "$probe_dir" 2>/dev/null || true
		return 0
	fi

	return 1
}

# ─── 查找 OpenClaw 入口文件 ───
# 优先级:
#   1. ${NPM_LIB}/<pnpm-version>/openclaw/openclaw.mjs  (pnpm 7+ 装法)
#   2. ${NPM_LIB}/openclaw/openclaw.mjs                  (npm 装法,默认)
#   3. ${NPM_LIB}/openclaw/dist/cli.js                  (旧版 fallback)
oc_find_oc_entry() {
	[ -n "$NPM_LIB" ] || return 1
	local d
	# pnpm 版本化目录(类似 ${NPM_LIB}/5/openclaw)
	for ver_dir in "${NPM_LIB}"/*/openclaw; do
		[ -d "$ver_dir" ] || continue
		if [ -f "${ver_dir}/openclaw.mjs" ]; then
			printf '%s\n' "${ver_dir}/openclaw.mjs"
			return 0
		elif [ -f "${ver_dir}/dist/cli.js" ]; then
			printf '%s\n' "${ver_dir}/dist/cli.js"
			return 0
		fi
	done
	# 标准 npm -g 装法
	if [ -f "${NPM_LIB}/openclaw/openclaw.mjs" ]; then
		printf '%s\n' "${NPM_LIB}/openclaw/openclaw.mjs"
		return 0
	elif [ -f "${NPM_LIB}/openclaw/dist/cli.js" ]; then
		printf '%s\n' "${NPM_LIB}/openclaw/dist/cli.js"
		return 0
	fi
	return 1
}

# ─── 安全检查:install_path 是否在白名单内(用于卸载时) ───
# 接受 v2 风格的 /opt/openclaw 包装(用户可能改 install_path 留 compat)
# 也接受 v3 风格的 /root/.openclaw 平铺(与 upstream 一致)
# 也接受 /openclaw-<profile> 多实例(为未来预留)
oc_safe_openclaw_root() {
	local root="${1:-}"

	# 必须以 .openclaw / .openclaw-<profile> / openclaw / openclaw-<profile> 结尾
	case "$root" in
		*/.openclaw|*/.openclaw-*|*/openclaw|*/openclaw-*) ;;
		*) return 1 ;;
	esac

	# 必须在允许的根目录下(防止 rm -rf / 误操作)
	case "$root" in
		# v3 upstream 默认(推荐)
		/root/.openclaw|/root/.openclaw-*) ;;
		# v2 风格包装(用户可能改 install_path 兼容)
		/root/openclaw|/root/openclaw-*) ;;
		# 经典 /opt 包装
		/opt/openclaw|/opt/openclaw-*|/opt/.openclaw|/opt/.openclaw-*) ;;
		# 外置盘
		/mnt/*/.openclaw|/mnt/*/.openclaw-*|/mnt/*/openclaw|/mnt/*/openclaw-*) ;;
		/media/*/.openclaw|/media/*/.openclaw-*|/media/*/openclaw|/media/*/openclaw-*) ;;
		# srv / home
		/srv/*/.openclaw|/srv/*/.openclaw-*|/srv/*/openclaw|/srv/*/openclaw-*) ;;
		/home/*/.openclaw|/home/*/.openclaw-*|/home/*/openclaw|/home/*/openclaw-*) ;;
		# OverlayFS 兼容(iStoreOS Docker bind mount)
		/overlay/upper/root/.openclaw|/overlay/upper/root/openclaw|/overlay/upper/opt/openclaw) ;;
		*)
			return 1
			;;
	esac

	return 0
}

# ─── 检测 v2 风格数据(用于拒绝启动) ───
# v2 数据布局有两种(取决于 v2 时 install_path 怎么配):
#   - install_path=/opt        → 数据在 /opt/openclaw/data/.openclaw/
#   - install_path=/opt/openclaw → 数据在 /opt/openclaw/data/.openclaw/
# v3 用 install_path 作为 state dir 自身,所以需要检查相对偏移
oc_detect_v2_layout() {
	local state_dir="${1:-}"
	[ -n "$state_dir" ] || return 1

	# 检查所有可能的 v2 风格数据位置
	local v2_candidates
	v2_candidates="
${state_dir}/data/.openclaw/openclaw.json
${state_dir}/openclaw/data/.openclaw/openclaw.json
"

	local f
	for f in $v2_candidates; do
		[ -f "$f" ] && {
			printf '%s\n' "$(dirname "$(dirname "$f")")"
			return 0
		}
	done

	# 同时检测 v2 特有的子目录签名
	# v2 的 extensions 在 ${state_dir}/data/.openclaw/extensions/
	# v3 的 extensions 在 ${state_dir}/extensions/ (没有 data/ 中间层)
	if [ -d "${state_dir}/data/.openclaw/extensions" ] || \
	   [ -d "${state_dir}/openclaw/data/.openclaw/extensions" ]; then
		for cand in "${state_dir}/data/.openclaw" "${state_dir}/openclaw/data/.openclaw"; do
			[ -d "$cand" ] && {
				printf '%s\n' "$cand"
				return 0
			}
		done
	fi

	return 1
}
