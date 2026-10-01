#!/usr/bin/env python3
import struct
import subprocess
import sys
from pathlib import Path

BAD_SYMBOLS = ("Dl_", "copyString", "msvcrt", "fwrite", "fflush", "exit", "strlen")


def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]
def u64(b, o): return struct.unpack_from('<Q', b, o)[0]


def rva_to_file(sections, rva):
    for name, va, vsz, raw, rawsz in sections:
        size = max(vsz, rawsz)
        if va <= rva < va + size:
            return raw + (rva - va)
    return None


def verify(path: Path):
    data = path.read_bytes()
    if data[:2] != b'MZ':
        raise SystemExit(f'{path}: not MZ')
    pe = u32(data, 0x3c)
    if data[pe:pe+4] != b'PE\0\0':
        raise SystemExit(f'{path}: not PE')
    machine = u16(data, pe + 4)
    if machine != 0x8664:
        raise SystemExit(f'{path}: not AMD64')
    nsec = u16(data, pe + 6)
    opt_size = u16(data, pe + 20)
    opt = pe + 24
    if u16(data, opt) != 0x20B:
        raise SystemExit(f'{path}: not PE32+')
    entry = u32(data, opt + 16)
    image_base = u64(data, opt + 24)
    dd = opt + 112
    import_rva, import_size = u32(data, dd + 8), u32(data, dd + 12)
    delay_rva, delay_size = u32(data, dd + 13*8), u32(data, dd + 13*8 + 4)
    sec_off = opt + opt_size
    sections = []
    for i in range(nsec):
        o = sec_off + i * 40
        name = data[o:o+8].split(b'\0', 1)[0].decode('ascii', 'replace')
        vsz = u32(data, o + 8)
        va = u32(data, o + 12)
        rawsz = u32(data, o + 16)
        raw = u32(data, o + 20)
        sections.append((name, va, vsz, raw, rawsz))
    text = next((s for s in sections if s[0] == '.text'), None)
    if text is None:
        raise SystemExit(f'{path}: missing .text')
    if entry != text[1]:
        raise SystemExit(f'{path}: entry RVA {entry:#x} is not start of .text {text[1]:#x}')
    if import_rva or import_size:
        raise SystemExit(f'{path}: import directory not empty rva={import_rva:#x} size={import_size:#x}')
    if delay_rva or delay_size:
        raise SystemExit(f'{path}: delay import directory not empty rva={delay_rva:#x} size={delay_size:#x}')
    print(f'{path}: OK PE32+ AMD64 zero-import entry=.text image_base={image_base:#x}')

    try:
        objdump = subprocess.check_output(['x86_64-w64-mingw32-objdump', '-p', str(path)], text=True, errors='replace')
        dll_lines = [line for line in objdump.splitlines() if 'DLL Name:' in line]
        if dll_lines:
            raise SystemExit(f'{path}: objdump found DLL imports: {dll_lines}')
    except FileNotFoundError:
        pass

    try:
        nm = subprocess.check_output(['x86_64-w64-mingw32-nm', str(path)], text=True, stderr=subprocess.STDOUT, errors='replace')
        bad = [line for line in nm.splitlines() if any(sym in line for sym in BAD_SYMBOLS)]
        if bad:
            raise SystemExit(f'{path}: bad symbols found:\n' + '\n'.join(bad[:20]))
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit('usage: verify_pe.py <exe> [<exe>...]')
    for arg in sys.argv[1:]:
        verify(Path(arg))
