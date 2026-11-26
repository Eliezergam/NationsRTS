--- Datos del catálogo de armamento real (diseno/catalogo-armamento.md, §3.1, §3.2 y §3.9).
--
-- Este es el ÚNICO archivo con los nombres visibles de las armas reales
-- (decisión P1 del dueño): el resto del juego guarda y manda por la red la
-- clave interna ('scudb') y lee el nombre de `nombres`. Para cambiar un
-- nombre basta con cambiarlo aquí: las partidas no se rompen.
--
-- Solo robots y lo hecho por el estudio (el dueño, 21-nov): el BM-21 y el
-- HIMARS (camiones con cabina humana) ya no están. Queda un modelo, el camión
-- de 4 misiles con robot conductor; su clave sigue siendo 'scudb' y sus
-- cifras, las del Scud-B que fue (las fórmulas no cambian). Las claves
-- retiradas de partidas viejas cuentan como él (armamento.lua, RETIRADOS).
--
-- Los números de la ficha salen de datos públicos (Wikipedia, consultada el
-- 2026-09-30) tal como los recoge el documento. Los
-- números sueltos (`masa`, `potencia`, `velocidad`...) son los que usan las
-- fórmulas (armamento.lua); los textos (`texto`) son los que enseña la ficha.
--
-- Solo datos: sin funciones, sin LÖVE.

local Catalogo = {}

-- Nombres visibles, por clave interna -------------------------------------------------------------

Catalogo.nombres = {
    scudb = 'Camión de misiles',
    -- Tecnologías de era (§3.4).
    era2 = 'blindaje compuesto',
    era3 = 'control de tiro digital',
    era4 = 'nueva generación',
}

-- Orden del catálogo: es también el orden fijo en que se recorren los modelos.
Catalogo.orden = {
    lanzacohetes = { 'scudb' },
}

-- Lanzacohetes y lanzamisiles (§3.2). `masa` del vehículo en t, `potencia`
-- en hp, `velocidad` en km/h, `proyectiles` por salva, `ojiva` en kg, `cep`
-- en m (nil: sin guiar o no recogido), `alcance` en km (el de referencia de F12).
-- `carga` (de juego): proyectiles que lleva cargados el camión antes de
-- recargar; sin ella, una salva (`proyectiles`).
Catalogo.lanzacohetes = {
    scudb = {
        anio = 1962,
        categoria = 'misiles',
        masa = 37.4,
        potencia = 525, -- motor D-12A-525A (el mismo nombre da 525 hp en otra ficha)
        velocidad = 45, -- ficha del R-17
        tripulacion = 7, -- de juego: robots de la dotación (el taller los cura aparte)
        proyectiles = 1,
        carga = 4, -- de juego (decisión del dueño, 2026-10-02): cuatro misiles en la rampa, de uno en uno
        ojiva = 900, -- de juego: la ficha rusa pide al menos 900 kg de carga útil
        cep = 450,
        alcance = 300,
        -- La ficha del camión del estudio (los números de arriba siguen
        -- siendo los del Scud-B, de Wikipedia: las fórmulas no cambian).
        texto = {
            anio = 'de partida (era 1)',
            tipo = 'Misiles en rampa',
            calibre = 'misil de 0,5 m de diámetro',
            proyectiles = '4 en la rampa, de uno en uno',
            alcance = '300 km',
            precision = 'CEP 450 m',
            ojiva = 'explosiva, 900 kg',
            cadencia = 'uno cada 2,5 s con la rampa arriba',
            vehiculo = 'camión de 8 ruedas sin cabina, 37,4 t, 45 km/h, con robot conductor',
            precio = 'no aplica',
            longitud = 'camión 14 m; misil 8,3 m',
        },
    },
}

return Catalogo
