-- Paleta de la interfaz militar, estilo Warpath original
-- (diseno/interfaz-militar.md, §3.2): los colores de diseño en valores de 0
-- a 1. `Tema` y `Acero` la comparten. Hay dos familias que no se mezclan en
-- una misma superficie:
--   - clara (hormigón): perfil, opciones, listas; texto NEGRO;
--   - oliva/caqui translúcida: HUD sobre el mapa; texto BLANCO con contorno.
-- Los estados de las piezas del kit (`assets/ui/indice.lua`, `Indice.paleta`)
-- se leen con `Paleta.kit`.

local Indice = require('assets.ui.indice')

local Paleta = {}

--- Color de un hex «#rrggbb» en valores de 0 a 1.
function Paleta.hex(texto)
    local r = tonumber(texto:sub(2, 3), 16) / 255
    local g = tonumber(texto:sub(4, 5), 16) / 255
    local b = tonumber(texto:sub(6, 7), 16) / 255
    return { r, g, b }
end

local hex = Paleta.hex

--- Color de una entrada de `Indice.paleta` en un estado (`normal`,
-- `resaltado`, `pulsado` o `desactivado`).
function Paleta.kit(nombre, estado)
    return hex(Indice.paleta[nombre][estado or 'normal'])
end

Paleta.colores = {
    -- Familia clara: hormigón.
    hormigon = hex('#c4c4cc'),
    hormigonSombra = hex('#9c9ca4'),
    papel = hex('#e4e4e4'),
    papelBoton = hex('#dcdcdc'),
    papelLinea = hex('#a4a4a4'),
    negro = hex('#181818'),
    tinta = hex('#080808'),
    tintaTenue = hex('#4a4a4a'),
    marino = hex('#242c3c'),
    marinoOscuro = hex('#1c2434'),
    poderMarron = hex('#886848'),
    cabecera = hex('#1c1c1c'),
    tituloClaro = hex('#e8e8e8'),
    -- Familia oliva/caqui (HUD sobre el mapa).
    olivaNegro = hex('#242c14'),
    oliva = hex('#343c2c'),
    olivaClaro = hex('#3c4424'),
    filoOliva = hex('#1c1c14'),
    lineaOliva = hex('#6c7448'),
    caqui = hex('#bcbcb4'),
    caquiFila = hex('#cccccc'),
    hexMetal = hex('#444444'),
    hexMetalClaro = hex('#b4b4b4'),
    hexBorde = hex('#242424'),
    textoHud = hex('#f0f0e8'),
    textoHudTenue = hex('#b8b8a8'),
    textoDesact = hex('#84867e'),
    -- Acentos comunes.
    amarillo = hex('#fcdc64'),
    amarilloDinero = hex('#ecb434'),
    caquiPestana = hex('#c4ac6c'),
    amarilloTinta = hex('#181818'),
    rojo = hex('#c43434'),
    rojoOscuro = hex('#7a1e1e'),
    rojoTexto = hex('#f07060'),
    verde = hex('#84c444'),
    verdeOscuro = hex('#74b434'),
    verdeGalon = hex('#5a9a24'),
    verdeNombre = hex('#74ec6c'),
}

--- Sustitutos de los colores del HUD oscuro cuando un panel va en gris caqui
-- claro con texto negro (`Tema.modoClaro`): cada nombre oscuro apunta al color
-- que se lee sobre `caqui` (#bcbcb4) con contraste de 4,5:1 o más.
Paleta.claro = {
    textoHud = hex('#080808'),
    textoHudTenue = hex('#38382f'),
    textoDesact = hex('#5c5c54'),
    amarillo = hex('#583a00'),
    amarilloDinero = hex('#583a00'),
    rojoTexto = hex('#86100e'),
    verde = hex('#1a4a0a'),
    verdeOscuro = hex('#1a4a0a'),
    olivaNegro = hex('#8e8e86'),
    olivaClaro = hex('#d6d6ce'),
    rojoOscuro = hex('#e2aca4'),
    lineaOliva = hex('#7a7a70'),
    caquiPestana = hex('#5c4a10'),
    filoOliva = hex('#4a4a42'),
}

return Paleta
