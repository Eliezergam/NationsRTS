-- Robots del almacén, con la misma forma que los vehículos de la batalla
-- (batalla/vehiculos/API.md): el robot tiene piezas que se mueven por capas
-- y scripts (especializaciones) que las mueven. `get...` devuelve algo y no
-- cambia nada; `set...` cambia algo y no devuelve nada. Todo con `:`.
--
--   local robot = GestorRobots.getRobots()[1]
--   robot:setIrA(-26.5, 0)              -- va con sus ruedas
--   robot:setMirarA(-29.6, 0, 7.4)      -- mira al contador del polvorín
--   robot:setPinza('der', 0.08)         -- abre la pinza derecha 8 cm
--
-- Medidas del almacén: metros; ejes del almacén (los del modelo de Blender):
-- x a lo largo de la nave (los portones en +30), y a lo ancho, z arriba;
-- ángulos en radianes, rumbo 0 = hacia +x. Ver almacen/robots/API.md.
--
-- Lo común a todos los robots (piezas, especializaciones, ajustes) está en
-- la librería robots/nucleo.lua; aquí, solo lo del almacén: dónde están sus
-- tipos, especializaciones y modelos (assets/almacen/<modelo>.glb y
-- <modelo>_piezas.lua, de tools/blender/robot_almacen.py --glb), sus brillos
-- y cómo se pasa de sus ejes (z arriba) a los de 3Dream (y arriba).

local dream = require('lib.3DreamEngine')
local Nucleo = require('robots.nucleo')
local PiezaRobot = require('robots.pieza')

-- De ejes del almacén (z arriba) a los de 3Dream (y arriba): x, z, -y.
local function aDream(m)
    return dream.mat4({
        m[1], m[3], -m[2], m[4],
        m[9], m[11], -m[10], m[12],
        -m[5], -m[7], m[6], -m[8],
        0, 0, 0, 1,
    })
end

local gestor = Nucleo.nuevoGestor({
    tipos = { 'almacen.robots.tipos', 'robots.tipos' },
    especializaciones = { 'almacen.robots.especializaciones', 'robots.especializaciones' },
    modelos = 'assets/almacen/',
    modeloPorDefecto = 'robot',
    -- Los ojos y el piloto brillan más de lo que guarda el glTF.
    alCargarModelo = function(base)
        for _, pieza in pairs(base.objects) do
            for _, malla in pairs(pieza.meshes or {}) do
                local material = malla.material
                if material and (material.name == 'robotOjo' or material.name == 'robotPiloto') then
                    material:setEmissionFactor(6, 6, 6)
                end
            end
        end
    end,
    -- En el suelo de la nave (z = 0).
    raiz = function(r)
        return PiezaRobot.multiplicar({ 1, 0, 0, r.x, 0, 1, 0, r.y, 0, 0, 1, 0, 0, 0, 0, 1 }, PiezaRobot.rotacion('z', r.rumbo))
    end,
    aDream = aDream,
    -- Rayo contra el mundo del almacén (cajas de la nave y objetos): para
    -- las balas (robots/especializaciones/combate.lua).
    rayo = function(x, y, z, dx, dy, dz, alcance, ignorar)
        return require('almacen.robots.mundo').rayo3D(x, y, z, dx, dy, dz, alcance, ignorar)
    end,
    -- Rayo horizontal del lidar (robots/especializaciones/lidar.lua): el
    -- suelo de la nave es z = 0.
    sensor = function(x, y, z, angulo, alcance, ignorar)
        return require('almacen.robots.mundo').rayo(x, y, z, angulo, alcance, ignorar)
    end,
})

-- Global, como GestorVehiculos.
GestorRobots = GestorRobots or {}
GestorRobots.gestor = gestor
GestorRobots.Robot = Nucleo.Robot
GestorRobots.registrarEspecializacion = Nucleo.registrarEspecializacion

--- Crea un robot de tipo `tipo` (almacen/robots/tipos/<tipo>.lua o
-- robots/tipos/<tipo>.lua) en (x, y) con rumbo `rumbo`.
---@return Robot
function GestorRobots.crear(tipo, x, y, rumbo)
    return gestor:crear(tipo, x, y, rumbo)
end

--- Todos los robots del almacén.
---@return Robot[]
function GestorRobots.getRobots()
    return gestor:getRobots()
end

--- Quita todos (al salir del almacén).
function GestorRobots.vaciar()
    gestor:vaciar()
end

function GestorRobots.actualizar(dt)
    gestor:actualizar(dt)
end

function GestorRobots.dibujar()
    gestor:dibujar()
end

return GestorRobots
