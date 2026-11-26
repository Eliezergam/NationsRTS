--- Consultas para la vista: lo que la interfaz lee de las batallas y del estado, sin cambiarlo.
--
-- Módulo de `mundo/simulacion.lua`: `Consultas.instalar(Simulacion)` cuelga sus
-- funciones de la clase, así que la API pública no cambia. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')
local Armamento = require('mundo.simulacion.armamento')

local ordenadas = Ayudas.ordenadas
local hipotenusa = Ayudas.hipotenusa
local esCiudad = Ayudas.esCiudad
local cargaDe = Ayudas.cargaDe
local LADOS = Ayudas.LADOS
local nacionesBando = Ayudas.nacionesBando
local sanosBando = Ayudas.sanosBando

local Consultas = {}

-- Se fija en `instalar`: la clase.
local Simulacion

-- Consultas de batallas para la vista ----------------------------------------------------------

--- Copia de una tabla de munición (o ceros).
local function copiaMunicion(m)
    m = m or {}
    return { balas = m.balas or 0, misiles = m.misiles or 0 }
end

--- Suma a `sanosPor` (modelo -> cantidad) los vehículos sanos de `q`.
local function sumarModelos(sanosPor, q)
    for _, tipo in ipairs(Armamento.TIPOS) do
        for _, d in ipairs(Armamento.desglose(q, tipo)) do
            sanosPor[d.modelo] = (sanosPor[d.modelo] or 0) + d.cantidad
        end
    end
end

--- Resumen de un bando: sus grupos (id, nación, líder, sanos, heridos,
-- munición, carga), sus naciones, lo sano, el poder, la munición y el
-- tamaño de escuadra (F10).
local function resumenBando(self, b, lado)
    local out = { grupos = {}, naciones = {}, sanos = sanosBando(self, b, lado, true), poder = 0, sanosPor = {} }
    local municiones = {}
    for _, g in ipairs(self:gruposBando(b, lado)) do
        sumarModelos(out.sanosPor, g)
        municiones[#municiones + 1] = copiaMunicion(g.municion)
        out.grupos[#out.grupos + 1] = {
            id = g.id,
            nacion = g.nacion,
            lider = g.lider,
            soldados = g.soldados,
            lanzacohetes = g.lanzacohetes or 0,
            lanzacohetesPor = Armamento.porModelo(g, 'lanzacohetes'),
            heridos = g.heridos and {
                soldados = g.heridos.soldados,
                lanzacohetes = g.heridos.lanzacohetes,
            },
            carga = cargaDe(g),
            tipoCarga = g.tipoCarga,
            municion = municiones[#municiones],
        }
        out.poder = out.poder + Simulacion.poder(g)
    end
    out.naciones = ordenadas(nacionesBando(self, b, lado))
    local s = lado == 'defensor' and self:sitioBando(b)
    if s then
        out.sitio = {
            id = s.id,
            nacion = s.nacion,
            tipo = s.tipo or 'ciudad',
            soldados = s.soldados or 0,
            lanzacohetes = s.lanzacohetes or 0,
            lanzacohetesPor = Armamento.porModelo(s, 'lanzacohetes'),
            baterias = s.baterias or 0,
            vida = Simulacion.vidaSitio(s),
            defensasFijas = not esCiudad(s) or (s.vida or Simulacion.vidaCiudad.maxima) > 0,
            -- El polvorín de su ciudad (compartido con ella).
            municion = copiaMunicion(self:polvorin(s.id)),
        }
        municiones[#municiones + 1] = out.sitio.municion
        sumarModelos(out.sanosPor, s)
        out.poder = out.poder + Simulacion.poderSitio(s)
    end
    out.municion = Simulacion.sumarMunicion(municiones)
    out.escuadra = math.max(1, math.ceil(out.sanos.soldados / Simulacion.produccion.figuras))
    return out
end

--- Estado de una batalla para la escena 3D o el panel: { id, lugar = { tipo,
-- id }, nombre, x, y, inicio, dias, enEscena, atacante = bando, defensor =
-- bando }, con bando = { grupos = { { id, nacion, lider, soldados,
-- lanzacohetes, lanzacohetesPor, heridos, municion, carga, tipoCarga } },
-- naciones = { nid, ... }, sanos = { soldados, lanzacohetes }, sanosPor
-- (modelo -> sanos, grupos y sitio), poder, municion (total del bando),
-- escuadra (soldados por figura, F10), sitio = { id, nacion, tipo,
-- soldados, lanzacohetes, lanzacohetesPor, baterias, vida, defensasFijas,
-- municion } (solo el defensor) }; municion = { balas, misiles }. Los desgloses son
-- modelo -> cantidad (armamento.lua; la ficha de cada modelo, en
-- `Simulacion.fichaModelo`).
-- Solo lo sano pelea: los heridos van aparte. nil si no existe. Lo que la
-- escena devuelve está en la cabecera de batallas.lua.
function Consultas:estadoBatalla(bid)
    local b = self.estado.batallas[bid]
    if not b then
        return nil
    end
    return {
        id = b.id,
        lugar = { tipo = b.lugar.tipo, id = b.lugar.id },
        nombre = self:nombreBatalla(b),
        x = b.x,
        y = b.y,
        inicio = b.inicio,
        dias = b.dias,
        enEscena = b.enEscena,
        atacante = resumenBando(self, b, 'atacante'),
        defensor = resumenBando(self, b, 'defensor'),
    }
end

--- Batallas en curso, en orden de id; con `nid`, solo aquellas en las que
-- pelea: { id, lugar, nombre, x, y, dias, enEscena, lado (el de `nid`),
-- decidido ('sola' si eligió no defender), puedeEntrar, jugador (pelea
-- alguna nación de un jugador), atacante = { naciones, poder }, defensor = {
-- naciones, poder, sitio } }.
function Consultas:batallasEnCurso(nid)
    local e = self.estado
    local out = {}
    for _, id in ipairs(ordenadas(e.batallas)) do
        local b = e.batallas[id]
        local lado = nid and self:ladoDe(b, nid)
        if not nid or lado then
            local jugador = false
            for _, l in ipairs(LADOS) do
                for n in pairs(nacionesBando(self, b, l)) do
                    if e.naciones[n] and e.naciones[n].jugador then
                        jugador = true
                    end
                end
            end
            local a, d = resumenBando(self, b, 'atacante'), resumenBando(self, b, 'defensor')
            out[#out + 1] = {
                id = b.id,
                lugar = { tipo = b.lugar.tipo, id = b.lugar.id },
                nombre = self:nombreBatalla(b),
                x = b.x,
                y = b.y,
                dias = b.dias,
                enEscena = b.enEscena,
                lado = lado or nil,
                decidido = nid and b.decision and b.decision[nid] or nil,
                puedeEntrar = lado ~= nil and lado ~= false and (not b.enEscena or b.enEscena == nid),
                jugador = jugador,
                atacante = { naciones = a.naciones, poder = a.poder },
                defensor = { naciones = d.naciones, poder = d.poder, sitio = d.sitio },
            }
        end
    end
    return out
end

--- Choques en campo abierto, para la vista de antes: { a, b (ids de grupo, el
-- primero de cada bando), x, y, jugador, batalla }, en orden de batalla.
function Consultas:choques()
    local out = {}
    for _, r in ipairs(self:batallasEnCurso()) do
        if r.lugar.tipo == 'campo' then
            local b = self.estado.batallas[r.id]
            local ga, gb = self:gruposBando(b, 'atacante')[1], self:gruposBando(b, 'defensor')[1]
            if ga and gb then
                out[#out + 1] = { a = ga.id, b = gb.id, x = r.x, y = r.y, jugador = r.jugador, batalla = r.id }
            end
        end
    end
    return out
end

-- Consultas para la vista (solo leen el estado) ---------------------------------------------

--- Recolectores de una mina ahora, por nación: { { nacion, trabajo, grupos
-- = { gid, ... } } }, del que más trabaja al que menos (a igual trabajo, por
-- id de nación). Solo los que están en ella (en su batalla, también).
function Consultas:recolectoresMina(id)
    local porNacion, ids = {}, {}
    for _, g in ipairs(self:gruposOrdenados()) do
        if g.mision == 'recolectar' and g.fase == 'recolectando' and g.yacimiento == id then
            local r = porNacion[g.nacion]
            if not r then
                r = { nacion = g.nacion, trabajo = 0, grupos = {} }
                porNacion[g.nacion] = r
                ids[#ids + 1] = g.nacion
            end
            r.trabajo = r.trabajo + Simulacion.trabajo(g)
            r.grupos[#r.grupos + 1] = g.id
        end
    end
    table.sort(ids)
    local out = {}
    for _, nid in ipairs(ids) do
        out[#out + 1] = porNacion[nid]
    end
    table.sort(out, function(a, b)
        if a.trabajo ~= b.trabajo then
            return a.trabajo > b.trabajo
        end
        return a.nacion < b.nacion
    end)
    return out
end

--- Una mina (yacimiento) para la vista: { id, tipo, x, y, riqueza, dueno
-- (nación de su celda o nil), queda, reserva, agotadaHasta (0 si abierta),
-- cerrada, diasCerrada, recolectores (ver `recolectoresMina`), principal (la
-- nación que más trabaja o nil), bonus (nación con el +25 %: la dueña de la
-- celda si recolecta allí, o nil), batalla (id o nil) }. nil si no existe.
function Consultas:mina(id)
    local e = self.estado
    local d = e.depositos[id]
    if not d then
        return nil
    end
    local queda, hasta, reserva = self:estadoMina(d)
    local dueno = self:duenoDeposito(d)
    local recolectores = self:recolectoresMina(id)
    local bonus
    for _, r in ipairs(recolectores) do
        if r.nacion == dueno then
            bonus = dueno
        end
    end
    local b = self:batallaEn('mina', id)
    return {
        id = d.id,
        tipo = d.tipo,
        x = d.x,
        y = d.y,
        riqueza = d.riqueza,
        dueno = dueno,
        queda = queda,
        reserva = reserva,
        agotadaHasta = hasta,
        cerrada = hasta > e.dia,
        diasCerrada = math.max(0, hasta - e.dia),
        recolectores = recolectores,
        principal = recolectores[1] and recolectores[1].nacion,
        bonus = bonus,
        batalla = b and b.id,
    }
end

--- Yacimientos registrados dentro del rectángulo (x0, y0)-(x1, y1), en orden
-- fijo, con lo mismo que `mina` (id, tipo, x, y, riqueza, dueno, queda,
-- reserva, agotadaHasta, cerrada, diasCerrada, recolectores, principal, bonus,
-- batalla). `explotadoPor` queda siempre nil (ya no hay extracciones).
function Consultas:yacimientosEn(x0, y0, x1, y1)
    local out = {}
    local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    local radio = hipotenusa(x1 - x0, y1 - y0) / 2
    for _, d in ipairs(self:depositosCerca(cx, cy, radio)) do
        if d.x >= x0 and d.x <= x1 and d.y >= y0 and d.y <= y1 then
            out[#out + 1] = self:mina(d.id)
        end
    end
    return out
end

--- Grupos de recolección (con `nid`, solo los suyos), en orden de id: { grupo,
-- nacion, yacimiento, recurso, fase ('ida', 'recolectando' o 'vuelta'), x, y,
-- carga, capacidad, ritmo (lo que saca al día en su mina), soldados,
-- lanzacohetes, batalla (id o nil) }. Los que vuelven cargados también salen.
function Consultas:recolectores(nid)
    local e = self.estado
    local out = {}
    for _, g in ipairs(self:gruposOrdenados()) do
        local recolecta = g.mision == 'recolectar' or (g.tipoCarga and cargaDe(g) > 0)
        if recolecta and (not nid or g.nacion == nid) then
            local d = e.depositos[g.yacimiento]
            out[#out + 1] = {
                grupo = g.id,
                nacion = g.nacion,
                yacimiento = g.yacimiento,
                recurso = g.tipoCarga,
                fase = g.fase or 'vuelta',
                x = g.x,
                y = g.y,
                carga = cargaDe(g),
                capacidad = Simulacion.capacidad(g),
                ritmo = d and self:ritmoRecoleccion(g, d) or 0,
                soldados = g.soldados,
                lanzacohetes = g.lanzacohetes or 0,
                batalla = g.batalla,
            }
        end
    end
    return out
end

-- Las banderas (`sim:banderas`, `sim:banderasEn`) están en banderas.lua.

--- Almacén, bóveda y afuera de una nación: { metal, petroleo, dinero (lo
-- guardado), afuera = { metal, petroleo, dinero }, almacen (tope del metal y
-- del petróleo), boveda (tope del dinero) }.
function Consultas:almacenDe(nid)
    local n = self.estado.naciones[nid]
    if not n then
        return nil
    end
    return {
        metal = n.recursos.metal or 0,
        petroleo = n.recursos.petroleo or 0,
        dinero = n.tesoro,
        afuera = { metal = n.afuera.metal, petroleo = n.afuera.petroleo, dinero = n.afuera.dinero },
        almacen = self:almacen(nid),
        boveda = self:boveda(nid),
    }
end

--- Fábricas de una ciudad para el Arsenal: { lineas (órdenes de unidades
-- que avanzan a la vez), unidades = { { id, tropa, modelo (nil los
-- soldados), cantidad (lo que falta), enLinea (avanza hoy), proxima (días a
-- la siguiente tanda), dias (días hasta acabar si sigue en su línea), tanda
-- } }, municion = { { id,
-- municion, lotes, cantidad, dias } }, sitiada } en orden de encargo; nil si
-- la ciudad no existe.
function Consultas:colaFabrica(cid)
    local c = self.estado.ciudades[cid]
    if not c then
        return nil
    end
    local reglas = Simulacion.produccion
    local lineas = c.nivel or 1
    local out = { lineas = lineas, unidades = {}, municion = {}, sitiada = self:sitiada(c) }
    for k, o in ipairs(c.fabrica or {}) do
        local porTanda = Simulacion.diasTanda(o.tropa, o.modelo)
        local tandas = math.ceil(o.cantidad / reglas.tanda[o.tropa])
        out.unidades[k] = {
            id = o.id,
            tropa = o.tropa,
            modelo = o.modelo,
            cantidad = o.cantidad,
            enLinea = k <= lineas,
            proxima = porTanda - o.dias,
            dias = tandas * porTanda - o.dias,
            tanda = reglas.tanda[o.tropa],
        }
    end
    for k, o in ipairs(c.fabricaMunicion or {}) do
        out.municion[k] = {
            id = o.id,
            municion = o.municion,
            lotes = o.lotes,
            cantidad = o.lotes * reglas.municion[o.municion].lote,
            dias = o.dias,
        }
    end
    return out
end

--- ¿Es (x, y) tierra sin dueño?
function Consultas:sinDueno(x, y)
    return self:dueno(x, y) == nil
end

local publicas = {
    'estadoBatalla',
    'batallasEnCurso',
    'choques',
    'recolectoresMina',
    'mina',
    'yacimientosEn',
    'recolectores',
    'almacenDe',
    'colaFabrica',
    'sinDueno',
}

local datos = {}

--- Cuelga de la clase Simulacion las funciones y datos de este módulo.
function Consultas.instalar(clase)
    Simulacion = clase
    for _, nombre in ipairs(datos) do
        clase[nombre] = Consultas[nombre]
    end
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Consultas[nombre]
    end
end

return Consultas
