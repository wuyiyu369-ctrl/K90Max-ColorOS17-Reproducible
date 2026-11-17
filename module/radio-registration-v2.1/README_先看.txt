K90 Max ColorOS 17 入网强恢复 v2.1

适用范围：Redmi K90 Max（prague / MT6993）ColorOS 17 移植系统。

本版与 v1 的区别：
1. 删除无效的 vendor/odm 设备身份伪装。
2. 修复 Android 17 把已加载 SIM 报为 LOADED 时脚本误判未就绪的问题。
3. SIM READY/LOADED 但持续无服务时，重启一次 MTK userspace RIL。
4. RIL 仍未驻网时，重新上电 SIM0，并重启 ColorOS NAS/PCDR/SIDO 恢复进程。
5. 每次开机只执行一轮，不循环重启手机或基带。
6. 可在 KernelSU 管理器中点“操作”手动再执行一轮。

安全边界：
- 不刷写或擦除 modem、persist、nvdata、nvcfg、protect、preloader。
- 不修改 IMEI。
- 不伪造信号格或运营商名称。
- 模块只能恢复卡住的 userspace 无线电链路，不能修复当地无联通覆盖、SIM 停机、
  射频硬件、天线或损坏的设备专属 NV 校准数据。

日志目录：/data/adb/k90max-radio-fix/
重点文件：service-v2.log、v2-before.txt、v2-after.txt。
普通 logcat 也可搜索标签：K90RadioFix。
