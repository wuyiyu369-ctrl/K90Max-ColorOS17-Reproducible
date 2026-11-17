# CPU 性能问题 - 真正的原因找到了！

## 实验结果

### 测试 1：修改 sconfig
- 写入 sconfig=20 (YUANSHEN 最高性能)
- 结果：**无效**，CPU 频率不变
- 结论：sconfig 不是控制者

### 测试 2：停止 mi_thermald
- 执行 \stop mi_thermald\
- 结果：**无效**，CPU 频率不变
- 结论：mi_thermald 不是控制者

### 测试 3：停止 mipower_hal ✅
- 执行 \stop mipower_hal\
- 结果：**频率立即提升到 1.8/2.4/3.05 GHz**
- 结论：**mipower_hal 是真正的限频者！**

## 根本原因

**mipower_hal** (vendor/bin/mipower_hal) 持续每隔几秒写入 scaling_max_freq，将 CPU 限制在：
- policy0: 1.5 GHz (物理最大 2.7 GHz)
- policy4: 1.9 GHz (物理最大 2.4 GHz)
- policy7: 1.85 GHz (物理最大 3.05 GHz)

这个限制在开机约 5 秒后生效，覆盖了所有其他调度策略。

## 解决方案

### 方案 1：禁用 mipower_hal（简单但可能影响其他功能）
- 在 RC 中禁用该服务
- 风险：可能影响小米的性能调度框架

### 方案 2：修改 mipower_hal 配置（推荐）
- 查找并修改 mipower_hal 的配置文件
- 让它使用更高的频率限制
- 保留服务运行

### 方案 3：守护进程持续修正（备选）
- 每 3 秒检查并写回 scaling_max_freq
- 与 mipower_hal 竞争

## 下一步

需要决定使用哪个方案。你希望：
1. 直接禁用 mipower_hal
2. 或者继续调查它的配置文件
