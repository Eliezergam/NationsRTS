-- La partida en un solo archivo (el dueño, 26-nov: «autoguardado»; antes el
-- mundo iba en `partida.lua` solo con F5 y el almacén y los ordenadores en
-- archivos aparte, que se guardaban solos: al abrir el juego el mundo
-- empezaba de cero y el almacén seguía como estaba).
--
-- `partida.lua` tiene ahora:
--
--   formato     2
--   sim         el mundo vivo (Simulacion:datosGuardado): lo único que manda
--               en el juego y lo único que viajará por la red
--   secciones   lo demás de la partida que no es simulación, una por sistema
--               (el almacén 3D de cada nación, el jugador...): cada sistema
--               se registra con `Partida.registrar(nombre, guardar, cargar)`
--
-- Todo se escribe con el serializador de la simulación (claves en orden fijo)
-- y se lee sin acceso a nada. Al escribir se usa un archivo nuevo y se cambia
-- de nombre al final, y el guardado anterior queda como `partida.anterior.lua`:
-- un corte a mitad no deja la partida rota.
--
-- Un guardado viejo (formato 1: solo el mundo) se lee igual, sin secciones.

local Simulacion = require('mundo.simulacion')

local Partida = {}

Partida.archivo = 'partida.lua'
Partida.anterior = 'partida.anterior.lua'
Partida.formato = 2

local secciones = {} -- { nombre, guardar, cargar } en el orden en que se registran

--- Registra una sección: `guardar()` devuelve sus datos (tablas, textos,
-- números y booleanos; las claves que empiezan por '_' y las funciones no se
-- guardan) y `cargar(datos)` los pone; `datos` es nil en una partida nueva o
-- en un guardado que no la tenía.
function Partida.registrar(nombre, guardar, cargar)
    for _, s in ipairs(secciones) do
        if s.nombre == nombre then
            s.guardar, s.cargar = guardar, cargar
            return
        end
    end
    secciones[#secciones + 1] = { nombre = nombre, guardar = guardar, cargar = cargar }
end

-- Copia solo con datos: sin funciones, objetos de LÖVE ni claves '_...', y
-- los números que no se pueden volver a leer (inf, nan) como 0.
local function limpiar(v)
    local t = type(v)
    if t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then
            return 0
        end
        return v
    elseif t == 'string' or t == 'boolean' then
        return v
    elseif t ~= 'table' then
        return nil
    end
    local copia = {}
    for k, x in pairs(v) do
        local tk = type(k)
        if tk == 'number' or (tk == 'string' and k:sub(1, 1) ~= '_') then
            copia[k] = limpiar(x)
        end
    end
    return copia
end

--- El texto de la partida de `sim` con todas las secciones.
function Partida.texto(sim)
    local datos = { formato = Partida.formato, sim = sim:datosGuardado(), secciones = {} }
    for _, s in ipairs(secciones) do
        datos.secciones[s.nombre] = limpiar(s.guardar())
    end
    return 'return ' .. Simulacion.serializar(datos) .. '\n'
end

--- Escribe la partida de `sim`. Devuelve true, o false y el motivo.
function Partida.guardar(sim)
    local bien, texto = pcall(Partida.texto, sim)
    if not bien then
        return false, texto
    end
    local nuevo = Partida.archivo .. '.nuevo'
    local escrito, motivo = love.filesystem.write(nuevo, texto)
    if not escrito then
        return false, motivo
    end
    -- Cambio de nombre en el disco (LÖVE no lo trae): primero se aparta el
    -- guardado de antes y luego el nuevo ocupa su sitio.
    local carpeta = love.filesystem.getSaveDirectory() .. '/'
    if love.filesystem.getInfo(Partida.archivo) then
        os.remove(carpeta .. Partida.anterior)
        os.rename(carpeta .. Partida.archivo, carpeta .. Partida.anterior)
    end
    local bien2, motivo2 = os.rename(carpeta .. nuevo, carpeta .. Partida.archivo)
    if not bien2 then
        return false, motivo2
    end
    return true
end

--- Los datos del guardado, como tabla, o nil y el motivo.
function Partida.datos()
    local texto = love.filesystem.read(Partida.archivo)
    if not texto then
        return nil, 'no hay partida guardada'
    end
    local trozo, err = loadstring(texto, 'partida')
    if not trozo then
        return nil, err
    end
    setfenv(trozo, {})
    local bien, datos = pcall(trozo)
    if not bien or type(datos) ~= 'table' then
        return nil, bien and 'partida sin datos' or datos
    end
    if datos.formato ~= Partida.formato then
        -- Formato 1 (un F5 de antes): el archivo era solo el mundo. Se
        -- carga con F9, pero no se sigue solo al abrir el juego.
        datos = { formato = Partida.formato, sim = datos, secciones = {}, viejo = true }
    end
    return datos
end

--- La semilla de la partida que se sigue al abrir el juego (la del
-- autoguardado), o nil si no hay o es un guardado de antes.
function Partida.semilla()
    local datos = Partida.datos()
    return datos and not datos.viejo and datos.sim and datos.sim.semilla or nil
end

--- Lee la partida guardada: la simulación (con `opciones` de
-- Simulacion.cargar) y una función que pone las secciones (se llama cuando
-- la simulación ya es la del juego). nil y el motivo si no se puede.
function Partida.cargar(opciones)
    local datos, motivo = Partida.datos()
    if not datos then
        return nil, motivo
    end
    local sim, err = Simulacion.desdeEstado(datos.sim, opciones)
    if not sim then
        return nil, err
    end
    return sim, function()
        for _, s in ipairs(secciones) do
            s.cargar(datos.secciones[s.nombre])
        end
    end
end

--- Partida nueva: cada sección empieza vacía.
function Partida.nueva()
    for _, s in ipairs(secciones) do
        s.cargar(nil)
    end
end

return Partida
