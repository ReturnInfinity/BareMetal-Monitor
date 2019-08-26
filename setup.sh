#!/bin/sh

./clean.sh

mkdir src/api
cd src/api
wget https://gitlab.com/ReturnInfinity/BareMetal/raw/master/api/libBareMetal.asm 
cd ../..

mkdir bin

./build.sh
