-- luci-app-openclaw v2026.6.10 — Lua 端路径解析
--
-- 设计原则 (与 openclaw-paths.sh 保持一致):
--   - install_path 直接就是 OpenClaw 的 state dir(类比上游 ~/.openclaw/)
--   - 默认 install_path = /root/.openclaw,与 upstream 完全一致
--   - 不再有 /opt/openclaw/{node,global,data} 包装层

local M = {}

-- upstream OpenClaw 在 root 用户下的默认 state dir
local DEFAULT_STATE_DIR = "/root/.openclaw"

-- ─── 工具函数 ───
local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- ─── 路径规范化 ───
-- 与 openclaw-paths.sh 的 oc_normalize_install_path 行为一致
-- 失败返回 nil
function M.normalize_install_path(value)
	local raw = trim(value)
	if raw == "" then raw = DEFAULT_STATE_DIR end
	-- 去掉末尾斜杠
	raw = raw:gsub("/+$", "")
	if raw == "" then raw = "/" end

	if raw:sub(1, 1) ~= "/" then return nil end
	if raw:match("[%s'\"`$;&|<>()]") then return nil end
	if raw == "/" or raw == "/proc" or raw:match("^/proc/") or
		raw == "/sys" or raw:match("^/sys/") or
		raw == "/dev" or raw:match("^/dev/") or
		raw == "/tmp" or raw:match("^/tmp/") or
		raw == "/var" or raw:match("^/var/") or
		raw == "/etc" or raw:match("^/etc/") or
		raw == "/usr" or raw:match("^/usr/") or
		raw == "/bin" or raw:match("^/bin/") or
		raw == "/sbin" or raw:match("^/sbin/") or
		raw == "/lib" or raw:match("^/lib/") or
		raw == "/rom" or raw:match("^/rom/") or
		raw == "/overlay" or raw:match("^/overlay/") then
		return nil
	end

	return raw
end

-- ─── 派生所有路径 ───
-- 输入:install_path(state dir 路径)
-- 输出:含 STATE_DIR / NODE_BASE / CONFIG_FILE / 等所有路径的 table
-- 失败返回 nil
function M.derive_paths(value)
	local base = M.normalize_install_path(value) or DEFAULT_STATE_DIR

	-- 状态层(state dir 内容,匹配 upstream 平铺布局)
	local state_dir = base
	local config_file = state_dir .. "/openclaw.json"
	local workspace_dir = state_dir .. "/workspace"
	local ext_dir = state_dir .. "/extensions"
	local hooks_dir = state_dir .. "/hooks"
	local logs_dir = state_dir .. "/logs"
	local agents_dir = state_dir .. "/agents"
	local backups_dir = state_dir .. "/backups"
	local secrets_file = state_dir .. "/secrets.json"
	local npm_projects_dir = ext_dir .. "/npm/projects"

	-- 运行时层
	local node_base = state_dir .. "/node"
	local node_bin = node_base .. "/bin/node"
	local npm_bin = node_base .. "/bin/npm"
	local pnp_bin = node_base .. "/bin/pnpm"
	local npm_lib = node_base .. "/lib/node_modules"
	local oc_entry_default = npm_lib .. "/openclaw/openclaw.mjs"
	local oc_entry_fallback = npm_lib .. "/openclaw/dist/cli.js"

	-- 隔离目录
	local npm_cache_dir = state_dir .. "/.npm"
	local tmp_dir = state_dir .. "/.tmp"
	local cache_dir = state_dir .. "/.cache"
	local jiti_cache_dir = cache_dir .. "/jiti"

	return {
		-- 输入/输出
		install_path = state_dir,
		normalized = state_dir,

		-- 状态层
		state_dir = state_dir,
		config_file = config_file,
		workspace_dir = workspace_dir,
		ext_dir = ext_dir,
		hooks_dir = hooks_dir,
		logs_dir = logs_dir,
		agents_dir = agents_dir,
		backups_dir = backups_dir,
		secrets_file = secrets_file,
		npm_projects_dir = npm_projects_dir,

		-- 运行时层
		node_base = node_base,
		node_bin = node_bin,
		npm_bin = npm_bin,
		pnp_bin = pnp_bin,
		npm_lib = npm_lib,
		oc_entry_default = oc_entry_default,
		oc_entry_fallback = oc_entry_fallback,

		-- 隔离目录
		npm_cache_dir = npm_cache_dir,
		tmp_dir = tmp_dir,
		cache_dir = cache_dir,
		jiti_cache_dir = jiti_cache_dir,

		-- OpenClaw 上游 env var 值
		openclaw_state_dir = state_dir,
		openclaw_config_path = config_file,
		openclaw_home = state_dir,
	}
end

-- ─── shell 转义 ───
function M.shellquote(value)
	return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

-- ─── 安全检查:install_path 是否在白名单内(用于卸载时) ───
-- 与 openclaw-paths.sh 的 oc_safe_openclaw_root 行为一致
function M.is_safe_openclaw_root(value)
	if type(value) ~= "string" then return false end

	-- 必须以 .openclaw / .openclaw-<profile> / openclaw / openclaw-<profile> 结尾
	local recognized_suffix = value:match("/%.openclaw$") or
	                          value:match("/%.openclaw%-[^/]+$") or
	                          value:match("/openclaw$") or
	                          value:match("/openclaw%-[^/]+$")
	if not recognized_suffix then return false end

	-- 必须在允许的根目录下(防止 rm -rf / 误操作)
	-- v3 upstream 默认
	if value:match("^/root/%.openclaw$") or value:match("^/root/%.openclaw%-[^/]+$") then return true end
	-- v2 风格包装
	if value:match("^/root/openclaw$") or value:match("^/root/openclaw%-[^/]+$") then return true end
	-- 经典 /opt 包装
	if value:match("^/opt/openclaw$") or value:match("^/opt/openclaw%-[^/]+$") or
	   value:match("^/opt/%.openclaw$") or value:match("^/opt/%.openclaw%-[^/]+$") then return true end
	-- 外置盘
	if value:match("^/mnt/[^/]+/%.openclaw$") or value:match("^/mnt/[^/]+/%.openclaw%-[^/]+$") or
	   value:match("^/mnt/[^/]+/openclaw$") or value:match("^/mnt/[^/]+/openclaw%-[^/]+$") then return true end
	if value:match("^/media/[^/]+/%.openclaw$") or value:match("^/media/[^/]+/%.openclaw%-[^/]+$") or
	   value:match("^/media/[^/]+/openclaw$") or value:match("^/media/[^/]+/openclaw%-[^/]+$") then return true end
	-- srv / home
	if value:match("^/srv/[^/]+/%.openclaw$") or value:match("^/srv/[^/]+/%.openclaw%-[^/]+$") or
	   value:match("^/srv/[^/]+/openclaw$") or value:match("^/srv/[^/]+/openclaw%-[^/]+$") then return true end
	if value:match("^/home/[^/]+/%.openclaw$") or value:match("^/home/[^/]+/%.openclaw%-[^/]+$") or
	   value:match("^/home/[^/]+/openclaw$") or value:match("^/home/[^/]+/openclaw%-[^/]+$") then return true end
	-- OverlayFS 兼容
	if value == "/overlay/upper/root/.openclaw" or
	   value == "/overlay/upper/root/openclaw" or
	   value == "/overlay/upper/opt/openclaw" then return true end

	return false
end

-- ─── 检测 v2 风格数据(用于拒绝启动) ───
-- 与 openclaw-paths.sh 的 oc_detect_v2_layout 行为一致
function M.detect_v2_layout(state_dir)
	if type(state_dir) ~= "string" or state_dir == "" then return nil end

	-- 检查所有可能的 v2 风格数据位置
	local candidates = {
		state_dir .. "/data/.openclaw",
		state_dir .. "/openclaw/data/.openclaw",
	}
	for _, cand in ipairs(candidates) do
		if nixio and nixio.fs and nixio.fs.stat(cand, "type") then
			return cand
		end
		-- 兜底:用 luci.sys 或 io.open 检查
		local f = io.open(cand .. "/openclaw.json", "r")
		if f then
			f:close()
			return cand
		end
	end
	return nil
end

return M
