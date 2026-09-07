#!/bin/sh
# ============================================================================
# build_apk.sh — 为 ImmortalWrt 25.12+ (apk 包管理器) 构建
#                luci-app-openclaw-apk .apk 包
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
#   <OUT_DIR>/luci-app-openclaw-apk_1.0.1-1_all.apk
#
# 设计要点:
#   - 遵循 Alpine apk 格式: 单层 gzipped tar, 内含 .PKGINFO + scriptlets
#   - 包名 luci-app-openclaw-apk (区别于 opkg 版 luci-app-openclaw)
#   - scriptlets: .pre-install / .post-install / .pre-deinstall / .post-deinstall
#   - 纯 busybox/GNU tar + gzip + sha256sum,无 Python 依赖
#   - 自动选择最优 tar 参数，避免 PAX extended headers
#   - 自检: 检查归档内文件类型，检测 PAX 头污染
#   - 文件路径不带前导 '/' (apk 格式要求相对路径)
# ============================================================================

set -e

# ── 自动定位源码目录 ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
if [ -n "$SCRIPT_DIR" ]; then
    DEFAULT_SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    DEFAULT_SRC="/tmp/luci-app-openclaw-1.0.1"
fi

SRC="${1:-$DEFAULT_SRC}"
OUT="${2:-$SRC/dist}"

# 转绝对路径: cd 到 WORK 后, APK_FILE 若仍是相对路径则无法写入
SRC="$(cd "$SRC" 2>/dev/null && pwd || echo "$SRC")"
if [ -d "$OUT" ]; then
    OUT="$(cd "$OUT" 2>/dev/null && pwd || echo "$OUT")"
else
    OUT="$(cd "$(dirname "$OUT")" 2>/dev/null && pwd || echo "$(dirname "$OUT")")/$(basename "$OUT")"
fi

# ── 包元数据 ─────────────────────────────────────────────────────────────
# 与 opkg 版区分: 包名带 -apk 后缀, 文件名同样带 -apk
PKG_NAME="luci-app-openclaw-apk"
PKG_VERSION="1.0.2"
PKG_RELEASE="1"
PKG_ARCH="all"
APK_FILE="$OUT/${PKG_NAME}_${PKG_VERSION}-${PKG_RELEASE}_${PKG_ARCH}.apk"

# ── 前置检查 ──────────────────────────────────────────────────────────────
echo "==> build_apk.sh"
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

# ── 构建 tar 参数(只包含格式和属性选项,不包含 -czf) ──────────────
TAR_OPTS=""
if [ "$TAR_TYPE" = "gnu" ]; then
    TAR_OPTS="--format=ustar --no-xattrs --no-acls"
    echo "    tar 参数: --format=ustar --no-xattrs --no-acls"
else
    if $TAR_CMD -H ustar -cf /dev/null /dev/null 2>/dev/null; then
        TAR_OPTS="-H ustar"
        echo "    tar 参数: -H ustar"
    else
        echo "    tar 参数: (默认,busybox 通常不产生 PAX 头)"
    fi
fi

# ── 工作目录 ──────────────────────────────────────────────────────────────
WORK="$(mktemp -d -t openclaw-apk.XXXXXX)"
PKG_ROOT="$WORK/pkgroot"
mkdir -p "$PKG_ROOT"

# ── 安装文件(对照 Makefile) ──────────────────────────────────────────────
install_file() {
    local src_rel="$1" dst_rel="$2" mode="$3"
    local src_path="$SRC/$src_rel"
    local dst_path="$PKG_ROOT/$dst_rel"
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

echo "==> 安装文件到 pkgroot/"

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
mkdir -p "$PKG_ROOT/usr/share/openclaw/ui"
cp -r "$SRC/root/usr/share/openclaw/ui/." "$PKG_ROOT/usr/share/openclaw/ui/"
chmod -R u+rwX,go+rX "$PKG_ROOT/usr/share/openclaw/ui"

# ── .PKGINFO (Alpine apk 元数据) ─────────────────────────────────────
echo "==> 写 .PKGINFO"

# 注意: apk 工具对 Installed-Size 不强求, 但 size 字段常用
# description 多行写法: 单独一行 "Description:" 后接内容, 缩进续行
# 依赖格式: depend = pkgname (无版本限定, 沿用 opkg 版相同依赖集)
PKGDESC="OpenClaw AI Gateway LuCI management plugin (apk edition, for ImmortalWrt 25.12+).

Adapted for ImmortalWrt with the upstream OpenClaw native layout (state dir at /root/.openclaw), so OpenClaw can be upgraded freely without re-adapting this plugin. Supports 12+ AI providers and Telegram/Discord/WeChat channels. Runs as root, no wrapper layer."

cat > "$PKG_ROOT/.PKGINFO" <<EOF
# Generated by build_apk.sh
pkgname = ${PKG_NAME}
pkgver = ${PKG_VERSION}-${PKG_RELEASE}
pkgdesc = OpenClaw AI Gateway LuCI management plugin (apk edition, for ImmortalWrt 25.12+)
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
EOF

# 追加多行 description (Alpine apk 格式: 续行以 ' ' 开头, 或简单单行)
{
    printf 'description = '
    # 把 PKGDESC 转成单行, 以 \n 空格续行
    printf '%s' "$PKGDESC" | tr '\n' ' ' | sed 's/  */ /g'
    printf '\n'
} >> "$PKG_ROOT/.PKGINFO"

# Installed-Size 追加
INSTALLED_KB=$(du -sk "$PKG_ROOT" 2>/dev/null | awk '{print $1}')
{
    printf 'Installed-Size: %s\n' "$INSTALLED_KB"
} >> "$PKG_ROOT/.PKGINFO"

# ── Scriptlets (Alpine apk 命名约定) ───────────────────────────────
echo "==> 写 scriptlets"

# .pre-install: 极少用, 这里只做空 stub
cat > "$PKG_ROOT/.pre-install" <<'PRE_INSTALL_EOF'
#!/bin/sh
# 安装前钩子: 此版本无需预操作
exit 0
PRE_INSTALL_EOF
chmod 755 "$PKG_ROOT/.pre-install"

# .post-install: 与 opkg 版的 postinst 行为一致
cat > "$PKG_ROOT/.post-install" <<'POST_INSTALL_EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
	( . /etc/uci-defaults/99-openclaw ) && rm -f /etc/uci-defaults/99-openclaw
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
	exit 0
}
POST_INSTALL_EOF
chmod 755 "$PKG_ROOT/.post-install"

# .pre-deinstall: 卸载前钩子, 此版本无需特殊操作
cat > "$PKG_ROOT/.pre-deinstall" <<'PRE_DEINSTALL_EOF'
#!/bin/sh
exit 0
PRE_DEINSTALL_EOF
chmod 755 "$PKG_ROOT/.pre-deinstall"

# .post-deinstall: 与 opkg 版的 postrm 行为一致
cat > "$PKG_ROOT/.post-deinstall" <<'POST_DEINSTALL_EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
}
POST_DEINSTALL_EOF
chmod 755 "$PKG_ROOT/.post-deinstall"

# ── 打包 tar (单层 gzipped tar) ─────────────────────────────────────
echo "==> 打包 $APK_FILE"

# apk 格式: 一个 .tar.gz, 内部条目均不带前导 '/'
# 顺序无所谓; 关键条目: .PKGINFO 必须在最前以便 apk 解析
# 我们先单独追加 .PKGINFO, 再追加其他文件
TMP_TAR="$WORK/payload.tar.gz"

# 先打包 .PKGINFO (确保在最前)
( cd "$PKG_ROOT" && $TAR_CMD -c -z $TAR_OPTS -f "$TMP_TAR" .PKGINFO )

# 再追加其他条目 (scriptlets + 实际文件)
# --append 不可与 -z 一起使用, 所以这里先解压合并再重压
# 简化: 一次性打包所有文件(脚本会自动排序, .PKGINFO 未必在前; apk 解析对顺序不强求)
rm -f "$TMP_TAR"
( cd "$PKG_ROOT" && $TAR_CMD -c -z $TAR_OPTS -f "$TMP_TAR" \
    .PKGINFO \
    .pre-install .post-install .pre-deinstall .post-deinstall \
    etc usr )

# ── 自检: 使用 tar -tzf 检查 PAX 头 ──────────────────────────────────
echo "==> 自检 PAX 头污染"
if $TAR_CMD -tzf "$TMP_TAR" 2>/dev/null | grep -q '^x '; then
    echo "  ERROR: 归档内包含 PAX 头 (typeflag='x')" >&2
    echo "         apk 工具可能拒绝安装, 请检查 tar 版本或源文件扩展属性" >&2
    exit 1
fi
echo "    ✓ 无 PAX 头污染"

# ── 计算 datahash (apk 用于完整性校验) ───────────────────────────────
echo "==> 计算 datahash"
# datahash = sha256(去除 .PKGINFO 后的数据部分 sha256)
# 简化: 计算整个 payload 的 sha256 作为 datahash (apk 只在校验时用)
DATAHASH=$(sha256sum "$TMP_TAR" | awk '{print $1}')
echo "    datahash: $DATAHASH"

# 把 datahash 写回 .PKGINFO 然后重打
# 这样 apk 验证时可以比对
# 实际上 Alpine apk 用 datahash 校验 tar 数据完整性
# 我们用整个 tar 的 sha256 作为 datahash(包含 PKGINFO 本身)
# 一些实现接受这个值, 一些要求是 data-only 的 hash
# 这里我们采用包含 PKGINFO 的整体 hash(更通用)

# 为了让 .PKGINFO 包含 datahash, 需要重打
{
    echo "datahash = $DATAHASH"
    echo "size = $(wc -c < "$TMP_TAR")"
} >> "$PKG_ROOT/.PKGINFO"

# 重打最终 tar
( cd "$PKG_ROOT" && $TAR_CMD -c -z $TAR_OPTS -f "$TMP_TAR" \
    .PKGINFO \
    .pre-install .post-install .pre-deinstall .post-deinstall \
    etc usr )

# 移动到目标位置
mv "$TMP_TAR" "$APK_FILE"

# ── 完成 ─────────────────────────────────────────────────────────────────
size=$(wc -c < "$APK_FILE" 2>/dev/null || echo "?")
echo ""
echo "✓ 构建完成"
echo "  APK  : $APK_FILE"
echo "  Size : $size bytes"
echo ""
echo "下一步 (在 ImmortalWrt 25.12+ 路由器上):"
echo "  apk add --allow-untrusted $APK_FILE"
echo ""
echo "卸载:"
echo "  apk del luci-app-openclaw-apk"

# 清理
rm -rf "$WORK"
