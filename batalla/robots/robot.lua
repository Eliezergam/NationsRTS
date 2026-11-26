-- Robots de la batalla 3D (el dueño, 17-nov: la infantería son robots). Lo
-- común a todos los robots (piezas por capas, especializaciones, ajustes)
-- está en la librería robots/nucleo.lua, la misma que usa el almacén; aquí,
-- solo lo de la batalla.
--
-- Modelos: assets/batalla/robots/<modelo>.glb y <modelo>_piezas.lua
-- (tools/blender/robot_soldado.py --glb). Tipos: batalla/robots/tipos/ y
-- robots/tipos/; especializaciones: batalla/robots/especializaciones/ y
-- robots/especializaciones/.
--
-- Unidades: el robot vive en metros con los ejes de todos los robots (x, y a
-- la izquierda, z arriba; rumbo 0 = +x), como en el almacén, para que las
-- especializaciones comunes valgan aquí. El juego tiene píxeles (10 px =
-- 1 m) y la y hacia el sur: x_m = x_px / 10, y_m = -y_px / 10 y un rumbo del
-- juego `r` es aquí `-r`. `robot:getJuego()` da la posición en el juego.

local dream = require('lib.3DreamEngine')
local Nucleo = require('robots.nucleo')
local PiezaRobot = require('robots.pieza')
local BibliotecaPbr = require('batalla.dream.biblioteca_pbr')
local MundoBatalla = require('batalla.robots.mundo')

local RobotsBatalla = {}

local PX_POR_M = 10

-- Del marco del robot (metros, z arriba) a 3Dream (y arriba, 1 unidad = 10 m,
-- centrado como el conversor de la batalla: batalla/dream/conversor.lua).
-- Una matriz de 3Dream por cada matriz del robot (la de cada pieza es
-- siempre la misma tabla: robots/pieza.lua colocarEn), rellenada cada
-- cuadro: sin tablas nuevas para el recolector.
local enDream = setmetatable({}, { __mode = 'k' })
local function aDream(m, _, conversor)
    local e = 0.1
    local r = enDream[m]
    if not r then
        r = dream.mat4()
        enDream[m] = r
    end
    r[1], r[2], r[3], r[4] = m[1] * e, m[3] * e, -m[2] * e, (m[4] * PX_POR_M - conversor.cx) * 0.01
    r[5], r[6], r[7], r[8] = m[9] * e, m[11] * e, -m[10] * e, m[12] * e
    r[9], r[10], r[11], r[12] = -m[5] * e, -m[7] * e, m[6] * e, (-m[8] * PX_POR_M - conversor.cy) * 0.01
    r[13], r[14], r[15], r[16] = 0, 0, 0, 1
    return r
end

-- Tamaño real de cada modelo (medidas.lua): la raíz del robot se escala y
-- todas sus piezas con ella.
local Medidas = require('medidas')
local function escalar(m, r)
    local e = r.escalaMedida
    if e == nil then
        e = Medidas.escalaRobot(tostring(r.nombreModelo):match('([^/]+)$'))
        r.escalaMedida = e
    end
    if e == 1 then
        return m
    end
    return PiezaRobot.multiplicar(m, { e, 0, 0, 0, 0, e, 0, 0, 0, 0, e, 0, 0, 0, 0, 1 })
end

local gestor = Nucleo.nuevoGestor({
    tipos = { 'batalla.robots.tipos', 'robots.tipos' },
    especializaciones = { 'batalla.robots.especializaciones', 'robots.especializaciones' },
    modelos = 'assets/batalla/robots/',
    alCargarModelo = function(base)
        for _, pieza in pairs(base.objects) do
            for _, malla in pairs(pieza.meshes or {}) do
                local material = malla.material
                -- Blender duplica algunos nombres («robotArticulacion.001»):
                -- esos toman también el material de la biblioteca por su
                -- nombre base.
                local nombreBase = material and material.name and material.name:match('^[^%.]+')
                if nombreBase and nombreBase ~= material.name and dream.materialLibrary[nombreBase] then
                    malla.material = dream.materialLibrary[nombreBase]
                    material = malla.material
                end
                -- Lo cian (núcleo del ojo, oídos) brilla más de lo que guarda el glTF.
                if material and (material.name == 'robotNucleo' or material.name == 'robotOjo') then
                    material:setEmissionFactor(6, 6, 6)
                end
            end
        end
    end,
    -- Sobre el suelo de la batalla, donde esté cada cuadro.
    raiz = function(r)
        -- Montado en otro (el conductor en su asiento: sentado.lua).
        if r.raizFija then
            r.zJuego = r.raizFija[12] * PX_POR_M
            return r.raizFija
        end
        -- Con las superficies puestas encima (la pista, la bodega del
        -- avión de carga): MundoBatalla.altura.
        r.zJuego = MundoBatalla.altura(r.x, r.y) * PX_POR_M
        -- Vehículos (`inclinar = { largo, ancho }` en su tipo): se inclinan
        -- con el terreno bajo sus cuatro esquinas.
        local inc = r.inclinar
        if inc then
            local c, s = math.cos(r.rumbo), math.sin(r.rumbo)
            local L, A = inc[1] / 2, inc[2] / 2
            local function h(f, l)
                return MundoBatalla.altura(r.x + c * f - s * l, r.y + s * f + c * l)
            end
            local delante, detras = h(L, 0), h(-L, 0)
            local izquierda, derecha = h(0, A), h(0, -A)
            local cabeceo = math.atan2(delante - detras, 2 * L)
            local alabeo = math.atan2(izquierda - derecha, 2 * A)
            local z = (delante + detras + izquierda + derecha) / 4
            r.zJuego = z * PX_POR_M
            local m = PiezaRobot.multiplicar({ 1, 0, 0, r.x, 0, 1, 0, r.y, 0, 0, 1, z, 0, 0, 0, 1 }, PiezaRobot.rotacion('z', r.rumbo))
            m = PiezaRobot.multiplicar(m, PiezaRobot.rotacion('y', -cabeceo))
            return escalar(PiezaRobot.multiplicar(m, PiezaRobot.rotacion('x', alabeo)), r)
        end
        local m = PiezaRobot.multiplicar(
            { 1, 0, 0, r.x, 0, 1, 0, r.y, 0, 0, 1, r.zJuego / PX_POR_M, 0, 0, 0, 1 },
            PiezaRobot.rotacion('z', r.rumbo)
        )
        return escalar(m, r)
    end,
    aDream = aDream,
    -- Copias de lejos (robots/nucleo.lua Robot:elegirNivel): la de cerca
    -- hasta 15 m, la media hasta 45 m y luego la lejana.
    lod = {
        distancias = { 15, 45 },
        ojo = function()
            local o = require('batalla.dream.viento').ojo
            return o[1], o[2], o[3]
        end,
        metrosPorUnidad = 10,
        forzar = tonumber(os.getenv('ROBOTS_LOD') or ''),
    },
    -- Rayos de los ojos y de las balas: lo que toquen en el mundo físico.
    rayo = function(x, y, z, dx, dy, dz, alcance)
        return MundoBatalla.rayo(x, y, z, dx, dy, dz, alcance)
    end,
    -- Rayo horizontal del lidar (robots/especializaciones/lidar.lua), a `z` m
    -- sobre el suelo: lo que toca da sus etiquetas (el terreno, `suelo`).
    sensor = function(x, y, z, angulo, alcance)
        local d, etiquetas, colision = MundoBatalla.rayo(x, y, MundoBatalla.altura(x, y) + z, math.cos(angulo), math.sin(angulo), 0, alcance)
        if not d then
            return alcance, nil, nil
        end
        return d, etiquetas, colision.dueno
    end,
})

--- Crea un robot `tipo` en (x, y) px del juego, sobre el suelo de `suelo`,
-- con rumbo del juego `rumbo` (atan2(dy, dx), y al sur).
function RobotsBatalla.crear(tipo, suelo, x, y, rumbo)
    -- Las mismas texturas PBR que los robots del almacén (chapa, acero,
    -- goma: tools/texturas_robots.py), buscadas por nombre de material.
    -- El mundo que perciben: las colisiones de la batalla y su mundo físico
    -- (uno por batalla, se hace con el primer robot).
    MundoBatalla.usarSuelo(suelo)
    if not suelo.fisicaRobots then
        suelo.fisicaRobots = require('batalla.robots.fisica').batalla(suelo)
    end
    MundoBatalla.usarFisica(suelo.fisicaRobots)
    if not dream.materialLibrary.robotBlanco then
        BibliotecaPbr.cargar(dream, 'assets/almacen/materiales_robot')
    end
    return gestor:crear(tipo, x / PX_POR_M, -y / PX_POR_M, -(rumbo or 0), { suelo = suelo })
end

--- El modelo `nombre` de los robots (el mismo que usan al crearse, cargado
-- una vez, con sus materiales): { base, piezas, lods }, o nil si falta su
-- .glb. Para dibujar una pieza suelta (el misil en vuelo del camión).
function RobotsBatalla.cargarModelo(nombre)
    local ruta = nombre:find('/') and nombre or ('assets/batalla/robots/' .. nombre)
    if not love.filesystem.getInfo(ruta .. '.glb', 'file') then
        return nil
    end
    if not dream.materialLibrary.robotBlanco then
        BibliotecaPbr.cargar(dream, 'assets/almacen/materiales_robot')
    end
    return gestor:cargarModelo(nombre)
end

function RobotsBatalla.getRobots()
    return gestor:getRobots()
end

function RobotsBatalla.vaciar()
    gestor:vaciar()
end

function RobotsBatalla.actualizar(dt)
    gestor:actualizar(dt)
end

--- Dibuja los robots con el centro de la escena del conversor
-- (batalla/dream/conversor.lua).
function RobotsBatalla.dibujar(conversor)
    gestor:dibujar(conversor)
end

--- Posición en el juego: x, y, z en px (y al sur) y rumbo del juego.
function Nucleo.Robot:getJuego()
    local z = self.zJuego or (self.suelo and self.suelo:altura(self.x * PX_POR_M, -self.y * PX_POR_M)) or 0
    return self.x * PX_POR_M, -self.y * PX_POR_M, z, -self.rumbo
end

return RobotsBatalla
