Redmi K90 Max（prague）ColorOS 17 中文一键刷机包

作者：哆啦A梦

使用方法：
1. 解压到空间充足的本地磁盘，路径中可以有中文。
2. 使用原厂或质量可靠的数据线，手机电量高于 30%。
3. 双击 START_FLASH.cmd。
4. 根据中文提示输入 OK、1 或 2。
5. 刷写关键分区和 super.img 时禁止拔线。
6. 刷机成功后可选择保留或自动删除解压出的约 13GB 文件；原始 EXE 和数据
   分卷不会被自动删除。

模式说明：
- 系统更新/修复：保留用户数据。
- 全新刷入：适合从小米系统或其他系统转入，可选择保留或格式化数据。
- Root：末尾可选原厂无 Root init_boot 或 KernelSU init_boot。

安全边界：
本刷机包明确不刷写 modem、persist、nvdata、nvcfg、nvram、protect_f、
protect_s、preloader、lk 等基带、校准、身份和敏感启动分区。

如果检测不到手机：
- 脚本会询问是否安装包内 Google USB 驱动。
- 安装驱动需要管理员权限。
- 仍无法识别时，请更换 USB 端口、数据线，并确认手机处于 ADB、Fastboot
  或 Fastbootd 状态。

遇到失败：
- 不要连续重复刷写。
- 不要随意格式化。
- 保留窗口完整报错和 logs 文件夹。
