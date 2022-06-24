#!/bin/sh

set -xe

# LLVM_VERSION="11.1.0"
LLVM_VERSION="13.0.0"
CLANG="$HOME/opt/clang+llvm-${LLVM_VERSION}-x86_64-linux-gnu-ubuntu-16.04/bin/clang"
WASMLD="$HOME/opt/clang+llvm-${LLVM_VERSION}-x86_64-linux-gnu-ubuntu-16.04/bin/wasm-ld"
WASM2WAT="$HOME/opt/wabt-1.0.29/bin/wasm2wat"
WAT2WASM="$HOME/opt/wabt-1.0.29/bin/wat2wasm"

$CLANG --target=wasm32 -c ./.build/wasm-jai_0_w3.ll
$WASM2WAT ./wasm-jai_0_w3.o > wasm-jai_0_w3.wat
$WAT2WASM -r wasm-jai_0_w3.wat -o wasm-jai_0_w3_fixed.o
$WASM2WAT ./wasm-jai_0_w3_fixed.o > wasm-jai_0_w3_fixed.wat
$WASMLD -m wasm32 --no-entry --export-all --allow-undefined wasm-jai_0_w3_fixed.o -o main.wasm
$WASM2WAT ./main.wasm > main.wat
$WAT2WASM main.wat -o main_fixed.wasm
