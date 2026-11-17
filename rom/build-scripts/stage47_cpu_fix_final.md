# Stage47 CPU 性能修复 - 最终方案

## 当前状态确认

### 已内置的调度系统
1. ✅ \/odm/bin/k90_perf_bridge.sh\ - 性能桥脚本
2. ✅ RC 服务 \k90-performance-bridge\
3. ✅ 通过 sconfig 控制温控场景

### 发现的冲突
- **mipower_hal** 在开机 5 秒后启动
- 持续写入低频率限制到 sconfig
- 覆盖了 k90_perf_bridge.sh 的设置
- 导致 CPU 被锁定在 1.5/1.9/1.85 GHz

## 最终解决方案

### 方案：在 RC 中禁用 mipower_hal

修改 \/odm/etc/init/\ 中的 RC 文件，添加：

\\\
c
# 禁用 mipower_hal，使用 K90 原生性能桥替代
on boot
    stop mipower_hal

on property:sys.boot_completed=1
    stop mipower_hal
\\\

### 物理最大频率
- policy0 (小核): 2.7 GHz
- policy4 (中核): 3.5 GHz
- policy7 (大核): **4.21 GHz** ✅

### 验证步骤
1. 停止 mipower_hal
2. 检查 k90_perf_bridge.sh 是否正常运行
3. 验证 sconfig 可以正常切换
4. 确认 CPU 频率可以达到物理最大值

## 下一步
编译 Stage47 镜像，内置该修复。
