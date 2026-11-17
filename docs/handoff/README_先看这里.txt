K90 Max / Prague ColorOS 17 完整迁移包
日期：2026-10-28

第一步请阅读：
K90Max_ColorOS17_完整迁移交接_20261028.md

当前可刷包位于：
..\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage13_COMBINED\

注意：目录名仍含 Stage13_COMBINED，但其中 images\super.img 已替换为实机成功开机的 Stage14 CPU/充电候选。
该包只允许在 Redmi K90 Max（prague）fastbootd 中保数据刷 super；不要执行 -w，不要擦除 userdata/metadata。

WSL 316GB 虚拟磁盘未纳入迁移包，仍在：
D:\WSL\Ubuntu-24.04\ext4.vhdx

已从 WSL 移出的不可替代产物位于：
..\06_WSL关键产物_虚拟磁盘不迁移\

目录清单、关键 SHA-256 和迁移记录也在本目录。
