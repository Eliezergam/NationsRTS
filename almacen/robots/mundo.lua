-- Lo que tocan los rayos de los sensores del robot: las cajas de colisión de
-- la nave (assets/almacen/colisiones.lua, sacadas del modelo de Blender) y
-- las de los objetos y muebles (GestorObjetos), cada una con lo que es.
--
-- Los rayos los lanza Jolt en C++ (ver «Rayos en C++» más abajo). La
-- cuadrícula de 1 m con las cajas fijas queda para `cajasEn` (la física del
-- robot).
--
--   local d, tipo, objeto = MundoRobot.rayo(x, y, z, angulo, alcance, ignorar)

require('almacen.objetos.objetos')

local MundoRobot = {}

local COLISIONES = 'assets/almacen/colisiones.lua'
-- Zonas de información (disparadores: no paran a nadie) que leen los ojos:
-- puertas y portones con su ancho y alto, marcos y esquinas
-- (tools/blender/almacen_interior.py --info).
local INFORMACION = 'assets/almacen/informacion.lua'
local informacion
local CELDA = 1.0
local X0, Y0 = -76, -16
local ANCHO, ALTO = 142, 44 -- hasta x = 66 e y = 28 (anexo y patio)

local cajas -- { {tipo, x0, y0, z0, x1, y1, z1}, ... }
local rejilla -- [indice] = { caja, ... }
local marca = {}
local vuelta = 0

local function indice(cx, cy)
    return cy * ANCHO + cx
end

--- Carga las cajas fijas (una vez).
function MundoRobot.cargar()
    if cajas then
        return
    end
    cajas = love.filesystem.load(COLISIONES)()
    informacion = love.filesystem.getInfo(INFORMACION) and love.filesystem.load(INFORMACION)() or {}
    -- Cada marco apunta a su hueco.
    local porNombre = {}
    for _, z in ipairs(informacion) do
        porNombre[z.nombre] = z
    end
    for _, z in ipairs(informacion) do
        if z.de then
            z.hueco = porNombre[z.de]
        end
    end
    rejilla = {}
    for k, c in ipairs(cajas) do
        c.id = k
        local cx0 = math.max(0, math.floor((c[2] - X0) / CELDA))
        local cx1 = math.min(ANCHO - 1, math.floor((c[5] - X0) / CELDA))
        local cy0 = math.max(0, math.floor((c[3] - Y0) / CELDA))
        local cy1 = math.min(ALTO - 1, math.floor((c[6] - Y0) / CELDA))
        for cy = cy0, cy1 do
            for cx = cx0, cx1 do
                local i = indice(cx, cy)
                local l = rejilla[i]
                if not l then
                    l = {}
                    rejilla[i] = l
                end
                l[#l + 1] = c
            end
        end
    end
end

--- Las zonas de información del almacén (ver INFORMACION).
function MundoRobot.getInformacion()
    MundoRobot.cargar()
    return informacion
end

--- Las cajas fijas de un tipo ('contenedorMisil'...).
function MundoRobot.getCajasDeTipo(tipo)
    MundoRobot.cargar()
    local r = {}
    for _, c in ipairs(cajas) do
        if c[1] == tipo then
            r[#r + 1] = c
        end
    end
    return r
end

-- Rayos en C++ (el dueño, 19-nov: «pasa a C++ las cosas que necesiten
-- control de memoria»): los lanza Jolt (batalla/robots/fisica.lua), el
-- mismo motor que la batalla, sobre un mundo físico del almacén con un
-- cuerpo fijo por cada caja de la nave, el suelo (z = 0) y un cuerpo por
-- cada caja de cada objeto, que se recoloca cuando el objeto se mueve. Antes
-- iban en Lua y los ojos avanzaban a pasos de 3 cm: los sensores se comían
-- un 28 % del hilo principal siguiendo al robot de las cajas.
local Fisica = require('batalla.robots.fisica')
local J, ffi
local fisica
local posicion, giro
local porObjeto = {} -- objeto -> { ids, colisiones, cajas, m1, m5, m4, m8, m12 }
local cuadro, sincronizado = 0, -1

--- Cada cuadro (almacen/escena.lua): los objetos se recolocan una vez.
function MundoRobot.cuadro()
    cuadro = cuadro + 1
end

local function crearMundo()
    J, ffi = Fisica.jolt()
    fisica = Fisica.crear(0, 0)
    fisica.radio = 300
    fisica:crearPlano()
    for _, c in ipairs(cajas) do
        fisica:ponerColision({
            tipo = c[1],
            etiquetas = { solido = true },
            forma = {
                tipo = 'caja',
                x = (c[2] + c[5]) / 2, y = (c[3] + c[6]) / 2,
                hx = (c[5] - c[2]) / 2, hy = (c[6] - c[3]) / 2,
                rumbo = 0, z0 = c[4], z1 = c[7],
            },
        })
    end
    J.JPC_PhysicsSystem_OptimizeBroadPhase(fisica.sistema)
    posicion = ffi.new('JPC_RVec3')
    giro = ffi.new('JPC_Quat')
end

local function quitarObjeto(o, e)
    for _, c in ipairs(e.colisiones) do
        fisica:quitarColision(c)
    end
    porObjeto[o] = nil
end

--- Cuerpos de los objetos al día: nuevos, quitados, movidos o con otras cajas.
local function sincronizar()
    if sincronizado == cuadro then
        return
    end
    sincronizado = cuadro
    local vivos = {}
    for _, o in ipairs(GestorObjetos and GestorObjetos.getObjetos() or {}) do
        vivos[o] = true
        local m = o.matrizRayos or o.matriz
        local lista = o.cajasPropias or o.datos.cajas or {}
        local e = porObjeto[o]
        if e and e.cajas ~= lista then
            quitarObjeto(o, e)
            e = nil
        end
        if not e then
            e = { colisiones = {}, ids = {}, cajas = lista }
            for k, b in ipairs(lista) do
                local c = {
                    tipo = o.tipo,
                    objeto = o,
                    etiquetas = { solido = true },
                    forma = {
                        tipo = 'caja', x = 0, y = 0, rumbo = 0,
                        hx = (b[4] - b[1]) / 2, hy = (b[5] - b[2]) / 2,
                        z0 = -(b[6] - b[3]) / 2, z1 = (b[6] - b[3]) / 2,
                    },
                }
                e.colisiones[k] = c
                e.ids[k] = fisica:ponerColision(c)
            end
            porObjeto[o] = e
        end
        if e.m1 ~= m[1] or e.m5 ~= m[5] or e.m4 ~= m[4] or e.m8 ~= m[8] or e.m12 ~= m[12] then
            e.m1, e.m5, e.m4, e.m8, e.m12 = m[1], m[5], m[4], m[8], m[12]
            local c, s = m[1], m[5]
            local rumbo = math.atan2(s, c)
            giro.x, giro.y, giro.z, giro.w = 0, math.sin(rumbo / 2), 0, math.cos(rumbo / 2)
            for k, b in ipairs(lista) do
                local bx, by, bz = (b[1] + b[4]) / 2, (b[2] + b[5]) / 2, (b[3] + b[6]) / 2
                local x, y, z = m[4] + c * bx - s * by, m[8] + s * bx + c * by, m[12] + bz
                posicion.x, posicion.y, posicion.z = fisica:aJolt(x, y, z)
                J.JPC_BodyInterface_SetPositionAndRotation(fisica.cuerpos, e.ids[k], posicion, giro, J.JPC_ACTIVATION_DONT_ACTIVATE)
            end
        end
    end
    for o, e in pairs(porObjeto) do
        if not vivos[o] then
            quitarObjeto(o, e)
        end
    end
end

--- Lo primero que toca el rayo (sin `ignorar` ni lo que va sin rayos):
-- distancia (o nil), tipo y objeto.
local function lanzar(x, y, z, dx, dy, dz, alcance, ignorar)
    if not fisica then
        MundoRobot.cargar()
        crearMundo()
    end
    sincronizar()
    local hecho = 0
    for _ = 1, 8 do
        local d, c = fisica:rayo(x, y, z, dx, dy, dz, alcance - hecho)
        if not d then
            return nil
        end
        local o = c.objeto
        if not (o and (o == ignorar or o.sinRayos)) then
            if c == Fisica.colisionNada then
                -- El único cuerpo sin colisión declarada es el suelo.
                return hecho + d, 'suelo', nil
            end
            return hecho + d, c.tipo, o
        end
        -- Lo que lleva el robot: sigue un poco más allá.
        local paso = d + 0.01
        x, y, z = x + dx * paso, y + dy * paso, z + dz * paso
        hecho = hecho + paso
    end
    return nil
end

--- Entrada del rayo en la caja c = { x0, y0, z0, x1, y1, z1 } (0 si sale
-- de dentro), o nil. Método de las franjas en 3D.
local function entrada(x, y, z, dx, dy, dz, c, maximo)
    local tmin, tmax = 0, maximo
    local o, d = { x, y, z }, { dx, dy, dz }
    for eje = 1, 3 do
        local a0, a1 = c[eje], c[eje + 3]
        if math.abs(d[eje]) < 1e-9 then
            if o[eje] < a0 or o[eje] > a1 then
                return nil
            end
        else
            local a, b = (a0 - o[eje]) / d[eje], (a1 - o[eje]) / d[eje]
            if a > b then
                a, b = b, a
            end
            tmin, tmax = math.max(tmin, a), math.min(tmax, b)
            if tmin > tmax then
                return nil
            end
        end
    end
    return tmin
end

--- Lanza un rayo horizontal desde (x, y) a la altura z, hacia `angulo`.
-- Devuelve la distancia al primer choque (o `alcance` si no choca), qué es
-- (el tipo: 'rack', 'muro', 'cajaRobot'...) y el objeto (si es de
-- GestorObjetos). `ignorar`: un objeto que no cuenta (lo que lleva el robot).
function MundoRobot.rayo(x, y, z, angulo, alcance, ignorar)
    local d, tipo, objeto = lanzar(x, y, z, math.cos(angulo), math.sin(angulo), 0, alcance, ignorar)
    if not d then
        return alcance, nil, nil
    end
    return d, tipo, objeto
end

--- Rayo en cualquier dirección (los ojos: pueden mirar arriba o abajo).
-- Devuelve distancia, tipo y objeto de lo que toca ('suelo' para el suelo;
-- alcance y nil si no toca nada) y, aparte, la primera zona de información
-- que cruza antes (un portón, un marco, una esquina).
function MundoRobot.rayo3D(x, y, z, dx, dy, dz, alcance, ignorar)
    local n = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / n, dy / n, dz / n
    local d, tipo, objeto = lanzar(x, y, z, dx, dy, dz, alcance, ignorar)
    local hasta = d or alcance
    local info, primera = nil, math.huge
    for _, zona in ipairs(informacion) do
        local t = entrada(x, y, z, dx, dy, dz, zona.caja, hasta)
        if t and t < primera then
            info, primera = zona, t
        end
    end
    if not d then
        return alcance, nil, nil, info
    end
    return d, tipo, objeto, info
end

--- Las cajas fijas que tocan el rectángulo (x0, y0)-(x1, y1) y cruzan las
-- alturas z0..z1 (para la física del robot: almacen/robots/especializaciones/fisica.lua).
function MundoRobot.cajasEn(x0, y0, x1, y1, z0, z1)
    MundoRobot.cargar()
    vuelta = vuelta + 1
    local lista = {}
    local cx0 = math.max(0, math.floor((x0 - X0) / CELDA))
    local cx1 = math.min(ANCHO - 1, math.floor((x1 - X0) / CELDA))
    local cy0 = math.max(0, math.floor((y0 - Y0) / CELDA))
    local cy1 = math.min(ALTO - 1, math.floor((y1 - Y0) / CELDA))
    for cy = cy0, cy1 do
        for cx = cx0, cx1 do
            for _, c in ipairs(rejilla[indice(cx, cy)] or {}) do
                if marca[c.id] ~= vuelta and c[4] < z1 and c[7] > z0 then
                    marca[c.id] = vuelta
                    lista[#lista + 1] = c
                end
            end
        end
    end
    return lista
end

-- Las cajas de un objeto cambian solo cuando se mueve: se guardan por su
-- matriz.
function GestorObjetos.Objeto:getCajasColisionCache()
    if self.cacheMatriz ~= self.matriz then
        self.cacheMatriz = self.matriz
        self.cacheCajas = self:getCajasColision()
    end
    return self.cacheCajas
end

return MundoRobot
