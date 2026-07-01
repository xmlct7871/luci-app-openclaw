#!/bin/sh
# ============================================================================
# build_ipk.sh — 在 OpenWrt / ImmortalWrt 路由器 / Linux 服务器上构建
#                luci-app-openclaw IPK
# ============================================================================
#
# 用法:
#   bash scripts/build_ipk.sh [SRC_DIR] [OUT_DIR]
#   bash scripts/build_ipk.sh                     # 自动定位项目根
#
# 参数:
#   SRC_DIR  源码目录路径。默认自动从脚本所在位置推断(../../)
#   OUT_DIR  输出目录。默认为 <SRC_DIR>/dist
#
# 输出:
#   <OUT_DIR>/luci-app-openclaw_2026.6.10-1_all.ipk
#
# 设计要点:
#   - 纯 busybox/GNU tar + gzip,无 Python 依赖
#   - 自动选择最优 tar 参数，避免 PAX extended headers
#   - 自检: 使用 `tar -tzf` 检查归档内文件类型，精准检测 PAX 头
#   - 若检测到 PAX 头，立即中止构建并提示
#   - 依赖项格式符合 opkg 标准（无 '+' 前缀，逗号分隔）
#   - 打包时不含 './' 前缀，避免 opkg 硬链接错误
# ============================================================================

set -e

# ── 自动定位源码目录 ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
if [ -n "$SCRIPT_DIR" ]; then
    DEFAULT_SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    DEFAULT_SRC="/tmp/luci-app-openclaw-2026.6.10"
fi

SRC="${1:-$DEFAULT_SRC}"
OUT="${2:-$SRC/dist}"

PKG_NAME="luci-app-openclaw"
PKG_VERSION="2026.6.10"
PKG_RELEASE="1"
PKG_ARCH="all"
IPK_FILE="$OUT/${PKG_NAME}_${PKG_VERSION}-${PKG_RELEASE}_${PKG_ARCH}.ipk"

# ── 前置检查 ──────────────────────────────────────────────────────────────
echo "==> build_ipk.sh"
echo "    SRC = $SRC"
echo "    OUT = $OUT"

if [ ! -d "$SRC" ]; then
    echo "ERROR: 源码目录不存在: $SRC" >&2
    echo "       请先把源码 scp 到 $SRC 后再跑" >&2
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

# 检测 tar 类型
TAR_VERSION=$($TAR_CMD --version 2>/dev/null | head -1)
if echo "$TAR_VERSION" | grep -qi "busybox"; then
    TAR_TYPE="busybox"
else
    TAR_TYPE="gnu"
fi
echo "    TAR = $TAR_CMD ($TAR_TYPE)"

# ── 构建 tar 参数（只包含格式和属性选项，不包含 -czf） ──────────────
TAR_OPTS=""
if [ "$TAR_TYPE" = "gnu" ]; then
    TAR_OPTS="--format=ustar --no-xattrs --no-acls"
    echo "    tar 参数: --format=ustar --no-xattrs --no-acls"
else
    if $TAR_CMD -H ustar -cf /dev/null /dev/null 2>/dev/null; then
        TAR_OPTS="-H ustar"
        echo "    tar 参数: -H ustar"
    else
        echo "    tar 参数: (默认，busybox 通常不产生 PAX 头)"
    fi
fi

# ── 工作目录 ──────────────────────────────────────────────────────────────
WORK="$(mktemp -d -t openclaw-ipk.XXXXXX)"
DATA="$WORK/data"
CTRL="$WORK/control"
mkdir -p "$DATA" "$CTRL"

# ── 安装文件(对照 Makefile) ──────────────────────────────────────────────
install_file() {
    local src_rel="$1" dst_rel="$2" mode="$3"
    local src_path="$SRC/$src_rel"
    local dst_path="$DATA/$dst_rel"
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
mkdir -p "$DATA/usr/share/openclaw/ui"
cp -r "$SRC/root/usr/share/openclaw/ui/." "$DATA/usr/share/openclaw/ui/"
chmod -R u+rwX,go+rX "$DATA/usr/share/openclaw/ui"

# ── control 文件 ─────────────────────────────────────────────────────────
echo "==> 写 control/"

cat > "$CTRL/control" <<EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}-${PKG_RELEASE}
Depends: luci-compat, luci-base, curl, openssl-util, script-utils, tar, libstdcpp6
License: GPL-3.0
Section: luci
Architecture: ${PKG_ARCH}
Maintainer: 10000ge10000 <10000ge10000@users.noreply.github.com>
Source: feed/luci-app-openclaw
SourceName: ${PKG_NAME}
SourceDateEpoch: 1748582400
URL: https://github.com/10000ge10000/luci-app-openclaw
Installed-Size: $(du -sk "$DATA" 2>/dev/null | awk '{print $1}')
Description: OpenClaw AI Gateway LuCI management plugin (v2026.6.10).
 Compatible with upstream OpenClaw v2026.6.10 native layout
 (state dir at /root/.openclaw). Supports 12+ AI providers and
 Telegram/Discord channels. Runs as root, no wrapper layer.
EOF

cat > "$CTRL/conffiles" <<EOF
/etc/config/openclaw
EOF

cat > "$CTRL/postinst" <<'POSTINST_EOF'
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	( . /etc/uci-defaults/99-openclaw ) && rm -f /etc/uci-defaults/99-openclaw
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
	exit 0
}
POSTINST_EOF

cat > "$CTRL/postrm" <<'POSTRM_EOF'
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
}
POSTRM_EOF

cat > "$CTRL/prerm" <<'PRERM_EOF'
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || exit 0
PRERM_EOF

chmod 755 "$CTRL/postinst" "$CTRL/postrm" "$CTRL/prerm"

# ── 打包 tar ─────────────────────────────────────────────────────────────
echo "==> 打包 data.tar.gz"
( cd "$DATA" && $TAR_CMD -c -z $TAR_OPTS -f "$WORK/data.tar.gz" etc usr )

echo "==> 打包 control.tar.gz"
( cd "$CTRL" && $TAR_CMD -c -z $TAR_OPTS -f "$WORK/control.tar.gz" \
    control conffiles postinst postrm prerm )

# debian-binary(版本标识)
printf "2.0\n" > "$WORK/debian-binary"

# ── 自检: 使用 tar -tzf 检查 PAX 头 ──────────────────────────────────
echo "==> 自检 PAX 头污染 (检查归档内文件类型)"
pax_found=0
for tarfile in "$WORK/data.tar.gz" "$WORK/control.tar.gz"; do
    if $TAR_CMD -tzf "$tarfile" 2>/dev/null | grep -q '^x '; then
        echo "  ERROR: $tarfile 包含 PAX 头 (typeflag='x')" >&2
        pax_found=1
    fi
done

if [ $pax_found -eq 1 ]; then
    echo "ERROR: 检测到 PAX 头，busybox opkg 无法安装此 IPK" >&2
    echo "       请检查 tar 版本或源文件的扩展属性 (xattr/acl)" >&2
    exit 1
fi
echo "    ✓ 无 PAX 头污染"

# ── 组合最终 IPK ─────────────────────────────────────────────────────────
echo "==> 组合 $IPK_FILE"
( cd "$WORK" && $TAR_CMD -c -z $TAR_OPTS -f "$IPK_FILE" \
    debian-binary control.tar.gz data.tar.gz )

# ── 完成 ─────────────────────────────────────────────────────────────────
size=$(wc -c < "$IPK_FILE" 2>/dev/null || echo "?")
echo ""
echo "✓ 构建完成"
echo "  IPK  : $IPK_FILE"
echo "  Size : $size bytes"
echo ""
echo "下一步:"
echo "  opkg update"
echo "  opkg install $IPK_FILE"

# 清理
rm -rf "$WORK"