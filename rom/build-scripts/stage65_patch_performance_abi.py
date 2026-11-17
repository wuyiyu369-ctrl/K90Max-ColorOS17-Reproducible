#!/usr/bin/env python3
import pathlib
import re
import sys


DEVICE_VERSION = 5
DEVICE_HASH = "ae5dbae1f1d35dcb2c795c46ea9d9950f813e739"


def load_device_transactions(path: pathlib.Path) -> dict[str, int]:
    result: dict[str, int] = {}
    in_performance = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line == "CLASS vendor.oplus.hardware.performance.IPerformance$Stub":
            in_performance = True
            continue
        if in_performance and line.startswith("CLASS "):
            break
        match = re.fullmatch(r"FIELD TRANSACTION_(\w+)=(\d+)", line)
        if match and int(match.group(2)) < 1000:
            result[match.group(1)] = int(match.group(2))
    return result


def patch_text(text: str, transactions: dict[str, int]) -> tuple[str, set[str]]:
    changed: set[str] = set()

    def replace_header(match: re.Match[str]) -> str:
        name = match.group(1)
        if name not in transactions:
            return match.group(0)
        changed.add(name)
        return f"TRANSACTION_{name} = FIRST_CALL_TRANSACTION + {transactions[name] - 1}"

    text = re.sub(
        r"TRANSACTION_(\w+) = FIRST_CALL_TRANSACTION \+ \d+",
        replace_header,
        text,
    )

    def replace_case_or_proxy(match: re.Match[str]) -> str:
        name = match.group(2)
        if name not in transactions:
            return match.group(0)
        changed.add(name)
        return f"{match.group(1)}{transactions[name] - 1} /*{name}*/"

    text = re.sub(
        r"(FIRST_CALL_TRANSACTION \+ )\d+ /\*(\w+)\*/",
        replace_case_or_proxy,
        text,
    )
    return text, changed


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: stage65_patch_performance_abi.py <aidl-root> <transaction-dump>")

    root = pathlib.Path(sys.argv[1])
    dump = pathlib.Path(sys.argv[2])
    header = root / "include/aidl/vendor/oplus/hardware/performance/IPerformance.h"
    source = root / "src/vendor/oplus/hardware/performance/IPerformance.cpp"
    transactions = load_device_transactions(dump)
    required_missing = {"readMMParameters", "writeMMParameters", "writeHoraeQmi"}
    generated_methods = set(
        re.findall(
            r"TRANSACTION_(\w+) = FIRST_CALL_TRANSACTION",
            header.read_text(encoding="utf-8"),
        )
    )
    expected_generated = set(transactions) - required_missing
    if generated_methods != expected_generated:
        raise SystemExit(
            f"generated/device method mismatch: missing={sorted(expected_generated - generated_methods)} "
            f"extra={sorted(generated_methods - expected_generated)}"
        )

    header_text, header_changed = patch_text(header.read_text(encoding="utf-8"), transactions)
    source_text, source_changed = patch_text(source.read_text(encoding="utf-8"), transactions)
    header_text = re.sub(r"static inline const int32_t version = \d+;", f"static inline const int32_t version = {DEVICE_VERSION};", header_text)
    header_text = re.sub(r'static inline const std::string hash = "[0-9a-f]+";', f'static inline const std::string hash = "{DEVICE_HASH}";', header_text)

    marker = "    case (FIRST_CALL_TRANSACTION + 16777214 /*getInterfaceVersion*/): {"
    if marker not in source_text:
        raise SystemExit("cannot locate interface-version transaction marker")
    extra_cases = r'''    case (FIRST_CALL_TRANSACTION + 172 /*readMMParameters*/): {
      int32_t in_type;
      std::string _aidl_return;
      _aidl_ret_status = ::ndk::AParcel_readData(_aidl_in, &in_type);
      if (_aidl_ret_status != STATUS_OK) break;
      (void)in_type;
      ::ndk::ScopedAStatus _aidl_status = ::ndk::ScopedAStatus::ok();
      _aidl_ret_status = AParcel_writeStatusHeader(_aidl_out, _aidl_status.get());
      if (_aidl_ret_status != STATUS_OK) break;
      _aidl_ret_status = ::ndk::AParcel_writeData(_aidl_out, _aidl_return);
      if (_aidl_ret_status != STATUS_OK) break;
      break;
    }
    case (FIRST_CALL_TRANSACTION + 173 /*writeMMParameters*/): {
      int32_t in_type;
      std::string in_value;
      int32_t _aidl_return = 0;
      _aidl_ret_status = ::ndk::AParcel_readData(_aidl_in, &in_type);
      if (_aidl_ret_status != STATUS_OK) break;
      _aidl_ret_status = ::ndk::AParcel_readData(_aidl_in, &in_value);
      if (_aidl_ret_status != STATUS_OK) break;
      (void)in_type;
      (void)in_value;
      ::ndk::ScopedAStatus _aidl_status = ::ndk::ScopedAStatus::ok();
      _aidl_ret_status = AParcel_writeStatusHeader(_aidl_out, _aidl_status.get());
      if (_aidl_ret_status != STATUS_OK) break;
      _aidl_ret_status = ::ndk::AParcel_writeData(_aidl_out, _aidl_return);
      if (_aidl_ret_status != STATUS_OK) break;
      break;
    }
    case (FIRST_CALL_TRANSACTION + 174 /*writeHoraeQmi*/): {
      std::string in_value;
      int32_t _aidl_return = 0;
      _aidl_ret_status = ::ndk::AParcel_readData(_aidl_in, &in_value);
      if (_aidl_ret_status != STATUS_OK) break;
      (void)in_value;
      ::ndk::ScopedAStatus _aidl_status = ::ndk::ScopedAStatus::ok();
      _aidl_ret_status = AParcel_writeStatusHeader(_aidl_out, _aidl_status.get());
      if (_aidl_ret_status != STATUS_OK) break;
      _aidl_ret_status = ::ndk::AParcel_writeData(_aidl_out, _aidl_return);
      if (_aidl_ret_status != STATUS_OK) break;
      break;
    }
'''
    source_text = source_text.replace(marker, extra_cases + marker, 1)
    header.write_text(header_text, encoding="utf-8")
    source.write_text(source_text, encoding="utf-8")

    if header_changed != expected_generated or source_changed != expected_generated:
        raise SystemExit(
            f"incomplete ABI patch: header={len(header_changed)} source={len(source_changed)} "
            f"expected={len(expected_generated)}"
        )
    print(f"patched {len(expected_generated)} generated transactions plus 3 v5 transactions")
    print(f"version={DEVICE_VERSION} hash={DEVICE_HASH}")


if __name__ == "__main__":
    main()
