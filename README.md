# luci-app-openclaw v2026.6.10

[![Bilibili](https://img.shields.io/badge/B%E7%AB%99-59438380-00a1d6?logo=bilibili)](https://space.bilibili.com/59438380)
[![Blog](https://img.shields.io/badge/Blog-910501.xyz-orange)](https://blog.910501.xyz/)
[![Build & Release](https://github.com/xmlct7871/luci-app-openclaw/actions/workflows/build.yml/badge.svg)](https://github.com/xmlct7871/luci-app-openclaw/actions/workflows/build.yml)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

[OpenClaw v2026.6.10](https://github.com/openclaw/openclaw/releases/tag/v2026.6.10) AI 网关的 OpenWrt LuCI 管理插件。

在路由器上运行 OpenClaw,通过 LuCI 管理界面完成OpenClaw安装。

> **本仓库是全新架构重构版本(2026.6.10)**。
> 原版仓库地址: [10000ge10000/luci-app-openclaw](https://github.com/10000ge10000/luci-app-openclaw) (v2.0.6)。
> 下方表格是本版本与原版的核心差异。

**与原版的核心差异**:

| 维度 | 原版 (v2.0.6) | 本版 (v2026.6.10) |
|------|---------------|-------------------|
| 安装路径 | `/opt/openclaw/{node,global,data}/` 包装层 | `/root/.openclaw`(扁平化,直接 = upstream OpenClaw 在 root 下的默认布局) |
| 运行用户 | 自建 `openclaw` Unix 用户 | 以 root 跑(OpenWrt 惯例) |
| 目录布局 | 三层包装(node / global / data) | 跟 upstream OpenClaw 一一对应 |
| 与 OpenClaw 上游 | 多一层包装,布局与 upstream 不一致 | 安装路径 = upstream 的 `~/.openclaw`,等价调用 |

<div align="center">
  <img src="docs/images/2.png" alt="OpenClaw LuCI 管理界面" width="800" style="border-radius:8px;" />
</div>

**系统要求**

| 项目 | 要求 |
|------|------|
| 架构 | x86_64 或 aarch64 (ARM64) |
| C 库 | musl（自动检测；离线包仅支持 musl） |
| 依赖 | luci-compat, luci-base, curl, openssl-util, tar, script-utils |
| 存储 | **2GB 以上可用空间** |
| 内存 | 推荐 1GB 及以上 |

**当前适配版本**

| 组件 | 默认版本 | 说明 |
|------|----------|------|
| OpenClaw | `2026.6.10` | 与 luci-app-openclaw 版本号对齐 |
| Node.js | `24.15.0` | OpenClaw 2026.6.x 要求 `>=22.19.0`；安装后会按 `engines.node` 做强校验，低于要求会直接失败 |
| 微信插件 | `@tencent-weixin/openclaw-weixin@2.4.3` | CLI 使用 `@tencent-weixin/openclaw-weixin-cli@2.1.4` |

## 📦 安装

### 方式一：.run 自解压包（推荐）

无需 SDK，适用于已安装好的系统。

```bash
# 下载最新版本（自动获取版本号）
VER=$(curl -sI "https://github.com/xmlct7871/luci-app-openclaw/releases/latest" 2>/dev/null | grep -i "location:" | sed 's/.*tag\/v\{0,1\}//' | tr -d '\r\n')
wget "https://github.com/xmlct7871/luci-app-openclaw/releases/download/v${VER}/luci-app-openclaw_${VER}.run"
sh "luci-app-openclaw_${VER}.run"
```

### 方式二：.ipk 安装

```bash
# 下载最新版本（自动获取版本号）
VER=$(curl -sI "https://github.com/xmlct7871/luci-app-openclaw/releases/latest" 2>/dev/null | grep -i "location:" | sed 's/.*tag\/v\{0,1\}//' | tr -d '\r\n')
wget "https://github.com/xmlct7871/luci-app-openclaw/releases/download/v${VER}/luci-app-openclaw_${VER}-1_all.ipk"
opkg install "luci-app-openclaw_${VER}-1_all.ipk"
```

### 方式三：集成到固件编译

适用于自行编译固件或使用在线编译平台的用户。

```bash
cd /path/to/openwrt

# 添加 feeds
echo "src-git openclaw https://github.com/xmlct7871/luci-app-openclaw.git" >> feeds.conf.default

# 更新安装
./scripts/feeds update -a
./scripts/feeds install -a

# 选择插件
make menuconfig
# LuCI → Applications → luci-app-openclaw

# 编译
make package/luci-app-openclaw/compile V=s
```

使用 OpenWrt SDK 单独编译：

```bash
git clone https://github.com/xmlct7871/luci-app-openclaw.git package/luci-app-openclaw
make defconfig
make package/luci-app-openclaw/compile V=s
find bin/ -name "luci-app-openclaw*.ipk"
```


## 🔰 首次使用

1. 打开 LuCI → 服务 → OpenClaw，点击「安装运行环境」
2. 安装完成后服务会自动启动，点击「刷新页面」查看状态
3. 在「基本设置」点击「Web 控制台」添加 AI 模型和 API Key
4. SSH 登录系统，运行 `openclaw config` 在终端配置消息渠道（QQ / Telegram / Discord 等）

默认安装路径是 `/root/.openclaw`(与上游 OpenClaw 在 root 用户下的默认路径完全一致)。

## 自定义安装路径

UCI 字段是 `openclaw.main.install_path`,本版语义为 **state dir 自身** —— 所填路径就是 OpenClaw state dir 的根目录,脚本不会在其下再加一层 `openclaw/` 包装。例如:

```bash
uci set openclaw.main.install_path='/mnt/data/openclaw'
uci commit openclaw
openclaw-env setup
```

实际运行目录就是 `/mnt/data/openclaw`(直接)。插件不会做 `/xxx/openclaw` 包装。

外置盘场景推荐:把整个 OpenClaw 装到 `/mnt/sda1/openclaw` 这样的子目录,备份时直接 `tar` 整目录。

安装前会执行写入探针；如果 overlay 已满、只读或外置盘未正确挂载，安装会在下载前失败并给出明确日志。如果 `/opt` 或 `/root` 在 iStoreOS Docker bind mount 下不可写,`_oc_fix_overlay` 会自动 bind mount `/overlay/upper/<base>` 修复;最坏情况下会 fallback 到 `/tmp/openclaw-fallback-$$`。

## 微信插件依赖

本版微信插件以 **root** 身份运行(不创建独立的 `openclaw` Unix 用户)。安装前会检查:

- `python3` 是否已安装
- `${install_path}/extensions/`、`${install_path}/.npm/`、`${install_path}/.tmp/` 等目录可写(以 root 跑天然满足)
- 旧渠道名 `weixin` 会迁移为 `openclaw-weixin`

如缺少 Python3：

```bash
opkg update
opkg install python3
```

## 已知说明

- OpenClaw 的 diagnostic heartbeat 可能在日志中出现类似周期性探测记录。它不是一次真实用户对话请求；如需降低噪音，优先在 OpenClaw 配置或日志采集侧降低诊断日志级别，不建议直接修改模型调用逻辑。
- 当前仓库提供源码、OpenWrt feeds 集成方式、本地 `.run` / `.ipk` 构建脚本入口；本次维护不自动生成 Release 产物。

## 📂 目录结构

```
luci-app-openclaw/
├── Makefile                          # OpenWrt 包定义
├── luasrc/
│   ├── controller/openclaw.lua       # LuCI 路由和 API
│   ├── openclaw/paths.lua            # 路径规范化与安全校验
│   ├── model/cbi/openclaw/basic.lua  # 主页面
│   └── view/openclaw/
│       ├── status.htm                # 状态面板
│       ├── console.htm               # Web 控制台
│       └── wechat.htm                # 微信渠道向导
├── root/
│   ├── etc/
│   │   ├── config/openclaw           # UCI 配置
│   │   ├── init.d/openclaw           # 服务脚本
│   │   └── uci-defaults/99-openclaw  # 初始化脚本
│   └── usr/
│       ├── libexec/                  # 共享 shell helper
│       ├── bin/openclaw-env          # 环境管理工具
│       └── share/openclaw/           # 配置终端资源
├── scripts/
│   └── build_ipk.sh                  # 本地 IPK 构建
└── .github/workflows/
    └── build.yml                     # CI 中构建 IPK
```

## 📂 运行时目录结构

**v2026.6.10 默认 `install_path = /root/.openclaw`**,目录布局完全匹配上游 OpenClaw v2026.6.10:

```
/root/.openclaw/                          # install_path 自身(就是 state dir)
├── node/                                 # Node.js 运行时(本插件管理)
│   ├── bin/{node, npm, pnpm}
│   └── lib/node_modules/openclaw/        # OpenClaw 包 (npm install -g --prefix=$node_parent)
├── openclaw.json                         # upstream: ~/.openclaw/openclaw.json
├── workspace/                            # upstream: ~/.openclaw/workspace/
│   └── skills/<skill>/SKILL.md
├── extensions/                           # upstream: ~/.openclaw/extensions/
│   ├── openclaw-weixin/                  # 微信插件
│   └── npm/projects/                     # 微信 npm 子项目
├── secrets.json, .env                    # 由 openclaw onboard 自动创建
├── agents/main/agent/                    # 由 openclaw onboard 自动创建
├── hooks/transforms/                     # 由 openclaw onboard 自动创建
├── backups/                              # LuCI 备份功能
├── logs/                                 # upstream: ~/.openclaw/logs/
├── .npm/, .tmp/                          # 显式隔离 npm cache + 临时文件
└── .cache/jiti/                          # jiti TypeScript 编译缓存
```

**外置盘示例**:把整个 state dir 放到 `/mnt/sda1/openclaw`:
```bash
uci set openclaw.main.install_path='/mnt/sda1/openclaw'
uci commit openclaw
opkg install luci-app-openclaw_2026.6.10-1_all.ipk
```

**关键变化 (相比原版)**:
- 原版: `${install_path}/openclaw/{node,global,data}/...` 三层包装
- 本版: `${install_path}/{node,openclaw.json,workspace,extensions,...}` 扁平化,完全对齐 upstream OpenClaw
- 本版不再使用 `/opt/openclaw/{node,global,data}` 包装层
- 本版不再创建 `openclaw` Unix 用户,以 root 跑(OpenWrt 惯例)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 License

[GPL-3.0](LICENSE)
