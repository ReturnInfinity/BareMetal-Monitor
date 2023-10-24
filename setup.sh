#!/bin/sh

./clean.sh

mkdir src/api
cd src/api
if [ command -v curl >/dev/null 2>&1 ]; then
	curl -s -o libBareMetal.asm https://raw.githubusercontent.com/ReturnInfinity/BareMetal/master/api/libBareMetal.asm
else
	wget -q https://raw.githubusercontent.com/ReturnInfinity/BareMetal/master/api/libBareMetal.asm
fi
cd ../..

mkdir bin

./build.sh
