
# =============================================================================
# BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
# Copyright (C) 2025 Tom Everett -- see LICENSE.TXT
#
# Version 1.0
# =============================================================================

# requires 'brew install x86_64-elf-gcc'

CC=x86_64-elf-gcc
LD=x86_64-elf-ld
CFLAGS=-c -m64 -nostdlib -nostartfiles -nodefaultlibs -ffreestanding -fomit-frame-pointer -mno-red-zone -fno-builtin -mcmodel=large
LDFLAGS=
NASM=nasm

# objcopy
OBJCOPY=x86_64-elf-objcopy
OBJCOPYFLAGS=-O binary

# strip
STRIP=x86_64-elf-strip
STRIPFLAGS=

# ar
AR=x86_64-elf-ar
ARFLAGS=-crs
