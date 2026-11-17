# K90Max ColorOS 17 Stage24 brightness candidate

This is a keep-data incremental package based on the bootable Stage23 image.

1. Disable KSU/LSPosed modules before testing.
2. Run `FLASH_KEEP_DATA.ps1 -CheckOnly` first.
3. Flash only `images\super.img` from fastbootd; do not use `-w`.
4. After boot, verify minimum brightness, automatic brightness, status-bar brightness changes, fingerprint, signal, and WeChat scan.
5. If boot fails, restore Stage23; do not touch `boot`, `init_boot`, `vendor_boot`, `modem`, `persist`, `nvdata`, `nvcfg`, or `protect*`.

The candidate changes only the system_ext brightness table minimum from 222 to 5. It is not an assertion that the hardware curve or automatic-brightness behavior is fully validated until the device test is performed.
