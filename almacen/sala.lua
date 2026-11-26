-- Sala de control del almacén (diseno/almacen.md): lo que se ve en sus
-- pantallas. El modelo sale de tools/blender/almacen_interior.py
-- (crearSalaControl) con cinco mallas que se pintan aquí:
--
--   * el muro de pantallas del frente, en tres partes: `pantallaMapa` (las
--     4 de la izquierda, una sola imagen), `pantallaNacion` (arriba a la
--     derecha) y `pantallaArsenal` (abajo a la derecha). Qué enseña cada una
--     se elige desde los ordenadores (programa «Muro», almacen/pc/muro.lua):
--     el mapa 2D de la capital (assets/almacen/mapa_capital.png, una
--     captura fija del mapa del juego), la nación (nombre, capital, poder,
--     nivel, día y los cuatro recursos), los misiles del almacén, los
--     robots, la depuración o la pantalla de un puesto; o una sola cosa en
--     el muro entero. Al empezar: mapa, nación y misiles.
--   * `pantallaPC1`..`pantallaPC6`: el monitor de cada puesto, un ordenador
--     propio con su escritorio y sus programas (almacen/pc/ordenador.lua). Lo
--     que tiene abierto cada uno lo guarda el almacén entre visitas.
--   * `ledsServidores`: cada luz de los armarios es un píxel de una imagen
--     de 32 x 18 que parpadea.
--
-- Todos los datos salen de la partida en vivo por el objeto Almacen
-- (`getMisiles`, `getCapacidad` y `getPartida`): nada está inventado.

local dream = require('lib.3DreamEngine')
local Dibujo = require('almacen.pc.dibujo')
local Guardado = require('almacen.pc.guardado')
local Memoria = require('almacen.memoria')
local Ordenador = require('almacen.pc.ordenador')
local Muro = require('almacen.pc.muro')
local Depuracion = require('almacen.pc.depuracion')
local ApiRobots = require('almacen.pc.api_robots')

local SalaControl = {}
SalaControl.__index = SalaControl

local MAPA = 'assets/almacen/mapa_capital.png'
local LETRA_TITULO = 'assets/fuentes/BarlowCondensed-SemiBold.ttf'
local LETRA_DATO = 'assets/fuentes/JetBrainsMono-SemiBold.ttf'

-- Cada cuánto se vuelven a pintar las pantallas de datos (s) y las luces.
SalaControl.refresco = 0.5
SalaControl.refrescoMuroVivo = 0.1 -- con la pantalla de un puesto o la depuración
SalaControl.refrescoLeds = 0.08
-- Brillo de las pantallas (factor de emisión del motor).
SalaControl.brilloMuro = 1.6
SalaControl.brilloMonitores = 1.8
SalaControl.brilloLeds = 5.0

local LEDS_ANCHO, LEDS_ALTO, LEDS = 32, 18, 560

local VERDE = Dibujo.verde
local COLOR_ESTADO = Dibujo.colorEstado
local TEXTO_ESTADO = Dibujo.textoEstado
local COLOR_RECURSO = Dibujo.colorRecurso
local miles = Dibujo.miles

-- Lo que tiene abierto cada ordenador la primera vez (después, lo que se
-- dejó): cada puesto con lo suyo.
local INICIO_PC = {
    { { 'hoja', 170, 30, 900, 610, { archivo = '/red/almacen/polvorin.hoja' } } },
    { { 'hoja', 220, 60, 820, 540 } },
    { { 'hoja', 150, 40, 980, 560, { archivo = '/red/almacen/recursos.hoja' } } },
    { { 'terminal', 200, 70, 860, 520 } },
    { { 'hoja', 150, 30, 720, 470, { archivo = '/red/almacen/recursos.hoja' } }, { 'terminal', 640, 250, 600, 400 } },
    {},
}

--- Material emisivo con `textura` para todas las mallas de `pieza`.
local function ponerPantalla(pieza, nombre, textura, brillo)
    local material = dream:newMaterial(nombre)
    material:setColor(0.01, 0.01, 0.012, 1)
    material:setRoughness(0.25)
    material:setMetallic(0)
    material:setEmissionTexture(textura)
    material:setEmissionFactor(brillo, brillo, brillo)
    for _, malla in pairs(pieza and pieza.meshes or {}) do
        malla:setMaterial(material)
    end
end

--- `objeto`: el modelo del almacén ya cargado; `almacen`: el de la nación.
function SalaControl.nueva(objeto, almacen)
    local self = setmetatable({}, SalaControl)
    self.almacen = almacen
    self.objetos = objeto.objects
    local g = love.graphics
    -- Las letras a doble densidad: en la parte grande del muro todo sale al
    -- doble y se tiene que leer igual de nítido.
    self.letras = {
        enorme = g.newFont(LETRA_TITULO, 110, 'normal', 2),
        grande = g.newFont(LETRA_TITULO, 64, 'normal', 2),
        titulo = g.newFont(LETRA_TITULO, 40, 'normal', 2),
        medio = g.newFont(LETRA_TITULO, 30, 'normal', 2),
        dato = g.newFont(LETRA_DATO, 20, 'normal', 2),
        chico = g.newFont(LETRA_DATO, 15, 'normal', 2),
    }
    -- Las tres partes del muro (almacen/pc/muro.lua).
    self.muro = {
        grande = g.newCanvas(Muro.partes.grande[3], Muro.partes.grande[4], { mipmaps = 'auto' }),
        arriba = g.newCanvas(Muro.partes.arriba[3], Muro.partes.arriba[4], { mipmaps = 'auto' }),
        abajo = g.newCanvas(Muro.partes.abajo[3], Muro.partes.abajo[4], { mipmaps = 'auto' }),
    }
    -- Los ordenadores de los puestos (lo que se dejó abierto, del almacén).
    -- Si el juego se cerró, lo que quedó guardado (almacen/pc/guardado.lua),
    -- con lo que enseñaba el muro.
    -- Viven en la memoria del almacén de la nación (almacen/memoria.lua),
    -- que se guarda con la partida.
    local memoria = Memoria.de(almacen:getNacion())
    if not memoria.ordenadores then
        local ordenadores, muro = Guardado.leerViejo(almacen, almacen:getSemilla())
        memoria.ordenadores = ordenadores or {}
        memoria.muro = memoria.muro or muro
    end
    memoria.muro = memoria.muro or Muro.porDefecto()
    almacen.ordenadores, almacen.muro = memoria.ordenadores, memoria.muro
    Muro.estado = almacen.muro
    Muro.sala = self
    self.almacen = almacen
    self.ordenadores = {}
    for k = 1, 6 do
        local nuevo = not almacen.ordenadores[k]
        local pc = Ordenador.nuevo(k, almacen.ordenadores[k])
        almacen.ordenadores[k] = pc.datos
        if nuevo then
            for _, v in ipairs(INICIO_PC[k] or {}) do
                pc:abrir(v[1], v[2], v[3], v[4], v[5], v[6])
            end
        end
        self.ordenadores[k] = pc
        ponerPantalla(self.objetos['pantallaPC' .. k], 'pantallaPC' .. k .. 'Viva', pc:getLienzo(), SalaControl.brilloMonitores)
    end
    self.ledsDatos = love.image.newImageData(LEDS_ANCHO, LEDS_ALTO)
    self.leds = g.newImage(self.ledsDatos)
    self.leds:setFilter('nearest', 'nearest')
    self.mapa = g.newImage(MAPA, { mipmaps = true })
    self.mapa:setFilter('linear', 'linear')
    ponerPantalla(self.objetos.pantallaMapa, 'pantallaMapaViva', self.muro.grande, SalaControl.brilloMuro)
    ponerPantalla(self.objetos.pantallaNacion, 'pantallaNacionViva', self.muro.arriba, SalaControl.brilloMuro)
    ponerPantalla(self.objetos.pantallaArsenal, 'pantallaArsenalViva', self.muro.abajo, SalaControl.brilloMuro)
    ponerPantalla(self.objetos.ledsServidores, 'ledsServidoresVivos', self.leds, SalaControl.brilloLeds)
    -- Vidrio de los tabiques: transparente (pasada de alfa del motor), apenas
    -- teñido y sin desviar lo de detrás. Una luna plana y fina no deforma lo
    -- que se ve a través (los dos lados se compensan); con índice 1,5 el motor
    -- lo torcía como un espejo de feria (el dueño, 17-nov). La refracción
    -- queda para lo que sí la tiene: líquidos y vidrios curvos.
    local vidrio = dream:newMaterial('vidrioSalaVivo')
    vidrio:setColor(0.9, 0.97, 0.96, 0.18)
    vidrio:setRoughness(0.03)
    vidrio:setMetallic(0)
    vidrio:setIOR(1.0)
    vidrio:setAlpha()
    for _, malla in pairs(self.objetos.vidriosSala and self.objetos.vidriosSala.meshes or {}) do
        malla:setMaterial(vidrio)
    end
    -- Cada luz: color (0 verde, 1 ámbar, 2 azul, 3 rojo), ritmo y fase.
    local azar = love.math.newRandomGenerator(4242)
    self.luces = {}
    for k = 1, LEDS do
        local columna = (k - 1) % 7
        local color = columna == 0 and 2 or (azar:random() < 0.86 and 0 or (azar:random() < 0.7 and 1 or 3))
        self.luces[k] = { color = color, ritmo = 2 + azar:random() * 10, fase = azar:random() * 10, fijo = columna == 0 or azar:random() < 0.3 }
    end
    self.reloj = 0
    self.proximo = 0
    self.proximoLeds = 0
    self.proximoMuro = 0
    self:pintar()
    self:pintarLeds()
    return self
end

function SalaControl:actualizar(dt)
    self.reloj = self.reloj + dt
    for _, pc in ipairs(self.ordenadores) do
        pc:actualizar(dt)
    end
    if self.reloj >= self.proximo then
        self.proximo = self.reloj + SalaControl.refresco
        self:pintar()
    end
    -- El muro: enseguida si se ha cambiado lo que enseña; a menudo si enseña
    -- algo vivo (la pantalla de un puesto); si no, con los datos.
    if Muro.cambiado or self.reloj >= self.proximoMuro then
        Muro.cambiado = false
        self.proximoMuro = self.reloj + (Muro.esVivo() and SalaControl.refrescoMuroVivo or SalaControl.refresco)
        self:pintarMuro()
    end
    if self.reloj >= self.proximoLeds then
        self.proximoLeds = self.reloj + SalaControl.refrescoLeds
        self:pintarLeds()
    end
end

--- Las mallas de la sala, en el pase de dibujo de la escena (el vidrio, al
-- final, va en la pasada de alfa).
function SalaControl:dibujar()
    local o = self.objetos
    for _, nombre in ipairs({ 'pantallaMapa', 'pantallaNacion', 'pantallaArsenal', 'pantallaPC1', 'pantallaPC2', 'pantallaPC3', 'pantallaPC4', 'pantallaPC5', 'pantallaPC6', 'ledsServidores', 'vidriosSala' }) do
        if o[nombre] then
            dream:draw(o[nombre])
        end
    end
end

function SalaControl:cerrar()
    for _, lienzo in pairs(self.muro) do
        lienzo:release()
    end
    if Muro.sala == self then
        Muro.sala = nil
        Muro.estado = nil
    end
    for _, pc in ipairs(self.ordenadores) do
        pc:cerrar()
    end
end

-- Pintar -----------------------------------------------------------------------

function SalaControl:pintar()
    local partida = self.almacen:getPartida()
    local misiles, capacidad = self.almacen:getMisiles(), self.almacen:getCapacidad()
    self.partida = partida
    self.datosPC = { partida = partida, misiles = misiles, capacidad = capacidad }
    for k in ipairs(self.ordenadores) do
        self:pintarOrdenador(k)
    end
end

--- Deja lo de los ordenadores (ventanas, carpetas personales y muro) en la
-- memoria del almacén, que va con la partida.
function SalaControl:guardarOrdenadores()
    local memoria = Memoria.de(self.almacen:getNacion())
    memoria.ordenadores, memoria.muro = self.almacen.ordenadores, self.almacen.muro
end

--- Vuelve a pintar el ordenador `k` con los datos de la última lectura (el
-- que se está usando se pinta cada cuadro: almacen/pc/uso.lua).
function SalaControl:pintarOrdenador(k)
    local d = self.datosPC or {}
    local ctx = { partida = d.partida, misiles = d.misiles or 0, capacidad = d.capacidad or 0, reloj = self.reloj }
    self.ordenadores[k]:pintar(ctx)
end

local fondo = Dibujo.fondo
local trebol = Dibujo.trebol

-- string.upper no sabe de tildes (UTF-8).
local TILDES = { ['á'] = 'Á', ['é'] = 'É', ['í'] = 'Í', ['ó'] = 'Ó', ['ú'] = 'Ú', ['ñ'] = 'Ñ', ['ü'] = 'Ü' }
local function mayusculas(texto)
    return (texto:upper():gsub('\195[\128-\191]', TILDES))
end

--- Pinta las tres partes del muro con lo que enseña cada una (o la misma
-- fuente repartida por todo el muro).
function SalaControl:pintarMuro()
    local e = Muro.estado or Muro.porDefecto()
    local g = love.graphics
    g.push('all')
    for _, z in ipairs(Muro.zonas) do
        local parte = Muro.partes[z.clave]
        g.setCanvas(self.muro[z.clave])
        g.origin()
        g.clear(0, 0, 0, 1)
        if e.entero then
            -- Su trozo del muro entero.
            g.translate(-parte[1], -parte[2])
            self:pintarFuente(e.todo, Muro.ancho, Muro.alto)
        else
            self:pintarFuente(e[z.clave], parte[3], parte[4])
        end
    end
    g.pop()
end

-- Las pantallas de datos están pensadas a 768 x 436: a otro tamaño se
-- escalan por el alto (y se estiran a lo ancho).
local function aEscala(w, h, f)
    local g = love.graphics
    local s = h / 436
    g.push()
    g.scale(s)
    f(w / s, 436)
    g.pop()
end

--- Pinta la fuente `clave` (almacen/pc/muro.lua) en (0, 0, w, h).
function SalaControl:pintarFuente(clave, w, h)
    local g = love.graphics
    g.setColor(1, 1, 1, 1)
    if clave == 'mapa' then
        -- Que llene la parte entera (recorta lo que sobre).
        local iw, ih = self.mapa:getDimensions()
        local s = math.max(w / iw, h / ih)
        g.draw(self.mapa, (w - iw * s) / 2, (h - ih * s) / 2, 0, s, s)
    elseif clave == 'nacion' then
        aEscala(w, h, function(ew, eh)
            self:pintarNacion(self.partida, ew, eh)
        end)
    elseif clave == 'arsenal' then
        aEscala(w, h, function(ew, eh)
            self:pintarArsenal(self.almacen:getMisiles(), self.almacen:getCapacidad(), ew, eh)
        end)
    elseif clave == 'robots' then
        aEscala(w, h, function(ew, eh)
            self:pintarRobots(ew, eh)
        end)
    elseif clave == 'depuracion' then
        aEscala(w, h, function(ew, eh)
            self:pintarDepuracion(ew, eh)
        end)
    elseif clave and clave:match('^pc%d$') then
        -- La pantalla del puesto tal cual, entera (con bandas si no cabe).
        local pc = self.ordenadores[tonumber(clave:sub(3))]
        fondo(w, h, 0, 0, 0)
        if pc then
            local lienzo = pc:getLienzo()
            local lw, lh = Ordenador.ancho, Ordenador.alto
            local s = math.min(w / lw, h / lh)
            g.setColor(1, 1, 1, 1)
            g.draw(lienzo, (w - lw * s) / 2, (h - lh * s) / 2, 0, s, s)
        end
    else
        fondo(w, h, 0.035, 0.05, 0.055)
    end
end

--- Los robots del almacén: qué ejecuta cada uno, qué está haciendo y dónde.
function SalaControl:pintarRobots(w, h)
    local g = love.graphics
    local L = self.letras
    fondo(w, h, 0.035, 0.05, 0.055)
    g.setColor(0.31, 0.76, 1)
    g.setFont(L.titulo)
    g.print('ROBOTS DEL ALMACÉN', 28, 16)
    local lista = ApiRobots.robots()
    if #lista == 0 then
        g.setColor(0.62, 0.7, 0.74)
        g.setFont(L.dato)
        g.print('No hay robots en el almacén.', 28, 90)
        return
    end
    -- Filas de 150: con dos robots la segunda empieza bajo la junta de las
    -- pantallas grandes (a media altura), no partida por ella.
    local alto = math.min(150, (h - 80) / #lista)
    for k, e in ipairs(lista) do
        local r = e.robot
        local y = 76 + (k - 1) * alto
        local parado = r:getModo() == 'parado'
        local color = parado and { 0.95, 0.72, 0.25 } or VERDE
        g.setColor(color)
        g.rectangle('fill', 28, y + 4, 12, alto - 22)
        g.setColor(1, 1, 1)
        g.setFont(L.medio)
        g.print(mayusculas(e.titulo), 54, y)
        g.setColor(color)
        g.setFont(L.dato)
        g.printf(parado and 'PARADO' or ('EJECUTA ' .. tostring(r:getGuion())), 54, y + 4, w - 82, 'right')
        g.setColor(0.62, 0.7, 0.74)
        g.setFont(L.chico)
        local tarea = r.getTarea and r:getTarea() or nil
        g.print(string.format('x %.1f  y %.1f', r.x or 0, r.y or 0) .. ((tarea and tarea ~= '') and ('   ·   ' .. tostring(tarea)) or ''), 54, y + 42)
    end
end

--- Lo último que han escrito los robots y los programas con print().
function SalaControl:pintarDepuracion(w, h)
    local g = love.graphics
    local L = self.letras
    fondo(w, h, 0.03, 0.035, 0.04)
    g.setColor(0.95, 0.5, 0.42)
    g.setFont(L.titulo)
    g.print('DEPURACIÓN', 28, 12)
    local letra = L.dato
    g.setFont(letra)
    local alto = letra:getHeight() + 4
    local caben = math.floor((h - 70) / alto)
    local lineas = Depuracion.lineas
    local y = 64
    for k = math.max(1, #lineas - caben + 1), #lineas do
        local l = lineas[k]
        local quien = (l.robot or l.puesto or '') .. (l.archivo and (' · ' .. l.archivo .. (l.linea and (':' .. l.linea) or '')) or '')
        g.setColor(0.45, 0.5, 0.52)
        local cabeza = l.hora:sub(4) .. ' [' .. quien .. '] '
        g.print(cabeza, 28, y)
        local color = l.tipo == 'error' and { 1, 0.42, 0.36 } or (l.tipo == 'orden' and { 0.45, 0.8, 0.95 } or (l.tipo == 'resultado' and { 0.5, 0.88, 0.55 } or { 0.88, 0.9, 0.9 }))
        g.setColor(color)
        g.print(l.texto, 28 + letra:getWidth(cabeza), y)
        y = y + alto
    end
    if #lineas == 0 then
        g.setColor(0.45, 0.5, 0.52)
        g.print('Aquí sale lo que escriben con print() los robots y los programas.', 28, y)
    end
end

function SalaControl:pintarNacion(p, w, h)
    local g = love.graphics
    local L = self.letras
    fondo(w, h, 0.035, 0.05, 0.055)
    if not p then
        g.setColor(1, 0.4, 0.3)
        g.setFont(L.titulo)
        g.print('SIN NACIÓN', 28, 28)
        return
    end
    g.setColor(0.91, 0.77, 0.28)
    g.setFont(L.titulo)
    g.printf(p.nacion:upper(), 28, 16, w - 56, 'left')
    g.setColor(0.62, 0.7, 0.74)
    g.setFont(L.dato)
    g.print(string.format('Capital %s · %s hab.', p.capital, miles(p.habitantes)), 28, 70)
    g.print(string.format('Poder %s · Nivel %d · Año %d, día %d', miles(p.poder), p.nivel, p.anio, p.dia), 28, 98)
    for k, r in ipairs(p.recursos) do
        local y = 140 + (k - 1) * 72
        local color = COLOR_RECURSO[r.tipo]
        g.setColor(color)
        g.rectangle('fill', 28, y, 12, 52)
        g.setColor(0.85, 0.89, 0.86)
        g.setFont(L.dato)
        g.print(r.nombre:upper(), 54, y)
        g.setColor(COLOR_ESTADO[r.estado] or VERDE)
        g.setFont(L.chico)
        g.print(TEXTO_ESTADO[r.estado] or '', 54 + L.dato:getWidth(r.nombre:upper()) + 14, y + 4)
        g.setColor(r.cantidad <= 0 and { 1, 0.35, 0.28 } or { 1, 1, 1 })
        g.setFont(L.grande)
        g.printf(miles(r.cantidad), w - 300, y - 14, 272, 'right')
        g.setColor(0.11, 0.15, 0.17)
        g.rectangle('fill', 54, y + 34, w - 360, 12)
        g.setColor(color)
        local f = r.tope and r.tope > 0 and math.min(1, r.cantidad / r.tope) or 0
        g.rectangle('fill', 54, y + 34, (w - 360) * f, 12)
    end
end

function SalaControl:pintarArsenal(misiles, capacidad, w, h)
    local g = love.graphics
    local L = self.letras
    fondo(w, h, 0.035, 0.05, 0.055)
    trebol(56, 52, 26)
    g.setColor(0.31, 0.76, 1)
    g.setFont(L.titulo)
    g.print('ALMACÉN · MISILES', 100, 26)
    g.setColor(misiles == 0 and { 1, 0.35, 0.28 } or { 1, 1, 1 })
    g.setFont(L.enorme)
    g.print(misiles .. ' / ' .. capacidad, 28, 84)
    g.setColor(0.62, 0.7, 0.74)
    g.setFont(L.dato)
    g.print((capacidad - misiles) .. ' huecos libres en el polvorín', 28, 220)
    local columnas = 20
    local cw = (w - 56) / columnas
    for k = 0, capacidad - 1 do
        local c, f = k % columnas, math.floor(k / columnas)
        if k < misiles then
            g.setColor(0.17, 0.54, 0.24)
        else
            g.setColor(0.11, 0.15, 0.17)
        end
        g.rectangle('fill', 28 + c * cw + 2, 262 + f * 38, cw - 5, 30)
    end
    local estado, color
    if misiles == 0 then
        estado, color = '● SIN MISILES: NO SE PUEDE DISPARAR', { 1, 0.3, 0.25 }
    elseif misiles >= capacidad then
        estado, color = '● POLVORÍN LLENO', { 0.31, 0.76, 1 }
    else
        estado, color = '● LISTO PARA CARGAR CAMIONES', VERDE
    end
    local parpadeo = math.floor(self.reloj * 2) % 2 == 0 and 1 or 0.45
    g.setColor(color[1] * parpadeo, color[2] * parpadeo, color[3] * parpadeo)
    g.setFont(L.dato)
    g.print(estado, 28, h - 46)
end

--- Las luces de los servidores: cada una se enciende y se apaga a su ritmo.
function SalaControl:pintarLeds()
    local colores = { { 0.24, 1, 0.42 }, { 1, 0.71, 0 }, { 0.23, 0.63, 1 }, { 1, 0.24, 0.24 } }
    local t = self.reloj
    local d = self.ledsDatos
    for k, luz in ipairs(self.luces) do
        local x, y = (k - 1) % LEDS_ANCHO, math.floor((k - 1) / LEDS_ANCHO)
        local c = colores[luz.color + 1]
        local f = (luz.fijo or math.sin(t * luz.ritmo + luz.fase) > -0.2) and 1 or 0.08
        d:setPixel(x, y, c[1] * f, c[2] * f, c[3] * f, 1)
    end
    self.leds:replacePixels(d)
end

return SalaControl
