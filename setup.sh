#!/bin/sh

./clean.sh

mkdir src/api
cd src/api
curl -s -o libBareMetal.asm https://github.com/ReturnInfinity/BareMetal/raw/master/api/libBareMetal.asm 
cd ../..

mkdir bin

./build.sh
