# DDWRT (ImmortalWrt) 固件全自动编译库

利用 GitHub Actions，基于设备的完全隔离架构，实现在线编译、自动打包、每周自动检测上游源码并构建你专属的 ImmortalWrt 路由固件。

---

## 🚀 核心优势：为什么选择这个架构？

- **免维护、自动更新**：系统每周五会自动对比 ImmortalWrt 官方最新源码，一旦有修改便自动触发编译并发布到 Releases。旧产物只保留7天，永不爆仓。
- **设备强隔离**：告别修改 A 设备导致 B 设备编译失败。每个设备都有自己**独立的目录**。
- **高阶定制化**：无论是修改全设备的默认 IP，还是专门给某台设备（如 MT3000）修改特定的硬件驱动补丁，都有清晰的文件夹存放。

---

## 📁 核心目录结构详解 (必读)

本项目采用**层叠挂载**的方式。工作流会优先读取 `common`（通用）目录的设定，一旦你的设备专属目录有同名文件或者专属补丁，工作流会自动追加或覆盖。

```text
DDWRT/
├── .github/workflows/          # [无需修改] GitHub 自动化工作流存放处
│   ├── build.yml               # 核心编译流水线
│   ├── cache-cleanup.yml       # 每周自动清理 7 天前无用缓存
│   └── update-checker.yml      # 每周五自动检查官方源码并触发编译
│
├── tools/
│   └── make-config.sh          # [交互工具] 一键为指定设备生成 target.config
│   
└── devices/                    # [⭐ 所有配置的核心区域 ⭐]
    │
    ├── common/                 # 🟢 所有设备共用的核心底座
    │   ├── base.config         # [必需] 所有固件都要包含的基础包（如 LuCI, Passwall 等）
    │   ├── feeds.conf          # [必需] 第三方软件源列表
    │   ├── settings.sh         # [必需] 通用脚本：统一修改所有机器的默认 IP (192.168.30.1) 和时区
    │   ├── files/              # [可选] 放入此文件夹的文件会覆盖进所有路由器的对应目录 (如自定义的 /etc/banner)
    │   └── patches/            # [可选] 放在这里的 .patch 补丁，每个设备编译时都会打上
    │
    ├── x86_64/                 # 🔵 专属设备目录：只对 x86_64 生效
    │   ├── target.config       # [必需] 专属包配置：目标架构设定、专有驱动网卡包等
    │   ├── settings.sh         # [可选] 专属脚本：编译 x86_64 前额外执行的 shell 命令
    │   ├── files/              # [可选] 专属文件：只覆盖 x86_64 的文件 (会覆盖 common 的同名文件)
    │   └── patches/            # [可选] 专属补丁：只给 x86_64 源码打的特定代码补丁
    │
    ├── glinet-gl-mt3000/       # 🔵 专属设备目录：只对 MT3000 生效
    │   ├── target.config       
    │   ├── settings.sh         # (如需单独修改 MT3000 的 DTS 节点，可在此脚本中用 sed 替换)
    │   ├── files/              
    │   └── patches/            
    │   
    └── [其它设备目录...]
```

---

## 🛠️ 快速开始：我是小白该如何操作？

### 第一步：开启你自己的工厂
1. 注册/登录你的 GitHub 账号。
2. 点击本仓库右上角的 `Fork`，将其克隆一份到你自己的账号下。
3. 进入你 Fork 后的仓库，点击顶部的 `Actions` 选项卡。
4. 点击绿色按钮 `I understand my workflows, go ahead and enable them` 允许工作流运行。

### 第二步：如何手动出包？
目前预设了 `x86_64`、`glinet-gl-mt3000`、`netcore-n60-pro` 等多款硬件。
1. 在 `Actions` 页面左侧点击 `Build ImmortalWrt`。
2. 点击右侧的 `Run workflow` 按钮。
3. 在弹出的菜单中，选择你想编译的**设备名**（默认为 `x86_64`）。
4. 点击绿色的 `Run workflow`，喝杯咖啡，约 1-2 小时后即可在首页右侧的 `Releases` 中下载做好的固件包。

---

## ➕ 进阶 1：如何添加一台全新的路由器？

假设你想扩充一台支持的设备，名叫 `ASUS-AX6000`。由于你本地不能直接改工作流界面的选项，你需要在电脑的操作终端（Linux 或 Windows 的 WSL2）执行以下 4 步：

1. **一键生成专有配置**：
   在终端执行下方命令，它会自动下载源码，并弹出一个蓝色的选择菜单：
   ```bash
   ./tools/make-config.sh asus-ax6000
   ```
   *菜单操作：配置你的目标硬件架构 (Target System / Subtarget)，按需勾选特定插件，选完点 Save 后 Exit。脚本会自动抓取差异内容，保存到 `devices/asus-ax6000/target.config`。*

2. **自动补全目录结构**：
   执行完脚本后，你会发现 `devices/asus-ax6000/` 里除了 `.config`，还自动生成了空白的 `files/` 和 `patches/` 准备让你高定。

3. **让 Actions 菜单认识新设备**：
   打开代码里的 `.github/workflows/build.yml` 文件。
   - 在 `options:` 列表里手动加一行：`- asus-ax6000`
   - 在 `DEVICES=` 映射表里增加解析规则：
     ```bash
     ["asus-ax6000"]="mediatek|filogic|aarch64_cortex-a53|asus_ax6000"
     ```
     *(字符串规律：Target | Subtarget | Arch | Profile。这些名字可以在你刚刚生成的 target.config 里面找到赋值的变量名)*

4. **保存推送到 GitHub**：
   ```bash
   git add .
   git commit -m "Add new device ASUS-AX6000"
   git push
   ```
   现在你的 Actions 里就有这台新机器了！

---

## 🛠️ 进阶 2：定制化高阶玩法解答

**Q1: 我想修改全设备的默认 IP 地址，在哪里改？**
请找到 `devices/common/settings.sh`，在里面找到这一句修改即可：
```bash
safe_sed 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate
```

**Q2: 我只要 MT3000 的 IP 地址和别人不一样，怎么弄？**
在 `devices/glinet-gl-mt3000/` 下新建一个文本文件命名为 `settings.sh`，赋予可执行权限，然后写入：
```bash
#!/bin/bash
# 这个脚本只在编译 MT3000 时运行，它会覆盖掉 common 里刚刚改的 IP
sed -i 's/192.168.30.1/192.168.8.1/g' package/base-files/files/bin/config_generate
```

**Q3: 我想专门为 x86 加入某个自定义界面的背景图片？**
把想要覆盖的资源图片丢到：
`devices/x86_64/files/www/luci-static/resources/background.jpg`
只要路径和固件系统内的全路径对准，编译时会自动打包进去。

**Q4: 为什么有的第三方软件（如魔改版某App）编译选项里找不到？**
请检查 `devices/common/feeds.conf` 是否加入了该库的 github 链接，并且在 `devices/common/base.config` 中声明为 `=y` 的必定安装状态。
