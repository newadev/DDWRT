# DDWRT (OpenWrt) 自动编译库

基于 GitHub Actions 的 OpenWrt 固件自动编译系统。采用设备级配置隔离架构，支持多设备独立编译与定制。

---

## 特性

- **自动化构建**：每周五 UTC 00:00（新加坡时间 08:00）检测上游更新，固定同一个源码提交触发全部设备构建；全部触发成功后才记录版本。
- **构建校验**：提交与 PR 自动运行工作流检查、ShellCheck 和回归测试；每次固件构建还会检查目标 Profile、互斥包及被 `defconfig` 丢弃的软件包。
- **设备配置隔离**：每个设备拥有独立的配置文件夹，避免不同设备间的配置和补丁冲突。
- **层叠配置设计**：优先加载 `common`（通用）配置，随后根据具体设备加载专属配置、文件或补丁。

---

## 目录结构

```text
├── .github/workflows/          # GitHub Actions 工作流配置文件
│   ├── build.yml               # 固件编译流水线
│   ├── clean-releases-and-runs.yml # 历史 Release 与构建记录定期清理流水线 (按设备独立保留)
│   ├── cache-cleanup.yml       # 缓存清理流水线
│   ├── validate.yml            # 工作流、脚本与回归测试
│   └── update-checker.yml      # 上游源码更新检测流水线
├── tools/
│   ├── make-config.sh          # 本地设备配置生成脚本
│   ├── merge-config.sh         # 按符号合并配置，设备选项覆盖通用选项
│   ├── prepare-source.sh       # 本地与 CI 共用的 feeds、补丁和文件准备
│   ├── prepare-artifacts.sh    # 固件整理与 SHA256 校验
│   └── validate-config.sh      # 目标 Profile、互斥包与请求包校验
├── tests/project_test.rb       # 配置、打包、更新及清理流程回归测试
└── devices/                    # 设备配置目录
    ├── common/                 # 通用配置底座
    │   ├── base.config         # 基础软件包配置（如 LuCI 界面等）
    │   ├── feeds.conf          # 软件源配置文件
    │   ├── settings.sh         # 通用系统初始脚本（默认 IP、时区等）
    │   ├── files/              # 通用覆盖文件目录
    │   └── patches/            # 通用源码补丁目录
    └── <device-name>/          # 专属设备配置目录（如 x86_64, glinet-gl-mt3000, 360-t7）
        ├── target.config       # 设备专属软件包与架构配置
        ├── settings.sh         # 设备专属系统初始脚本（可选）
        ├── files/              # 设备专属覆盖文件目录（可选）
        └── patches/            # 设备专属源码补丁目录（可选）
```

---

## 使用指南

### 1. 初始化仓库
1. Fork 本仓库到您的 GitHub 账号下。
2. 进入 Fork 后的仓库，在 **Actions** 页面启用工作流（点击 `I understand my workflows, go ahead and enable them`）。

### 2. 手动触发编译
1. 在仓库的 **Actions** 页面，选择左侧的 `Build OpenWrt` 工作流。
2. 点击右侧的 `Run workflow` 按钮。
3. 选择目标设备（可选 `x86_64`、`netcore-n60-pro`、`cudy-tr3000-v1`、`glinet-gl-mt3000`、`360-t7`），点击 `Run workflow` 开始编译。
4. 编译完成后，可在仓库的 **Releases** 页面下载固件和校验文件。

`source_ref` 可填写 OpenWrt 的完整 40 位提交 SHA，留空则使用 `openwrt-25.12` 的最新提交。`clean` 会跳过 ccache 和下载缓存。工具链从源码构建，不恢复缺少构建状态的 `staging_dir` 缓存。

每次构建保存固件和独立的 `build-config-*` Artifact（包括配置种子、feeds 版本及软件包清单），保留 7 天。失败时保存配置与下载/编译日志 3 天。Release 每台设备保留最近两个正式版本，未匹配设备命名规则、草稿及预发布版本不参与清理。

下载后在固件目录执行 `sha256sum -c sha256sums` 校验文件完整性。

### 360T7 全 UBI 布局

`360-t7` 使用 OpenWrt `openwrt-25.12` 官方的 `qihoo_360t7-ubi` Profile。BL2 保留前 1 MiB，其余 127 MiB 为 UBI 分区，包含 `factory`、`fip`、`fit`、`ubootenv` 和 `ubootenv2` 卷。

构建产物以 `qihoo_360t7-ubi` 标识，包含 `sysupgrade.itb`、`initramfs-recovery.itb` 以及配套的 `preloader.bin` 和 `bl31-uboot.fip`。

此固件要求设备已使用匹配的全 UBI U-Boot / preloader 与分区布局。从其他布局迁移时，需要先备份原始 `factory` 校准数据及引导分区，按对应引导程序的流程转换布局；直接刷入 `sysupgrade.itb` 不会完成布局转换。

设备定义见 [OpenWrt 镜像配置](https://github.com/openwrt/openwrt/blob/openwrt-25.12/target/linux/mediatek/image/filogic.mk)和 [360T7 UBI 设备树](https://github.com/openwrt/openwrt/blob/openwrt-25.12/target/linux/mediatek/dts/mt7981b-qihoo-360t7-ubi.dts)。

---

## 进阶配置

### 添加新设备支持
以添加设备 `asus-ax6000` 为例：

1. **生成设备专属配置**：
   在本地 Linux 或 WSL 环境下执行以下命令：
   ```bash
   ./tools/make-config.sh asus-ax6000
   ```
   在弹出的 menuconfig 界面中选择目标硬件架构（Target System / Subtarget）及所需软件包，保存并退出。脚本将自动提取配置差异并保存至 `devices/asus-ax6000/target.config`。

   默认使用仓库内的 `openwrt/` 源码，也可传入第二个参数指定其他源码目录。工具使用当前检出的版本，不自动拉取源码；请在运行前显式更新源码并确认本地修改。

2. **在工作流中注册设备**：
   - 修改 `.github/workflows/build.yml` 文件：
     - 在 `options` 列表中添加设备名：`- asus-ax6000`
     - 在 `device` 解析步骤的 `DEVICES` 映射表中添加设备的硬件参数解析规则：
       ```bash
       ["asus-ax6000"]="mediatek|filogic|aarch64_cortex-a53|asus_ax6000"
       ```
       *(格式：`"Target|Subtarget|Arch|Profile"`)*
   - 更新检查会自动发现 `devices/*/target.config`，无需再维护设备数组。校验流程会检查配置目录、工作流选项和 Profile 映射是否一致。

   设备级 `feeds.conf` 会追加到通用 feeds，feed 名称必须唯一。补丁不适用时立即报错，已应用的补丁可重复执行；文件覆盖包含隐藏文件，设备文件优先。

3. **提交并推送代码**：
   ```bash
   git add .
   git commit -m "Add support for asus-ax6000"
   git push
   ```

---

## 常见问题与定制

**Q: 如何在本地检查修改？**
```bash
ruby tests/project_test.rb
shellcheck tools/*.sh devices/*/settings.sh
actionlint
```
回归测试需要 Ruby、minitest、Node.js、Git 和 Bash。GitHub 的 `Validate Project` 工作流会准备检查环境，并在手动固件构建前自动运行。

**Q: 为什么有些旧配置项被删除？**
当前 25.12 源码与配置的 feeds 不提供 `default-settings`、`default-settings-chn`、`luci-app-autoreboot`、旧版 Shadowsocks-libev、`filebrowser` 和 `kmod-iptables` 等选项。这些项目此前会被 `defconfig` 忽略，已清理失效引用；中文设置由通用配置提供，原有 Nikki、Shadowsocks-rust、LuCI 文件管理器及 iptables-nft 等有效选项保留。以后请求的软件包未进入最终配置时，构建会在配置阶段报错。

**Q: 如何修改所有固件的默认管理 IP 地址？**  
当前通用默认 IP 为 `192.168.30.1`。若需修改，编辑 `devices/common/settings.sh` 中的替换规则：
```bash
safe_sed 's/192\.168\.1\.1/192.168.10.1/g' package/base-files/files/bin/config_generate
```

**Q: 如何为特定设备设置不同的管理 IP 地址？**  
在设备专属目录（如 `devices/glinet-gl-mt3000/settings.sh`）中创建独立的替换脚本：
```bash
#!/bin/bash
sed -i 's/192\.168\.30\.1/192.168.8.1/g' package/base-files/files/bin/config_generate
```

**Q: 编译选项中找不到某些第三方软件包？**  
确保在 `devices/common/feeds.conf` 中添加了该软件包的软件源，并在 `devices/common/base.config` 或设备专属的 `target.config` 中声明 `CONFIG_PACKAGE_xxx=y`。
