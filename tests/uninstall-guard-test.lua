-- luci-app-openclaw v1.0.13 — 卸载路径两个隐患修复的验证脚本
-- 用法: lua5.1 /tmp/oc-uninstall-test.lua <修改后的 controller 路径>
local CTRL = arg[1] or "/tmp/openclaw.lua"

-- ── 1) 语法检查(loadfile 只编译不执行,不会触发 luci 依赖) ──
local chunk, err = loadfile(CTRL)
if not chunk then
	print("❌ 语法检查失败: " .. tostring(err))
	os.exit(1)
end
print("✅ 语法检查通过: " .. CTRL)

-- ── 2) 从源文件里抽取被测函数(测的是真实代码,不是复制品) ──
local fh = io.open(CTRL, "r")
if not fh then print("❌ 打不开 " .. CTRL); os.exit(1) end
local src = fh:read("*a")
fh:close()

local s = src:find("local function sanitize_port", 1, true)
local e = src:find("local function find_wechat_plugin_dir", 1, true)
if not s or not e then
	print("❌ 抽取辅助函数失败 (sanitize_port=" .. tostring(s) .. " find_wechat=" .. tostring(e) .. ")")
	os.exit(1)
end
-- 把 local function 改成 global function,才能从 chunk 外面拿到
local body = src:sub(s, e - 1)
	:gsub("local function sanitize_port", "function sanitize_port")
	:gsub("local function list_mounts_under", "function list_mounts_under")

local fchunk, ferr = loadstring(body)
if not fchunk then
	print("❌ 辅助函数编译失败: " .. tostring(ferr))
	os.exit(1)
end
-- Lua 5.1 的 loadstring 不接受 env 参数,函数会落到全局环境
fchunk()
local sanitize_port = _G.sanitize_port
local list_mounts_under = _G.list_mounts_under
if not sanitize_port or not list_mounts_under then
	print("❌ 辅助函数未导出")
	os.exit(1)
end
print("✅ 已从源文件抽取 sanitize_port / list_mounts_under\n")

-- ── 3) sanitize_port:端口注入防护 ──
print("=== sanitize_port ===")
local cases = {
	{ "18789",            "18789" },
	{ "  18790  ",        "18790" },
	{ "018789",           "18789" },
	{ "0",                "9999"  },
	{ "65536",            "9999"  },
	{ "99999",            "9999"  },
	{ "18789; rm -rf /",  "9999"  },
	{ "18789 && reboot",  "9999"  },
	{ "$(reboot)",        "9999"  },
	{ "`id`",             "9999"  },
	{ "'; reboot; '",     "9999"  },
	{ "",                 "9999"  },
	{ nil,                "9999"  },
}
local failed = 0
for _, c in ipairs(cases) do
	local got = sanitize_port(c[1], "9999")
	local ok = (got == c[2])
	if not ok then failed = failed + 1 end
	print(string.format("%s input=%-20s -> %-8s (期望 %s)", ok and "✅" or "❌",
		tostring(c[1]), tostring(got), c[2]))
end

-- ── 4) list_mounts_under:挂载点检测 ──
print("\n=== list_mounts_under (/proc/mounts 实际内容) ===")
local probes = {
	"/root/.openclaw",              -- 当前 install_path:应为空
	"/root",                        -- 应为空
	"/opt",                         -- /opt/docker 是子挂载点 → 应命中
	"/opt/docker",                  -- 自身是挂载点 → 应命中
	"/overlay/upper/root/.openclaw",-- upper 层残留:应为空
	"/mnt/sda1",                    -- 自身是挂载点 → 应命中
	"/tmp",                         -- 自身是挂载点 → 应命中
}
for _, p in ipairs(probes) do
	local l = list_mounts_under(p)
	print(string.format("%-32s -> %d 个  %s", p, #l, table.concat(l, ", ")))
end

-- ── 5) 模拟 action_uninstall 的挂载点判定 ──
print("\n=== 模拟卸载判定 ===")
local function uninstall_would_abort(install_path)
	local nested = {}
	for _, m in ipairs(list_mounts_under(install_path)) do
		if m ~= install_path then nested[#nested+1] = m end
	end
	for _, m in ipairs(list_mounts_under("/overlay/upper" .. install_path)) do
		nested[#nested+1] = m
	end
	return nested
end
for _, p in ipairs({ "/root/.openclaw", "/opt/openclaw", "/mnt/sda1/openclaw" }) do
	local n = uninstall_would_abort(p)
	print(string.format("%-24s 嵌套挂载点 %d 个 %s", p, #n, #n > 0 and "→ ⛔ 中止卸载" or "→ ✅ 允许卸载"))
end

print("\n" .. (failed == 0 and "✅ 全部用例通过" or ("❌ " .. failed .. " 个用例失败")))
os.exit(failed == 0 and 0 or 1)
