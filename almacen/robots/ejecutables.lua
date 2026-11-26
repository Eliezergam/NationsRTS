-- Los ejecutables que trae el juego para los robots (el dueño, 26-nov): lo
-- que hacían de siempre, como un guion más que se ejecuta desde los
-- ordenadores de la sala. Cada uno pone en marcha especializaciones de
-- trabajo del robot (las de `trabajo = { ... }` en su tipo); un robot puede
-- ejecutar los que tienen todas sus especializaciones en su lista.
--
-- Se ven en /red/almacen/guiones/ (solo lectura: al abrirlos se ve el código
-- de la especialización) y en el programa Robots, junto a los de ~/guiones.
-- Al entrar en el almacén, cada robot ejecuta el primero que le sirve.

return {
    {
        archivo = 'trabajar.lua',
        descripcion = 'el robot del almacén guarda y ordena lo que llega al patio',
        especializaciones = { 'almacenaje' },
    },
    {
        archivo = 'practicar.lua',
        descripcion = 'el soldado explora la nave, practica yendo a sitios y dispara a los blancos',
        especializaciones = { 'exploracion', 'practicaSoldado', 'combate' },
    },
}
