#!/usr/bin/env python3
import hashlib
import struct
import sys
import zlib


def uleb(data, offset):
    value = 0
    shift = 0
    while True:
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, offset
        shift += 7


def read_string(data, string_ids_off, index):
    offset = struct.unpack_from('<I', data, string_ids_off + index * 4)[0]
    _, offset = uleb(data, offset)
    end = data.index(0, offset)
    return data[offset:end].decode('utf-8', errors='replace')


def main():
    source, target = sys.argv[1:3]
    data = bytearray(open(source, 'rb').read())
    if data[:4] != b'dex\n':
        raise SystemExit('not a DEX file')

    string_ids_off = struct.unpack_from('<I', data, 0x3C)[0]
    type_ids_off = struct.unpack_from('<I', data, 0x44)[0]
    method_ids_off = struct.unpack_from('<I', data, 0x5C)[0]
    class_defs_size = struct.unpack_from('<I', data, 0x60)[0]
    class_defs_off = struct.unpack_from('<I', data, 0x64)[0]

    def type_name(index):
        string_index = struct.unpack_from('<I', data, type_ids_off + index * 4)[0]
        return read_string(data, string_ids_off, string_index)

    found = []
    for class_index in range(class_defs_size):
        base = class_defs_off + class_index * 32
        class_idx, class_data_off = struct.unpack_from('<I20xI4x', data, base)
        if type_name(class_idx) != 'LPf/e;' or not class_data_off:
            continue
        cursor = class_data_off
        static_fields, cursor = uleb(data, cursor)
        instance_fields, cursor = uleb(data, cursor)
        direct_methods, cursor = uleb(data, cursor)
        virtual_methods, cursor = uleb(data, cursor)
        for _ in range(static_fields + instance_fields):
            _, cursor = uleb(data, cursor)
            _, cursor = uleb(data, cursor)
        method_index = 0
        for _ in range(direct_methods + virtual_methods):
            diff, cursor = uleb(data, cursor)
            _, cursor = uleb(data, cursor)
            code_off, cursor = uleb(data, cursor)
            method_index += diff
            method_base = method_ids_off + method_index * 8
            _, _, name_idx = struct.unpack_from('<HHI', data, method_base)
            name = read_string(data, string_ids_off, name_idx)
            if name != 'd' or not code_off:
                continue
            registers, ins_size, _, _, _, insns_size = struct.unpack_from('<HHHHII', data, code_off)
            if ins_size == 3 and registers == 7 and insns_size == 93:
                instruction_offset = code_off + 16
                old = struct.unpack_from('<H', data, instruction_offset)[0]
                if old != 0x0071:
                    raise SystemExit(f'unexpected first instruction 0x{old:04x}')
                for unit in range(insns_size):
                    struct.pack_into('<H', data, instruction_offset + unit * 2, 0x0000)
                struct.pack_into('<H', data, instruction_offset, 0x000E)
                found.append((code_off, instruction_offset))

    if len(found) != 1:
        raise SystemExit(f'expected exactly one Pf.e.d target, found {found}')

    data[12:32] = hashlib.sha1(data[32:]).digest()
    struct.pack_into('<I', data, 8, zlib.adler32(data[12:]) & 0xFFFFFFFF)
    with open(target, 'wb') as output:
        output.write(data)
    print(f'patched code_off={found[0][0]} instruction_off={found[0][1]}')
    print(hashlib.sha256(data).hexdigest())


if __name__ == '__main__':
    main()
