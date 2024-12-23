#!/usr/bin/env bash

cd src
nasm monitor.asm -o ../bin/monitor.bin -l ../bin/monitor-debug.txt
