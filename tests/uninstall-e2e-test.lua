-- luci-app-openclaw v1.0.13 — 卸载路径端到端验证
--
-- 用 stub 加载**真实的** controller 源码,调用真实的 action_uninstall()。
-- 关键点:luci.sys.exec 被替换成"只记录不执行",所以测试期间
--        rm -rf / umount 一条都不会真的跑,不会动到任何真实数据。
--
-- 用法: lua5.1 /tmp/oc-uninstall-e2e.lua <controller路径> <install_path>
local CTRL       = arg[1] or "/tmp/openclaw.lua"
local INSTALL_PATH = arg[2] or "/root/openclaw"
local PORT_OVERRIDE = arg[3]

local RESP = {}
local EXECS = {}

-- ── stub 掉所有会真正动系统的 luci 依赖 ──
package.loaded["luci.http"] = {
	prepare_content = function() end,
	write_json = function(t) RESP = t end,
}
package.loaded["luci.sys"] = {
	exec = function(c)
		table.insert(EXECS, c)
		return ""
	end,
}
package.loaded["luci.model.uci"] = {
	cursor = function()
		return {
			get = function(self, cfg, sect, opt)
				if opt == "install_path" then return INSTALL_PATH end
				if opt == "port" then return PORT_OVERRIDE or "18789" end
				if opt == "pty_port" then return "18793" end
				return nil
			end
		}
	end,
}
package.loaded["nixio"] = { fs = { stat = function() return nil end } }

dofile(CTRL)
local m = _G.luci and _G.luci.controller and _G.luci.controller.openclaw
if not m or type(m.action_uninstall) ~= "function" then
	print("❌ controller 未正确加载")
	os.exit(1)
end

m.action_uninstall()

-- ── 输出结果 ──
print("install_path = " .. INSTALL_PATH)
print("响应 status  = " .. tostring(RESP.status))
print("响应 message = " .. tostring(RESP.message))
print("")
print("--- 实际下发执行的命令(共 " .. #EXECS .. " 条) ---")
for i, c in ipairs(EXECS) do
	print(string.format("  [%d] %s", i, c))
end

-- ── 断言 ──
local rm_hits = {}
for i, c in ipairs(EXECS) do
	if c:find("rm %-rf") or c:find("rm -rf") then rm_hits[#rm_hits+1] = i end
end

print("")
if RESP.status == "error" and RESP.message and RESP.message:find("挂载点") then
	if #rm_hits == 0 then
		print("✅ PASS: 检测到嵌套挂载点 → 卸载中止,且**没有下发任何 rm -rf**")
		os.exit(0)
	end
	print("❌ FAIL: 中止了但仍下发了 rm -rf (第 " .. table.concat(rm_hits, ",") .. " 条)")
	os.exit(1)
end

if RESP.status == "ok" then
	if #rm_hits > 0 then
		print("✅ PASS: 无挂载点 → 正常卸载路径,rm -rf 已下发")
		print("   (注: sys.exec 已被 stub,rm 只是被记录,没有真的执行)")
		os.exit(0)
	end
	print("❌ FAIL: 声称卸载成功但没有 rm -rf")
	os.exit(1)
end

print("❌ FAIL: 意外响应 " .. tostring(RESP.status))
os.exit(1)
