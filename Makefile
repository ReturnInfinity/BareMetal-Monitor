
# =============================================================================
# BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
# Copyright (C) 2025 Tom Everett -- see LICENSE.TXT
#
# Version 1.0
# =============================================================================

include mk/build.mk

OBJDIR=bin
SRCDIR=src
BAREMETAL_REPO=https://raw.githubusercontent.com/ReturnInfinity/BareMetal/master

all: apps

apps: $(OBJDIR)/monitor.bin 

$(OBJDIR)/monitor.bin: objdir $(SRCDIR)/monitor.asm $(SRCDIR)/api/libBareMetal.asm
	$(NASM) $(SRCDIR)/monitor.asm -o $(OBJDIR)/monitor.bin -l $(OBJDIR)/monitor-debug.txt -I $(SRCDIR)

$(SRCDIR)/api/libBareMetal.asm:
	curl -s -o $(SRCDIR)/api/libBareMetal.asm $(BAREMETAL_REPO)/api/libBareMetal.asm
clean:
	rm -rf $(OBJDIR)
	rm -f $(SRCDIR)/api/libBareMetal.asm

objdir:
	mkdir -p $(OBJDIR)


