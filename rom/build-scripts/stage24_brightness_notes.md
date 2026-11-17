# Stage24 brightness candidate

- Baseline: `K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage23_SCAN_BRIGHTNESS`.
- Changed only `system_ext/etc/display_brightness_config_default.xml`.
- `<brightness_table max="8191" min="222">` -> `min="5"`.
- The rest of the table, boot chain, modem, persist, nvdata, nvcfg, protect partitions, userdata, and super metadata are unchanged.
- Offline checks: EROFS fsck passed; system_ext fits its original extent; bytes before/after the system_ext extent match Stage23; no device boot or brightness operation has been verified yet.
- Do not combine with the failed Stage24 SMS framework replacement. That replacement caused `NoSuchMethodError: ExtLoader.type(Class)` in `SystemServer`.
