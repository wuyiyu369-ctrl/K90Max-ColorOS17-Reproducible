# Stage34 变更说明

本版由 `build_stage33_native_partitions.sh` 生成 `product.img`/`odm.img`，再由
`build_stage33_camera_perf_aod.sh` 合并为：

```text
K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage34_CHARGE_CAMERA_AOD_R1
```

## 内置内容

- `oplus_battery_agent_debug_force_entry=1`：在 `sys.boot_completed=1` 后写入。
- 充电桥接与遥测守护：系统完全开机后延迟启动，MiCharge 服务不存在时直接退出。
- 默认 `MODE=aggressive`，但仍受电池、接口、主板温度、PD 认证、电量和电流硬保护约束。
- Stage32 的第三方相机 `EXTRA_OUTPUT`/`RESULT_OK` 返回修复继续来自 `my_product.img`。
- AOD、自动熄屏和亮度学习数据清理继续保留。

## 安全边界

- 不修改 userdata，不格式化数据。
- 不触碰 modem、persist、nvdata、nvcfg、protect、preloader、TEE/key material。
- 不永久关闭 JEITA 或温控，不强制锁定最高功率。
- 充电桥必须在完整开机后启动，失败只影响充电扩展，不应阻塞开机。
- 构建脚本会检查 product/odm 根目录 SELinux xattr、UUID、固定 extent、super 前后元数据哈希。

## 尚不能离线确认

相机机型校验、录像、动图保存延迟、连续拍照、微信调用返回、90Hz 私有档和 URCC
真实 CPU/GPU/DDR/UFS 调度仍需手机回来后实测；静态打包不等于实机修复。
