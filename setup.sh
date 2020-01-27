#!/bin/sh

./clean.sh

mkdir src/api
cd src/api
wget -q https://github.com/ReturnInfinity/BareMetal/raw/master/api/libBareMetal.asm 
cd ../..

mkdir bin

./build.sh
