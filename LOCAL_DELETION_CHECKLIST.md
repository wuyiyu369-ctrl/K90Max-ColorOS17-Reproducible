# 删除本地归档前检查

GitHub 仓库只能保存继续开发所需的源码和文档，不能替代完整固件备份。删除本地 K90 Max 目录前，请确认下列内容能从合法来源重新取得。

## 已保存到 GitHub

- 当前统一 KSU 模块文本源码；
- 无线电注册修复 v2.1 源码；
- Stage24～80 关键构建、补丁、审计与验证脚本；
- 原生性能/URCC/风扇桥源码；
- Stage78/80 刷机与日志工具源码；
- 交接文档、问题矩阵、关键哈希与动态分区布局。

## 无法上传、删除后必须重新下载或重新提取

- K90 Max 官方完整底包和匹配版本的 ColorOS donor 固件；
- 当前可启动 `super.img` 及回滚镜像；
- stock/KSU `init_boot.img`、boot、vendor_boot、dtbo 和 vbmeta 系列；
- 原始 framework/vendor JAR、SO、APK 与完整 SELinux split-CIL 输入；
- Android Platform Tools、EROFS/lpmake/simg 工具链、JDK/Smali/NDK；
- 设备私有 modem/NV/TEE/校准数据——这些只能保留属于该设备自己的备份，绝不能从其他设备复制。

## 最低建议

如果确实不保留本地工程，至少在离线硬盘保留一份当前可启动刷机包、原始底包、donor 固件和对应 SHA-256。没有这些闭源输入，仅凭 GitHub 仓库不能重新生成完整可刷 ROM。
