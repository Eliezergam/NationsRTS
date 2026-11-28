-- Comarcas: el mundo físico se genera por cuadrados de 8 x 8 trozos (4096 px
-- de mundo, unos 410 m) en hilos aparte y se sube a la GPU poco a poco.
--
--   · Hilos: uno por núcleo menos el principal (`mundo/obrero.lua`). Generan
--     la comarca entera en datos planos (`mundo/generador.lua`); el hilo
--     principal solo crea las mallas, con un presupuesto de ms por cuadro.
--   · Por delante de la cámara: se pide todo lo que cabe en la vista con el
--     zoom más lejano (aunque se mire de cerca, para que al alejarse ya esté),
--     con un anillo de margen y más margen hacia donde va la cámara. Primero
--     lo que se ve, luego lo más cercano a donde estará la cámara.
--   · Detalle según el zoom: de lejos (menos de 7,5 %), el suelo con la mitad
--     de vértices por lado y cada planta con su silueta sola; de cerca (más de
--     8,5 %), todo; entre medias, un fundido.
--   · Memoria: lo que se sale de la zona se queda (volver es instantáneo) hasta
--     pasar el tope; entonces se descarta lo más antiguo y lejano.
--   · Disco: cada comarca generada se guarda comprimida en
--     `mundo-cache/<versión>/<semilla>/` (los hilos, mientras se juega). Lo
--     descartado, y todo al volver a abrir el juego con esa semilla, se lee de
--     ahí (unos ms) en vez de generarse. Hasta 20 GB por semilla y 50 GB en
--     total (se borran las semillas más antiguas). La versión es la huella
--     del código que genera: si cambia, la caché vieja se borra. No es una
--     partida guardada: se puede borrar sin perder nada.
--
-- Todo sale de la semilla: lo generado es igual en todas las máquinas.

local Generador = require('mundo.generador')
local Ciudades = require('mundo.ciudades')
local Sombreado = require('mundo.sombreado')
local Iso = require('mundo.iso')

local Comarcas = {}
Comarcas.__index = Comarcas

Comarcas.lado = Generador.lado
Comarcas.trozos = Generador.trozos
Comarcas.presupuesto = 4 -- ms por cuadro para subir comarcas a la GPU (jugando)
Comarcas.presupuestoCarga = 40 -- ms por cuadro en la pantalla de carga
Comarcas.presupuestoHuecos = 16 -- ms por cuadro si falta algo a la vista (tras un salto de la cámara)
Comarcas.anticipo = 1.2 -- s de camino por delante que se piden
Comarcas.ampliar = 1.5 -- la zona: la vista del zoom más lejano por 1,5
local GB = 1024 * 1024 * 1024

--- RAM del equipo en bytes (Linux: /proc/meminfo; LÖVE no la da), o nil.
local function ramDelEquipo()
    local ok, archivo = pcall(io.open, '/proc/meminfo', 'r')
    if not ok or not archivo then
        return nil
    end
    local texto = archivo:read('*a') or ''
    archivo:close()
    local kb = tonumber(texto:match('MemTotal:%s*(%d+)%s*kB'))
    return kb and kb * 1024 or nil
end

-- Tope de memoria (mallas y datos): la décima parte de la RAM, entre 2 y 3 GB;
-- 3 GB si no se sabe la RAM. Medido: con más, el proceso pasa de 5 GB y hay
-- más cuadros lentos al presentar (memoria de vídeo); volver a lo descartado
-- cuesta poco porque está en disco.
local ram = ramDelEquipo()
Comarcas.ram = ram
Comarcas.tope = ram and math.max(2 * GB, math.min(3 * GB, ram / 10)) or 3 * GB
Comarcas.disco = true -- caché en disco de lo generado (por semilla)
Comarcas.topeDisco = 20 * GB -- en disco por semilla; pasado, se sigue leyendo pero no se guarda más
Comarcas.topeDiscoTotal = 50 * GB -- entre todas las semillas: se borran las más antiguas
-- Detalle según el zoom: por debajo de `zoomDetalle`, las mallas de lejos;
-- por encima de `zoomDetalleTotal`, las de cerca; entre los dos, el suelo de
-- cerca aparece fundido sobre el de lejos (no se ve el cambio).
Comarcas.zoomDetalle = 0.075 -- el mismo fundido que la capa de cerca (mundo/capas.lua)
Comarcas.zoomDetalleTotal = 0.085
Comarcas.alturaMaxima = 2400 -- px de vista que puede subir algo (montes y árboles) antes de generarlo

local FORMATO_PLANTA = {
    { 'VertexPosition', 'float', 2 },
    { 'VertexColor', 'byte', 4 },
}

-- Hilos, compartidos por todos los mundos de la partida -----------------------------------

local hilos
local version
local limpiado
local pedidos = love.thread.getChannel('mundo.pedidos')
local hechos = love.thread.getChannel('mundo.hechos')
local siguienteMundo = 0

local function arrancarHilos()
    if hilos then
        return hilos
    end
    hilos = {}
    local cuantos = math.max(1, (love.system.getProcessorCount() or 2) - 1)
    for k = 1, cuantos do
        local ok, hilo = pcall(love.thread.newThread, 'mundo/obrero.lua')
        if ok then
            hilo:start()
            hilos[k] = hilo
        end
    end
    return hilos
end

--- Huella del código que genera el mundo: si cambia, lo guardado en disco
-- ya no sirve.
local function versionGenerador()
    if version then
        return version
    end
    local partes = {}
    for _, archivo in ipairs({
        'mundo/generador.lua',
        'mundo/terreno.lua',
        'mundo/ruido.lua',
        'mundo/plantas.lua',
        'mundo/ciudades.lua',
        'mundo/recursos.lua',
        'mundo/iso.lua',
    }) do
        partes[#partes + 1] = love.filesystem.read(archivo) or archivo
    end
    version = love.data.encode('string', 'hex', love.data.hash('md5', table.concat(partes))):sub(1, 12)
    return version
end

-- Borra (en un hilo, para no parar el juego) las cachés de otras versiones
-- del generador y, de las otras semillas, las más viejas hasta que todo junto
-- cabe en `topeTotal`. Dice lo que ocupa la semilla actual.
local LIMPIEZA = [[
require('love.filesystem')
local raiz, version, actual, topeTotal = ...
local function tamano(carpeta)
    local total = 0
    for _, nombre in ipairs(love.filesystem.getDirectoryItems(carpeta)) do
        local info = love.filesystem.getInfo(carpeta .. '/' .. nombre)
        total = total + (info and info.size or 0)
    end
    return total
end
local function borrar(ruta)
    local info = love.filesystem.getInfo(ruta)
    if info and info.type == 'directory' then
        for _, nombre in ipairs(love.filesystem.getDirectoryItems(ruta)) do
            borrar(ruta .. '/' .. nombre)
        end
    end
    love.filesystem.remove(ruta)
end
for _, nombre in ipairs(love.filesystem.getDirectoryItems(raiz)) do
    if nombre ~= version then
        borrar(raiz .. '/' .. nombre)
    end
end
local semillas = {}
local actualBytes = tamano(raiz .. '/' .. version .. '/' .. actual)
local total = actualBytes
for _, nombre in ipairs(love.filesystem.getDirectoryItems(raiz .. '/' .. version)) do
    local ruta = raiz .. '/' .. version .. '/' .. nombre
    local info = love.filesystem.getInfo(ruta)
    if nombre ~= actual and info then
        local bytes = tamano(ruta)
        total = total + bytes
        semillas[#semillas + 1] = { ruta = ruta, fecha = info.modtime or 0, bytes = bytes }
    end
end
table.sort(semillas, function(a, b)
    return a.fecha < b.fecha
end)
for _, s in ipairs(semillas) do
    if total <= topeTotal then
        break
    end
    borrar(s.ruta)
    total = total - s.bytes
end
love.thread.getChannel('mundo.disco'):push({ semilla = actual, bytes = actualBytes })
]]

--- Carpeta de la caché en disco de esta semilla (la crea), o nil.
local function carpetaDisco(semilla)
    if not Comarcas.disco then
        return nil
    end
    local carpeta = 'mundo-cache/' .. versionGenerador() .. '/' .. semilla
    if not love.filesystem.createDirectory(carpeta) then
        return nil
    end
    if not limpiado then
        limpiado = true
        local ok, hilo = pcall(love.thread.newThread, LIMPIEZA)
        if ok then
            hilo:start('mundo-cache', versionGenerador(), tostring(semilla), Comarcas.topeDiscoTotal)
        end
    end
    return carpeta
end

--- Firma de una lista de obras { x, y, r, ... }: la del archivo en disco
-- tiene que ser la misma (si no, sus plantas no se apartan donde toca).
local function firmaObras(obras)
    local partes = {}
    for k = 1, #obras, 3 do
        partes[#partes + 1] = string.format('%.1f,%.1f,%d', obras[k], obras[k + 1], obras[k + 2])
    end
    table.sort(partes)
    return table.concat(partes, ';')
end

--- Índices de los triángulos de una rejilla de `n` x `n` celdas (los mismos
-- para todas las comarcas: se hacen una vez).
local indicesRejilla = {}
local function indices(n)
    if indicesRejilla[n] then
        return indicesRejilla[n]
    end
    local ffi = require('ffi')
    local datos = love.data.newByteData(n * n * 6 * 2)
    local p = ffi.cast('uint16_t*', datos:getFFIPointer())
    local k = 0
    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local a = j * (n + 1) + i
            local b, c, d = a + 1, a + n + 1, a + n + 2
            p[k], p[k + 1], p[k + 2], p[k + 3], p[k + 4], p[k + 5] = a, b, d, a, d, c
            k = k + 6
        end
    end
    indicesRejilla[n] = datos
    return datos
end

function Comarcas.nuevo(mundo)
    local self = setmetatable({}, Comarcas)
    siguienteMundo = siguienteMundo + 1
    self.id = siguienteMundo
    self.mundo = mundo
    self.semilla = mundo.semilla
    self.lista = {} -- 'cx,cy' -> comarca
    self.enVuelo = 0
    self.zonasPedidas = {}
    self.bytes = 0
    self.reloj = 0
    self.medidas = { generadas = 0, deDisco = 0, msHilo = 0, msSubir = 0 }
    self.carpeta = carpetaDisco(self.semilla)
    self.bytesDisco = 0 -- lo guardado en disco de esta semilla (se suma lo que había al saberlo)
    self.hilos = arrancarHilos()
    -- Lo que pidió un mundo anterior (otra semilla) ya no hace falta.
    pedidos:clear()
    -- Sin hilos (no debería pasar), se genera aquí mismo, una por cuadro.
    self.sinHilos = #self.hilos == 0
    if self.sinHilos then
        self.contexto = Generador.contexto(self.semilla)
    end
    return self
end

local function clave(cx, cy)
    return cx .. ',' .. cy
end

--- Caja de la comarca en la vista (con lo que puede subir sobre el suelo).
local function cajaVista(c)
    local l = Comarcas.lado
    local x0, y0 = c.cx * l, c.cy * l
    local arriba = c.hMax and (math.max(c.hMax, 0) * Iso.escalaAltura + 400) or Comarcas.alturaMaxima
    return x0 - y0 - l, (x0 + y0) * 0.5 - arriba, x0 - y0 + l, (x0 + y0) * 0.5 + l
end

local function toca(c, r)
    local ax, ay, bx, by = cajaVista(c)
    return bx > r.x and ax < r.x + r.w and by > r.y and ay < r.y + r.h
end

--- Comarcas (cx, cy) cuya caja puede tocar el rectángulo `r` de la vista.
local function candidatas(r)
    local l = Comarcas.lado
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local abajo = r.y + r.h + Comarcas.alturaMaxima
    for _, e in ipairs({ { r.x, r.y }, { r.x + r.w, r.y }, { r.x, abajo }, { r.x + r.w, abajo } }) do
        local x, y = Iso.mundo(e[1], e[2])
        minX, minY = math.min(minX, x), math.min(minY, y)
        maxX, maxY = math.max(maxX, x), math.max(maxY, y)
    end
    local lista = {}
    for cy = math.floor(minY / l) - 1, math.floor(maxY / l) + 1 do
        for cx = math.floor(minX / l) - 1, math.floor(maxX / l) + 1 do
            local c = { cx = cx, cy = cy }
            if toca(c, r) then
                lista[#lista + 1] = c
            end
        end
    end
    return lista
end

--- La zona que debe estar generada: la vista con el zoom más lejano
-- (`zoomMinimo`) por `ampliar`, centrada en la cámara y corrida hacia donde
-- va (`vx`, `vy` en px de vista por segundo).
function Comarcas.zona(vista, pantallaW, pantallaH, zoomMinimo, vx, vy)
    local w = math.max(vista.w, pantallaW / zoomMinimo) * Comarcas.ampliar
    local h = math.max(vista.h, pantallaH / zoomMinimo) * Comarcas.ampliar
    local cx, cy = vista.x + vista.w / 2, vista.y + vista.h / 2
    local zona = { x = cx - w / 2, y = cy - h / 2, w = w, h = h }
    -- Hacia donde va la cámara, se alarga la zona.
    local ax, ay = (vx or 0) * Comarcas.anticipo, (vy or 0) * Comarcas.anticipo
    if ax < 0 then
        zona.x = zona.x + ax
    end
    zona.w = zona.w + math.abs(ax)
    if ay < 0 then
        zona.y = zona.y + ay
    end
    zona.h = zona.h + math.abs(ay)
    return zona, cx + ax, cy + ay
end

--- Lista de obras (instalaciones y huertos) cerca de la comarca, plana:
-- { x, y, r, ... }. Lo único que no sale de la semilla: las plantas se apartan.
function Comarcas:obras(cx, cy)
    local l = Comarcas.lado
    local m = 512 * 2
    local x0, y0, x1, y1 = cx * l - m, cy * l - m, (cx + 1) * l + m, (cy + 1) * l + m
    local lista = {}
    local sim = self.mundo.sim
    local function poner(x, y, r)
        if x >= x0 and x <= x1 and y >= y0 and y <= y1 then
            lista[#lista + 1] = x
            lista[#lista + 1] = y
            lista[#lista + 1] = r
        end
    end
    for _, i in pairs(sim.estado.instalaciones) do
        poner(i.x, i.y, i.tipo == 'base' and 200 or 170)
    end
    for _, c in pairs(sim.estado.ciudades) do
        if c.huerto then
            poner(c.huerto.x, c.huerto.y, 150)
        end
    end
    return lista
end

--- Pide la comarca a los hilos (o la rehace, si ya estaba: obras nuevas).
function Comarcas:pedir(c)
    local obras = self:obras(c.cx, c.cy)
    c.pedida = true
    self.enVuelo = self.enVuelo + 1
    local pedido = { mundo = self.id, semilla = self.semilla, cx = c.cx, cy = c.cy, obras = obras }
    if self.carpeta then
        pedido.archivo = self.carpeta .. '/' .. c.cx .. '_' .. c.cy .. '.bin'
        pedido.firma = firmaObras(obras)
        -- Pasado el tope del disco se sigue leyendo, pero no se guarda más (lo
        -- primero que se guardó es lo de alrededor de casa).
        pedido.guardar = self.bytesDisco < Comarcas.topeDisco
    end
    if self.sinHilos then
        self.local_ = self.local_ or {}
        self.local_[#self.local_ + 1] = pedido
    else
        pedidos:push(pedido)
    end
end

--- Crea las mallas de lejos de una comarca generada y la explora (ciudades,
-- naciones y yacimientos, como hacía cada trozo al generarse). Las de cerca
-- se crean al acercarse (`detallar`); sus datos se quedan en memoria.
function Comarcas:instalar(r)
    local k = clave(r.cx, r.cy)
    local c = self.lista[k]
    if not c then
        -- Se descartó mientras se generaba: se instala igual (ya está hecha).
        c = { cx = r.cx, cy = r.cy }
        self.lista[k] = c
    end
    self:soltarMallas(c)
    local g = love.graphics
    local n = Generador.celdasLejos
    c.lejos = g.newMesh(Sombreado.formato, (n + 1) * (n + 1), 'triangles', 'static')
    c.lejos:setVertices(r.sueloLejos)
    c.lejos:setVertexMap(indices(n), 'uint16')
    if r.plantasLejos then
        c.plantasLejos = g.newMesh(FORMATO_PLANTA, r.nPlantasLejos, 'triangles', 'static')
        c.plantasLejos:setVertices(r.plantasLejos)
    end
    c.datos = r.suelo -- las alturas, para el territorio y la malla de cerca
    c.datosPlantas, c.nPlantas = r.plantas, r.nPlantas
    c.cuantas = r.cuantas
    c.hMin, c.hMax = r.hMin, r.hMax
    self:sumar(
        c,
        r.suelo:getSize()
            + (r.plantas and r.plantas:getSize() or 0)
            + r.sueloLejos:getSize()
            + indices(n):getSize()
            + (r.plantasLejos and r.plantasLejos:getSize() or 0)
    )
    -- Los datos de lejos ya están en la GPU: se sueltan ya (el recolector de
    -- Lua no sabe lo que ocupan y tardaría en hacerlo).
    r.sueloLejos:release()
    if r.plantasLejos then
        r.plantasLejos:release()
    end
    c.lista, c.pedida = true, false
    self.mundo:explorarComarca(c)
end

--- Suma `bytes` a lo que ocupa la comarca (y al total).
function Comarcas:sumar(c, bytes)
    c.bytes = (c.bytes or 0) + bytes
    self.bytes = self.bytes + bytes
end

--- Mallas de cerca (todo el detalle) de la comarca, a partir de sus datos.
function Comarcas:detallar(c)
    if c.suelo or not c.datos then
        return
    end
    local g = love.graphics
    local n = Generador.celdas
    c.suelo = g.newMesh(Sombreado.formato, (n + 1) * (n + 1), 'triangles', 'static')
    c.suelo:setVertices(c.datos)
    c.suelo:setVertexMap(indices(n), 'uint16')
    if c.datosPlantas then
        c.plantas = g.newMesh(FORMATO_PLANTA, c.nPlantas, 'triangles', 'static')
        c.plantas:setVertices(c.datosPlantas)
    end
    c.bytesCerca = c.datos:getSize() + indices(n):getSize() + (c.datosPlantas and c.datosPlantas:getSize() or 0)
    self:sumar(c, c.bytesCerca)
end

--- Suelta las mallas de cerca (los datos se quedan: se rehacen al volver).
function Comarcas:soltarDetalle(c)
    for _, campo in ipairs({ 'suelo', 'plantas' }) do
        if c[campo] then
            c[campo]:release()
            c[campo] = nil
        end
    end
    if c.bytesCerca then
        self:sumar(c, -c.bytesCerca)
        c.bytesCerca = nil
    end
end

function Comarcas:soltarMallas(c)
    self:soltarDetalle(c)
    for _, campo in ipairs({ 'lejos', 'plantasLejos', 'datos', 'datosPlantas' }) do
        if c[campo] then
            c[campo]:release()
            c[campo] = nil
        end
    end
    if c.bytes then
        self.bytes = self.bytes - c.bytes
        c.bytes = nil
    end
end

--- Con el zoom de cerca (o acercándose a él), las comarcas que se ven tienen
-- su malla de todo el detalle; como mucho `ms` milisegundos por cuadro. Las
-- que llevan un rato sin verse de cerca la sueltan.
function Comarcas:detalle(vista, zoom, ms)
    local inicio = love.timer.getTime()
    if zoom >= Comarcas.zoomDetalle * 0.9 then
        for _, c in ipairs(self:visibles(vista)) do
            c.vistaCerca = self.reloj
            if not c.suelo then
                self:detallar(c)
                if (love.timer.getTime() - inicio) * 1000 > ms then
                    break
                end
            end
        end
    end
    self.cuadros = (self.cuadros or 0) + 1
    if self.cuadros % 30 == 0 then
        for _, c in pairs(self.lista) do
            if c.suelo and self.reloj - (c.vistaCerca or 0) > 10 then
                self:soltarDetalle(c)
            end
        end
    end
end

--- Recoge lo que han hecho los hilos, como mucho `ms` milisegundos (al menos
-- una comarca si hay alguna).
function Comarcas:recibir(ms)
    local inicio = love.timer.getTime()
    if self.sinHilos and self.local_ and #self.local_ > 0 then
        local p = table.remove(self.local_, 1)
        local r = Generador.comarca(self.contexto, p.cx, p.cy, p.obras)
        r.mundo = self.id
        hechos:push(r)
    end
    local disco = love.thread.getChannel('mundo.disco')
    while disco:getCount() > 0 do
        local d = disco:pop()
        if d.semilla == tostring(self.semilla) then
            self.bytesDisco = self.bytesDisco + d.bytes
        end
    end
    while hechos:getCount() > 0 do
        local r = hechos:pop()
        if r.mundo == self.id and r.asegurada then
            local pc = self.precarga
            pc.enVuelo = pc.enVuelo - 1
            pc.hechas = pc.hechas + 1
            if r.generada then
                pc.generadas = pc.generadas + 1
            end
            if r.error then
                print('PRECARGA ' .. r.cx .. ',' .. r.cy .. ': ' .. r.error)
            end
            self.bytesDisco = self.bytesDisco + (r.guardado or 0)
        elseif r.mundo == self.id and r.zona then
            if r.datos then
                self.mundo.zonasHechas[r.zx .. ',' .. r.zy] = r.datos
                self.mundo:sembrarZona(r.zx, r.zy, r.datos, r.ciudades)
            else
                print('ZONA: ' .. tostring(r.error))
            end
        elseif r.mundo == self.id then
            self.enVuelo = self.enVuelo - 1
            if r.error then
                print('COMARCA ' .. r.cx .. ',' .. r.cy .. ': ' .. r.error)
                local c = self.lista[clave(r.cx, r.cy)]
                if c then
                    c.pedida = false
                end
            else
                local antes = love.timer.getTime()
                self:instalar(r)
                self.medidas.generadas = self.medidas.generadas + 1
                if r.disco then
                    self.medidas.deDisco = self.medidas.deDisco + 1
                end
                self.bytesDisco = self.bytesDisco + (r.guardado or 0)
                self.medidas.msHilo = self.medidas.msHilo + (r.ms or 0)
                self.medidas.msSubir = self.medidas.msSubir + (love.timer.getTime() - antes) * 1000
            end
        end
        if (love.timer.getTime() - inicio) * 1000 > ms then
            break
        end
    end
    return (love.timer.getTime() - inicio) * 1000
end

--- Precarga: deja en el disco todas las comarcas a menos de `radio` px del
-- punto (x, y) del mundo, de la más cercana a la más lejana. No se suben a la
-- GPU: al acercarse la cámara se leen del disco en unos ms.
function Comarcas:precargar(x, y, radio)
    local l = Comarcas.lado
    local lista = {}
    if self.carpeta and not self.sinHilos then
        local n = math.ceil(radio / l)
        local cx0, cy0 = math.floor(x / l), math.floor(y / l)
        for cy = cy0 - n, cy0 + n do
            for cx = cx0 - n, cx0 + n do
                local d = ((cx + 0.5) * l - x) ^ 2 + ((cy + 0.5) * l - y) ^ 2
                if d <= radio * radio then
                    lista[#lista + 1] = { cx = cx, cy = cy, d = d }
                end
            end
        end
        table.sort(lista, function(a, b)
            return a.d < b.d
        end)
    end
    self.precarga = { lista = lista, siguiente = 1, hechas = 0, generadas = 0, enVuelo = 0, radio = radio }
end

--- Manda a los hilos más comarcas de la precarga (pocas a la vez, para que
-- lo que pide la cámara no espere detrás).
function Comarcas:avanzarPrecarga()
    local pc = self.precarga
    if not pc then
        return
    end
    local maximo = #self.hilos * 3
    while pc.enVuelo < maximo and pc.siguiente <= #pc.lista do
        local e = pc.lista[pc.siguiente]
        pc.siguiente = pc.siguiente + 1
        local obras = self:obras(e.cx, e.cy)
        pc.enVuelo = pc.enVuelo + 1
        pedidos:push({
            mundo = self.id,
            semilla = self.semilla,
            cx = e.cx,
            cy = e.cy,
            obras = obras,
            asegurar = true,
            archivo = self.carpeta .. '/' .. e.cx .. '_' .. e.cy .. '.bin',
            firma = firmaObras(obras),
            guardar = self.bytesDisco < Comarcas.topeDisco,
        })
    end
end

--- Cuánto de la precarga está hecho: hechas, total.
function Comarcas:progresoPrecarga()
    local pc = self.precarga
    if not pc then
        return 0, 0
    end
    return pc.hechas, #pc.lista
end

--- Pide a los hilos los datos de las naciones de alrededor de las comarcas
-- `lista` (con una de margen por cada lado): al descubrir una ciudad, su
-- nación y las vecinas entran en la simulación sin esperar.
function Comarcas:pedirZonas(lista)
    local lado = Ciudades.porNacion * Ciudades.region
    local l = Comarcas.lado
    local vistas = {}
    for _, c in ipairs(lista) do
        local zx = math.floor((c.cx + 0.5) * l / lado)
        local zy = math.floor((c.cy + 0.5) * l / lado)
        vistas[zx .. ',' .. zy] = { zx, zy }
    end
    for _, z in pairs(vistas) do
        for dy = -1, 1 do
            for dx = -1, 1 do
                local zx, zy = z[1] + dx, z[2] + dy
                local k = zx .. ',' .. zy
                if not self.zonasPedidas[k] then
                    self.zonasPedidas[k] = true
                    if not self.sinHilos then
                        pedidos:push({ mundo = self.id, semilla = self.semilla, zona = true, zx = zx, zy = zy })
                    end
                end
            end
        end
    end
end

--- Pide lo que falta en la zona (lo más urgente primero) y descarta lo que
-- sobra. Devuelve cuántas comarcas de la zona faltan.
function Comarcas:actualizar(vista, zona, px, py, dt)
    self.reloj = self.reloj + (dt or 0)
    local faltan = {}
    local enZona = {}
    local lista = candidatas(zona)
    self:pedirZonas(lista)
    for _, c in ipairs(lista) do
        local k = clave(c.cx, c.cy)
        enZona[k] = true
        local hecha = self.lista[k]
        if hecha then
            hecha.vista = self.reloj
        end
        if not hecha or (not hecha.lista and not hecha.pedida) then
            local l = Comarcas.lado
            local vx, vy = Iso.vista((c.cx + 0.5) * l, (c.cy + 0.5) * l, 0)
            local d = (vx - px) ^ 2 + (vy - py) ^ 2
            -- Lo que ya se ve, antes que nada.
            if toca(c, vista) then
                d = d - 1e18
            end
            faltan[#faltan + 1] = { c = hecha or c, d = d }
        end
    end
    table.sort(faltan, function(a, b)
        return a.d < b.d
    end)
    local maximo = math.max(2, #self.hilos * 2)
    for _, f in ipairs(faltan) do
        if self.enVuelo >= maximo then
            break
        end
        local k = clave(f.c.cx, f.c.cy)
        self.lista[k] = f.c
        f.c.vista = self.reloj
        self:pedir(f.c)
    end
    self:avanzarPrecarga()
    self:descartar(enZona, px, py)
    local pendientes = 0
    for k in pairs(enZona) do
        if not (self.lista[k] and self.lista[k].lista) then
            pendientes = pendientes + 1
        end
    end
    self.pendientes = pendientes
    self.enZona = enZona
    return pendientes
end

--- Pasado el tope de memoria, descarta lo más antiguo y lejano que esté fuera
-- de la zona (nunca lo fijado: tu capital y tus instalaciones). La lista se
-- hace como mucho una vez por segundo y se sueltan con presupuesto de tiempo, para que
-- no haya tirones con miles de comarcas en memoria.
function Comarcas:descartar(enZona, px, py)
    local cola = self.colaDescarte
    if (not cola or #cola == 0) and self.bytes > Comarcas.tope and self.reloj - (self.ultimoDescarte or -1) >= 1 then
        self.ultimoDescarte = self.reloj
        local fijas = self.mundo:comarcasFijas()
        local lista = {}
        local l = Comarcas.lado
        for k, c in pairs(self.lista) do
            if c.lista and not enZona[k] and not fijas[k] then
                local vx, vy = Iso.vista((c.cx + 0.5) * l, (c.cy + 0.5) * l, 0)
                -- Un minuto sin verla cuenta como 20 comarcas de distancia.
                local lejos = math.sqrt((vx - px) ^ 2 + (vy - py) ^ 2) / l
                lista[#lista + 1] = { k = k, c = c, peso = lejos + (self.reloj - (c.vista or 0)) / 3 }
            end
        end
        table.sort(lista, function(a, b)
            return a.peso > b.peso
        end)
        -- Se baja hasta el 85 % del tope.
        cola = {}
        local sobra = self.bytes - Comarcas.tope * 0.85
        for _, e in ipairs(lista) do
            if sobra <= 0 then
                break
            end
            -- Al principio de la cola lo que menos interesa: se saca por el final.
            table.insert(cola, 1, e)
            sobra = sobra - (e.c.bytes or 0)
        end
        self.colaDescarte = cola
    end
    if not cola then
        return
    end
    -- Soltar mallas cuesta (unos 0,4 ms cada una): 1,5 ms por cuadro, y al
    -- menos una comarca (se genera más o menos una por cuadro).
    local inicio = love.timer.getTime()
    while love.timer.getTime() - inicio < 0.0015 do
        local e = table.remove(cola)
        if not e then
            break
        end
        -- Puede haber vuelto a la zona entretanto.
        if self.lista[e.k] == e.c and e.c.lista and not enZona[e.k] then
            self:soltarMallas(e.c)
            self.lista[e.k] = nil
            self.mundo:olvidarComarca(e.c)
        end
    end
end

--- Comarcas listas que se ven en el rectángulo `r` de la vista, de atrás adelante.
function Comarcas:visibles(r)
    local lista = {}
    for _, c in ipairs(candidatas(r)) do
        local hecha = self.lista[clave(c.cx, c.cy)]
        if hecha and hecha.lista and toca(hecha, r) then
            lista[#lista + 1] = hecha
        end
    end
    table.sort(lista, function(a, b)
        if a.cx + a.cy ~= b.cx + b.cy then
            return a.cx + a.cy < b.cx + b.cy
        end
        return a.cx < b.cx
    end)
    return lista
end

--- Comarca lista que contiene el punto (x, y) del mundo, o nil.
function Comarcas:en(x, y)
    local l = Comarcas.lado
    local c = self.lista[clave(math.floor(x / l), math.floor(y / l))]
    return c and c.lista and c or nil
end

--- Cuántas comarcas que tocan el rectángulo `r` de la vista no están listas.
function Comarcas:huecos(r)
    local n = 0
    for _, c in ipairs(candidatas(r)) do
        local hecha = self.lista[clave(c.cx, c.cy)]
        if not (hecha and hecha.lista) then
            n = n + 1
        end
    end
    return n
end

--- Rehace (en los hilos) las comarcas listas alrededor de una obra nueva: sus
-- plantas se apartan. Mientras, se sigue viendo la de antes.
function Comarcas:rehacerCerca(x, y)
    local l = Comarcas.lado
    local m = 512 * 2
    for cy = math.floor((y - m) / l), math.floor((y + m) / l) do
        for cx = math.floor((x - m) / l), math.floor((x + m) / l) do
            local c = self.lista[clave(cx, cy)]
            if c and c.lista and not c.pedida then
                self:pedir(c)
            end
        end
    end
end

--- Cuánto del detalle de cerca se ve con este zoom: 0 nada, 1 todo.
function Comarcas.fundido(zoom)
    local t = (zoom - Comarcas.zoomDetalle) / (Comarcas.zoomDetalleTotal - Comarcas.zoomDetalle)
    return math.max(0, math.min(1, t))
end

return Comarcas
