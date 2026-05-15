
# =============================================================================
# BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
# Copyright (C) 2025 Tom Everett -- see LICENSE.TXT
#
# Version 1.0
# =============================================================================

# detect build platform
UNAME := $(shell uname)
ifeq ($(UNAME),Darwin)
include mk/gcc-i386-darwin.mk
else
include mk/gcc-i386-linux.mk
endif