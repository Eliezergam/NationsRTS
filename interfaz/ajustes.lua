-- Ajustes del jugador (diseno/interfaz-militar.md, §5.15): calidad gráfica,
-- pantalla, sincronización vertical, FPS, sombras, oclusión y volúmenes.
-- Se guardan en `ajustes.lua` (love.filesystem) y se leen al arrancar; el
-- argumento `--calidad` de la línea de comandos gana sobre el archivo.
--
-- Solo son preferencias de esta máquina: no tocan la simulación ni viajan por
-- la red.

local Calidad = require('batalla.dream.calidad')

local Ajustes = {}

local ARCHIVO = 'ajustes.lua'

-- Niveles de calidad de fábrica, sin las sombras ni la oclusión del jugador.
local originales = {}

--- Valores de fábrica («Restablecer»).
Ajustes.fabrica = {
    calidad = 'alta',
    ancho = nil, -- nil: la resolución del monitor
    alto = nil,
    pantallaCompleta = true,
    vsync = true,
    mostrarFps = false,
    sombras = true,
    oclusion = true,
    volumen = 1,
    efectos = 1,
}

local ORDEN = {
    'calidad',
    'ancho',
    'alto',
    'pantallaCompleta',
    'vsync',
    'mostrarFps',
    'sombras',
    'oclusion',
    'volumen',
    'efectos',
}

--- Nivel de calidad de la tabla de niveles por su nombre.
Ajustes.niveles = { 'baja', 'media', 'alta' }

--- Copia de una tabla de valores.
function Ajustes.copiar(v)
    local c = {}
    for _, k in ipairs(ORDEN) do
        c[k] = v[k]
    end
    return c
end

-- Valores en uso.
Ajustes.valores = Ajustes.copiar(Ajustes.fabrica)

--- Lee el archivo de ajustes (si existe y es válido) sobre los de fábrica.
function Ajustes.cargar()
    Ajustes.valores = Ajustes.copiar(Ajustes.fabrica)
    if not love.filesystem.getInfo(ARCHIVO) then
        return Ajustes.valores
    end
    local texto = love.filesystem.read(ARCHIVO)
    local trozo = texto and loadstring and loadstring(texto) or (texto and load(texto))
    if not trozo then
        return Ajustes.valores
    end
    setfenv(trozo, {})
    local ok, tabla = pcall(trozo)
    if not ok or type(tabla) ~= 'table' then
        return Ajustes.valores
    end
    for _, k in ipairs(ORDEN) do
        local v = tabla[k]
        if type(v) == type(Ajustes.fabrica[k]) or (Ajustes.fabrica[k] == nil and type(v) == 'number') then
            Ajustes.valores[k] = v
        end
    end
    if not Calidad.niveles[Ajustes.valores.calidad] then
        Ajustes.valores.calidad = Ajustes.fabrica.calidad
    end
    -- A pantalla completa siempre se usa la resolución del monitor.
    if Ajustes.valores.pantallaCompleta then
        Ajustes.valores.ancho, Ajustes.valores.alto = nil, nil
    end
    return Ajustes.valores
end

--- Guarda los ajustes.
function Ajustes.guardar(v)
    local lineas = { 'return {' }
    for _, k in ipairs(ORDEN) do
        if v[k] ~= nil then
            local valor = type(v[k]) == 'string' and string.format('%q', v[k]) or tostring(v[k])
            lineas[#lineas + 1] = string.format('    %s = %s,', k, valor)
        end
    end
    lineas[#lineas + 1] = '}'
    return love.filesystem.write(ARCHIVO, table.concat(lineas, '\n') .. '\n')
end

--- Resoluciones que ofrece el sistema, de menor a mayor (sin repetir), y la
-- actual si no está entre ellas.
function Ajustes.resoluciones()
    local vistas, lista = {}, {}
    local function poner(ancho, alto)
        local clave = ancho .. 'x' .. alto
        if not vistas[clave] and ancho >= 1024 then
            vistas[clave] = true
            lista[#lista + 1] = { ancho = ancho, alto = alto }
        end
    end
    for _, m in ipairs(love.window.getFullscreenModes()) do
        poner(m.width, m.height)
    end
    poner(love.graphics.getDimensions())
    -- De mayor a menor: si la lista no cabe entera, se cortan las pequeñas.
    table.sort(lista, function(a, b)
        if a.ancho ~= b.ancho then
            return a.ancho > b.ancho
        end
        return a.alto > b.alto
    end)
    return lista
end

--- ¿Los sombreados y la oclusión son los del nivel? Si no, «Personalizada».
function Ajustes.personalizada(v)
    local nivel = originales[v.calidad] or Calidad.niveles[v.calidad]
    return nivel ~= nil and (v.oclusion ~= nivel.ao or v.sombras ~= true)
end

--- Rellena sombras y oclusión con los valores de un nivel de calidad.
function Ajustes.alNivel(v, nombre)
    local nivel = originales[nombre] or Calidad.niveles[nombre]
    if nivel then
        v.calidad = nombre
        v.sombras = true
        v.oclusion = nivel.ao
    end
end

--- Pone en marcha los valores: calidad de la batalla, volumen y, si
-- `conVentana`, el modo de ventana. Devuelve nil si va bien o el motivo del
-- fallo (entonces vuelve a la ventana de antes).
function Ajustes.aplicar(v, conVentana)
    -- Sombras y oclusión propias sobre el nivel elegido: se cambia una copia y
    -- la tabla de niveles conserva el nombre (`Calidad.nombre` sigue siendo
    -- baja, media o alta). Los niveles de fábrica se guardan la primera vez.
    for nombre, nivel in pairs(Calidad.niveles) do
        if not originales[nombre] then
            originales[nombre] = nivel
        end
    end
    local base = originales[v.calidad]
    local nivel = base
    if v.oclusion ~= base.ao or not v.sombras then
        nivel = {}
        for k, valor in pairs(base) do
            nivel[k] = valor
        end
        nivel.ao = v.oclusion
        if not v.sombras then
            nivel.sombra = 5
        end
    end
    Calidad.niveles[v.calidad] = nivel
    Calidad.elegir(v.calidad)
    love.audio.setVolume(math.max(0, math.min(1, v.volumen)))
    Ajustes.mostrarFps = v.mostrarFps
    Ajustes.volumenEfectos = v.efectos
    if not conVentana then
        return nil
    end
    local ancho, alto, banderas = love.window.getMode()
    local anchoMonitor, altoMonitor = love.window.getDesktopDimensions(banderas.display)
    -- En Wayland un juego no puede cambiar la resolución real del monitor:
    -- a pantalla completa siempre se usa la del monitor, sin bordes, y las
    -- demás resoluciones son tamaños de ventana (el dueño, 2026-09-30).
    local nuevoAncho, nuevoAlto = v.ancho or anchoMonitor, v.alto or altoMonitor
    if v.pantallaCompleta then
        nuevoAncho, nuevoAlto = anchoMonitor, altoMonitor
    end
    local tipo = 'desktop'
    local igual = nuevoAncho == ancho
        and nuevoAlto == alto
        and (banderas.fullscreen == v.pantallaCompleta)
        and (not v.pantallaCompleta or banderas.fullscreentype == tipo)
        and ((banderas.vsync ~= 0) == v.vsync)
    if igual then
        return nil
    end
    local ok = love.window.setMode(nuevoAncho, nuevoAlto, {
        fullscreen = v.pantallaCompleta,
        fullscreentype = tipo,
        vsync = v.vsync and 1 or 0,
        resizable = true,
        msaa = banderas.msaa,
        depth = banderas.depth,
    })
    if not ok then
        love.window.setMode(ancho, alto, banderas)
        return 'No se pudo cambiar la ventana; se dejó como estaba.'
    end
    return nil
end

Ajustes.mostrarFps = false
Ajustes.volumenEfectos = 1

return Ajustes
