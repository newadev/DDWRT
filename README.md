# DDWRT (OpenWrt) 自动编译库

基于 GitHub Actions 的 OpenWrt 固件自动编译系统。采用设备级配置隔离架构，支持多设备独立编译与定制。

---

## 特性

- **自动化构建**：每周五自动检测 OpenWrt 上游源码更新，检测到变更时自动触发编译并发布至 Releases（构建产物默认保留 7 天）。
- **设备配置隔离**：每个设备拥有独立的配置文件夹，避免不同设备间的配置和补丁冲突。
- **层叠配置设计**：优先加载 `common`（通用）配置，随后根据具体设备加载专属配置、文件或补丁。

---

## 目录结构

```text
├── .github/workflows/          # GitHub Actions 工作流配置文件
│   ├── build.yml               # 固件编译流水线
│   ├── cache-cleanup.yml       # 缓存清理流水线
│   └── update-checker.yml      # 上游源码更新检测流水线
├── tools/
│   └── make-config.sh          # 本地设备配置生成脚本
└── devices/                    # 设备配置目录
    ├── common/                 # 通用配置底座
    │   ├── base.config         # 基础软件包配置（如 LuCI 界面等）
    │   ├── feeds.conf          # 软件源配置文件
    │   ├── settings.sh         # 通用系统初始脚本（默认 IP、时区等）
    │   ├── files/              # 通用覆盖文件目录
    │   └── patches/            # 通用源码补丁目录
    └── <device-name>/          # 专属设备配置目录（如 x86_64, glinet-gl-mt3000）
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
3. 选择目标设备（默认值为 `x86_64`），然后点击 `Run workflow` 开始编译。
4. 编译完成后，可在仓库的 **Releases** 页面下载固件。

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

2. **在工作流中注册设备**：
   修改 `.github/workflows/build.yml` 文件：
   - 在 `options` 列表中添加设备名：`- asus-ax6000`
   - 在 `device` 解析步骤的 `DEVICES` 映射表中添加设备的硬件参数解析规则：
     ```bash
     ["asus-ax6000"]="mediatek|filogic|aarch64_cortex-a53|asus_ax6000"
     ```
     *(格式：`"Target|Subtarget|Arch|Profile"`)*

3. **提交并推送代码**：
   ```bash
   git add .
   git commit -m "Add support for asus-ax6000"
   git push
   ```

---

## 常见问题与定制

**Q: 如何修改所有固件的默认管理 IP 地址？**  
修改 `devices/common/settings.sh` 中的 IP 替换规则：
```bash
safe_sed 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate
```

**Q: 如何为特定设备设置不同的管理 IP 地址？**  
在设备专属目录（如 `devices/glinet-gl-mt3000/settings.sh`）中添加独立的替换脚本：
```bash
#!/bin/bash
sed -i 's/192.168.30.1/192.168.8.1/g' package/base-files/files/bin/config_generate
```

**Q: 编译选项中找不到某些第三方软件包？**  
确保在 `devices/common/feeds.conf` 中添加了该软件包的软件源，并在 `devices/common/base.config` 或设备专属的 `target.config` 中声明 `CONFIG_PACKAGE_xxx=y`。
