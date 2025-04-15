
# =============================================================================
# BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
# Copyright (C) 2025 Tom Everett -- see LICENSE.TXT
#
# Version 1.0
# =============================================================================

include mk/build.mk

# curl
ifneq ("/usr/bin/curl,"")
CURL_EXISTS = 1
else
CURL_EXISTS = 0
endif

OBJDIR=bin
SRCDIR=src
BAREMETAL_REPO=https://raw.githubusercontent.com/ReturnInfinity/BareMetal/master

all: apps

apps: $(OBJDIR)/monitor.bin 

$(OBJDIR)/monitor.bin: objdir $(SRCDIR)/monitor.asm $(SRCDIR)/api/libBareMetal.asm
	$(NASM) $(SRCDIR)/monitor.asm -o $(OBJDIR)/monitor.bin -l $(OBJDIR)/monitor-debug.txt -I $(SRCDIR)

$(SRCDIR)/api/libBareMetal.asm:
	mkdir $(SRCDIR)/api
ifeq ($(CURL_EXISTS), 1)
	curl -s -o $(SRCDIR)/api/libBareMetal.asm $(BAREMETAL_REPO)/api/libBareMetal.asm
else
	wget -q $(BAREMETAL_REPO)/api/libBareMetal.asm
	mv libBareMetal.asm $(SRCDIR)/api/
endif
clean:
	rm -rf $(OBJDIR)
	rm -rf $(SRCDIR)/api/

objdir:
	mkdir -p $(OBJDIR)


