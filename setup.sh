#!/bin/sh

./clean.sh

mkdir src/api
cd src/api
curl -s -o libBareMetal.asm https://raw.githubusercontent.com/ReturnInfinity/BareMetal/master/api/libBareMetal.asm
cd ../..

mkdir bin

./build.sh
