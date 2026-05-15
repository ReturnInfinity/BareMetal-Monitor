
# =============================================================================
# BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
# Copyright (C) 2025 Tom Everett -- see LICENSE.TXT
#
# Version 1.0
# =============================================================================

CC=gcc
LD=ld
CFLAGS=-c -m64 -nostdlib -nostartfiles -nodefaultlibs -ffreestanding -fomit-frame-pointer -mno-red-zone -fno-builtin
LDFLAGS=
NASM=nasm

# objcopy
OBJCOPY=objcopy
OBJCOPYFLAGS=-O binary

# strip
STRIP=strip
STRIPFLAGS=


# ar
AR=ar
ARFLAGS=-crs
