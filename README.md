# Redmi K90 Max ColorOS 17 移植复刻资料

这是 Redmi K90 Max（`prague / MT6993`）适配 ColorOS 17 的轻量复刻仓库。仓库只保存能够解释、重建和继续修复的源码、脚本、配置与文档，不包含可直接刷入的镜像或厂商闭源固件。

## 目录

- `docs/handoff/`：完整交接、当前进度、功能迁移边界。
- `docs/audits/`：关键 Stage 的故障根因、SELinux、性能、相机、风扇审计。
- `module/unified-ksu/`：当前统一 KernelSU 模块的文本源码和打包脚本。
- `module/radio-registration-v2.1/`：Android 17 SIM `LOADED/READY` 兼容修复源码；实机结果仍需按设备验证。
- `rom/build-scripts/`：镜像重建、补丁、审计和验证脚本。
- `rom/native-bridges/`：性能、URCC、风扇与策略桥的原生源码。
- `rom/metadata/`：动态分区布局等重建所需的非二进制元数据。
- `release-tools/`：Stage78/80 刷机、日志工具和自解压程序的源码与测试脚本，不含镜像和可执行文件。

## 明确不包含

- `super.img`、`boot.img`、`init_boot.img`、`vendor_boot.img` 等刷机镜像；
- modem、persist、nvdata、nvcfg、protect、preloader 等敏感分区；
- OPPO/小米闭源 APK、JAR、SO、固件、TEE TA、密钥和校准数据；
- 设备日志、序列号、IMEI、账号信息和本地凭据；
- WSL 虚拟磁盘、工具链压缩包、反编译输出和可再生成缓存。

## 身份边界

ColorOS framework/app 层维持 PMB110 兼容身份；vendor/odm/radio/security 层维持 K90 Max `prague / MT6993` 硬件身份。不要把 PMB110 身份全局写入底层，也不要跨设备复制 modem、NV、TEE 或校准分区。

## 使用方法

先阅读 `docs/handoff/README_先看这里.txt` 和完整交接文档，再根据 `rom/metadata/super_lpdump.txt` 准备合法取得的原始底包和 donor 固件。脚本中的绝对路径是历史构建环境记录，需要按本机目录调整。

此仓库不能单独生成完整 ROM：闭源输入必须由使用者自行从其有权使用的官方固件中提取。任何镜像修改都应先离线校验 EROFS、SELinux xattr、动态分区 extent 和哈希，再在可回滚设备上测试。

## 当前基线

- 最新公开源码归档日期：2026-11-17。
- 当前模块源码基线：`v1.10.8-20261115-auto-brightness-final`。
- 无线电修复源码基线：`v2.1_FINAL_20261112`。
- 已知可启动交付和实际大镜像不进入 GitHub；删除本地前请按 `LOCAL_DELETION_CHECKLIST.md` 另行离线保存或确认可重新下载。

本仓库公开不等于授予厂商闭源组件的再分发许可；仓库未附开源许可证的文件保留其原有权利状态。
