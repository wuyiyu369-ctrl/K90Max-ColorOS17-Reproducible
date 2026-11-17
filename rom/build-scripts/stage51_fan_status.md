# Stage51 风扇状态

当前设备的设置页面可以写入 `cooling_fan_main_switch`、`cooling_fan_mode` 和自定义档位，但实机未产生有效的风扇执行回读。

现场证据：

- `/sys/devices/platform/odm/odm:xiaomi_fan` 存在，但在当前 SELinux shell 下不可访问；没有读到 `pwm_duty` 或 `real_speed`。
- `/data/system/k90fan.request` 仍是旧内容，修改设置后没有更新时间变化。
- `k90_native_bridge` 正在运行，但日志只有 UniPerf 启动提示，没有 `fan-applied` 或 `fan-speed-readback`。

因此本阶段不能宣称风扇已经修好。下一步必须让设置值稳定发布到请求文件，并基于设备实际 `xiaomi_fan` 节点补齐精确的 SELinux 访问规则；不能用写入 Settings 或伪造 readback 代替真实转动。
