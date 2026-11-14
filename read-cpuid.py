#!/usr/bin/env python3
"""
Lee CPUID leaf 0x1 del CPU real del host, quita el hypervisor bit
(bit 31 de ECX) y devuelve los valores para VBoxInternal/Devices/0x1/Config/CustomCPUID.

En x86_64 usa mmap ejecutable + ctypes para llamar la instruccion CPUID directamente.
En arm64 (Apple Silicon) no aplica: VirtualBox ARM no usa CPUID leaf 0x1.
"""
import ctypes
import mmap
import os
import sys

def read_cpuid_leaf1():
    machine = os.uname().machine
    if machine not in ("x86_64", "amd64", "x86", "i386", "i686"):
        return None

    # x86_64 System V AMD64 ABI: primer argumento en RDI.
    # push rbx (CPUID clobbera RBX, que es callee-saved)
    # mov eax, 1  (leaf 0x1)
    # xor ecx, ecx (subleaf 0)
    # cpuid
    # mov [rdi], eax
    # mov [rdi+4], ebx
    # mov [rdi+8], ecx
    # mov [rdi+12], edx
    # pop rbx
    # ret
    code = bytes([
        0x53,
        0xB8, 0x01, 0x00, 0x00, 0x00,
        0x31, 0xC9,
        0x0F, 0xA2,
        0x89, 0x07,
        0x89, 0x5F, 0x04,
        0x89, 0x4F, 0x08,
        0x89, 0x57, 0x0C,
        0x5B,
        0xC3,
    ])

    try:
        mem = mmap.mmap(
            -1, 4096,
            prot=mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC,
        )
        mem.write(code)
        c_buf = ctypes.c_char.from_buffer(mem)
        addr = ctypes.addressof(c_buf)
        func_type = ctypes.CFUNCTYPE(None, ctypes.POINTER(ctypes.c_uint32))
        func = func_type(addr)
        result = (ctypes.c_uint32 * 4)()
        func(result)
        mem.close()
        eax, ebx, ecx, edx = result[0], result[1], result[2], result[3]
        ecx &= ~(1 << 31)
        return (eax, ebx, ecx, edx)
    except Exception as e:
        print(f"# Error leyendo CPUID: {e}", file=sys.stderr)
        return None


result = read_cpuid_leaf1()
if result:
    eax, ebx, ecx, edx = result
    print(f"0x{eax:08X},0x{ebx:08X},0x{ecx:08X},0x{edx:08X}")
    sys.exit(0)
else:
    sys.exit(1)