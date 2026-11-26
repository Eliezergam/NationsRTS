-- Línea de montaje de misiles de la fábrica del almacén (plano aprobado por
-- El dueño el 2026-11-17): un misil cada vez por los 4 puestos en U
--   1 cuerpo (motor y guiado)  →  2 aletas  →  3 ojiva  →  4 pintura
-- y la grúa puente lo lleva de un puesto al siguiente y, al final, a la caja
-- abierta de una de las dos mesas de encajado (una por pasillo del polvorín,
-- por turnos; lo gira 90° en el aire). Al dejarlo dentro, la tapa se cierra
-- y la caja queda llena para el robot grande, que se la lleva y deja otra
-- vacía: entonces la tapa se abre sola (cuando el robot se ha apartado).
--
-- La grúa, como las de taller: el puente corre por los carriles (x), el carro
-- por el puente (y) y el polipasto sube y baja el gancho; el gancho lleva un
-- balancín con dos eslingas que se enganchan a las bandas de manejo del
-- misil. Se mueve con aceleración y frenada suaves, y siempre sube a la
-- altura de paso antes de ir a otro sitio.
--
-- Datos: assets/almacen/fabrica.lua (puestos, alturas) y las plantillas del
-- modelo del almacén (plantillaGruaPuente/Carro/Cable/Gancho,
-- plantillaMisil1..4). Medidas en metros, ejes del almacén.

local dream = require('lib.3DreamEngine')

local Fabrica = {}
Fabrica.__index = Fabrica

Fabrica.DATOS = 'assets/almacen/fabrica.lua'
Fabrica.velocidadPuente = 0.5 -- m/s
Fabrica.velocidadCarro = 0.4
Fabrica.velocidadGancho = 0.3
Fabrica.velocidadGiro = 0.3 -- rad/s del gancho con la carga
Fabrica.aceleracion = 0.25 -- m/s² al arrancar y frenar
Fabrica.alturaPaso = 4.4 -- m del eje del misil al ir de un sitio a otro (por encima del robot grande, 3,6 m)
Fabrica.trabajo = { 8, 8, 8, 6 } -- s de trabajo en cada puesto
Fabrica.cerrarTapa = 4 -- s que tarda en cerrarse la tapa
Fabrica.rumboPuestos = -math.pi / 2 -- el misil en los puestos, a lo largo de x
-- Lo que gasta cada misil (decisión del dueño, 2026-11-17): una paca de
-- dinero, una caja de metal y una garrafa de petróleo. El robot pequeño lo
-- lleva al depósito del misil y la línea no empieza un misil sin ello.
Fabrica.coste = { dinero = 200, metal = 10, petroleo = 10 }
Fabrica.RECURSOS = { 'dinero', 'metal', 'petroleo' }
Fabrica.reserva = 2 -- misiles para los que el robot deja preparado el depósito

local function acercar(actual, objetivo, vMax, v, dt, a)
    -- Velocidad con aceleración y frenada (v² = 2·a·d).
    local d = objetivo - actual
    local frenar = math.sqrt(2 * a * math.abs(d))
    local deseada = math.min(vMax, frenar) * (d >= 0 and 1 or -1)
    v = v + math.max(-a * dt, math.min(a * dt, deseada - v))
    if math.abs(d) < 0.003 then
        return objetivo, 0
    end
    local nuevo = actual + v * dt
    if (objetivo - nuevo) * d <= 0 then
        return objetivo, 0
    end
    return nuevo, v
end

local function esperar(condicion)
    while not condicion() do
        coroutine.yield()
    end
end

--- `objeto`: el modelo del almacén (con las plantillas); `carriles`: las
-- mesas de encajado ({ mesa = { x, y, z }, caja = la que tiene encima });
-- `abierta`: lo que abre la tapa de la caja.
function Fabrica.nueva(objeto, carriles, abierta)
    local self = setmetatable({}, Fabrica)
    self.datos = love.filesystem.load(Fabrica.DATOS)()
    local o = objeto.objects
    self.mallas = {
        puente = o.plantillaGruaPuente,
        carro = o.plantillaGruaCarro,
        cable = o.plantillaGruaCable,
        gancho = o.plantillaGruaGancho,
        misil = { o.plantillaMisil1, o.plantillaMisil2, o.plantillaMisil3, o.plantillaMisil4 },
    }
    self.carriles = carriles
    self.abierta = abierta
    self.robotCerca = function() return false end
    -- La grúa empieza en reposo sobre el puesto 1, con el gancho arriba.
    local p = self.datos.puestos[1]
    self.grua = { x = p[1], y = 0, z = self.datos.cableZ - 1.2, giro = Fabrica.rumboPuestos, vx = 0, vy = 0, vz = 0 }
    self.reloj = 0
    self.estado = 'esperando'
    -- Misiles pedidos (los pide el jugador con el menú de la fábrica, E junto a la mesa);
    -- para probar, ALMACEN_PEDIR=N.
    self.pedidos = tonumber(os.getenv('ALMACEN_PEDIR')) or 0
    return self
end

-- Movimientos de la grúa (dentro de la corrutina) ------------------------------

function Fabrica:moverGrua(x, y)
    local g = self.grua
    g.destino = { x, y }
    esperar(function() return g.x == x and g.y == y end)
    g.destino = nil
end

function Fabrica:subirGancho(z)
    local g = self.grua
    g.zDestino = z
    esperar(function() return g.z == z end)
    g.zDestino = nil
end

function Fabrica:girarGancho(rumbo)
    local g = self.grua
    g.giroDestino = rumbo
    esperar(function() return g.giro == rumbo end)
    g.giroDestino = nil
end

function Fabrica:pausa(segundos)
    local hasta = self.reloj + segundos
    esperar(function() return self.reloj >= hasta end)
end

--- Lleva el misil de donde está a (x, y) con su eje a `ejeZ` y mirando a
-- `rumbo`: baja a por él, lo engancha, sube a la altura de paso, va, gira y
-- lo baja.
function Fabrica:llevarMisil(x, y, ejeZ, rumbo)
    local d = self.datos
    local m = self.misil
    local mx, my, mz = m:getPosicion()
    local paso = Fabrica.alturaPaso + d.cuelga
    self:subirGancho(paso)
    self:moverGrua(mx, my)
    self:girarGancho(m:getRumbo())
    self:subirGancho(mz + d.cuelga)
    self:pausa(1.5) -- enganchar las eslingas
    self.grua.carga = m
    self:subirGancho(paso)
    self:moverGrua(x, y)
    self:girarGancho(rumbo)
    self:subirGancho(ejeZ + d.cuelga)
    self:pausa(1.0)
    self.grua.carga = nil
    self:subirGancho(paso)
end

--- `f(x, y)`: true si el robot grande está junto a ese sitio (la grúa no
-- baja nada ni abre la tapa con él al lado).
function Fabrica:setRobotCerca(f)
    self.robotCerca = f
end

-- Una caja vacía, abierta, en su mesa y sin el robot al lado.
function Fabrica:mesaLista(carril)
    local c = carril.caja
    if not (c and not c:getLleno() and not c.llevadoPor and c:getTapa() >= self.abierta - 0.001) then
        return false
    end
    local m = carril.mesa
    return not self.robotCerca(m[1], m[2])
end

-- Las tapas de las cajas vacías que el robot deja en las mesas se abren
-- solas cuando se ha apartado.
function Fabrica:abrirTapas(dt)
    for _, carril in ipairs(self.carriles) do
        local c = carril.caja
        local m = carril.mesa
        if c and not c.enGrua and not c:getLleno() and not c.llevadoPor and c:getTapa() < self.abierta and not self.robotCerca(m[1], m[2]) then
            c:setTapa(math.min(self.abierta, c:getTapa() + self.abierta * dt / Fabrica.cerrarTapa))
        end
    end
end

function Fabrica:etapa(k)
    self.misil:setMalla(self.mallas.misil[k])
    self.etapaActual = k
end

--- El depósito del misil (objeto `depositoMisil`, con sus zonas por recurso)
-- y `pagar(coste)`: cobra a la partida lo que se gasta.
function Fabrica:setDeposito(deposito, pagar)
    self.deposito = deposito
    self.pagar = pagar
end

-- Lo que hay de `recurso` en el depósito: la suma y los objetos.
function Fabrica:enDeposito(recurso)
    local dep = self.deposito
    local suma, objetos = 0, {}
    for _, k in ipairs(dep and dep.datos.zonas[recurso] or {}) do
        local o = dep.huecosOcupados[k]
        if o and not o:getLlevadoPor() then
            suma = suma + (o.cantidad or 0)
            objetos[#objetos + 1] = o
        end
    end
    return suma, objetos
end

--- Lo que falta en el depósito para los misiles que esperan (hasta
-- `Fabrica.reserva`): { recurso = cantidad } (vacío si no falta nada).
function Fabrica:getFaltaEnDeposito()
    local misiles = math.min(Fabrica.reserva, self.pedidos + (self.esperandoMateriales and 1 or 0))
    local falta = {}
    for _, recurso in ipairs(Fabrica.RECURSOS) do
        local n = misiles * Fabrica.coste[recurso] - self:enDeposito(recurso)
        if n > 0 then
            falta[recurso] = n
        end
    end
    return falta
end

-- ¿Hay en el depósito lo de un misil?
function Fabrica:materialesListos()
    for _, recurso in ipairs(Fabrica.RECURSOS) do
        if self:enDeposito(recurso) < Fabrica.coste[recurso] then
            return false
        end
    end
    return true
end

-- Gasta del depósito lo de un misil (primero lo que sobró de otros) y lo
-- cobra a la partida.
function Fabrica:gastarMateriales()
    for _, recurso in ipairs(Fabrica.RECURSOS) do
        local falta = Fabrica.coste[recurso]
        local _, objetos = self:enDeposito(recurso)
        table.sort(objetos, function(a, b) return (a.cantidad or 0) < (b.cantidad or 0) end)
        for _, o in ipairs(objetos) do
            if falta <= 0 then
                break
            end
            local toma = math.min(o.cantidad or 0, falta)
            o.cantidad = (o.cantidad or 0) - toma
            falta = falta - toma
            if o.cantidad <= 0 then
                GestorObjetos.quitar(o)
            end
        end
    end
    local bien, motivo = true, nil
    if self.pagar then
        bien, motivo = self.pagar(Fabrica.coste)
    end
    print(string.format('FABRICA gastados del depósito 200 de dinero, 10 de metal y 10 de petróleo (partida: %s)', bien and 'pagado' or ('NO pagado: ' .. tostring(motivo))))
end

--- Pide `n` misiles más (0 o menos: para cuando acabe el que monta).
function Fabrica:setPedir(n)
    if n <= 0 then
        self.pedidos = 0
    else
        self.pedidos = self.pedidos + n
    end
end

--- Misiles pedidos que faltan por empezar.
function Fabrica:getPedidos()
    return self.pedidos
end

--- 1 si hay un misil empezado (de la línea a la caja), 0 si no.
function Fabrica:getEnCurso()
    return self.enCurso and 1 or 0
end

-- Un misil entero, del puesto 1 a la caja (cuando hay alguno pedido).
function Fabrica:montarUno()
    local d = self.datos
    local p = d.puestos
    self.estado = 'sin pedidos'
    esperar(function() return self.pedidos > 0 end)
    self.pedidos = self.pedidos - 1
    self.enCurso = true
    -- Lo de este misil, del depósito (lo trae el robot pequeño).
    if not self:materialesListos() then
        self.esperandoMateriales = true
        self.estado = 'esperando dinero, metal y petróleo en el depósito'
        esperar(function() return self:materialesListos() end)
        self.esperandoMateriales = false
    end
    self:gastarMateriales()
    self.estado = 'montando'
    self.misil = GestorObjetos.crear('misil', p[1][1], p[1][2], d.ejeZ, Fabrica.rumboPuestos)
    self:etapa(1)
    print('FABRICA misil nuevo en el puesto 1 (motor y guiado)')
    self:pausa(Fabrica.trabajo[1])
    for k = 2, 4 do
        self:llevarMisil(p[k][1], p[k][2], d.ejeZ, Fabrica.rumboPuestos)
        print('FABRICA misil en el puesto ' .. k)
        self:pausa(Fabrica.trabajo[k] * 0.5)
        self:etapa(k)
        self:pausa(Fabrica.trabajo[k] * 0.5)
    end
    -- A la caja de una mesa (abierta y vacía; por turnos si están las dos
    -- listas), girándolo 90° en el aire.
    self.estado = 'esperando una caja vacía'
    local carril
    esperar(function()
        local n = #self.carriles
        for i = 1, n do
            local c = self.carriles[((self.ultimaMesa or 0) + i - 1) % n + 1]
            if self:mesaLista(c) then
                carril = c
                return true
            end
        end
        return false
    end)
    for k, c in ipairs(self.carriles) do
        if c == carril then
            self.ultimaMesa = k
        end
    end
    self.estado = 'montando'
    local caja = carril.caja
    caja.enGrua = true -- la tapa, la mueve la grúa (no abrirTapas)
    local cx, cy, cz = caja:getPosicion()
    self:llevarMisil(cx, cy, cz + d.ejeEnCaja, caja:getRumbo())
    -- Cerrar la tapa y la caja queda llena (el misil va dentro).
    self.estado = 'cerrando'
    local abierta = caja:getTapa()
    local t = 0
    esperar(function()
        t = t + self.dt
        caja:setTapa(abierta * math.max(0, 1 - t / Fabrica.cerrarTapa))
        return t >= Fabrica.cerrarTapa
    end)
    GestorObjetos.quitar(self.misil)
    self.misil = nil
    caja:setLleno(true)
    caja.enGrua = nil
    self.enCurso = false
    print(string.format('FABRICA misil encajado: la caja de la mesa de %.0f está llena y cerrada', carril.pasillo))
    self.estado = 'esperando'
end

function Fabrica:actualizar(dt)
    self.dt = dt
    self.reloj = self.reloj + dt
    self:abrirTapas(dt)
    -- La grúa.
    local g = self.grua
    local F = Fabrica
    if g.destino then
        g.x, g.vx = acercar(g.x, g.destino[1], F.velocidadPuente, g.vx, dt, F.aceleracion)
        g.y, g.vy = acercar(g.y, g.destino[2], F.velocidadCarro, g.vy, dt, F.aceleracion)
    end
    if g.zDestino then
        g.z, g.vz = acercar(g.z, g.zDestino, F.velocidadGancho, g.vz, dt, F.aceleracion)
    end
    if g.giroDestino then
        local d = (g.giroDestino - g.giro + math.pi) % (2 * math.pi) - math.pi
        local paso = F.velocidadGiro * dt
        if math.abs(d) <= paso then
            g.giro = g.giroDestino
        else
            g.giro = g.giro + paso * (d > 0 and 1 or -1)
        end
    end
    if g.carga then
        g.carga:setPosicion(g.x, g.y, g.z - self.datos.cuelga, g.giro)
    end
    -- El trabajo: un misil detrás de otro.
    if not self.vuelta or coroutine.status(self.vuelta) == 'dead' then
        self.vuelta = coroutine.create(function()
            self:montarUno()
        end)
    end
    local bien, fallo = coroutine.resume(self.vuelta)
    if not bien then
        error(fallo)
    end
end

--- Qué está haciendo la línea, en palabras.
function Fabrica:getEstado()
    if self.estado == 'montando' then
        return 'montando un misil (etapa ' .. (self.etapaActual or 1) .. ')'
    end
    return self.estado
end

function Fabrica:dibujar()
    local aDream = GestorObjetos.aDream
    local g = self.grua
    local m = self.mallas
    m.puente:setTransform(aDream({ 1, 0, 0, g.x, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }))
    m.puente.dynamic = true
    dream:draw(m.puente)
    m.carro:setTransform(aDream({ 1, 0, 0, g.x, 0, 1, 0, g.y, 0, 0, 1, 0, 0, 0, 0, 1 }))
    m.carro.dynamic = true
    dream:draw(m.carro)
    local largo = self.datos.cableZ - g.z
    m.cable:setTransform(aDream({ 1, 0, 0, g.x, 0, 1, 0, g.y, 0, 0, largo, g.z, 0, 0, 0, 1 }))
    m.cable.dynamic = true
    dream:draw(m.cable)
    local c, s = math.cos(g.giro), math.sin(g.giro)
    m.gancho:setTransform(aDream({ c, -s, 0, g.x, s, c, 0, g.y, 0, 0, 1, g.z, 0, 0, 0, 1 }))
    m.gancho.dynamic = true
    dream:draw(m.gancho)
end

return Fabrica
