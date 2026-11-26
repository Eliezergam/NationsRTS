-- Índice de los modelos 3D del catálogo de armamento (diseno/catalogo-armamento.md).
--
-- Clave interna del catálogo -> su modelo. En el juego solo hay robots y lo
-- hecho por el estudio (el dueño, 21-nov): los tanques, el BM-21, el HIMARS y
-- el camión de cabina humana sacados del pack Synty ya no están (su historia,
-- en git). El único vehículo es el camión de 4 misiles con robot conductor,
-- un robot más de robots/nucleo.lua (tipo `camionMisiles`,
-- batalla/robots/tipos/camionMisiles.lua).
--
--   robot      el tipo de robot que lo dibuja y lo mueve
--   archivo    sin extensión: `<archivo>.glb` (las piezas, en metros) y
--              `<archivo>_piezas.lua` (padre y matriz de reposo de cada pieza)
--   misil      la pieza del .glb que se dibuja como misil en vuelo (su origen
--              es su cola; batalla/dream/efectos/misiles.lua)
--   largo, ancho, alto   metros (las del .glb en reposo)
--
-- `nombre` sale del archivo de datos del catálogo
-- (mundo/simulacion/catalogoArmamento.lua).

local Datos = require('mundo.simulacion.catalogoArmamento')

local Catalogo = {}

Catalogo.modelos = {
    -- La clave interna sigue siendo 'scudb' (las partidas guardadas la usan).
    scudb = {
        tipo = 'camion',
        robot = 'camionMisiles',
        archivo = 'assets/batalla/robots/camionMisiles',
        misil = 'misilExteriorDerecho',
        largo = 11.21,
        ancho = 3.74,
        alto = 4,
    },
}

-- Nombre visible de cada modelo: del archivo de datos del catálogo, nunca
-- escrito aquí.
for clave, entrada in pairs(Catalogo.modelos) do
    entrada.nombre = Datos.nombres[clave] or clave
end

--- Entrada del modelo de la clave `clave` (nil si no tiene modelo propio).
function Catalogo.modelo(clave)
    return Catalogo.modelos[clave]
end

return Catalogo
