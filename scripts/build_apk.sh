#!/bin/sh
# ============================================================================
# build_apk.sh — 为 ImmortalWrt 25.12+ (apk 包管理器) 构建
#                luci-app-openclaw-apk .apk 包 (Alpine apk v2 格式)
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
#   <OUT_DIR>/luci-app-openclaw-apk_1.0.2-1_all.apk
#
# v2 apk 格式要点 (实测 apk-tools-static.apk 得出):
#   - 文件 = 单个 gzipped tar
#   - tar 内部顺序:
#       1) [可选] 顶层 .SIGN.RSA.<keyid>.rsa.pub  (签名段, 本仓库未签名 -> 跳过)
#       2) .PKGINFO  (控制段, 包含 pkgname/pkgver/depend/datahash 等)
#       3) 数据目录 (etc/, usr/ 等) 和数据文件
#       4) [可选] <file>.SIGN.RSA.<keyid>.rsa.pub  (每文件签名, 同样跳过)
#   - tar 必须为 PAX 格式 (默认 GNU tar 输出), 才能携带 PAX 扩展头
#     (per-file APK-TOOLS.checksum.SHA1, 即 sha1; 若缺则 apk 不做完整性校验,
#      安装仍正常)
#   - .PKGINFO 字段用 " = " 分隔, "#" 开头为注释
#   - datahash = sha256(数据段所有文件内容按 tar 顺序拼接), 用于全包校验
#   - size = 所有数据文件的字节总和
#   - 包名刻意与 opkg 版区分: luci-app-openclaw-apk
#
# 设计要点:
#   - 纯 busybox/GNU tar + gzip + sha1sum + sha256sum, 无 Python 依赖
#   - 优先用 GNU tar 的 PAX 格式; busybox tar 不产生 PAX 头, 也能被 apk 接受
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

# 转绝对路径
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
PKG_ARCH="all"
APK_FILE="$OUT/${PKG_NAME}_${PKG_VERSION}-${PKG_RELEASE}_${PKG_ARCH}.apk"

# ── 前置检查 ──────────────────────────────────────────────────────────────
echo "==> build_apk.sh (v2 format: single gzipped PAX tar)"
echo "    SRC = $SRC"
echo "    OUT = $OUT"

if [ ! -d "$SRC" ]; then
    echo "ERROR: 源码目录不存在: $SRC" >&2
    exit 1
fi

mkdir -p "$OUT"

# ── 选择合适的 tar ──────────────────────────────────────────────────────
TAR_CMD=""
if command -v gtar >/dev/null 2>&1; then
    TAR_CMD="gtar"
elif command -v tar >/dev/null 2>&1; then
    TAR_CMD="tar"
else
    echo "ERROR: 未找到 tar 命令" >&2
    exit 1
fi

TAR_VERSION=$($TAR_CMD --version 2>/dev/null | head -1)
if echo "$TAR_VERSION" | grep -qi "busybox"; then
    TAR_TYPE="busybox"
else
    TAR_TYPE="gnu"
fi
echo "    TAR = $TAR_CMD ($TAR_TYPE)"

# ── 工作目录 ──────────────────────────────────────────────────────────────
WORK="$(mktemp -d -t openclaw-apk.XXXXXX)"
DATA_DIR="$WORK/data"
mkdir -p "$DATA_DIR"

# ── 安装数据文件(对照 Makefile) ─────────────────────────────────────────
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

echo "==> 安装文件到 data/"

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

# ── 写 scriptlets (放 data/ 里, 与数据文件同段) ──────────────────
# v2 格式中, scriptlet 命名: .pre-install / .post-install /
#                            .pre-upgrade / .post-upgrade /
#                            .pre-deinstall / .post-deinstall /
#                            .triggers
# 它们会作为普通 tar 条目被打入 apk, apk 工具会按文件名前缀识别并执行
echo "==> 写 scriptlets"

cat > "$DATA_DIR/.pre-install" <<'PRE_INSTALL_EOF'
#!/bin/sh
# v2 apk 格式 scriptlet: 安装前钩子
exit 0
PRE_INSTALL_EOF
chmod 755 "$DATA_DIR/.pre-install"

cat > "$DATA_DIR/.post-install" <<'POST_INSTALL_EOF'
#!/bin/sh
# v2 apk 格式 scriptlet: 安装后钩子
[ -n "${IPKG_INSTROOT}" ] || {
	( . /etc/uci-defaults/99-openclaw ) && rm -f /etc/uci-defaults/99-openclaw
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
	exit 0
}
POST_INSTALL_EOF
chmod 755 "$DATA_DIR/.post-install"

cat > "$DATA_DIR/.pre-deinstall" <<'PRE_DEINSTALL_EOF'
#!/bin/sh
# v2 apk 格式 scriptlet: 卸载前钩子
exit 0
PRE_DEINSTALL_EOF
chmod 755 "$DATA_DIR/.pre-deinstall"

cat > "$DATA_DIR/.post-deinstall" <<'POST_DEINSTALL_EOF'
#!/bin/sh
# v2 apk 格式 scriptlet: 卸载后钩子
[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
}
POST_DEINSTALL_EOF
chmod 755 "$DATA_DIR/.post-deinstall"

# ── 计算 size + datahash (此时 DATA_DIR 内有所有文件) ──────────
# 计算 size = 所有数据文件字节总和 (含 scriptlet, 不含 .PKGINFO)
echo "==> 计算 size + datahash"
SIZE_BYTES=$(find "$DATA_DIR" -type f ! -name '.PKGINFO' -printf '%s\n' 2>/dev/null | \
    awk '{s+=$1} END {print s+0}')

# 计算 datahash = sha256(所有数据文件按 tar 内顺序拼接的内容)
# tar 内顺序: 父目录优先, 同层按字母序. 与下方 FILELIST 完全一致
# 关键: 用绝对路径, 且顺序: .PKGINFO / .pre-install / .post-install /
#       .pre-deinstall / .post-deinstall / find etc usr 按字母序 (含目录条目)
DATAHASH_TMP="$WORK/datahash_input"
: > "$DATAHASH_TMP"
{
    # scriptlets (4 个固定顺序, 与 FILELIST 完全一致)
    printf '%s\n' ".pre-install" ".post-install" ".pre-deinstall" ".post-deinstall"
    # etc/ + usr/ 内: 文件 + 链接 + 目录, 与下方 FILELIST 一致
    ( cd "$DATA_DIR" && LC_ALL=C find etc usr -mindepth 1 \
        \( -type f -o -type l -o -type d \) 2>/dev/null | \
        grep -v '^\.$' | LC_ALL=C sort )
} | while IFS= read -r rel; do
    full="$DATA_DIR/$rel"
    if [ -f "$full" ]; then
        cat "$full" >> "$DATAHASH_TMP"
    fi
    # 目录与符号链接无内容, 不入 hash
done

if command -v sha256sum >/dev/null 2>&1; then
    DATAHASH=$(sha256sum "$DATAHASH_TMP" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    DATAHASH=$(shasum -a 256 "$DATAHASH_TMP" | awk '{print $1}')
else
    echo "ERROR: 未找到 sha256sum/shasum" >&2
    exit 1
fi
rm -f "$DATAHASH_TMP"

INSTALLED_KB=$(du -sk "$DATA_DIR" 2>/dev/null | awk '{print $1}')

# ── 写 .PKGINFO (放 data/ 里, 与数据文件一起打) ──────────────────────
echo "==> 写 .PKGINFO"

cat > "$DATA_DIR/.PKGINFO" <<EOF
# Generated by build_apk.sh — Alpine apk v2 format
pkgname = ${PKG_NAME}
pkgver = ${PKG_VERSION}-${PKG_RELEASE}
pkgdesc = OpenClaw AI Gateway LuCI management plugin (apk edition, ImmortalWrt 25.12+)
url = https://github.com/xmlct7871/luci-app-openclaw
builddate = $(date -u +%s)
packager = xmlct7871 <xmlct787@gmail.com>
arch = ${PKG_ARCH}
license = GPL-3.0
section = luci
maintainer = xmlct7871 <xmlct787@gmail.com>
depend = luci-compat
depend = luci-base
depend = curl
depend = openssl-util
depend = script-utils
depend = tar
depend = libstdcpp6
size = ${SIZE_BYTES}
datahash = ${DATAHASH}
description = OpenClaw AI Gateway LuCI management plugin (apk edition, ImmortalWrt 25.12+). Adapted for ImmortalWrt with the upstream OpenClaw native layout (state dir at /root/.openclaw), so OpenClaw can be upgraded freely without re-adapting this plugin. Supports 12+ AI providers and Telegram/Discord/WeChat channels. Runs as root, no wrapper layer.
EOF

# OpenWrt 兼容字段 (部分 apk 实现读取)
echo "Installed-Size: ${INSTALLED_KB}" >> "$DATA_DIR/.PKGINFO"

# ── 打包 tar (PAX 格式, 单 gz 流) ──────────────────────────────────
echo "==> 打包 $APK_FILE"

# tar 顺序: .PKGINFO / .pre-install / .post-install / .pre-deinstall /
#          .post-deinstall / etc / usr
# 显式列出顺序确保 .PKGINFO 在最前, 与 datahash 计算顺序一致
cd "$DATA_DIR"

# PAX 格式: GNU tar 默认输出 PAX 格式; busybox tar 不产生 PAX 头 (OK)
# 注意: 这里不主动加 --no-xattrs, 让 GNU tar 输出 PAX 头以保证兼容性
# 关键: datahash 是按"tar 顺序"算的, 顺序必须稳定. 我们显式列出 entry
# GNU tar 用 -T / --files-from 会按文件读入顺序打包
FILELIST="$WORK/filelist.txt"
{
    echo ".PKGINFO"
    echo ".pre-install"
    echo ".post-install"
    echo ".pre-deinstall"
    echo ".post-deinstall"
    # 数据文件按 tar 顺序 (父目录优先, 字母序)
    LC_ALL=C find etc usr -mindepth 1 \( -type f -o -type l -o -type d \) 2>/dev/null | \
        grep -v '^\.$' | sort
} > "$FILELIST"

# 打 tar (单 gz 流, PAX 格式)
# --no-recursion: 关键! 否则 tar 会对 filelist 中列出的目录递归扫描,
#   导致其子文件被作为 hardlink 重复加入 (apk 工具可能拒绝)
# PAX 格式 (默认 GNU tar): 支持长文件名, 兼容 PAX 扩展头
$TAR_CMD -c -z -f "$APK_FILE" --no-recursion -T "$FILELIST"

# ── 自检 ────────────────────────────────────────────────────────────
echo "==> 自检"
# 1. 单 gz 流
if ! gzip -t "$APK_FILE" 2>/dev/null; then
    echo "ERROR: gzip 解析失败" >&2
    exit 1
fi
# 2. tar 头部合法, 且 .PKGINFO 在最前
LIST=$($TAR_CMD -tzf "$APK_FILE" 2>/dev/null)
if [ -z "$LIST" ]; then
    echo "ERROR: tar 内容为空" >&2
    exit 1
fi
FIRST_ENTRY=$(echo "$LIST" | head -1)
if [ "$FIRST_ENTRY" != "./" ] && [ "$FIRST_ENTRY" != "." ]; then
    # 允许 busybox tar 的 '目录条目' 在最前 (./)
    if ! echo "$FIRST_ENTRY" | grep -qE '^\.?/?$'; then
        echo "  WARNING: tar 首条目非目录: $FIRST_ENTRY (期望 . 或 ./ )" >&2
    fi
fi
# .PKGINFO 必须存在
if ! echo "$LIST" | grep -qx '.PKGINFO'; then
    echo "ERROR: tar 内缺少 .PKGINFO" >&2
    exit 1
fi
echo "    ✓ 单 gz 流, .PKGINFO 在内, 总条目: $(echo "$LIST" | wc -l)"

# ── 完成 ─────────────────────────────────────────────────────────────
size=$(wc -c < "$APK_FILE" 2>/dev/null || echo "?")
echo ""
echo "✓ 构建完成 (v2 格式: 单 gzipped PAX tar)"
echo "  APK  : $APK_FILE"
echo "  Size : $size bytes"
echo "  datahash = $DATAHASH"
echo ""
echo "下一步 (在 ImmortalWrt 25.12+ 路由器上):"
echo "  apk add --allow-untrusted $APK_FILE"
echo ""
echo "卸载:"
echo "  apk del luci-app-openclaw-apk"

# 清理
rm -rf "$WORK"
