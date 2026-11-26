-- Una pieza de un vehículo concreto (batalla/vehiculos/vehiculo.lua).
--
-- No es una copia de la malla: todos los camiones iguales comparten las
-- mallas y se dibujan juntos (batalla/dream/lote_articulado.lua). La pieza
-- solo escribe en su unidad:
--   unidad.ajustesPiezas[nombre]   giro y desplazamiento sobre su pivote
--                                  (ArticulacionCamion:matrizLocal); sus
--                                  hijas la siguen
--   unidad.piezasOcultas[nombre]   quién la oculta (Lanzamisiles.visible)
--   unidad.apuntes[nombre]         a qué mira (pieza:setApuntarA)
--
-- Capas: cada especialización que mueve la pieza tiene su propia capa (la
-- que está llamando el vehículo, `vehiculo.actual`). Si una especialización
-- necesita dos giros a la vez (la rueda: el volante y lo que rueda), les da
-- nombre: `pieza:setGiro('z', volante, 'direccion')` y
-- `pieza:setGiro('y', rodado, 'rodar')` son dos capas suyas. `setGiro` y
-- `setDesplazamiento` sustituyen lo de SU capa, y las capas se suman en el orden en que cada
-- especialización tocó la pieza por primera vez. Así tres scripts pueden
-- mover la misma rampa sin borrarse: uno la sube, otro la hace temblar al
-- disparar, otro la inclina un poco... Igual con `setVisible(false)`: basta
-- con que una especialización la oculte para que no se dibuje.
--
-- Restricción (como «Track To» de Blender): `pieza:setApuntarA(destino, x, y, z)`
-- gira la pieza lo mínimo para que mire al punto (x, y, z) de la pieza
-- `destino` (sin punto, a su pivote), con el destino de este mismo cuadro:
-- así se estiran los amortiguadores y el pistón. Su eje es el que en reposo
-- ya mira al destino. `pieza:setApuntarA(nil)` la quita.
--
-- Cambiar (set): setGiro, setDesplazamiento, setVisible, setApuntarA.
-- Leer (get; todo en ejes y medidas del juego):
--   pieza.nombre
--   pieza:getPadre()            la pieza de la que cuelga (nil la raíz)
--   pieza:getHijas()            las que cuelgan de ella
--   pieza:getPivote()           x, y, z del pivote, relativo a su padre
--   pieza:getPivoteVehiculo()   x, y, z del pivote en el vehículo (en reposo)
--   pieza:getMatriz()           su matriz en el mundo de este cuadro (4x4 por
--                            filas, Matriz); solo para leer
--   pieza:getPosicion()         x, y, z de su pivote en el mundo
--   pieza:getRotacion()         rumbo, cabeceo y balanceo en el mundo
--   pieza:getCaja()             la caja de su malla alrededor del pivote:
--                            minX, minY, minZ, maxX, maxY, maxZ
--   pieza:getTamano()           largo (x), ancho (y) y alto (z) de esa caja
--   pieza:getGiro(capa, especializacion)            eje y ángulo de una capa:
--                            la de quien llama, o la de otra especialización
--                            (pieza:getGiro('rodar', 'ruedas'))
--   pieza:getDesplazamiento(capa, especializacion)  x, y, z de una capa
--   pieza:getVisible()
--   pieza:getApuntarA()          nombre del destino y x, y, z del punto
--
-- Ejes y medidas del juego: x hacia delante, y a la izquierda, z arriba;
-- ángulos en radianes; desplazamientos en px (1 px = 10 cm).

local Matriz = require('batalla.matriz')

---@class Pieza
---@field nombre string
---@field vehiculo Vehiculo
---@field unidad table
---@field datos table sus datos en el modelo (malla, pivote, padre)
---@field capas table[] sus capas, en orden
---@field porFuente table<string, table> cada capa por su clave
---@field trabajo table[] matrices de trabajo
local Pieza = {}
Pieza.__index = Pieza

-- Para lo que se llama fuera de una especialización.
local FUERA = 'fuera'

--- La pieza `nombre` del vehículo `vehiculo`.
---@param vehiculo Vehiculo
---@param nombre string
---@return Pieza
function Pieza.nueva(vehiculo, nombre)
    local self = setmetatable({}, Pieza)
    self.vehiculo = vehiculo
    self.unidad = vehiculo.unidad
    self.nombre = nombre
    self.datos = vehiculo.modelo.piezas[nombre]
    self.capas = {}
    self.porFuente = {}
    self.trabajo = { {}, {} }
    return self
end

--- Clave de la capa: la especialización `especializacion` (o la que está
-- llamando) y, si la nombra, su capa.
---@param nombreCapa? string
---@param especializacion? string
---@return string
function Pieza:clave(nombreCapa, especializacion)
    local fuente = especializacion or self.vehiculo.actual or FUERA
    if nombreCapa then
        return fuente .. '/' .. nombreCapa
    end
    return fuente
end

--- La capa `nombreCapa` (o la única) de quien llama; se crea la primera vez.
---@param nombreCapa? string
---@return table
function Pieza:capa(nombreCapa)
    local fuente = self:clave(nombreCapa)
    local capa = self.porFuente[fuente]
    if not capa then
        capa = { fuente = fuente, eje = 'y', angulo = 0, x = 0, y = 0, z = 0 }
        self.porFuente[fuente] = capa
        self.capas[#self.capas + 1] = capa
    end
    return capa
end

--- Matriz de giro `angulo` sobre el eje `eje` con traslación (x, y, z).
local function matrizCapa(eje, angulo, x, y, z, r)
    local c, s = math.cos(angulo), math.sin(angulo)
    if eje == 'x' then
        r[1], r[2], r[3], r[4] = 1, 0, 0, x
        r[5], r[6], r[7], r[8] = 0, c, -s, y
        r[9], r[10], r[11], r[12] = 0, s, c, z
        r[13], r[14], r[15], r[16] = 0, 0, 0, 1
        return r
    elseif eje == 'z' then
        return Matriz.colocar(x, y, z, angulo, 1, r)
    end
    return Matriz.cabecear(angulo, x, y, z, r)
end

--- Rehace el ajuste de la unidad: todas las capas, una tras otra.
function Pieza:aplicar()
    local unidad = self.unidad
    unidad.ajustesPiezas = unidad.ajustesPiezas or {}
    local total = unidad.ajustesPiezas[self.nombre] or {}
    Matriz.colocar(0, 0, 0, 0, 1, total)
    local capaMatriz, copia = self.trabajo[1], self.trabajo[2]
    for _, capa in ipairs(self.capas) do
        matrizCapa(capa.eje, capa.angulo, capa.x, capa.y, capa.z, capaMatriz)
        for i = 1, 16 do
            copia[i] = total[i]
        end
        Matriz.multiplicar(copia, capaMatriz, total)
    end
    unidad.ajustesPiezas[self.nombre] = total
    -- Las matrices se recalculan aunque el camión esté quieto
    -- (ArticulacionCamion:firma). Las piezas que se recomponen en cada
    -- cuadro de todos modos (los ventiladores) no lo fuerzan: con el camión
    -- parado se rehacen solas, sin recalcular todo el camión.
    if not self.vehiculo:recomponeSiempre(self.nombre) then
        unidad.versionAjustes = (unidad.versionAjustes or 0) + 1
    end
end

--- Gira la pieza `angulo` radianes sobre su eje `eje` ('x', 'y' o 'z'),
-- alrededor de su pivote. Sustituye el giro anterior de esta capa
-- (`nombreCapa`, opcional, para tener varias).
---@param eje Eje
---@param angulo number radianes
---@param nombreCapa? string
function Pieza:setGiro(eje, angulo, nombreCapa)
    local capa = self:capa(nombreCapa)
    if eje == capa.eje and angulo == capa.angulo then
        return
    end
    capa.eje = eje
    capa.angulo = angulo
    self:aplicar()
end

--- Desplaza la pieza (x, y, z) px desde su sitio. Sustituye el
-- desplazamiento anterior de esta capa (`nombreCapa`, opcional).
---@param x number px
---@param y number px
---@param z number px
---@param nombreCapa? string
function Pieza:setDesplazamiento(x, y, z, nombreCapa)
    local capa = self:capa(nombreCapa)
    if x == capa.x and y == capa.y and z == capa.z then
        return
    end
    capa.x, capa.y, capa.z = x, y, z
    self:aplicar()
end

--- Muestra (`true`) u oculta (`false`) la pieza. Cada especialización
-- oculta por su cuenta: no se dibuja mientras alguna la tenga oculta.
---@param visible boolean
function Pieza:setVisible(visible)
    local unidad = self.unidad
    local quien = self.vehiculo.actual or FUERA
    unidad.piezasOcultas = unidad.piezasOcultas or {}
    local ocultas = unidad.piezasOcultas
    if visible then
        local lista = ocultas[self.nombre]
        if lista then
            lista[quien] = nil
            if next(lista) == nil then
                ocultas[self.nombre] = nil
            end
        end
        return
    end
    local lista = ocultas[self.nombre]
    if not lista then
        lista = {}
        ocultas[self.nombre] = lista
    end
    lista[quien] = true
end

--- ¿Se dibuja la pieza?
---@return boolean
function Pieza:getVisible()
    local ocultas = self.unidad.piezasOcultas
    return not (ocultas and ocultas[self.nombre])
end

--- Hace que la pieza mire al punto (x, y, z) de la pieza `destino` (nombre o
-- pieza; sin punto, a su pivote) en cada cuadro. Con `nil`, deja de mirar.
---@param destino PiezaCamion|string|Pieza|nil
---@param x? number
---@param y? number
---@param z? number
function Pieza:setApuntarA(destino, x, y, z)
    if destino == nil then
        local apuntes = self.unidad.apuntes
        if apuntes and apuntes[self.nombre] then
            apuntes[self.nombre] = nil
            self.unidad.versionAjustes = (self.unidad.versionAjustes or 0) + 1
        end
        return
    end
    if type(destino) ~= 'string' then
        destino = destino.nombre
    end
    ---@cast destino string
    assert(self.vehiculo:getTienePieza(destino), 'Pieza: el modelo no tiene la pieza ' .. tostring(destino))
    local unidad = self.unidad
    unidad.apuntes = unidad.apuntes or {}
    local px, py, pz = self:getPivoteVehiculo()
    local dx, dy, dz = self.vehiculo:getPieza(destino):getPivoteVehiculo()
    local ax, ay, az = dx + (x or 0) - px, dy + (y or 0) - py, dz + (z or 0) - pz
    local largo = math.sqrt(ax * ax + ay * ay + az * az)
    unidad.apuntes[self.nombre] = {
        pieza = destino,
        punto = { x or 0, y or 0, z or 0 },
        -- La dirección que mira en reposo.
        reposo = { ax / largo, ay / largo, az / largo },
    }
    -- Se calcula después de su destino (ArticulacionCamion:despuesDe).
    local articulacion = self.vehiculo.lanzador and self.vehiculo.lanzador.articulacion
    if articulacion then
        articulacion:despuesDe(self.nombre, destino)
    end
    unidad.versionAjustes = (unidad.versionAjustes or 0) + 1
end

--- ¿A qué mira? Nombre de la pieza destino y x, y, z del punto (nil si a
-- nada).
---@return string? destino
---@return number? x
---@return number? y
---@return number? z
function Pieza:getApuntarA()
    local apunte = self.unidad.apuntes and self.unidad.apuntes[self.nombre]
    if not apunte then
        return nil
    end
    local p = apunte.punto
    return apunte.pieza, p[1], p[2], p[3]
end

--- La pieza de la que cuelga (nil la raíz).
---@return Pieza? padre
function Pieza:getPadre()
    local padre = self.datos.padre
    if padre and self.vehiculo:getTienePieza(padre) then
        return self.vehiculo:getPieza(padre)
    end
    return nil
end

--- Las piezas que cuelgan de esta, por nombre.
---@return Pieza[] hijas
function Pieza:getHijas()
    local hijas = {}
    for nombre, datos in pairs(self.vehiculo.modelo.piezas) do
        if datos.padre == self.nombre then
            hijas[#hijas + 1] = nombre
        end
    end
    table.sort(hijas)
    for indice, nombre in ipairs(hijas) do
        hijas[indice] = self.vehiculo:getPieza(nombre)
    end
    return hijas
end

--- x, y, z del pivote, relativo a su padre (px).
---@return number x
---@return number y
---@return number z
function Pieza:getPivote()
    local p = self.datos.pivote
    return p[1], p[2], p[3]
end

--- x, y, z del pivote en el vehículo, con todo en reposo (px).
---@return number x
---@return number y
---@return number z
function Pieza:getPivoteVehiculo()
    local x, y, z = self:getPivote()
    local padre = self:getPadre()
    while padre do
        local px, py, pz = padre:getPivote()
        x, y, z = x + px, y + py, z + pz
        padre = padre:getPadre()
    end
    return x, y, z
end

--- Su matriz en el mundo de este cuadro (solo para leer). De lejos el
-- vehículo solo compone las piezas que dibuja: si esta no está, se componen
-- todas ahora (una vez por cuadro).
---@return number[] matriz 4x4 por filas
function Pieza:getMatriz()
    local unidad = self.unidad
    local filtro = unidad.filtroMatrices
    local lanzador = self.vehiculo.lanzador
    if filtro and not filtro[self.nombre] and lanzador and not unidad.muerto then
        lanzador:actualizarTodas(unidad)
    end
    return self.vehiculo.matrices[self.nombre]
end

--- x, y, z de su pivote en el mundo (px).
---@return number x
---@return number y
---@return number z
function Pieza:getPosicion()
    local m = self:getMatriz()
    return m[4], m[8], m[12]
end

--- Rumbo (sobre z), cabeceo (sobre y, como Matriz.cabecear: negativo sube
-- la punta) y balanceo (sobre x) de la pieza en el mundo, en radianes.
---@return number rumbo
---@return number cabeceo
---@return number balanceo
function Pieza:getRotacion()
    local m = self:getMatriz()
    local rumbo = math.atan2(m[5], m[1])
    local cabeceo = math.asin(math.max(-1, math.min(1, -m[9])))
    local balanceo = math.atan2(m[10], m[11])
    return rumbo, cabeceo, balanceo
end

--- La caja de su malla alrededor del pivote (px), medida una vez por modelo.
---@return number minX
---@return number minY
---@return number minZ
---@return number maxX
---@return number maxY
---@return number maxZ
function Pieza:getCaja()
    local datos = self.datos
    if not datos.caja then
        local minX, minY, minZ = math.huge, math.huge, math.huge
        local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
        local malla = datos.malla
        for i = 1, malla:getVertexCount() do
            local x, y, z = malla:getVertex(i)
            minX, maxX = math.min(minX, x), math.max(maxX, x)
            minY, maxY = math.min(minY, y), math.max(maxY, y)
            minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
        end
        datos.caja = { minX, minY, minZ, maxX, maxY, maxZ }
    end
    local c = datos.caja
    return c[1], c[2], c[3], c[4], c[5], c[6]
end

--- Largo (x), ancho (y) y alto (z) de su caja (px).
---@return number largo
---@return number ancho
---@return number alto
function Pieza:getTamano()
    local minX, minY, minZ, maxX, maxY, maxZ = self:getCaja()
    return maxX - minX, maxY - minY, maxZ - minZ
end

--- Eje y ángulo del giro de la capa de quien llama ('y', 0 si no la ha
-- girado).
---@param nombreCapa? string
---@param especializacion? string
---@return Eje eje
---@return number angulo
function Pieza:getGiro(nombreCapa, especializacion)
    local capa = self.porFuente[self:clave(nombreCapa, especializacion)]
    if not capa then
        return 'y', 0
    end
    return capa.eje, capa.angulo
end

--- x, y, z del desplazamiento de la capa de quien llama.
---@param nombreCapa? string
---@param especializacion? string
---@return number x
---@return number y
---@return number z
function Pieza:getDesplazamiento(nombreCapa, especializacion)
    local capa = self.porFuente[self:clave(nombreCapa, especializacion)]
    if not capa then
        return 0, 0, 0
    end
    return capa.x, capa.y, capa.z
end

return Pieza
