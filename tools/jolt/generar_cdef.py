"""Cabecera de JoltC para la FFI de LuaJIT (lib/jolt/joltc_cdef.lua).

    python3 tools/jolt/generar_cdef.py ~/NationsRTS-deps/joltc

Preprocesa JoltC/JoltC.h sin las cabeceras del sistema (LuaJIT ya conoce
stdint/stdbool/stddef) y cambia lo que la FFI de LuaJIT no entiende:
  * enums con tipo base (C23 `enum X: uint8_t {...} X;`) -> enum aparte y
    typedef del tipo base;
  * `alignas(n) T x;` -> `T x __attribute__((aligned(n)));`
  * constantes `const int/float` -> fuera (las de float no caben en cdef;
    se copian a mano a jolt.lua si hacen falta).
"""

import os
import re
import subprocess
import sys
import tempfile

raiz = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else '~/NationsRTS-deps/joltc')
salida = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'lib', 'jolt', 'joltc_cdef.lua')

with tempfile.TemporaryDirectory() as stub:
    for h in ('stdalign.h', 'stdbool.h', 'stddef.h', 'stdint.h'):
        open(os.path.join(stub, h), 'w').close()
    texto = subprocess.run(['gcc', '-E', '-P', '-nostdinc', '-I' + stub, '-I' + raiz, '-D__x86_64__',
                            '-DJPC_OBJECT_LAYER_BITS=16', os.path.join(raiz, 'JoltC', 'JoltC.h')],
                           capture_output=True, text=True, check=True).stdout

texto = re.sub(r'^const \w+ \w+ = .*;$', '', texto, flags=re.M)
texto = re.sub(r'^static (float|double) .*;$', '', texto, flags=re.M)


def enumBase(m):
    nombre, base, cuerpo = m.group(1), m.group(2), m.group(3)
    return 'enum %s_ {%s};\ntypedef %s %s;' % (nombre, cuerpo, base, nombre)


texto = re.sub(r'typedef enum (\w+)\s*:\s*(\w+)\s*\{(.*?)\}\s*\1\s*;', enumBase, texto, flags=re.S)
TAM = {'uint32_t': '4'}
texto = re.sub(r'alignas\((\w+)\)\s+([\w ]+?)\s+(\w+(\[\d+\])?);',
               lambda m: '%s %s __attribute__((aligned(%s)));' % (m.group(2), m.group(3), TAM.get(m.group(1), m.group(1))), texto)
texto = re.sub(r'\n\s*\n+', '\n', texto)
with open(salida, 'w', encoding='utf8') as f:
    f.write('-- Generado por tools/jolt/generar_cdef.py desde JoltC (Jolt Physics 5.6.0): no editar a mano.\n')
    texto += '\nJPC_BroadPhaseLayerInterface *NJ_CapasAmplias(void);\nJPC_ObjectVsBroadPhaseLayerFilter *NJ_FiltroObjetoAmplia(void);\nJPC_ObjectLayerPairFilter *NJ_FiltroObjetos(void);\n'
    f.write('return [[\n' + texto + '\n]]\n')
print('escrito', salida, len(texto.splitlines()), 'líneas')
