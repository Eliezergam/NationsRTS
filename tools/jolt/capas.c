/* Capas de colisión de Nations RTS para Jolt (lib/jolt/libjoltc.so).
 *
 * Jolt llama a estas funciones desde sus hilos de trabajo: no pueden ser
 * callbacks de Lua (LuaJIT no admite que otro hilo entre en Lua), así que
 * van en C dentro de la biblioteca. Capas: 0 = fijo (terreno, troncos,
 * rocas), 1 = móvil suelto (cajas, restos), 2 o más = las piezas de un robot
 * (una capa por robot: sus piezas no chocan entre sí, como un grupo). Lo
 * fijo solo choca con lo móvil; lo móvil con todo, salvo consigo mismo.
 */
#include "JoltC/JoltC.h"

#ifdef __cplusplus
extern "C" {
#endif

static unsigned int numCapas(const void *self) { (void)self; return 2; }
static JPC_BroadPhaseLayer capaAmplia(const void *self, JPC_ObjectLayer capa) { (void)self; return capa == 0 ? 0 : 1; }
static bool objetoContraAmplia(const void *self, JPC_ObjectLayer a, JPC_BroadPhaseLayer b) { (void)self; return a == 0 ? b == 1 : true; }
static bool objetoContraObjeto(const void *self, JPC_ObjectLayer a, JPC_ObjectLayer b) {
    (void)self;
    if (a == 0 || b == 0) return a != b;
    return !(a == b && a >= 2);
}

JPC_BroadPhaseLayerInterface *NJ_CapasAmplias(void) {
    JPC_BroadPhaseLayerInterfaceFns f = { numCapas, capaAmplia };
    return JPC_BroadPhaseLayerInterface_new(0, f);
}
JPC_ObjectVsBroadPhaseLayerFilter *NJ_FiltroObjetoAmplia(void) {
    JPC_ObjectVsBroadPhaseLayerFilterFns f = { objetoContraAmplia };
    return JPC_ObjectVsBroadPhaseLayerFilter_new(0, f);
}
JPC_ObjectLayerPairFilter *NJ_FiltroObjetos(void) {
    JPC_ObjectLayerPairFilterFns f = { objetoContraObjeto };
    return JPC_ObjectLayerPairFilter_new(0, f);
}

#ifdef __cplusplus
}
#endif
