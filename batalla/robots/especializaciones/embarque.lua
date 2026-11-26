-- Embarque del avión de carga (el dueño, 20-nov: «que los robots entren y se
-- acomoden en filas y bien ordenados»). Va en el avión (tipos/avionCarga.lua),
-- detrás de `vueloAvion`.
--
-- Como los vehículos de Arma (Bohemia): el avión tiene huecos de carga fijos
-- en la bodega y cada pasajero recibe uno. Como las formaciones de los RTS:
-- se llena de delante hacia atrás (nadie tapa el paso a los que vienen) y,
-- en cada fila, de fuera hacia el centro (el pasillo central queda libre
-- hasta el último). Cada uno:
--   1. espera formado junto a la pista;
--   2. le toca (de uno en uno, cada `intervalo` s, el más cercano primero):
--      va al pie de la rampa, sube, recorre el pasillo central hasta la
--      fila de detrás de la suya, se aparta a su columna y avanza a su
--      hueco, así llega mirando al frente;
--   3. en su hueco queda montado en el avión (como el conductor del camión,
--      sentado.lua): su raíz es la del avión por la del hueco, y viaja con él.
--
-- Mientras dura, el suelo de la bodega y la rampa son una superficie del
-- mundo (MundoBatalla.superficies): los pasajeros suben rodando de verdad.
--
-- Órdenes:
--   avion:setPasajeros(lista)    los robots que tienen que subir
--   avion:getEmbarquePendiente() true mientras falte alguno por sentarse
--   Embarque.hueco(k)            x, y (m, ejes del avión) del hueco k

local Nucleo = require('robots.nucleo')
local Mundo = require('batalla.robots.mundo')
local Robot = Nucleo.Robot

local Embarque = {}

Embarque.columnas = { -3, 3, -1.5, 1.5, 0 } -- m a un lado; en este orden se llenan
Embarque.frente = 14.0 -- x de la primera fila (el mamparo, a 16,5)
Embarque.pasoFila = 1.8
Embarque.suelo = 1.55 -- m del suelo de la bodega sobre el del avión
Embarque.bisagra = -16.5 -- x de la bisagra de la rampa
Embarque.puntaRampa = -19.6 -- x donde la rampa abierta toca el suelo
Embarque.medioAnchoBodega = 4.4
Embarque.medioAnchoRampa = 3.6
Embarque.fondo = -16.5 -- la bodega, de aquí al mamparo
Embarque.mamparo = 16.5
Embarque.pieRampa = -24 -- x del punto donde esperan su turno para subir
Embarque.intervalo = 2.0 -- s entre uno y el siguiente
-- Como el soldado de asalto, patinando (piernasSoldado.lua patina desde
-- 3 m/s; con 2,6 de tope iban con los pies juntos, el dueño, 20-nov), y
-- despacio solo al meterse en su hueco.
Embarque.velocidad = 6 -- m/s hasta la fila
Embarque.velocidadHueco = 2 -- m/s de la fila a su hueco
Embarque.paso = 0.9 -- m: a esto de un punto de paso, al siguiente

--- x, y (m, ejes del avión) del hueco k (1 el primero que se llena).
function Embarque.hueco(k)
    local n = #Embarque.columnas
    local fila = math.floor((k - 1) / n)
    local columna = Embarque.columnas[(k - 1) % n + 1]
    return Embarque.frente - fila * Embarque.pasoFila, columna
end

-- Mundo ← avión: (lx, ly, lz) por la matriz del avión.
local function aMundo(m, lx, ly, lz)
    return m[1] * lx + m[2] * ly + m[3] * lz + m[4],
        m[5] * lx + m[6] * ly + m[7] * lz + m[8],
        m[9] * lx + m[10] * ly + m[11] * lz + m[12]
end

-- Avión ← mundo, en horizontal (la traspuesta del giro).
local function aAvion(m, x, y)
    local dx, dy = x - m[4], y - m[8]
    return m[1] * dx + m[5] * dy, m[2] * dx + m[6] * dy
end

--- Superficie del mundo: el suelo de la bodega y la rampa abierta.
local Superficie = {}
Superficie.__index = Superficie

function Superficie:altura(x, y)
    local avion = self.avion
    local d = avion.datos.embarque
    if not d.activa then
        return nil
    end
    local m = avion.datos.vueloAvion.matriz
    if not m[1] then
        return nil
    end
    local lx, ly = aAvion(m, x, y)
    local E = Embarque
    if lx > E.fondo and lx < E.mamparo and math.abs(ly) < E.medioAnchoBodega then
        local _, _, z = aMundo(m, lx, ly, E.suelo)
        return z
    end
    local rampa = avion.datos.avionCarga.rampa or 0
    if rampa > 0.98 and lx <= E.fondo and lx > E.puntaRampa and math.abs(ly) < E.medioAnchoRampa then
        local _, _, z = aMundo(m, lx, ly, E.suelo * (lx - E.puntaRampa) / (E.bisagra - E.puntaRampa))
        return z
    end
    return nil
end

function Embarque.onLoad(self)
    local d = self.datos.embarque
    d.pasajeros = {}
    d.superficie = setmetatable({ avion = self }, Superficie)
    self.datos.vueloAvion.excluir = d.superficie
    local lista = Mundo.superficies
    lista[#lista + 1] = d.superficie
end

--- Los robots que tienen que subir. Los huecos van por cercanía al pie de
-- la rampa: el más cercano, el primer hueco (delante del todo).
-- Con `sentados`, ya van dentro, cada uno en su hueco (vienen de otro
-- sitio o salen sin embarcar delante de la cámara).
function Robot:setPasajeros(robots, sentados)
    local d = self.datos.embarque
    local m = self.datos.vueloAvion.matriz
    if not m[1] then
        local c, s = math.cos(self.rumbo), math.sin(self.rumbo)
        m = { c, -s, 0, self.x, s, c, 0, self.y, 0, 0, 1, 0, 0, 0, 0, 1 }
    end
    local px, py = aMundo(m, Embarque.pieRampa, 0, 0)
    local orden = {}
    for _, r in ipairs(robots) do
        orden[#orden + 1] = { robot = r, distancia = (r.x - px) ^ 2 + (r.y - py) ^ 2 }
    end
    table.sort(orden, function(a, b)
        return a.distancia < b.distancia
    end)
    d.pasajeros = {}
    for k, o in ipairs(orden) do
        local hx, hy = Embarque.hueco(k)
        d.pasajeros[k] = { robot = o.robot, hx = hx, hy = hy, estado = sentados and 'sentado' or 'espera', sx = hx, sy = hy }
        if sentados then
            o.robot.guardado = true
        end
    end
    d.reloj, d.soltados = 0, 0
end

function Robot:getEmbarquePendiente()
    local d = self.datos.embarque
    for _, p in ipairs(d.pasajeros) do
        if p.estado ~= 'sentado' then
            return true
        end
    end
    return false
end

-- Puntos de paso (ejes del avión) del pasajero `p`.
local function ruta(p)
    local detras = p.hx - Embarque.pasoFila
    return {
        { Embarque.pieRampa, 0 },
        { Embarque.bisagra + 1.5, 0 },
        { detras, 0 },
        { detras, p.hy, despacio = true },
        { p.hx, p.hy, final = true, despacio = true },
    }
end

-- Monta al pasajero en su hueco: raíz = avión · traslación del hueco. Los
-- primeros instantes se desliza (0,5 m/s) desde donde paró hasta el hueco.
local function montar(m, p, dt)
    local r = p.robot
    local dx, dy = p.hx - p.sx, p.hy - p.sy
    local l = math.sqrt(dx * dx + dy * dy)
    local paso = 0.5 * dt
    if l <= paso then
        p.sx, p.sy = p.hx, p.hy
    else
        p.sx, p.sy = p.sx + dx / l * paso, p.sy + dy / l * paso
    end
    local f = r.raizFija or {}
    for k = 1, 16 do
        f[k] = m[k]
    end
    f[4], f[8], f[12] = aMundo(m, p.sx, p.sy, Embarque.suelo)
    r.raizFija = f
    r.x, r.y, r.rumbo = f[4], f[8], math.atan2(m[5], m[1])
end

function Embarque.onUpdate(self, dt)
    local d = self.datos.embarque
    if #d.pasajeros == 0 then
        d.activa = false
        return
    end
    local m = self.datos.vueloAvion.matriz
    local rumboAvion = math.atan2(m[5], m[1])
    local abierta = (self.datos.avionCarga.rampa or 0) > 0.98
    d.activa = self.datos.vueloAvion.fase == 'embarque'
    d.reloj = (d.reloj or 0) + dt
    -- Suelta al siguiente cada `intervalo` s, con la rampa abajo.
    if abierta and d.activa and d.soltados < #d.pasajeros and d.reloj >= Embarque.intervalo then
        d.reloj = 0
        d.soltados = d.soltados + 1
        local p = d.pasajeros[d.soltados]
        p.estado, p.puntos, p.punto = 'subiendo', ruta(p), 1
        p.robot:setVelocidadMaxima(Embarque.velocidad)
    end
    for _, p in ipairs(d.pasajeros) do
        local r = p.robot
        if p.estado == 'subiendo' then
            local q = p.puntos[p.punto]
            local x, y = aMundo(m, q[1], q[2], 0)
            -- Cada punto se pide una vez (pedirlo cada cuadro no deja que la
            -- conducción lo dé por alcanzado).
            local nuevo = p.pedido ~= p.punto
            p.pedido = p.punto
            if q.final then
                if nuevo then
                    r:setVelocidadMaxima(Embarque.velocidadHueco)
                    r:setIrA(x, y, rumboAvion)
                end
                if r:getHaLlegado() and (r.x - x) ^ 2 + (r.y - y) ^ 2 < 0.6 ^ 2 then
                    r:setParar()
                    p.estado = 'sentado'
                    -- Desde donde paró, se desliza al hueco exacto (filas rectas).
                    p.sx, p.sy = aAvion(m, r.x, r.y)
                end
            else
                if nuevo then
                    r:setVelocidadMaxima(q.despacio and Embarque.velocidadHueco or Embarque.velocidad)
                    r:setIrA(x, y, nil, true)
                end
                if (r.x - x) ^ 2 + (r.y - y) ^ 2 < Embarque.paso ^ 2 then
                    p.punto = p.punto + 1
                end
            end
        end
        if p.estado == 'sentado' then
            -- Con la bodega cerrada (puertas y rampa arriba) no se ve: ni se
            -- actualiza ni se dibuja (robots/nucleo.lua, `guardado`). Al
            -- abrirse vuelve a salir en su hueco.
            local ac = self.datos.avionCarga
            r.guardado = (ac.rampa or 0) == 0 and (ac.puertas or 0) == 0
            if not r.guardado then
                montar(m, p, dt)
            end
        end
    end
    -- AVION_REGISTRO=1: una línea por segundo con cada pasajero (estado,
    -- punto, dónde está en ejes del avión y su altura sobre el suelo del avión).
    if os.getenv('AVION_REGISTRO') then
        d.registro = (d.registro or 0) + dt
        if d.registro > 1 then
            d.registro = 0
            local partes = {}
            for k, p in ipairs(d.pasajeros) do
                local lx, ly = aAvion(m, p.robot.x, p.robot.y)
                local z = (p.robot.zJuego or 0) / 10 - m[12]
                partes[#partes + 1] = string.format('%d:%s%s(%.1f,%.1f,%.2f)', k, p.estado:sub(1, 3), p.punto or '', lx, ly, z)
            end
            local guardados = 0
            for _, p in ipairs(d.pasajeros) do
                guardados = guardados + (p.robot.guardado and 1 or 0)
            end
            print('EMBARQUE rampa=' .. string.format('%.2f', self.datos.avionCarga.rampa or 0) .. ' guardados=' .. guardados .. ' ' .. table.concat(partes, ' '))
        end
    end
end

return Embarque
