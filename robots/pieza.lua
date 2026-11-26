-- Una pieza de un robot (robots/nucleo.lua, para todas las escenas): igual que las
-- piezas de los vehículos (batalla/vehiculos/pieza.lua), con capas.
--
-- Cada especialización que mueve la pieza tiene su propia capa (la que el
-- robot está llamando, `robot.actual`); `setGiro` y `setDesplazamiento`
-- sustituyen lo de SU capa y las capas se suman en el orden en que cada una
-- tocó la pieza por primera vez. Si una especialización necesita dos giros a
-- la vez, les da nombre: `pieza:setGiro('y', a, 'rodar')`.
--
-- Ejes de la pieza: los suyos en reposo (los del modelo de Blender). Para el
-- robot entero: x delante, y izquierda, z arriba; medidas en metros y
-- ángulos en radianes.

---@class PiezaRobot
---@field nombre string
---@field robot Robot
local PiezaRobot = {}
PiezaRobot.__index = PiezaRobot

function PiezaRobot.nueva(robot, datos)
    local self = setmetatable({}, PiezaRobot)
    self.nombre = datos.nombre
    self.robot = robot
    self.datos = datos
    self.capas = {}
    self.porClave = {}
    self.visible = true
    self.hijas = {}
    self.mundo = nil -- matriz 4x4 por filas de este cuadro
    return self
end

local function rotacion(eje, a)
    local c, s = math.cos(a), math.sin(a)
    if eje == 'x' then
        return { 1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0, 0, 0, 0, 1 }
    elseif eje == 'y' then
        return { c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0, 0, 0, 0, 1 }
    end
    return { c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
end
PiezaRobot.rotacion = rotacion

local function multiplicar(a, b)
    local r = {}
    for i = 0, 3 do
        for j = 1, 4 do
            r[i * 4 + j] = a[i * 4 + 1] * b[j] + a[i * 4 + 2] * b[4 + j] + a[i * 4 + 3] * b[8 + j] + a[i * 4 + 4] * b[12 + j]
        end
    end
    return r
end
PiezaRobot.multiplicar = multiplicar

--- a·b escrito en `r` (que no sea ni a ni b), sin crear tablas: con 20 robots
-- de 100-180 piezas, una tabla nueva por pieza y cuadro llenaba la memoria
-- y el recolector paraba el juego (tirones de hasta 1,4 s, 18-nov).
local function multiplicarEn(a, b, r)
    for i = 0, 3 do
        local a1, a2, a3, a4 = a[i * 4 + 1], a[i * 4 + 2], a[i * 4 + 3], a[i * 4 + 4]
        for j = 1, 4 do
            r[i * 4 + j] = a1 * b[j] + a2 * b[4 + j] + a3 * b[8 + j] + a4 * b[12 + j]
        end
    end
    return r
end
PiezaRobot.multiplicarEn = multiplicarEn

-- Tablas de paso de local_ (una sola vez a la vez: no se anida).
local pasoA, pasoB, paso = {}, {}, {}
local function rotacionEn(eje, a, r)
    local c, s = math.cos(a), math.sin(a)
    for i = 1, 16 do
        r[i] = 0
    end
    r[16] = 1
    if eje == 'x' then
        r[1], r[6], r[7], r[10], r[11] = 1, c, -s, s, c
    elseif eje == 'y' then
        r[1], r[3], r[6], r[9], r[11] = c, s, 1, -s, c
    else
        r[1], r[2], r[5], r[6], r[11] = c, -s, s, c, 1
    end
    return r
end

--- La capa de quien llama (se crea la primera vez).
function PiezaRobot:capa(nombreCapa)
    local clave = (self.robot.actual or 'robot') .. '/' .. (nombreCapa or '')
    local c = self.porClave[clave]
    if not c then
        c = { clave = clave, eje = 'z', angulo = 0, x = 0, y = 0, z = 0 }
        self.porClave[clave] = c
        self.capas[#self.capas + 1] = c
        self.movil = true
    end
    return c
end

--- Matriz local de este cuadro: la de reposo por las capas. Devuelve una
-- tabla de paso (o la de reposo): úsala antes de volver a llamar.
function PiezaRobot:local_()
    local m = self.fija or self.datos.matriz
    local libre = pasoA
    for _, c in ipairs(self.capas) do
        if c.x ~= 0 or c.y ~= 0 or c.z ~= 0 then
            for i = 1, 16 do
                paso[i] = 0
            end
            paso[1], paso[6], paso[11], paso[16] = 1, 1, 1, 1
            paso[4], paso[8], paso[12] = c.x, c.y, c.z
            m = multiplicarEn(m, paso, libre)
            libre = libre == pasoA and pasoB or pasoA
        end
        if c.angulo ~= 0 then
            m = multiplicarEn(m, rotacionEn(c.eje, c.angulo, paso), libre)
            libre = libre == pasoA and pasoB or pasoA
        end
    end
    return m
end

--- Su matriz en el mundo con la de su madre (o la raíz): en su propia tabla.
function PiezaRobot:colocarEn(padre)
    self.mundo = multiplicarEn(padre, self:local_(), self.mundo or {})
end

-- Cambiar ------------------------------------------------------------------

--- Gira `angulo` radianes sobre su eje `'x'`, `'y'` o `'z'`, en su pivote.
---@param eje string
---@param angulo number
---@param nombreCapa? string
function PiezaRobot:setGiro(eje, angulo, nombreCapa)
    local c = self:capa(nombreCapa)
    c.eje, c.angulo = eje, angulo
end

--- La desplaza (metros, en sus ejes) desde su sitio.
function PiezaRobot:setDesplazamiento(x, y, z, nombreCapa)
    local c = self:capa(nombreCapa)
    c.x, c.y, c.z = x or 0, y or 0, z or 0
end

--- Su matriz local entera (respecto al padre, por filas), en lugar de la
-- de reposo; las capas se aplican encima. nil: vuelve a la de reposo. (Las
-- tejas de las orugas, que van por un camino.)
function PiezaRobot:setMatrizLocal(m)
    self.fija = m
    if m then
        self.movil = true
    end
end

--- `false` la oculta (y a sus hijas); `true` la vuelve a mostrar.
function PiezaRobot:setVisible(visible)
    self.visible = visible ~= false
    -- `movil`: alguna especialización la mueve o la oculta (las copias de
    -- lejos, <modelo>_lod1/2.glb, solo la dejan aparte si lo es).
    self.movil = true
end

-- Leer ---------------------------------------------------------------------

function PiezaRobot:getVisible()
    return self.visible
end

function PiezaRobot:getPadre()
    return self.padre
end

function PiezaRobot:getHijas()
    return self.hijas
end

--- x, y, z de su pivote en el almacén (metros).
function PiezaRobot:getPosicion()
    local m = self.mundo
    if not m then
        return nil
    end
    return m[4], m[8], m[12]
end

--- Un punto (x, y, z) de la pieza, en el almacén.
function PiezaRobot:getPunto(x, y, z)
    local m = self.mundo
    return m[1] * x + m[2] * y + m[3] * z + m[4], m[5] * x + m[6] * y + m[7] * z + m[8], m[9] * x + m[10] * y + m[11] * z + m[12]
end

--- Su matriz en el almacén (4x4 por filas; solo leer).
function PiezaRobot:getMatriz()
    return self.mundo
end

--- `eje, angulo` de una capa (la tuya, o la de otra especialización).
function PiezaRobot:getGiro(nombreCapa, especializacion)
    local c = self.porClave[(especializacion or self.robot.actual or 'robot') .. '/' .. (nombreCapa or '')]
    if not c then
        return 'z', 0
    end
    return c.eje, c.angulo
end

return PiezaRobot
