-- Sistema de archivos de los ordenadores de la sala de control.
--
-- Hay dos partes, como en una oficina de verdad:
--   * `/red/almacen/`: la unidad de red, la misma en todos los puestos. Sus
--     archivos los escribe la partida en vivo (como /proc en Linux): al
--     abrir `polvorin.hoja` se ve lo que hay ahora en el polvorín.
--   * `/home/operador/`: la carpeta de cada ordenador (lo que guarde ese
--     puesto; de cada uno lo suyo).
--
-- Un archivo es { nombre, tipo = 'hoja' | 'texto', leer = function(ctx) }:
-- `leer` devuelve el contenido con los datos del momento (`ctx` = partida,
-- misiles, capacidad...). El de una hoja es { filas = { { celda, ... }, ... },
-- anchos = { px por columna } }; una celda es un texto, un número o
-- { texto, color = { r, g, b }, negrita = true }. El de un texto, una lista de
-- líneas.

local Dibujo = require('almacen.pc.dibujo')

local Archivos = {}
Archivos.__index = Archivos

local function celda(texto, color, negrita)
    return { texto = texto, color = color, negrita = negrita }
end

local AMARILLO = { 0.91, 0.77, 0.28 }
local ROJO = { 1, 0.35, 0.28 }
local GRIS = { 0.55, 0.6, 0.6 }

local function leerPolvorin(ctx)
    local misiles, capacidad = ctx.misiles or 0, ctx.capacidad or 0
    local filas = {
        { celda('POLVORÍN DEL ALMACÉN', AMARILLO, true) },
        {},
        { celda('Misiles', nil, true), misiles },
        { celda('Capacidad', nil, true), capacidad },
        { celda('Huecos libres', nil, true), capacidad - misiles },
        { celda('Estado', nil, true), misiles == 0 and celda('SIN MISILES', ROJO) or (misiles >= capacidad and celda('LLENO', { 0.31, 0.76, 1 }) or celda('LISTO', Dibujo.verde)) },
        {},
        { celda('Hueco', nil, true), celda('Contenido', nil, true) },
    }
    for k = 1, capacidad do
        filas[#filas + 1] = { k, k <= misiles and celda('Misil', Dibujo.verde) or celda('Libre', GRIS) }
    end
    return { filas = filas, anchos = { 170, 150 } }
end

local function leerRecursos(ctx)
    local p = ctx.partida
    local filas = {
        { celda('RECURSOS DE LA NACIÓN', AMARILLO, true) },
        { p and (p.nacion .. ' · año ' .. p.anio .. ', día ' .. p.dia) or 'Sin nación' },
        {},
        { celda('Recurso', nil, true), celda('Cantidad', nil, true), celda('Tope', nil, true), celda('%', nil, true), celda('Estado', nil, true) },
    }
    for _, r in ipairs(p and p.recursos or {}) do
        local porcentaje = r.tope and r.tope > 0 and math.floor(100 * r.cantidad / r.tope + 0.5) or nil
        filas[#filas + 1] = {
            celda(r.nombre, Dibujo.colorRecurso[r.tipo]),
            r.cantidad <= 0 and celda(Dibujo.miles(r.cantidad), ROJO) or Dibujo.miles(r.cantidad),
            r.tope and Dibujo.miles(r.tope) or '',
            porcentaje and (porcentaje .. ' %') or '',
            celda(Dibujo.textoEstado[r.estado] or '', Dibujo.colorEstado[r.estado]),
        }
    end
    return { filas = filas, anchos = { 150, 140, 140, 80, 120 } }
end

local function leerNoticias(ctx)
    local p = ctx.partida
    local lineas = {}
    for _, n in ipairs(p and p.noticias or {}) do
        lineas[#lineas + 1] = 'Día ' .. (n.dia or 0) .. ': ' .. n.texto
    end
    if #lineas == 0 then
        lineas[1] = 'Sin noticias.'
    end
    return lineas
end

-- La unidad de red: la misma tabla para todos los ordenadores.
-- Los ejecutables del juego (almacen/robots/ejecutables.lua), en
-- /red/almacen/guiones: al abrirlos se ve el código de sus especializaciones.
local function ejecutablesDelJuego()
    local lista = {}
    for _, e in ipairs(require('almacen.robots.ejecutables')) do
        lista[#lista + 1] = {
            nombre = e.archivo,
            tipo = 'texto',
            ejecutable = e,
            leer = function()
                local t = { '-- ' .. e.archivo .. ': ' .. e.descripcion .. '.', '-- Ejecutable del juego: pone en marcha estas especializaciones.', '' }
                for _, n in ipairs(e.especializaciones) do
                    local ruta = 'almacen/robots/especializaciones/' .. n .. '.lua'
                    if not love.filesystem.getInfo(ruta) then
                        ruta = 'robots/especializaciones/' .. n .. '.lua'
                    end
                    t[#t + 1] = '-- ' .. ruta .. ' ' .. string.rep('-', 40)
                    for l in ((love.filesystem.read(ruta) or '') .. '\n'):gmatch('(.-)\n') do
                        t[#t + 1] = l
                    end
                end
                return t
            end,
        }
    end
    return lista
end

local red = {
    nombre = 'red',
    carpeta = true,
    hijos = {
        {
            nombre = 'almacen',
            carpeta = true,
            hijos = {
                { nombre = 'polvorin.hoja', tipo = 'hoja', leer = leerPolvorin },
                { nombre = 'recursos.hoja', tipo = 'hoja', leer = leerRecursos },
                { nombre = 'noticias.txt', tipo = 'texto', leer = leerNoticias },
                { nombre = 'guiones', carpeta = true, hijos = ejecutablesDelJuego() },
            },
        },
    },
}

local function lineas(texto)
    local t = {}
    for l in (texto .. '\n'):gmatch('(.-)\n') do
        t[#t + 1] = l
    end
    return t
end

--- Los guiones de ejemplo de ~/guiones (los que se mandan a un robot).
function Archivos.guionesDeEjemplo()
    return {
        { nombre = 'LEEME.txt', tipo = 'texto', contenido = lineas([[
Guiones para los robots: cada uno es un ejecutable.

Un guion es una especialización, igual que las del juego
(almacen/robots/especializaciones/patrulla.lua): una tabla con onLoad y
onUpdate(dt), donde self es el robot. Con él se programa el robot desde 0.
Mejor muchos pequeños, uno para cada cosa, que uno enorme.

Un robot ejecuta uno solo a la vez: el nuevo sustituye al anterior, nunca
va encima. Si llevaba una caja, la caja vuelve al hueco de donde la cogió
(rack o mesa de descarga). El cuerpo sigue igual: andar, lidar, mapa,
brazos, pinzas, ojos.

Lo que hacían de siempre también son ejecutables, en /red/almacen/guiones
(solo lectura: al abrirlos se ve su código):
  trabajar.lua   el robot del almacén guarda y ordena lo que llega
  practicar.lua       el soldado explora, practica y dispara a los blancos

Se ejecutan con el programa Robots (doble clic o «Ejecutar»), desde la
terminal:      robot soldado ejecutar ~/guiones/patrulla.lua
               robot almacen ejecutar /red/almacen/guiones/trabajar.lua
o desde un programa: robots.ejecutar('soldado', '~/guiones/patrulla.lua')
«Parar» lo deja quieto sin ejecutar nada.

Forma de un guion (el nombre de la tabla es el que quieras):

    ---@class MiGuion : Robot
    local MiGuion = {}

    function MiGuion:onLoad()
        local d = self.datos.miguion   -- sus datos: self.datos.<archivo>
        d.reloj = 0
    end

    function MiGuion:onUpdate(dt)
        local d = self.datos.miguion
        d.reloj = d.reloj + dt
    end

    return MiGuion

onUpdate se llama en cada cuadro: no se espera dentro (nada de bucles que
esperan); se mira el reloj o el estado y se sigue en el cuadro siguiente.
Un onUpdate que no termina, o un error, para el robot y sale en Robots.

Lo que tiene self (todos los robots):
  self.x, self.y, self.rumbo           dónde está (m del almacén, radianes)
  self:setNavegarA(x, y)               va por su mapa, esquivando
  self:getNavegando()                  true mientras va
  self:getSinCamino()                  true si no encontró camino
  self:setIrA(x, y, rumbo)             va en recto (o gira: setIrA(self.x, self.y, r))
  self:getHaLlegado()                  true al llegar (de setIrA)
  self:setParar()                      se para
  self:setMirarA(x, y, z)              mira un punto; setMirarA(nil) deja de mirar
  self:setTarea(texto)                 lo que dice que hace (sale en Robots)
  self:setOrden('parar')               acaba el guion (queda quieto)
  self:setOrden('trabajar')            pasa a lo de siempre (trabajar...)
  print(...)                           escribe en su salida (programa Robots)
Robot del almacén, además:
  self:setBrazo(lado, hombro, abrir, codo, muñeca)   lado 'izq' o 'der'
  self:setPinza(lado, apertura)        en metros (0 a 0,1)
  self:setAgachar(f)                   0 de pie, 1 agachado
  self:setLlevar(objeto, mueble, n)    coger y dejar en el hueco n
  self:getOcupado()                    true mientras lleva algo
Sitios con nombre: Lugares.patio, Lugares.plazas, Lugares.anexo,
Lugares.espera, Lugares.sala, Lugares.calle, Lugares.fabrica  ({ x, y })]]) },
        { nombre = 'ir_al_patio.lua', tipo = 'texto', contenido = lineas([[
-- Va al patio, mira a un lado y al otro y vuelve a su trabajo.
---@class IrAlPatio : Robot
local IrAlPatio = {}

IrAlPatio.espera = 2 -- s mirando a cada lado

function IrAlPatio:onLoad()
    local d = self.datos.ir_al_patio
    d.paso = 'ir'
    d.reloj = 0
    self:setTarea('voy al patio')
    self:setNavegarA(Lugares.patio[1], Lugares.patio[2])
end

function IrAlPatio:onUpdate(dt)
    local d = self.datos.ir_al_patio
    d.reloj = d.reloj + dt
    if d.paso == 'ir' then
        if self:getSinCamino() then
            print('no encuentro camino al patio')
            self:setOrden('trabajar')
        elseif not self:getNavegando() then
            print('en el patio')
            self:setTarea('miro el patio')
            d.paso = 'izquierda'
            d.reloj = 0
            self:setIrA(self.x, self.y, self.rumbo + math.pi / 2)
        end
    elseif d.paso == 'izquierda' and d.reloj > IrAlPatio.espera then
        d.paso = 'derecha'
        d.reloj = 0
        self:setIrA(self.x, self.y, self.rumbo - math.pi)
    elseif d.paso == 'derecha' and d.reloj > IrAlPatio.espera then
        self:setOrden('trabajar')
    end
end

return IrAlPatio]]) },
        { nombre = 'patrulla.lua', tipo = 'texto', contenido = lineas([[
-- Ronda sin fin por la nave: patio, plazas y anexo, con una pausa en cada
-- sitio. Se acaba con «Trabajar» o «Parar» en el programa Robots.
---@class Ronda : Robot
local Ronda = {}

Ronda.SITIOS = { 'patio', 'plazas', 'anexo' }
Ronda.pausa = 1.5 -- s parado en cada sitio

local function ir(self, d)
    local nombre = Ronda.SITIOS[d.sitio]
    local p = Lugares[nombre]
    self:setTarea('ronda ' .. d.vuelta .. ': voy a ' .. nombre)
    self:setNavegarA(p[1], p[2])
    d.yendo = true
end

function Ronda:onLoad()
    local d = self.datos.patrulla
    d.sitio = 1
    d.vuelta = 1
    d.reloj = 0
    ir(self, d)
end

function Ronda:onUpdate(dt)
    local d = self.datos.patrulla
    if d.yendo then
        if not self:getNavegando() then
            d.yendo = false
            d.reloj = 0
            if self:getSinCamino() then
                print('no llego a ' .. Ronda.SITIOS[d.sitio])
            end
        end
        return
    end
    d.reloj = d.reloj + dt
    if d.reloj > Ronda.pausa then
        d.sitio = d.sitio % #Ronda.SITIOS + 1
        if d.sitio == 1 then
            d.vuelta = d.vuelta + 1
        end
        ir(self, d)
    end
end

return Ronda]]) },
    }
end

--- Los programas de ejemplo de ~/programas (los que corre el ordenador).
function Archivos.programasDeEjemplo()
    return {
        { nombre = 'estado.lua', tipo = 'texto', contenido = lineas([[
-- Qué hace cada robot y dónde está.
for _, nombre in ipairs(robots.lista()) do
    local modo, tarea = robots.estado(nombre)
    local x, y = robots.posicion(nombre)
    print(nombre .. ' (' .. modo .. ') en ' .. x .. ', ' .. y .. ': ' .. tarea)
end]]) },
        { nombre = 'vigilar.lua', tipo = 'texto', contenido = lineas([[
-- Cada 5 s escribe dónde está el soldado (Ctrl+T para cortarlo).
while true do
    local x, y = robots.posicion('soldado')
    print('soldado en ' .. x .. ', ' .. y)
    sleep(5)
end]]) },
    }
end

--- El sistema de archivos del ordenador `nombre`. `casa`: su carpeta
-- personal guardada (si vuelve al almacén), o nil para una nueva.
function Archivos.nuevo(nombre, casa)
    local self = setmetatable({}, Archivos)
    self.casa = casa or {
        nombre = 'operador',
        carpeta = true,
        hijos = {
            { nombre = 'guiones', carpeta = true, hijos = Archivos.guionesDeEjemplo() },
            { nombre = 'notas.txt', tipo = 'texto', contenido = { 'Turno de ' .. nombre .. '.', '' } },
            { nombre = 'programas', carpeta = true, hijos = Archivos.programasDeEjemplo() },
        },
    }
    self.raiz = {
        nombre = '',
        carpeta = true,
        hijos = {
            { nombre = 'home', carpeta = true, hijos = { self.casa } },
            red,
        },
    }
    return self
end

--- El nodo de `ruta` ('/red/almacen/polvorin.hoja') o nil.
function Archivos:buscar(ruta)
    local nodo = self.raiz
    for parte in ruta:gmatch('[^/]+') do
        local siguiente
        for _, h in ipairs(nodo.hijos or {}) do
            if h.nombre == parte then
                siguiente = h
                break
            end
        end
        if not siguiente then
            return nil
        end
        nodo = siguiente
    end
    return nodo
end

--- Lo que hay ahora en el archivo de `ruta`, o nil.
function Archivos:leer(ruta, ctx)
    local nodo = self:buscar(ruta)
    if not nodo or nodo.carpeta then
        return nil
    end
    if nodo.leer then
        return nodo.leer(ctx)
    end
    return nodo.contenido
end

--- Las rutas de todos los archivos de tipo `tipo` (o todos), en orden.
function Archivos:listar(tipo)
    local lista = {}
    local function recorrer(nodo, ruta)
        for _, h in ipairs(nodo.hijos or {}) do
            local r = ruta .. '/' .. h.nombre
            if h.carpeta then
                recorrer(h, r)
            elseif not tipo or h.tipo == tipo then
                lista[#lista + 1] = r
            end
        end
    end
    recorrer(self.raiz, '')
    table.sort(lista)
    return lista
end

--- Los nombres que hay en la carpeta `ruta` (las carpetas con '/' al final).
function Archivos:contenidoDe(ruta)
    local nodo = self:buscar(ruta)
    local nombres = {}
    for _, h in ipairs(nodo and nodo.hijos or {}) do
        nombres[#nombres + 1] = h.nombre .. (h.carpeta and '/' or '')
    end
    return nombres
end

--- La ruta absoluta y limpia de `ruta` vista desde la carpeta `actual`
-- (entiende '..', '.', y '~' = la carpeta personal).
function Archivos.resolver(actual, ruta)
    if not ruta or ruta == '' then
        return actual
    end
    if ruta:sub(1, 1) == '~' then
        ruta = '/home/operador' .. ruta:sub(2)
    elseif ruta:sub(1, 1) ~= '/' then
        ruta = actual .. '/' .. ruta
    end
    local partes = {}
    for parte in ruta:gmatch('[^/]+') do
        if parte == '..' then
            partes[#partes] = nil
        elseif parte ~= '.' then
            partes[#partes + 1] = parte
        end
    end
    return '/' .. table.concat(partes, '/')
end

--- ¿Se puede escribir en `ruta`? Solo en la carpeta personal (la red la
-- escribe la partida).
function Archivos.escribible(ruta)
    return ruta:sub(1, 15) == '/home/operador/' or ruta == '/home/operador'
end

--- Crea el archivo de texto `ruta` (vacío) en la carpeta personal, o la
-- carpeta si `carpeta`. Devuelve el nodo o nil y el motivo.
function Archivos:crear(ruta, carpeta)
    if not Archivos.escribible(ruta) then
        return nil, 'solo se puede escribir en /home/operador'
    end
    if self:buscar(ruta) then
        return self:buscar(ruta)
    end
    local padre = self:buscar(ruta:match('^(.*)/[^/]+$') or '/')
    if not padre or not padre.carpeta then
        return nil, 'no existe la carpeta'
    end
    local nombre = ruta:match('[^/]+$')
    local nodo
    if carpeta then
        nodo = { nombre = nombre, carpeta = true, hijos = {} }
    else
        nodo = { nombre = nombre, tipo = nombre:match('%.hoja$') and 'hoja' or 'texto', contenido = nombre:match('%.hoja$') and { filas = {} } or { '' } }
    end
    padre.hijos[#padre.hijos + 1] = nodo
    table.sort(padre.hijos, function(a, b)
        return a.nombre < b.nombre
    end)
    return nodo
end

--- Borra `ruta` de la carpeta personal.
function Archivos:borrar(ruta)
    if not Archivos.escribible(ruta) or ruta == '/home/operador' then
        return false, 'solo se puede borrar en /home/operador'
    end
    local padre = self:buscar(ruta:match('^(.*)/[^/]+$') or '/')
    for k, h in ipairs(padre and padre.hijos or {}) do
        if h.nombre == ruta:match('[^/]+$') then
            table.remove(padre.hijos, k)
            return true
        end
    end
    return false, 'no existe'
end

--- El programa que abre el archivo `ruta`: 'hoja', 'texto' o 'archivos'.
function Archivos:programaPara(ruta)
    local nodo = self:buscar(ruta)
    if not nodo then
        return nil
    end
    if nodo.carpeta then
        return 'archivos'
    end
    return nodo.tipo == 'hoja' and 'hoja' or 'texto'
end

return Archivos
