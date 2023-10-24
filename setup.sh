#!/bin/sh

./clean.sh

mkdir src/api
cd src/api
if which curl &> /dev/null; then
	curl -s -o libBareMetal.asm https://raw.githubusercontent.com/ReturnInfinity/BareMetal/master/api/libBareMetal.asm
else
	wget https://raw.githubusercontent.com/ReturnInfinity/BareMetal/master/api/libBareMetal.asm
fi
cd ../..

mkdir bin

./build.sh
