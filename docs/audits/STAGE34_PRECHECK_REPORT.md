# Stage34 交付前检查报告

检查日期：2026-11-05（Asia/Shanghai）

## 结论

当前还没有生成目录：

```text
D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage34_CHARGE_CAMERA_AOD_R1
```

因此目前不能称为“已完成可刷包”。现在只有构建脚本和输入树。

## 已写入 Stage34 构建脚本、但尚未生成成品

- `oplus_battery_agent_debug_force_entry=1`
- `stay_on_while_plugged_in=0`
- 清理 `brightness_drag_point` 和 `screen_auto_brightness_adj`
- AOD 原生 overlay
- 充电桥延迟启动
- 充电遥测脚本和默认 `MODE=aggressive`
- 温度、接口温度、PD 认证、电量、电流保护
- `perfserv_freq` 的 MTK PowerHAL 权限触发

这些内容只有在 Stage34 构建、EROFS 校验、super 合并完成后才算进入刷机包。

## 当前可以从已验证基线继承的内容

- Stage31 的系统、vendor、system_ext 基线
- Stage32 `my_product.img` 的第三方相机 `EXTRA_OUTPUT`/`RESULT_OK` 返回修复输入
- Stage31 已验证的部分相机启动/缓存修复
- 之前已验证的短信版本（前提是实际选择的基线确实包含它）

注意：脚本只引用 `my_product.img`，没有在 Windows 目录中找到 Stage34 成品来证明它已被合并。

## 明确尚未内置或尚未完成实机验证

### KSU/LSPosed 源文件审计结论

已核对 `build_v1747`、`K90Max_A17_NATIVE_HANDOFF_20261026.md` 和模块 ZIP：

- 模块确实包含 URCC/Performance 二进制、VINTF、init rc、`liburcccore.so`、`libuahcore.so` 和性能配置。
- 这些文件目前没有进入 Stage34 的 product/odm 合并脚本。
- 不能仅复制它们：当前设备审计明确记录 `default_android_service` 的 SELinux `find` 拒绝，且旧 HAL 存在 ABI/依赖风险。
- 因此“OPPO 性能调度已经修复”目前不成立；准确状态是“候选 donor 文件已找到，但真实 CPU/GPU/DDR/UFS 调度未验证、未内置”。
- Stage34 只保留已经验证的 `perfserv_freq` 权限触发，不冒充完整 URCC。

### 相机

- 小米相机机型校验仍会提示“当前相机版本和机型不匹配”
- 录像模式、60fps、8K
- 动态照片处理速度
- 连续多次拍照后卡住
- 第三方/微信调用拍照后点击勾，照片返回调用方
- 第三方录像返回
- MIVI 后处理、保存延迟、黑屏预览
- 相机算法和性能调度协同

Stage32 的 `EXTRA_OUTPUT`/`RESULT_OK` 修复只覆盖已经确认的外部拍照返回路径，不能等同于完整微信兼容。

### 生物识别

- 指纹录入进度动画
- 指纹超声波类型、图标和坐标的最终实机复验
- 人脸录入过难/remaining 回调兼容

### 性能

- 完整 OPPO `IPerformance/URCC/UAH` 到 MTK CPU/GPU/DDR/UFS 的真实映射
- 游戏场景调度和应用启动调度
- 不应直接把 `build_v1747/odm` 中整套 URCC/Performance 二进制复制进镜像；需要先做 SELinux、VINTF、依赖和实机动态验证

### 充电与电池

- 真实协议瓦数显示
- 插拔状态延迟的最终实机确认
- ICharger 服务是否能在当前 SELinux 域成功注册
- “激进档”是否真的作用于当前 Xiaomi MiCharge；脚本只提供受保护的调度入口，不能凭空增加协议能力
- 电池健康完整功能；目前主要是入口和桥接能力，不是异厂商健康算法移植

### 显示与系统

- 90Hz 私有 Xiaomi DisplayFeature 映射
- 自动亮度曲线、学习数据和环境光回归
- AOD 全天/定时/节能/口袋策略回归
- 最低亮度曲线、PWM/DC、色彩对比度
- 自动熄屏在充电/USB 状态下的全部场景

### 其他

- 微信扫一扫卡顿/闪退
- 触感编号映射和侧边触感
- MiSound/Bose 音效
- NFC 钱包、eID、查找手机：异厂 TEE/密钥，不能靠镜像伪造
- DRM/Widevine L1
- 双卡/空信号和 5G-A UI 的实机验证
- Root 检测规避不作承诺

## 开机风险检查

构建脚本已经加入 product/odm 根目录 SELinux xattr、UUID、固定分区大小和 super 前后元数据哈希门禁；但这些门禁只有在 WSL 工具链和输入镜像可用时才能实际执行。

Stage33 曾因 product/odm 根目录 SELinux 标签丢失而不开机，Stage34 必须在生成后检查：

```text
product root = u:object_r:system_file:s0
odm root     = u:object_r:vendor_file:s0
```

在 `super.img` 尚未生成、上述门禁尚未通过前，不应刷入设备。
