# Stage44 风扇与性能桥候选包

本版基于能开机的 Stage43，采用保数据更新。功能内置于 system 和 ODM；运行不依赖 KSU、LSPosed 或第三方调度软件。

## 本轮实现

1. 风扇设置发布链：保留 ColorOS 原有 SettingsObserver。系统只把主开关、模式、自定义 PWM、游戏开关和充电开关发布至 `/data/system/k90fan.request`，不再由 system_server 写两个风扇 sysfs 节点。
2. 原生执行链：`/odm/bin/k90_native_bridge` 由 init 启动，以 system UID 运行。读取真实前台、屏幕状态和温度，执行风扇请求，并回读 PWM 与 real_speed。模式为智能/静音/全速/自定义；智能模式充满后停止充电散热，游戏中仍可按温度散热。AOD 按熄屏处理；关主开关停止本桥控制。
3. 真实小米启动性能提示：复用同一个 vendor 镜像里的 `libuniperf_client_vendor.so`，调用已核对 ABI 的 `UniperfHint`。前台切换时提交普通启动或游戏启动的 5 秒提示，使用本机 `UniperfHintMapsConfig.xml` 中 `0x1081/type1 -> MTK21`、`type4 -> MTK54`，由小米库分配句柄，切换或灭屏时释放。高温/读温度失败时不提交新启动提示。
4. MediaTek PowerHAL 权限：init 将 `perfserv_freq` 设置为 system:system、0660，并补 vendor_init 的 setattr 和 PowerHAL 的读写权限。未使用 0666。
5. 保留 Stage43 其他框架 JAR 成员；仅重汇编 services.jar 的 classes4.dex，源代码变动限于 K90ThermalBridge 一类，没有删除任何原有类。

## SELinux 构建方式与边界

旧版电脑 secilc 不能识别 Android 17 的 nlmsg。已从 SELinuxProject 源码构建兼容编译器，版本记录在工具目录 libsepol/VERSION。

采集的完整 CIL 基线存在原移植包自己的 neverallow 冲突。因此不能宣称“完整源策略严格编译通过”。本轮没有使用 `-N`、没有删除 neverallow、没有设置 permissive。

候选规则按合法 UniPerf HAL 客户端关系声明后，完整源码的严格编译诊断与原始基线相同，没有增加新的冲突。最终使用 libsepol 对 **Stage43 镜像自身的 precompiled_sepolicy** 做列举规则和客户端关系的增量修改，保留原策略版本、类型集合、约束、转换和 permissive map。不是使用 Stage42 的二进制，也不是把某个参考 ROM 的策略拼入本包。

候选的哈希标记取自 Stage43 自身的 system/system_ext/product；采集的 CIL/mapping 与镜像逐一核对。这样 init 能选择本轮增量策略。这个改变仍需要整机开机回归，离线检查不能替代。

## 不能宣称已经解决的部分

- 尚未实机验证本包能开机、菜单可见、风扇真实转动、性能提升或耗电变化。
- 这次接入的是 Xiaomi 原生启动 hint，不是完整 OPPO IPerformance/URCC/UAH 服务。原 OPPO 接口缺失的查询错误不保证消失。
- 未新增游戏常驻的 CPU/GPU/DDR/UFS QoS 资源映射。它们是否随启动 hint 提升，要看底层 MTK 场景配置、实际负载和实机回读；不能把返回句柄视作提频证明。
- 原厂 mi_thermal_interface、GPU THERMAL_AP 限制保留。本轮不关闭温控，不保证被温控限制时仍可跑最高频。
- 风扇主开关为关闭时不会擅自打开；需要测试设置页面实际写入上述五个键。
- 相机、人脸、指纹、充电显示等继承 Stage43，没有借本轮重做或宣称修好。

## 刷后检查

使用包内中文入口保数据刷写。手机本轮未连接，交付时只做离线检查，没有自动刷入。

1. `adb shell getprop sys.boot_completed` 返回 1，等待数分钟确认 system_server 不重启。
2. `adb shell getprop init.svc.k90-stage44-native` 应为 running。
3. `adb logcat -d -s K90NativeBridge`：应看到 `uniperf-loaded`；切换应用后检查 `launch-hint` 及返回句柄。温度超限会记录未提交提示。
4. 风扇主开关启用，先试静音，再试自定义与关闭。日志的 `fan-applied` 只证明 PWM 回读；`fan-speed-readback` 和实物转动才是机械执行证据。
5. 普通使用、游戏、熄屏/AOD、充电、满电分别观察风扇和耗电。没有这些回归，不能分发为稳定版。
6. 同时读取 CPU policy0/4/7 的 cur/max、GPU limiter、DDR/UFS devfreq、温度和 QoS 持有者。不要仅凭桌面某一瞬间频率判定成功。

## 工程位置

- 工作源码：`C:\Users\USERNAME\Documents\Codex\2026-10-08\wo\stage44_*`
- 单类 smali：`stage44_payload\K90ThermalBridge.smali`
- init 服务：`stage44_payload\k90-stage44-native.rc`
- 完整策略严格比对：`stage44_policy\baseline.log`、`candidate.log`、`strict_differential.txt`
- JAR 检查：`stage44_services\source_audit.txt`
- 镜像缓存：`D:\K90Max_ColorOS17_完整迁移_20261028\02_Codex完整工作区\wo\stage44_final_work\out`
- 回退包：同 delivery 下 `K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage43_BOOT_REPAIR`

本包只更新 super 中的 system 和 ODM，不清 userdata/metadata，不写 boot/init_boot、modem、persist、nvdata、nvcfg、protect 或 preloader。
