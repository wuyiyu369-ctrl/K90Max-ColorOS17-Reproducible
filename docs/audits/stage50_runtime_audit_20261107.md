# Stage50 runtime audit

Date: 2026-11-07
Baseline: `K90Max_ColorOS17_Prague_FACTORY_RESET_CANDIDATE_Stage49`

## Confirmed on the connected device

- `sys.boot_completed=1`; ADB is connected and the phone is not in fastboot.
- `k90-performance-bridge`, `k90-stage44-native`, `mipower_hal`, and `uniperf_halservice` are running.
- Xiaomi/MediaTek GPU, APU, MTK power, MiPower and UniPerf binder services are declared.
- The Xiaomi fan device tree node exists at `/sys/devices/platform/odm/odm:xiaomi_fan`.
- `com.oplus.devicesettings` was disabled for user 0. It was re-enabled with `pm enable` for runtime inspection; this does not change the system image.
- The fan UI activity is protected by `com.oplus.devicesettings.permission.FAN_SETTINGS`, so a shell-launched activity cannot be used as a functional test.

## Root cause found for the repeated battery errors

The running native bridge emits an AVC denial every roughly two seconds:

```text
scontext=u:r:vendor_touch_init_shell:s0
tcontext=u:object_r:sysfs_batteryinfo:s0
denied { search } name="battery-manager"
```

The existing Stage44 policy increment only grants `sysfs_battery_supply`. It does not grant the `sysfs_batteryinfo` directory type shown by the actual device log. This is a real policy mismatch and is a candidate source of retry activity and excess logging.

The current log buffer contains 2,071 matching AVC records; the last records are two seconds apart, confirming that this is an active retry loop rather than a historical boot message.

`stage44_compile_policy.py` now contains the narrow `sysfs_batteryinfo` directory/file read rules. No permissive rule, wildcard rule, frequency lock, or fake battery value was added.

## Build status

The policy change has **not** been packaged or flashed. The local WSL distributions currently fail to mount their VHD (`ERROR_FILE_NOT_FOUND`), so `secilc` and the image builder cannot run in this turn. Stage49 remains the known bootable image and was not overwritten.

## Next build gate

1. Restore a working WSL distribution or run the existing Linux toolchain in a working environment.
2. Compile baseline and candidate policy with strict diagnostics and require identical baseline diagnostics.
3. Patch only the ODM policy extent, rebuild `super.img`, run EROFS/AVB/readback checks, and keep Stage49 as rollback.
4. After boot, verify that the AVC count for `k90_native_brid` and `sysfs_batteryinfo` is zero before evaluating fan behavior.

## Charging module audit

The supplied module payload is present in the current product image:

- `/product/bin/vendor.oplus.hardware.charger-V11-service`
- `/product/bin/k90-native-charge-launcher.sh`
- `/product/bin/k90-charge-daemon.sh`
- `/product/bin/k90-charge-ctl.sh`
- `/product/etc/init/k90-native-charge.rc`

The launcher is not sufficient by itself on this build. A direct runtime launch produced:

```text
Error: Security / Ok: SELinux denied for service.
```

and the service list still has no `vendor.oplus.hardware.charger.ICharger/default`. The system log confirms that the service name is being resolved as `default_android_service`, so the missing piece is the matching service-context/policy entry, not a missing MiCharge HAL.

The current phone exposes the real Xiaomi/MTK charging stack (`IMiCharge`, MTK charger power-supply nodes), but the connected USB session is presently only about 5 V / 0.5 A and reports `ChargeFastCharger=false`. This is not evidence of a 100 W session. The next image will include the module's V11 bridge and its guarded Xiaomi rule set, but it will only report/allow high power after the adapter, PD authentication, temperatures, battery level, and kernel limits all confirm it.
