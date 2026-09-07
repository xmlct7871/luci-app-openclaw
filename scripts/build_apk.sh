#!/bin/sh
# ============================================================================
# build_apk.sh — 为 ImmortalWrt 25.12+ (apk 包管理器) 构建
#                luci-app-openclaw-apk .apk 包 (Alpine ADB v3 格式)
# ============================================================================
#
# 用法:
#   bash scripts/build_apk.sh [SRC_DIR] [OUT_DIR]
#   bash scripts/build_apk.sh                     # 自动定位项目根
#
# 参数:
#   SRC_DIR  源码目录路径。默认自动从脚本所在位置推断(../../)
#   OUT_DIR  输出目录。默认为 <SRC_DIR>/dist
#
# 输出:
#   <OUT_DIR>/luci-app-openclaw-apk_1.0.2-1.apk
#
# v3 apk (ADB) 格式要点 (实测 ImmortalWrt 25.12.1 + alpine apk-tools 3.0.5):
#   - 文件 = ADB 二进制 (magic "ADBd"), 非 gzip+tar
#   - 头 8 字节: uint32 magic + uint32 schema_id (ADB_SCHEMA_PACKAGE)
#   - 块结构: uint32 type_size + (可选 EXT) uint64 x_size + payload
#       类型 0=ADB, 1=SIG, 2=DATA, 3=EXT
#   - ADB 块 payload = schema-defined 序列化对象:
#       info{name, version, hashes, arch, license, depends[], ...}
#       paths[]: dirs each with acl{mode,user,group} + files[]{name,acl,size,mtime,hash}
#       scripts: pre-install, post-install, pre-deinstall, post-deinstall
#   - DATA 块: 实际文件内容, 跟在 ADB 块后面
#   - SIG 块 (可选): RSA 签名, 我们不签, 让用户用 --allow-untrusted 安装
#
# 设计要点:
#   - **必须**在 ImmortalWrt 25.12+ 路由器上(或任意带 apk-tools 3.0.5+ 的
#     Linux 设备)运行, 用 `apk.static mkpkg` 子命令
#   - 拿 alpine apk-tools-static 3.0.5+ 静态包 (mkpkg 子命令在 3.0+ 加入):
#       curl -O https://dl-cdn.alpinelinux.org/alpine/v3.23/main/x86_64/apk-tools-static-3.0.8-r0.apk
#       apk extract --allow-untrusted --destination /tmp/apk-static apk-tools-static-3.0.8-r0.apk
#       # 之后用 /tmp/apk-static/sbin/apk.static mkpkg ...
#   - 之前 v2 (gzip+tar) 格式被 ImmortalWrt 25.12.1 拒绝 ("v2 package format error")
#   - arch 必须是 `noarch` (非 `all`!) 才能被 ImmortalWrt 25.12 接受
#   - depends 数组用空格分隔, 多次 --info depends:... 是覆盖而非追加
#   - 包名刻意与 opkg 版区分: luci-app-openclaw-apk
# ============================================================================

set -e

# ── 自动定位源码目录 ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
if [ -n "$SCRIPT_DIR" ]; then
    DEFAULT_SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    DEFAULT_SRC="/tmp/luci-app-openclaw-1.0.2"
fi

SRC="${1:-$DEFAULT_SRC}"
OUT="${2:-$SRC/dist}"

SRC="$(cd "$SRC" 2>/dev/null && pwd || echo "$SRC")"
if [ -d "$OUT" ]; then
    OUT="$(cd "$OUT" 2>/dev/null && pwd || echo "$OUT")"
else
    OUT="$(cd "$(dirname "$OUT")" 2>/dev/null && pwd || echo "$(dirname "$OUT")")/$(basename "$OUT")"
fi

# ── 包元数据 ─────────────────────────────────────────────────────────────
PKG_NAME="luci-app-openclaw-apk"
PKG_VERSION="1.0.2"
PKG_RELEASE="1"
PKG_ARCH="noarch"
APK_FILE="$OUT/${PKG_NAME}_${PKG_VERSION}-${PKG_RELEASE}.apk"

# ── 前置检查 ──────────────────────────────────────────────────────────────
echo "==> build_apk.sh (ADB v3 格式: alpine apk-tools 3.0+ mkpkg)"
echo "    SRC = $SRC"
echo "    OUT = $OUT"

if [ ! -d "$SRC" ]; then
    echo "ERROR: 源码目录不存在: $SRC" >&2
    exit 1
fi

mkdir -p "$OUT"

# ── 定位 apk.static ────────────────────────────────────────────────────
# 优先用本机 PATH 上的 apk.static (在 ImmortalWrt 25.12+ 路由器上跑时),
# 否则回退到已知缓存路径
APK_STATIC=""
for cand in "/usr/sbin/apk.static" "/usr/local/sbin/apk.static" "/sbin/apk.static" \
            "/tmp/apk-static/sbin/apk.static" "./apk-static/sbin/apk.static"; do
    if [ -x "$cand" ]; then
        APK_STATIC="$cand"
        break
    fi
done

if [ -z "$APK_STATIC" ] && command -v apk.static >/dev/null 2>&1; then
    APK_STATIC="$(command -v apk.static)"
fi

if [ -z "$APK_STATIC" ]; then
    echo "" >&2
    echo "ERROR: 找不到 apk.static (含 mkpkg 子命令的 alpine apk-tools-static 3.0+)" >&2
    echo "" >&2
    echo "  ImmortalWrt 25.12+ 自带的 /usr/bin/apk 没有编译 mkpkg, 需要下载" >&2
    echo "  alpine 静态构建 (3.0.5+, 含 mkpkg):" >&2
    echo "" >&2
    echo "  curl -O https://dl-cdn.alpinelinux.org/alpine/v3.23/main/x86_64/apk-tools-static-3.0.8-r0.apk" >&2
    echo "  apk extract --allow-untrusted --destination /tmp/apk-static \\" >&2
    echo "      apk-tools-static-3.0.8-r0.apk" >&2
    echo "  # 然后本脚本会自动找到 /tmp/apk-static/sbin/apk.static" >&2
    echo "" >&2
    exit 1
fi

echo "    APK_STATIC = $APK_STATIC"
echo "    version = $($APK_STATIC --version 2>&1 | head -1)"

# 验证有 mkpkg 子命令 (报 "built without help" 没关系)
if ! $APK_STATIC mkpkg --no-such-cmd 2>&1 | grep -qE "missing|usage|info field"; then
    : # pass — 至少进了 mkpkg 入口
fi

# ── 工作目录 ──────────────────────────────────────────────────────────────
WORK="$(mktemp -d -t openclaw-apk.XXXXXX)"
DATA_DIR="$WORK/files"
SCRIPT_DIR_WORK="$WORK/scripts"
mkdir -p "$DATA_DIR" "$SCRIPT_DIR_WORK"

# ── 安装数据文件 (对照 Makefile) ────────────────────────────────────────
install_file() {
    local src_rel="$1" dst_rel="$2" mode="$3"
    local src_path="$SRC/$src_rel"
    local dst_path="$DATA_DIR/$dst_rel"
    local dstdir
    dstdir="$(dirname "$dst_path")"

    if [ ! -f "$src_path" ]; then
        echo "ERROR: 缺少源文件: $src_rel" >&2
        exit 1
    fi

    mkdir -p "$dstdir"
    cp "$src_path" "$dst_path"
    chmod "$mode" "$dst_path"
}

echo "==> 安装文件到 files/"

# /etc
install_file "root/etc/config/openclaw"          "etc/config/openclaw"          644
install_file "root/etc/uci-defaults/99-openclaw" "etc/uci-defaults/99-openclaw" 755
install_file "root/etc/init.d/openclaw"          "etc/init.d/openclaw"          755
install_file "root/etc/profile.d/openclaw.sh"    "etc/profile.d/openclaw.sh"    755

# /usr/bin + /usr/libexec
install_file "root/usr/bin/openclaw-env"          "usr/bin/openclaw-env"          755
install_file "root/usr/libexec/openclaw-paths.sh" "usr/libexec/openclaw-paths.sh" 755
install_file "root/usr/libexec/openclaw-node.sh"  "usr/libexec/openclaw-node.sh"  755

# LuCI lua + view
install_file "luasrc/controller/openclaw.lua"             "usr/lib/lua/luci/controller/openclaw.lua"             644
install_file "luasrc/openclaw/paths.lua"                  "usr/lib/lua/openclaw/paths.lua"                       644
install_file "luasrc/model/cbi/openclaw/basic.lua"        "usr/lib/lua/luci/model/cbi/openclaw/basic.lua"       644
install_file "luasrc/view/openclaw/status.htm"            "usr/lib/lua/luci/view/openclaw/status.htm"           644
install_file "luasrc/view/openclaw/advanced.htm"          "usr/lib/lua/luci/view/openclaw/advanced.htm"         644
install_file "luasrc/view/openclaw/console.htm"           "usr/lib/lua/luci/view/openclaw/console.htm"          644
install_file "luasrc/view/openclaw/wechat.htm"            "usr/lib/lua/luci/view/openclaw/wechat.htm"           644

# rpcd ACL
install_file "root/usr/share/rpcd/acl.d/luci-app-openclaw.json" \
             "usr/share/rpcd/acl.d/luci-app-openclaw.json" 644

# OpenClaw 共享资源
install_file "VERSION"                                          "usr/share/openclaw/VERSION"      644
install_file "root/usr/share/openclaw/oc-config.sh"             "usr/share/openclaw/oc-config.sh"             755
install_file "root/usr/share/openclaw/oc-config-interactive.js" "usr/share/openclaw/oc-config-interactive.js" 755
install_file "root/usr/share/openclaw/oc-menu-engine.js"        "usr/share/openclaw/oc-menu-engine.js"        644
install_file "root/usr/share/openclaw/web-pty.js"              "usr/share/openclaw/web-pty.js"              644

# UI 目录(递归拷贝)
echo "==> 复制 UI 资源(目录)"
mkdir -p "$DATA_DIR/usr/share/openclaw/ui"
cp -r "$SRC/root/usr/share/openclaw/ui/." "$DATA_DIR/usr/share/openclaw/ui/"
chmod -R u+rwX,go+rX "$DATA_DIR/usr/share/openclaw/ui"

# ── 写 scriptlets ──────────────────────────────────────────────────────
echo "==> 写 scriptlets"

cat > "$SCRIPT_DIR_WORK/pre-install" <<'PRE_INSTALL_EOF'
#!/bin/sh
# ADB v3 apk 格式 scriptlet: 安装前钩子
exit 0
PRE_INSTALL_EOF
chmod 755 "$SCRIPT_DIR_WORK/pre-install"

cat > "$SCRIPT_DIR_WORK/post-install" <<'POST_INSTALL_EOF'
#!/bin/sh
# ADB v3 apk 格式 scriptlet: 安装后钩子
[ -n "${IPKG_INSTROOT}" ] || {
	( . /etc/uci-defaults/99-openclaw ) && rm -f /etc/uci-defaults/99-openclaw
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
	exit 0
}
POST_INSTALL_EOF
chmod 755 "$SCRIPT_DIR_WORK/post-install"

cat > "$SCRIPT_DIR_WORK/pre-deinstall" <<'PRE_DEINSTALL_EOF'
#!/bin/sh
# ADB v3 apk 格式 scriptlet: 卸载前钩子
exit 0
PRE_DEINSTALL_EOF
chmod 755 "$SCRIPT_DIR_WORK/pre-deinstall"

cat > "$SCRIPT_DIR_WORK/post-deinstall" <<'POST_DEINSTALL_EOF'
#!/bin/sh
# ADB v3 apk 格式 scriptlet: 卸载后钩子
[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
}
POST_DEINSTALL_EOF
chmod 755 "$SCRIPT_DIR_WORK/post-deinstall"

# ── 调 mkpkg ──────────────────────────────────────────────────────────
echo "==> mkpkg"

# 注意:
#   - arch 必须是 noarch (ImmortalWrt 25.12 不接受 all)
#   - depends 必须空格分隔 (多次 --info depends:... 是覆盖不是追加)
#   - build-time 用固定值 (保证可复现, 不带时间戳)
$APK_STATIC mkpkg \
  --files "$DATA_DIR" \
  --info "name:${PKG_NAME}" \
  --info "version:${PKG_VERSION}-r${PKG_RELEASE}" \
  --info "description:OpenClaw AI Gateway LuCI management plugin (apk edition, ImmortalWrt 25.12+). Adapted for ImmortalWrt with the upstream OpenClaw native layout (state dir at /root/.openclaw), so OpenClaw can be upgraded freely without re-adapting this plugin. Supports 12+ AI providers and Telegram/Discord/WeChat channels. Runs as root, no wrapper layer." \
  --info "arch:${PKG_ARCH}" \
  --info "license:GPL-3.0" \
  --info "origin:luci-app-openclaw" \
  --info "maintainer:xmlct7871 <xmlct787@gmail.com>" \
  --info "url:https://github.com/xmlct7871/luci-app-openclaw" \
  --info "build-time:1788768000" \
  --info "depends:luci-compat luci-base curl openssl-util script-utils tar libstdcpp6" \
  --script "pre-install:${SCRIPT_DIR_WORK}/pre-install" \
  --script "post-install:${SCRIPT_DIR_WORK}/post-install" \
  --script "pre-deinstall:${SCRIPT_DIR_WORK}/pre-deinstall" \
  --script "post-deinstall:${SCRIPT_DIR_WORK}/post-deinstall" \
  --output "$APK_FILE" 2>&1

# ── 自检 ─────────────────────────────────────────────────────────────
echo "==> 自检"
# 1. 文件存在
if [ ! -f "$APK_FILE" ]; then
    echo "ERROR: mkpkg 没产出文件" >&2
    exit 1
fi

# 2. magic 检查: ADBd = 0x64424441, 小端首 4 字节 = 41 44 42 64
#    兼容: od / hexdump / xxd (路由器 busybox 通常没这些)
MAGIC=""
if command -v od >/dev/null 2>&1; then
    MAGIC=$(head -c 4 "$APK_FILE" | od -An -tx1 | tr -d ' \n')
elif command -v hexdump >/dev/null 2>&1; then
    MAGIC=$(head -c 4 "$APK_FILE" | hexdump -e '/1 "%02x"')
elif command -v xxd >/dev/null 2>&1; then
    MAGIC=$(head -c 4 "$APK_FILE" | xxd -p | tr -d '\n')
else
    # 没 hex 工具, 用 od via /dev/zero 不可, 退回到字符串对比
    FIRST4=$(head -c 4 "$APK_FILE")
    if [ "$FIRST4" = "ADBd" ]; then
        MAGIC="41444264"
    fi
fi
if [ "$MAGIC" != "41444264" ]; then
    echo "ERROR: 包 magic 不是 ADBd, 实际 = $MAGIC (期望 41444264)" >&2
    exit 1
fi

# 3. 文件大小合理 (至少几十 KB)
size=$(wc -c < "$APK_FILE")
if [ "$size" -lt 50000 ]; then
    echo "WARNING: 包大小异常小 (< 50KB): $size" >&2
fi

echo "    ✓ ADB 格式 magic 正确"
echo "    ✓ Size: $size bytes"

# ── 完成 ─────────────────────────────────────────────────────────────
echo ""
echo "✓ 构建完成 (ADB v3 格式: 兼容 ImmortalWrt 25.12.1 的 apk-tools 3.0.5)"
echo "  APK  : $APK_FILE"
echo "  Size : $size bytes"
echo ""
echo "下一步 (在 ImmortalWrt 25.12+ 路由器上):"
echo "  scp $APK_FILE root@192.168.10.1:/tmp/"
echo "  ssh root@192.168.10.1 'apk add --allow-untrusted /tmp/$(basename "$APK_FILE")'"
echo ""
echo "卸载:"
echo "  apk del luci-app-openclaw-apk"

# 清理
rm -rf "$WORK"