--- Guarnición de las banderas del borde, panel de tropas y la IA que defiende las banderas (diseno/banderas-borde.md, 3.12 y 3.13).
--
-- La guarnición de una bandera son grupos del ejército con misión
-- 'guarnicion' y `objetivo` = id de la bandera; `g.bandera` = id cuando ya
-- están en ella y `g.alerta` = último día con aviso o batalla (la IA la hace
-- regresar tras `Simulacion.bandera.diasGuardiaIA` días sin ninguno). Siguen
-- siendo de su ciudad (`g.desde`, `g.origen`): cuentan en su inventario,
-- cobran y gastan como cualquier grupo fuera. Tope por bandera (F5):
-- `guarnicionPorNivel` × nivel de la capital, en vida de grupo, contando
-- también a los que van hacia ella y a los que se sumaron a su bando defensor.
--
-- Comandos (`Simulacion:ejecutar`): 'enviarGrupo' con mision = 'guarnicion',
-- 'guarnecer' (ataques.lua), 'regresarGrupo' (= 'retirar') y 'regresarTodos'.
-- Para el panel de tropas: `sim:tropasFuera(nid)`, `sim:diasRegreso(gid)` y
-- `Simulacion.puedeRegresar(g)`.
--
-- Módulo de `mundo/simulacion.lua`: `Guarnicion.instalar(Simulacion)` cuelga
-- sus funciones de la clase. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')
local Armamento = require('mundo.simulacion.armamento')

local ordenadas = Ayudas.ordenadas
local distancia = Ayudas.distancia

local Guarnicion = {}

-- Se fija en `instalar`: la clase.
local Simulacion

-- Guarnición (3.12, F5) -----------------------------------------------------------------------------

--- Tope de guarnición de una bandera de `nid` (F5), en vida de grupo.
function Guarnicion:topeGuarnicion(nid)
    return Simulacion.bandera.guarnicionPorNivel * self:nivelCapital(nid)
end

--- Grupos de guarnición de la bandera `id`, en ella o en camino, en orden de id.
function Guarnicion:guarnicion(id)
    local out = {}
    for _, g in ipairs(self:gruposHacia(id)) do
        if g.mision == 'guarnicion' then
            out[#out + 1] = g
        end
    end
    return out
end

--- Vida que ya ocupa el tope de la bandera `id` (F5): su guarnición (en ella
-- o en camino) y los grupos que se sumaron a su bando defensor. Sin `salvo`
-- (un grupo que no cuenta).
function Guarnicion:cargaGuarnicion(id, salvo)
    local carga = 0
    local contados = {}
    for _, g in ipairs(self:guarnicion(id)) do
        if g ~= salvo then
            carga = carga + Simulacion.vidaGrupo(g)
            contados[g.id] = true
        end
    end
    local b = self:batallaEn('sitio', id)
    if b then
        for _, g in ipairs(self:gruposBando(b, 'defensor')) do
            if g ~= salvo and not contados[g.id] then
                carga = carga + Simulacion.vidaGrupo(g)
            end
        end
    end
    return carga
end

--- La bandera `id` si es de `nid` y de borde (la única que admite
-- guarnición), o nil.
function Guarnicion:banderaDeBorde(nid, id)
    local dueno, bx, by = Simulacion.leerIdBandera(id)
    if dueno ~= nid or not self:esBorde(nid, bx, by) then
        return nil
    end
    return self:banderaPorId(id)
end

--- ¿Puede `nid` mandar a la bandera `id` una guarnición de `vida`? Devuelve
-- la bandera, o nil y el motivo ('destino' o 'llena'). `salvo`: un grupo
-- que ya cuenta y no se suma dos veces.
function Guarnicion:admiteGuarnicion(nid, id, vida, salvo)
    local b = self:banderaDeBorde(nid, id)
    if not b then
        return nil, 'destino'
    end
    if self:cargaGuarnicion(id, salvo) + vida > self:topeGuarnicion(nid) then
        return nil, 'llena'
    end
    return b
end

--- Un grupo de guarnición llega a su bandera: se queda en ella (`g.bandera`)
-- y, si ya la atacan, se suma a su bando defensor. Si ya no es de borde,
-- vuelve (P9 B); si ya no cabe, queda en el campo en ese punto (misión 'mover').
function Guarnicion:llegarAGuarnicion(g)
    if g.bandera then
        return
    end
    local e = self.estado
    local nid, bx, by = Simulacion.leerIdBandera(g.objetivo)
    if not nid or nid ~= g.nacion or not self:esBorde(nid, bx, by) then
        return self:volver(g)
    end
    local b = self:batallaEn('sitio', g.objetivo)
    if self:cargaGuarnicion(g.objetivo, g) + Simulacion.vidaGrupo(g) > self:topeGuarnicion(nid) then
        g.mision, g.objetivo = 'mover', nil
        self:reindexarGrupo(g)
        return
    end
    g.bandera = g.objetivo
    g.alerta = e.dia
    if b and self:ladoDe(b, g.nacion) == 'defensor' then
        self:unirBatalla(b, g, 'defensor')
    end
end

--- Guarnición que defiende la bandera `s` cuando llega un ataque: sus grupos
-- que ya están en ella y no pelean, en orden de id.
function Guarnicion:defensoresBandera(s)
    local out = {}
    for _, g in ipairs(self:gruposHacia(s.id)) do
        if g.mision == 'guarnicion' and g.bandera == s.id and g.nacion == s.nacion and not g.batalla then
            out[#out + 1] = g
        end
    end
    return out
end

-- Panel de tropas (3.13) --------------------------------------------------------------------------

--- Sitio al que volvería `g` (como `volver`), o nil.
local function casaDe(self, g)
    local casa = self:sitio(g.desde)
    if not casa or casa.nacion ~= g.nacion or casa.tipo == 'bandera' then
        casa = self:sitioCercano(g.nacion, g.x, g.y, 0)
    end
    return casa
end

--- Días que tardaría `g` en volver a casa andando (redondeado arriba): el
-- camino real (`trazar`) a la velocidad de su modelo más lento (y a media
-- marcha sin combustible). Un grupo que ya vuelve, lo que le queda.
function Guarnicion:diasRegreso(gid)
    local g = self.estado.grupos[gid]
    if not g then
        return nil
    end
    local largo
    if g.mision == 'regreso' and g.ruta then
        largo = g.largo - g.recorrido
    else
        local casa = casaDe(self, g)
        if not casa then
            return nil
        end
        largo = Simulacion.largoRuta(self:trazar(g.x, g.y, casa.x, casa.y) or { g.x, g.y, casa.x, casa.y })
    end
    local paso = Simulacion.velocidadEjercito * Armamento.velocidadGrupo(g)
    local n = self.estado.naciones[g.nacion]
    if n and n.sinCombustible and (g.lanzacohetes or 0) > 0 then
        paso = paso / 2
    end
    return math.ceil(largo / paso - 1e-9)
end

--- ¿Aceptaría `regresarGrupo` al grupo `g`? true, o false y el motivo:
-- 'yaVuelve', 'obra', 'entrega', 'abasto' o 'remolque'.
function Guarnicion.puedeRegresar(g)
    if g.remolque then
        return false, 'remolque'
    elseif g.mision == 'regreso' then
        return false, 'yaVuelve'
    elseif g.mision == 'construir' then
        return false, 'obra'
    elseif g.mision == 'entrega' then
        return false, 'entrega'
    elseif g.mision == 'abasto' then
        return false, 'abasto'
    end
    return true
end

--- Todas las tropas de `nid` que están fuera, una fila por grupo en orden de
-- id: { id, mision, ejercito, bandera (id, si es guarnición), batalla,
-- x, y, destinoX, destinoY, falta (px de camino), diasRegreso, puede, motivo }.
function Guarnicion:tropasFuera(nid)
    local out = {}
    for _, g in ipairs(self:gruposDe(nid)) do
        local puede, motivo = Guarnicion.puedeRegresar(g)
        out[#out + 1] = {
            id = g.id,
            mision = g.mision,
            ejercito = g.lider ~= nil,
            bandera = g.mision == 'guarnicion' and g.objetivo or nil,
            enBandera = g.bandera ~= nil,
            batalla = g.batalla,
            x = g.x,
            y = g.y,
            destinoX = g.destinoX,
            destinoY = g.destinoY,
            falta = g.ruta and math.max(0, g.largo - g.recorrido) or 0,
            diasRegreso = self:diasRegreso(g.id),
            puede = puede,
            motivo = motivo,
        }
    end
    return out
end

--- «Regresar todos» (3.13.3): cada grupo de `nid` que se pueda, en orden de
-- id, vuelve andando (`retirarGrupo`). Los que pelean solo con `conBatalla`.
-- Devuelve true y { vuelven, noPueden, enBatalla }.
function Guarnicion:regresarTodos(nid, conBatalla)
    if not self.estado.naciones[nid] then
        return false, 'nacion'
    end
    local cuenta = { vuelven = 0, noPueden = 0, enBatalla = 0 }
    for _, g in ipairs(self:gruposDe(nid)) do
        if not Guarnicion.puedeRegresar(g) then
            cuenta.noPueden = cuenta.noPueden + 1
        elseif g.batalla and not conBatalla then
            cuenta.enBatalla = cuenta.enBatalla + 1
        elseif self:retirarGrupo(nid, g.id) then
            cuenta.vuelven = cuenta.vuelven + 1
        else
            cuenta.noPueden = cuenta.noPueden + 1
        end
    end
    return true, cuenta
end

-- IA (3.12.8) ---------------------------------------------------------------------------------

--- Ataques que van hacia banderas y llegan en `avisoDias` o menos (el mismo
-- aviso que recibe el jugador, `avisosAtaque`): nación -> id de bandera ->
-- grupos. Se cuenta una vez al día.
local function avisosBanderas(self)
    local dia = self.estado.dia
    local c = self.cacheAvisosBanderas
    if c and c.dia == dia then
        return c.porNacion
    end
    local porNacion = {}
    local aviso = Simulacion.recoleccion.avisoDias
    for _, g in ipairs(self:gruposConMision('atacar')) do
        local nid = Simulacion.leerIdBandera(g.objetivo)
        if nid and nid ~= g.nacion and not g.batalla and not g.detenido and g.ruta then
            local dias = (g.largo - g.recorrido) / Simulacion.velocidadEjercito
            if dias <= aviso and dias > 0 then
                porNacion[nid] = porNacion[nid] or {}
                porNacion[nid][g.objetivo] = porNacion[nid][g.objetivo] or {}
                table.insert(porNacion[nid][g.objetivo], g)
            end
        end
    end
    self.cacheAvisosBanderas = { dia = dia, porNacion = porNacion }
    return porNacion
end

--- El presidente NPC defiende sus banderas con la misma regla que el
-- jugador (3.12.8): se entera por el aviso de ataque o por la batalla; si la
-- bandera vale más de 1 (`valorBandera`) y no tiene ya guarnición, estima la
-- fuerza del atacante por sus informes (sin informe, a ciegas, y manda un
-- explorador) y manda de guarnición, desde el sitio más cercano que pueda,
-- lo que la supere y quepa en el tope; si no puede, la deja caer. Hace
-- regresar la guarnición tras `diasGuardiaIA` días sin aviso ni batalla.
function Guarnicion:defenderBanderas(n)
    local e = self.estado
    local reglas = Simulacion.bandera
    local amenazas = {}
    for id, grupos in pairs(avisosBanderas(self)[n.id] or {}) do
        amenazas[id] = {}
        for _, g in ipairs(grupos) do
            if e.grupos[g.id] == g and g.mision == 'atacar' and g.objetivo == id then
                table.insert(amenazas[id], g)
            end
        end
    end
    for _, b in ipairs(self:instalacionesDe(n.id, 'bandera')) do
        if (b.atacadaDia or -math.huge) >= e.dia - 1 and not amenazas[b.id] then
            local batalla = self:batallaEn('sitio', b.id)
            amenazas[b.id] = batalla and self:gruposBando(batalla, 'atacante') or {}
        end
    end
    local cola = {}
    for _, id in ipairs(ordenadas(amenazas)) do
        local b = self:banderaPorId(id)
        if b and b.nacion == n.id then
            for _, g in ipairs(self:guarnicion(id)) do
                g.alerta = e.dia
            end
            cola[#cola + 1] = { bandera = b, valor = self:valorBandera(n, b), atacantes = amenazas[id] }
        end
    end
    table.sort(cola, function(a, b)
        if a.valor ~= b.valor then
            return a.valor > b.valor
        end
        return a.bandera.id < b.bandera.id
    end)
    for _, amenaza in ipairs(cola) do
        local b = amenaza.bandera
        local libre = self:topeGuarnicion(n.id) - self:cargaGuarnicion(b.id)
        if amenaza.valor > 1 and #self:guarnicion(b.id) == 0 and libre > 0 then
            local fuerza = 0
            for _, g in ipairs(amenaza.atacantes) do
                fuerza = fuerza + self:poderEstimado(n.id, g, true) / Simulacion.escalaPoder
            end
            local sitios = {}
            for _, s in ipairs(self:sitiosDe(n.id)) do
                sitios[#sitios + 1] = { sitio = s, distancia = distancia(s, b) }
            end
            table.sort(sitios, function(a, c)
                if a.distancia ~= c.distancia then
                    return a.distancia < c.distancia
                end
                return a.sitio.id < c.sitio.id
            end)
            for _, par in ipairs(sitios) do
                local s = par.sitio
                local soldados = math.floor(s.soldados * 0.6)
                if soldados > libre then
                    soldados = math.floor(libre)
                end
                local vida = soldados
                if fuerza > 0 and vida > fuerza and vida <= libre then
                    local gid = self:ejecutar({
                        tipo = 'enviarGrupo',
                        nacion = n.id,
                        desde = s.id,
                        mision = 'guarnicion',
                        objetivo = b.id,
                        soldados = soldados,
                    })
                    if gid then
                        self:noticia(string.format('%s manda una guarnición a su bandera', n.nombre), n.color)
                        break
                    end
                end
            end
        end
    end
    -- Sin aviso ni batalla en `diasGuardiaIA` días, la guarnición vuelve.
    for _, g in ipairs(self:gruposConMision('guarnicion')) do
        if g.nacion == n.id and g.bandera and not g.batalla and e.dia - (g.alerta or e.dia) > reglas.diasGuardiaIA then
            self:ejecutar({ tipo = 'regresarGrupo', nacion = n.id, grupo = g.id })
        end
    end
end

local publicas = {
    'topeGuarnicion',
    'guarnicion',
    'cargaGuarnicion',
    'banderaDeBorde',
    'admiteGuarnicion',
    'llegarAGuarnicion',
    'defensoresBandera',
    'diasRegreso',
    'tropasFuera',
    'regresarTodos',
    'defenderBanderas',
}

--- Cuelga de la clase Simulacion las funciones de la guarnición y del panel de tropas.
function Guarnicion.instalar(clase)
    Simulacion = clase
    clase.puedeRegresar = Guarnicion.puedeRegresar
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Guarnicion[nombre]
    end
end

return Guarnicion
