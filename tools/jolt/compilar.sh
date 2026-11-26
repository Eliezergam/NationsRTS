#!/bin/sh
# Compila Jolt Physics 5.6.0 + JoltC + las capas de Nations RTS en
# lib/jolt/libjoltc.so y regenera lib/jolt/joltc_cdef.lua.
#   tools/jolt/compilar.sh [~/NationsRTS-deps/joltc]
# Las fuentes: git clone https://github.com/SecondHalfGames/JoltC (con
# submódulos). Modo determinista entre plataformas (servidor futuro).
set -e
J=${1:-$HOME/NationsRTS-deps/joltc}
R=$(cd "$(dirname "$0")/../.." && pwd)
cmake -S "$J" -B "$J/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCROSS_PLATFORM_DETERMINISTIC=ON -DINTERPROCEDURAL_OPTIMIZATION=OFF -DJPH_USE_DX12=OFF -DJPH_USE_VK=OFF -DJPH_USE_MTL=OFF
nice cmake --build "$J/build" -j6
g++ -std=c++17 -x c++ -O2 -fPIC -c "$R/tools/jolt/capas.c" -I"$J" -DJPC_OBJECT_LAYER_BITS=16 -o "$J/build/capas.o"
g++ -shared -o "$R/lib/jolt/libjoltc.so" "$J/build/capas.o" -Wl,--whole-archive "$J/build/libjoltc.a" -Wl,--no-whole-archive "$J/build/JoltPhysics/Build/libJolt.a" -lpthread
strip "$R/lib/jolt/libjoltc.so"
cp "$J/JoltPhysics/LICENSE" "$R/lib/jolt/LICENSE-JoltPhysics"
python3 "$R/tools/jolt/generar_cdef.py" "$J"
echo "listo: $R/lib/jolt/libjoltc.so"
