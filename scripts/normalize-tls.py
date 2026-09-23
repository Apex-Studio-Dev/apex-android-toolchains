#!/usr/bin/env python3
"""
normalize-tls.py - Ensure ELF PT_TLS segment alignment satisfies Android Bionic requirements.
Bionic on ARM64 strictly aborts if PT_TLS alignment is < 64.
Bionic on ARM32/x86 strictly aborts if PT_TLS alignment is < 32.
This tool traverses a directory and normalizes p_align on all matching ELF binaries.
"""
import os
import sys
import struct

def normalize_elf_tls(filepath: str):
    if not os.path.isfile(filepath) or os.path.islink(filepath):
        return
    try:
        with open(filepath, 'r+b') as f:
            magic = f.read(4)
            if magic != b'\x7fELF':
                return
            ei_class = f.read(1)[0]
            if ei_class == 2:  # 64-bit ELF
                min_align = 64
                f.seek(32)
                e_phoff = struct.unpack('<Q', f.read(8))[0]
                f.seek(54)
                e_phentsize = struct.unpack('<H', f.read(2))[0]
                e_phnum = struct.unpack('<H', f.read(2))[0]
                for i in range(e_phnum):
                    offset = e_phoff + i * e_phentsize
                    f.seek(offset)
                    phdr = f.read(e_phentsize)
                    p_type = struct.unpack('<I', phdr[0:4])[0]
                    if p_type == 7:  # PT_TLS
                        p_align = struct.unpack('<Q', phdr[48:56])[0]
                        if p_align < min_align:
                            f.seek(offset + 48)
                            f.write(struct.pack('<Q', min_align))
                            print(f"[normalize-tls] Adjusted {filepath} PT_TLS alignment: {p_align} -> {min_align}")
            elif ei_class == 1:  # 32-bit ELF
                min_align = 32
                f.seek(28)
                e_phoff = struct.unpack('<I', f.read(4))[0]
                f.seek(42)
                e_phentsize = struct.unpack('<H', f.read(2))[0]
                e_phnum = struct.unpack('<H', f.read(2))[0]
                for i in range(e_phnum):
                    offset = e_phoff + i * e_phentsize
                    f.seek(offset)
                    phdr = f.read(e_phentsize)
                    p_type = struct.unpack('<I', phdr[0:4])[0]
                    if p_type == 7:  # PT_TLS
                        p_align = struct.unpack('<I', phdr[28:32])[0]
                        if p_align < min_align:
                            f.seek(offset + 28)
                            f.write(struct.pack('<I', min_align))
                            print(f"[normalize-tls] Adjusted {filepath} PT_TLS alignment: {p_align} -> {min_align}")
    except Exception:
        pass

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <directory_or_file>", file=sys.stderr)
        sys.exit(1)
    target = sys.argv[1]
    if os.path.isfile(target):
        normalize_elf_tls(target)
    elif os.path.isdir(target):
        for root, _, files in os.walk(target):
            for file in files:
                normalize_elf_tls(os.path.join(root, file))

if __name__ == '__main__':
    main()
