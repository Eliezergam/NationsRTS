-- Soldado que sube al avión de carga (embarque.lua, el dueño, 20-nov): el
-- soldado de siempre, sin asalto; lo mueve el avión con setIrA.
return {
    base = 'soldado',
    ajustes = {
        conduccion = {
            velocidadSinCarga = 6,
            aceleracionSinCarga = 3,
            giroMaximo = 2.2,
            aceleracionGiro = 5,
            agacharDesde = 3,
        },
        piernasSoldado = { patinador = true },
    },
    'brazosVivos',
}
