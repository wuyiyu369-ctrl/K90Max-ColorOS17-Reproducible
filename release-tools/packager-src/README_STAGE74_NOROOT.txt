Redmi K90 Max（prague）ColorOS 17 Stage74 无 Root 中文一键刷机包

作者：哆啦A梦

本包特性：
1. 固定刷入小米原厂 Android 17 init_boot，不包含 KernelSU 修补镜像。
2. 不包含 KernelSU 管理器、KSU 模块或 LSPosed 模块。
3. 系统更新模式保留数据，只刷 Stage74 super.img 和原厂 init_boot。
4. 全新刷入模式补齐 boot、vendor_boot、dtbo、vbmeta*、原厂 init_boot 和 super.img。
5. 全新刷入可选择保留数据或格式化；从小米系统首次转入建议格式化数据。

使用方法：
1. 使用原厂或质量可靠的数据线，手机电量高于 30%。
2. Bootloader 必须已经解锁。
3. 双击 START_FLASH.cmd。
4. 按中文提示输入 OK、1 或 2。
5. 刷写关键分区和 super.img 时禁止拔线。

模式说明：
- 1 系统更新/修复：适合已经运行本项目 ColorOS 的手机，保留用户数据。
- 2 全新刷入：适合从小米系统或其他系统转入，可选择保留或格式化数据。

无 Root 说明：
- 脚本每次都会刷入原厂 init_boot，从启动镜像层移除 KernelSU。
- 如果旧系统的数据分区中仍有管理器 APK 或模块残留，它们不会获得 Root 权限；
  格式化数据会一并清除这些用户数据残留。

安全边界：
本包明确不刷写 modem、persist、nvdata、nvcfg、nvram、protect_f、
protect_s、preloader、lk 等基带、校准、身份和敏感启动分区。

遇到失败：
- 不要连续重复刷写，不要随意格式化。
- 保留窗口完整报错和 logs 文件夹。
