# 发布与诊断工具源码

- `stage78/`：Stage78 一键刷机、Root init_boot 拖入安装与完整日志工具脚本。
- `stage80/`：最终 Stage80 Windows 刷机向导与日志收集器脚本。
- `packager-src/`：自解压启动器、Windows 刷机向导及其构建/安全说明。
- `log-collector/`：独立日志收集工具源码。
- `tests/`：不会真实调用 ADB/fastboot 的脚本测试入口与 mock。

仓库刻意不包含 `adb.exe`、`fastboot.exe`、7-Zip、USB 驱动、生成的 EXE、镜像和固件。使用者应从官方 Android Platform Tools、设备厂商或可信工具源重新取得依赖，并自行校验哈希。

这些脚本包含历史构建路径和分区假设。使用前必须根据实际包目录调整，并再次确认禁止刷写 modem、persist、nvdata、nvcfg、protect、preloader 等设备敏感分区。
