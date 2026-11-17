# 复刻与继续修复指南

## 必需输入

1. Redmi K90 Max 对应版本的官方底包；
2. 合法取得且版本匹配的 ColorOS donor 固件；
3. Linux/WSL、EROFS 工具、Android sparse/dynamic partition 工具；
4. 可回滚设备、ADB、fastboot/fastbootd 和充足磁盘空间。

仓库不提供上述固件、二进制工具链或厂商密钥。

## 推荐顺序

1. 阅读 `docs/handoff`，确定当前可启动基线和禁止刷写分区；
2. 用 `super_lpdump.txt` 复核分区 extent，不要凭旧 Stage 偏移重建；
3. 从原始镜像提取真实 SELinux xattr、file_contexts 与 split CIL 输入；
4. 只应用需要的脚本/源码变更；
5. 重建后检查文件标签、EROFS、JAR/DEX 类集合和未修改 extent；
6. 先保留回滚包，再进行实机验证；
7. 静态构建成功不能写成实机修复成功，必须保留运行日志证据。

## 永远不要跨设备复制或刷写

`modem`、`persist`、`nvdata`、`nvcfg`、`protect*`、`md_sec`、`preloader`、设备 TEE/StrongBox 密钥和任何校准分区。

## 仓库完整性

`tools/check_public_repo.ps1` 会拒绝超过 1 MiB 的文件、常见二进制/镜像扩展、私钥标记和已知设备序列号。提交前必须运行该检查。
