--- Aviones de transporte: todo traslado del mapa va en avión
-- (diseno/aviones-de-transporte.md, decisiones del dueño del 20 y el 26-nov).
--
-- Módulo de `mundo/simulacion.lua` (`Aviones.instalar(Simulacion)`). Solo
-- datos y sin LÖVE, determinista como el resto de la simulación.
--
--   * Cada nación empieza con 5 aviones en su capital (el dueño, 26-nov: «al
--     principio el transporte no debería ser una limitación»); los demás
--     se fabrican en una ciudad (200 dinero, 40 metal, 10 petróleo, 15 días).
--   * Un grupo con un viaje por delante (`g.ruta` sin acabar) ESPERA en su
--     sitio hasta que le toca avión. Los grupos se atienden en orden de id.
--   * Un VUELO (`e.vuelos`) es de su grupo hasta que el grupo se deshace
--     (el dueño, 26-nov: «ellos mismos llevan lo recolectado a la ciudad... y
--     así en todo»): los aviones salen de su ciudad a buscarlo ('buscar'), lo
--     llevan en línea recta, cruzando el agua ('llevar': el grupo anda a la
--     velocidad del avión) y se quedan con él ('esperar') donde lo dejan. En
--     un ataque lo dejan y esperan en la ciudad propia más cercana
--     ('aparcar'). Cuando el grupo vuelve a viajar lo llevan otra vez; cuando
--     se deshace, vuelven a su ciudad ('volver').
--   * La carga va en toneladas reales: 80 t por avión, un robot 150 kg, un
--     camión de misiles 37 t. Un grupo más pesado sale en varios aviones; si
--     no hay tantos, los que hay hacen varios viajes (el grupo tarda lo que
--     tardan todos los viajes: ida y vuelta por cada uno de más).
--   * Nada choca por el camino: solo se pelea en minas y ciudades.
--
-- Estado:
--   e.aviones[id] = { id, nacion, base }            base: id de su ciudad
--   e.vuelos[id]  = { id, nacion, grupo, aviones, viajes, fase,
--                     x, y, antesX, antesY, ox, oy, dx, dy, recorrido, largo }
--   g.vuelo       = id del vuelo que lleva (o va a buscar) al grupo
--   c.obraAviones = { { dias }, ... }               aviones en obra en la ciudad

local Ayudas = require('mundo.simulacion.ayudas')

local ordenadas = Ayudas.ordenadas
local hipotenusa = Ayudas.hipotenusa

local Aviones = {}

-- Se fija en `instalar`: la clase.
local Simulacion

Aviones.reglas = {
    -- px de mundo (1 px = 1 m) por día: el avión 3D va a unos 75 m/s y un día
    -- dura 60 s a velocidad normal.
    velocidad = 4500,
    carga = 80, -- t por avión
    peso = { soldados = 0.15, lanzacohetes = 37 }, -- t por unidad
    -- Un viaje más corto que esto no necesita avión: se hace a pie.
    sinAvion = 60,
    coste = { dinero = 200, metal = 40, petroleo = 10 },
    dias = 15,
    inicial = 5, -- aviones de cada nación al empezar, en su capital
    -- La IA no pasa de tantos aviones por nación (el jugador, igual mientras
    -- no tenga su menú para fabricarlos).
    maximoIA = 10,
}

--- Toneladas que pesa el grupo `g` (sus tropas y sus heridos).
function Aviones.peso(g)
    local p = Aviones.reglas.peso
    local total = 0
    for tipo, t in pairs(p) do
        total = total + (g[tipo] or 0) * t
        if type(g.heridos) == 'table' then
            total = total + (g.heridos[tipo] or 0) * t
        end
    end
    return total
end

--- Aviones que harían falta para llevar `g` de una vez.
function Aviones.necesarios(g)
    return math.max(1, math.ceil(Aviones.peso(g) / Aviones.reglas.carga - 1e-9))
end

--- ¿Va `g` en avión (tiene un viaje largo por delante)?
function Aviones.vuela(g)
    return g.ruta ~= nil and (g.largo or 0) >= Aviones.reglas.sinAvion and (g.recorrido or 0) < g.largo
end

--- Lo que cabe de carga (unidades de recurso, 1 = 1 t) en los aviones que
-- llevan a `g`: 80 t por avión menos lo que pesan sus tropas.
function Aviones.capacidadCarga(g)
    return math.max(0, Aviones.necesarios(g) * Aviones.reglas.carga - Aviones.peso(g))
end

--- Un avión nuevo de `nid` con base en la ciudad `cid`. Devuelve su id.
function Aviones:nuevoAvion(nid, cid)
    local e = self.estado
    e.aviones = e.aviones or {}
    local id = e.siguienteAvion or 1
    e.siguienteAvion = id + 1
    e.aviones[id] = { id = id, nacion = nid, base = cid }
    return id
end

--- Dónde está la base del avión `a`: su ciudad o, si ya no es de su nación,
-- la capital (y pasa a ser su base).
function Aviones:baseDe(a)
    local e = self.estado
    local c = e.ciudades[a.base]
    if not (c and c.nacion == a.nacion) then
        local n = e.naciones[a.nacion]
        c = n and e.ciudades[n.capital]
        if c then
            a.base = c.id
        end
    end
    return c
end

--- Aviones de `nid`: { libres = {...}, total = n } en orden de id.
function Aviones:avionesDe(nid)
    local e = self.estado
    local libres, total = {}, 0
    for _, id in ipairs(ordenadas(e.aviones or {})) do
        local a = e.aviones[id]
        if a.nacion == nid then
            total = total + 1
            if not a.vuelo then
                libres[#libres + 1] = a
            end
        end
    end
    return { libres = libres, total = total }
end

--- El vuelo que lleva ahora a `g` (en la fase 'llevar'), o nil.
function Aviones:vueloLlevando(g)
    local v = g.vuelo and self.estado.vuelos and self.estado.vuelos[g.vuelo]
    if v and v.fase == 'llevar' and v.grupo == g.id then
        return v
    end
    return nil
end

--- Paso de marcha de un grupo que va en avión: 0 mientras espera el suyo;
-- con él, la velocidad del avión repartida entre los viajes que haga falta.
function Aviones:pasoEnAvion(g)
    local v = self:vueloLlevando(g)
    if not v then
        return 0
    end
    return Aviones.reglas.velocidad / (2 * v.viajes - 1) / Simulacion.pasosDia
end

local function tramo(v, ox, oy, dx, dy)
    v.ox, v.oy, v.dx, v.dy = ox, oy, dx, dy
    v.largo = hipotenusa(dx - ox, dy - oy)
    v.recorrido = 0
end

--- Da avión a los grupos que esperan (`esperan`, en orden de id).
function Aviones:asignarAviones(esperan)
    local e = self.estado
    local porNacion = {}
    for _, g in ipairs(esperan) do
        if e.grupos[g.id] == g and not (g.vuelo and e.vuelos[g.vuelo]) then
            local flota = porNacion[g.nacion]
            if not flota then
                flota = self:avionesDe(g.nacion)
                porNacion[g.nacion] = flota
            end
            if #flota.libres > 0 then
                local k = Aviones.necesarios(g)
                local n = math.min(k, #flota.libres)
                local ids = {}
                for i = 1, n do
                    ids[i] = table.remove(flota.libres, 1).id
                end
                local primero = e.aviones[ids[1]]
                local base = self:baseDe(primero)
                local bx, by = base and base.x or g.x, base and base.y or g.y
                local id = e.siguienteVuelo or 1
                e.siguienteVuelo = id + 1
                local v = {
                    id = id,
                    nacion = g.nacion,
                    grupo = g.id,
                    aviones = ids,
                    viajes = math.ceil(k / n),
                    fase = 'buscar',
                    x = bx,
                    y = by,
                    antesX = bx,
                    antesY = by,
                }
                tramo(v, bx, by, g.x, g.y)
                for _, aid in ipairs(ids) do
                    e.aviones[aid].vuelo = id
                end
                e.vuelos[id] = v
                g.vuelo = id
                if v.largo < Aviones.reglas.sinAvion then
                    -- Los aviones ya están donde sale el grupo.
                    v.fase = 'llevar'
                    v.x, v.y = g.x, g.y
                    self.activos = nil
                end
            end
        end
    end
end

--- Dónde espera el avión de un ejército que ataca: la ciudad propia más
-- cercana a él (nil si no le queda ninguna).
function Aviones:sitioDeEspera(nid, x, y)
    local e = self.estado
    local mejor, mejorD
    for _, cid in ipairs(ordenadas(e.ciudades)) do
        local c = e.ciudades[cid]
        if c.nacion == nid then
            local d = hipotenusa(c.x - x, c.y - y)
            if not mejor or d < mejorD then
                mejor, mejorD = c, d
            end
        end
    end
    return mejor
end

-- Vuelve vacío a su base desde donde está.
local function aVolver(self, v)
    local e = self.estado
    local a = e.aviones[v.aviones[1]]
    local base = a and self:baseDe(a)
    v.fase = 'volver'
    tramo(v, v.x, v.y, base and base.x or v.x, base and base.y or v.y)
    local g = e.grupos[v.grupo]
    if g and g.vuelo == v.id then
        g.vuelo = nil
    end
end

--- Un paso de los vuelos: avanzan los que buscan y los que vuelven; los que
-- llevan siguen a su grupo. Va antes de que anden los grupos.
function Aviones:moverVuelos()
    local e = self.estado
    if not e.vuelos then
        return
    end
    local paso = Aviones.reglas.velocidad / Simulacion.pasosDia
    for _, id in ipairs(ordenadas(e.vuelos)) do
        local v = e.vuelos[id]
        v.antesX, v.antesY = v.x, v.y
        local g = e.grupos[v.grupo]
        if v.fase == 'buscar' then
            if not (g and g.vuelo == v.id and Aviones.vuela(g)) then
                -- El grupo ya no existe o ya no viaja: vuelven.
                aVolver(self, v)
            else
                -- El grupo espera donde está (puede haber cambiado de sitio).
                v.dx, v.dy = g.x, g.y
                v.largo = hipotenusa(v.dx - v.ox, v.dy - v.oy)
                v.recorrido = math.min(v.largo, v.recorrido + paso)
                local t = v.largo > 0 and v.recorrido / v.largo or 1
                v.x, v.y = v.ox + (v.dx - v.ox) * t, v.oy + (v.dy - v.oy) * t
                if v.recorrido >= v.largo then
                    v.fase = 'llevar'
                    -- El grupo ya puede andar: se vuelven a buscar los activos.
                    self.activos = nil
                end
            end
        elseif v.fase == 'llevar' then
            if g and g.vuelo == v.id and Aviones.vuela(g) and not g.batalla then
                v.x, v.y = g.x, g.y
            elseif g and g.vuelo == v.id then
                -- Lo dejó donde iba: se queda con él; si ataca, espera en lo propio.
                v.x, v.y = g.x, g.y
                local espera = (g.mision == 'atacar' or g.mision == 'apoyo') and self:sitioDeEspera(g.nacion, g.x, g.y)
                if espera then
                    v.fase = 'aparcar'
                    tramo(v, v.x, v.y, espera.x, espera.y)
                else
                    v.fase = 'esperar'
                    -- En tierra, mirando hacia donde venía (para dibujarlo).
                    local r = g.ruta
                    if r then
                        v.ox, v.oy, v.dx, v.dy = r[1], r[2], r[#r - 1], r[#r]
                    end
                    v.largo, v.recorrido = 1, 1
                end
            else
                if g then
                    v.x, v.y = g.x, g.y
                end
                aVolver(self, v)
            end
        elseif v.fase == 'aparcar' then
            if not (g and g.vuelo == v.id) then
                aVolver(self, v)
            else
                v.recorrido = math.min(v.largo, v.recorrido + paso)
                local t = v.largo > 0 and v.recorrido / v.largo or 1
                v.x, v.y = v.ox + (v.dx - v.ox) * t, v.oy + (v.dy - v.oy) * t
                if v.recorrido >= v.largo then
                    v.fase = 'esperar'
                end
            end
        end
        if v.fase == 'esperar' then
            if not (g and g.vuelo == v.id) then
                aVolver(self, v)
            elseif Aviones.vuela(g) and not (g.batalla or g.detenido) then
                -- Su grupo vuelve a viajar: lo va a buscar o, si está con él, lo lleva.
                if hipotenusa(g.x - v.x, g.y - v.y) < Aviones.reglas.sinAvion then
                    v.fase = 'llevar'
                    self.activos = nil
                else
                    v.fase = 'buscar'
                    tramo(v, v.x, v.y, g.x, g.y)
                end
            end
        end
        if v.fase == 'volver' then
            v.recorrido = math.min(v.largo, v.recorrido + paso)
            local t = v.largo > 0 and v.recorrido / v.largo or 1
            v.x, v.y = v.ox + (v.dx - v.ox) * t, v.oy + (v.dy - v.oy) * t
            if v.recorrido >= v.largo then
                for _, aid in ipairs(v.aviones) do
                    if e.aviones[aid] then
                        e.aviones[aid].vuelo = nil
                    end
                end
                e.vuelos[id] = nil
            end
        end
    end
end

-- Fabricar ---------------------------------------------------------------------------------------

--- ¿Puede `nid` encargar un avión en `cid`? true, o false y el motivo.
function Aviones:puedeFabricarAvion(nid, cid)
    local e = self.estado
    local n, c = e.naciones[nid], e.ciudades[cid]
    if not (n and c and c.nacion == nid) then
        return false, 'ciudad'
    end
    for recurso, cantidad in pairs(Aviones.reglas.coste) do
        if Simulacion.disponible(n, recurso) < cantidad then
            return false, recurso
        end
    end
    return true
end

--- Encarga un avión en la ciudad `cid` (se paga al encargar). Devuelve true,
-- o false y el motivo.
function Aviones:fabricarAvion(nid, cid)
    local puede, motivo = self:puedeFabricarAvion(nid, cid)
    if not puede then
        return false, motivo
    end
    local e = self.estado
    Simulacion.pagar(e.naciones[nid], Aviones.reglas.coste)
    local c = e.ciudades[cid]
    c.obraAviones = c.obraAviones or {}
    c.obraAviones[#c.obraAviones + 1] = { dias = Aviones.reglas.dias }
    return true
end

--- ¿Le hace falta un avión más a `nid`? Alguien suyo espera avión, no tiene
-- ninguno en obra y no pasa del máximo de la IA.
function Aviones:quiereAvion(nid)
    local e = self.estado
    local espera = false
    for _, g in ipairs(self:gruposDe(nid)) do
        if Aviones.vuela(g) and not (g.vuelo and e.vuelos[g.vuelo]) then
            espera = true
            break
        end
    end
    if not espera then
        return false
    end
    for _, cid in ipairs(ordenadas(e.ciudades)) do
        local c = e.ciudades[cid]
        if c.nacion == nid and c.obraAviones then
            return false
        end
    end
    return self:avionesDe(nid).total < Aviones.reglas.maximoIA
end

--- Al terminar el día: avanzan las obras de aviones y la IA encarga los que
-- le hacen falta (un grupo esperando avión y ninguno en obra).
function Aviones:diaAviones()
    local e = self.estado
    for _, cid in ipairs(ordenadas(e.ciudades)) do
        local c = e.ciudades[cid]
        if c.obraAviones then
            local quedan = {}
            for _, o in ipairs(c.obraAviones) do
                o.dias = o.dias - 1
                if o.dias <= 0 then
                    if c.nacion and e.naciones[c.nacion] then
                        self:nuevoAvion(c.nacion, cid)
                    end
                else
                    quedan[#quedan + 1] = o
                end
            end
            c.obraAviones = #quedan > 0 and quedan or nil
        end
    end
    for _, n in ipairs(self:vivas()) do
        local capital = e.ciudades[n.capital]
        if capital and self:quiereAvion(n.id) then
            self:fabricarAvion(n.id, capital.id)
        end
    end
end

--- Los aviones de una nación nueva: `inicial` en su capital.
function Aviones:avionInicial(nid)
    local e = self.estado
    local n = e.naciones[nid]
    if n and e.ciudades[n.capital] and self:avionesDe(nid).total == 0 then
        for _ = 1, Aviones.reglas.inicial do
            self:nuevoAvion(nid, n.capital)
        end
    end
end

--- Cuelga las funciones de la clase.
function Aviones.instalar(clase)
    Simulacion = clase
    clase.aviones = Aviones.reglas
    clase.Aviones = Aviones
    for nombre, f in pairs(Aviones) do
        if type(f) == 'function' and nombre ~= 'instalar' and nombre ~= 'peso' and nombre ~= 'necesarios' and nombre ~= 'vuela' and nombre ~= 'capacidadCarga' then
            clase[nombre] = f
        end
    end
end

return Aviones
