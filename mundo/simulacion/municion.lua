--- Munición: polvorín de cada ciudad, dotación de los grupos, convoyes de abastecimiento y avisos.
--
-- Dos tipos (diseno/economia.md, 3.6): balas (soldados) y misiles
-- (lanzacohetes); los obuses se fueron con los tanques (19-nov, partida v30).
-- Se fabrican con `producir` (produccion.lua) y van al POLVORÍN de la ciudad
-- (`c.municion = { balas, misiles }`). Las
-- guarniciones disparan del polvorín de su ciudad (una base o un campamento,
-- del de la ciudad que los abastece). Un grupo se lleva la suya
-- (`g.municion`), que sale del polvorín al salir y vuelve a él al llegar a
-- casa; si el grupo cae entero, se pierde.
--
-- Contrato con la vista:
--   enviarGrupo / recolectar aceptan `municion`: una tabla { balas, misiles }
--     (lo que se lleva, recortado a lo que hay), un número (días
--     de dotación, F5) o nil (la dotación de su misión: `dotacion.atacar`,
--     `mover` o `recolectar`). Lo disponible se lee con `sim:polvorin(sitio)`.
--   ejecutar({ tipo = 'abastecer', nacion, desde, grupo, balas, misiles })
--     saca munición del polvorín de `desde` (una ciudad propia) y la manda en
--     un convoy (grupo sin líder, misión 'abasto') al grupo `grupo`. Llega en
--     lo que tarda un ejército (al menos un día); si el grupo ya no existe,
--     vuelve al polvorín. Devuelve el id del convoy o false y el motivo:
--     'noEsSuya', 'grupo', 'nada'.
--   sim:municionGrupo(gid) -> { balas, misiles, dias = { balas, ... },
--     sin = { soldados, lanzacohetes } } (días de batalla que le
--     quedan de cada una y qué tropas ya no disparan).
--   sim:avisosMunicion(nid) -> grupos de `nid` en batalla con menos de
--     `umbralAbasto` días de alguna munición: { { grupo, batalla, falta =
--     'misiles', dias } }. Al jugador además le llega una noticia (una vez).
--
-- Módulo de `mundo/simulacion.lua`: `Municion.instalar(Simulacion)` cuelga sus
-- funciones de la clase. Solo datos y sin LÖVE.

local Armamento = require('mundo.simulacion.armamento')

local Municion = {}

-- Se fija en `instalar`: la clase.
local Simulacion

local MUNICIONES = { 'balas', 'misiles' }
local DE_TROPA = { soldados = 'balas', lanzacohetes = 'misiles' }
local TROPA_DE = { balas = 'soldados', misiles = 'lanzacohetes' }
Municion.MUNICIONES = MUNICIONES
Municion.DE_TROPA = DE_TROPA

--- Polvorín (tabla guardada) de la ciudad que abastece al sitio `sid` (o al
-- sitio `s`), creado si no existía; nil si su nación no tiene ciudades.
function Municion:polvorinDe(s)
    local c = s and self:ciudadDeSitio(s.nacion, s)
    if not c then
        return nil
    end
    c.municion = c.municion or Simulacion.municionVacia()
    return c.municion
end

--- Polvorín del sitio `sid` para la vista: { balas, misiles } (una
-- base o un campamento, el de su ciudad), o nil.
function Municion:polvorin(sid)
    local s = self:sitio(sid)
    local c = s and self:ciudadDeSitio(s.nacion, s)
    if not c then
        return nil
    end
    local m = c.municion or {}
    return { balas = m.balas or 0, misiles = m.misiles or 0, ciudad = c.id }
end

--- Munición de tipo `tipo` que gastan en un día de batalla las unidades de
-- `q` (un grupo, un sitio o { soldados, lanzacohetes } con sus
-- desgloses): cada lanzacohetes, la de su modelo (F11; con el Scud-B, la de hoy).
local function necesita(q, tipo)
    local reglas = Simulacion.produccion.municion[tipo]
    local tropa = TROPA_DE[tipo]
    if tropa == 'soldados' then
        return (q.soldados or 0) * reglas.porDia
    end
    return reglas.porDia * Armamento.suma(q, tropa, 'municion')
end
Municion.necesita = necesita

--- Dotación de `dias` días de batalla para `unidades` ({ soldados,
-- lanzacohetes } y sus desgloses) (F5).
function Municion.dotacion(unidades, dias)
    local out = {}
    for _, m in ipairs(MUNICIONES) do
        out[m] = necesita(unidades, m) * dias
    end
    return out
end

--- Da a `g` la munición que pide (`pedido`, ver la cabecera) del polvorín
-- del sitio `desde`, sin pasar de lo que hay.
function Municion:dotar(g, desde, pedido)
    local reglas = Simulacion.produccion
    local quiere = pedido
    if type(pedido) ~= 'table' then
        local dias = tonumber(pedido) or reglas.dotacion[g.mision] or 0
        quiere = Municion.dotacion(g, dias)
    end
    local polvorin = self:polvorinDe(desde)
    g.municion = g.municion or Simulacion.municionVacia()
    if not polvorin then
        return
    end
    for _, m in ipairs(MUNICIONES) do
        local lleva = math.max(0, math.min(polvorin[m], math.floor(tonumber(quiere[m]) or 0)))
        polvorin[m] = polvorin[m] - lleva
        g.municion[m] = g.municion[m] + lleva
    end
end

--- La munición de `g` vuelve al polvorín de la ciudad de `sitio`.
function Municion:devolverMunicion(g, sitio)
    local m = g.municion
    g.municion = nil
    if not m then
        return
    end
    local polvorin = self:polvorinDe(sitio)
    if not polvorin then
        return
    end
    for _, tipo in ipairs(MUNICIONES) do
        polvorin[tipo] = polvorin[tipo] + (m[tipo] or 0)
    end
end

--- La munición de `g` se pierde (el grupo cayó entero).
function Municion:perderMunicion(g)
    if g.municion then
        for _, m in ipairs(MUNICIONES) do
            self:medir('municionPerdida|' .. m, g.municion[m])
        end
    end
    g.municion = nil
end

--- Parte que puede disparar hoy de cada tropa de `q` (un grupo o una
-- guarnición) con la munición `m` (F6): min(1, munición / (unidades × porDia)).
function Municion.partes(q, m)
    local out = {}
    for tropa, tipo in pairs(DE_TROPA) do
        local falta = necesita(q, tipo)
        out[tropa] = falta > 0 and math.min(1, (m and m[tipo] or 0) / falta) or 1
    end
    return out
end

--- Gasta la munición de un día de batalla de `q` (F6): lo que le toque a cada
-- tropa, sin pasar de lo que hay en `m`. Devuelve lo gastado.
function Municion.gastarDia(q, m)
    local gastado = Simulacion.municionVacia()
    if not m then
        return gastado
    end
    for _, tipo in ipairs(MUNICIONES) do
        local gasta = math.min(m[tipo] or 0, necesita(q, tipo))
        m[tipo] = (m[tipo] or 0) - gasta
        gastado[tipo] = gasta
    end
    return gastado
end

--- Días de batalla que le quedan a `g` de cada munición (math.huge sin
-- unidades de esa tropa).
function Municion.diasDe(g)
    local out = {}
    for _, tipo in ipairs(MUNICIONES) do
        local porDia = necesita(g, tipo)
        out[tipo] = porDia > 0 and ((g.municion and g.municion[tipo] or 0) / porDia) or math.huge
    end
    return out
end

--- Munición de un grupo para la vista (ver la cabecera), o nil.
function Municion:municionGrupo(gid)
    local g = self.estado.grupos[gid]
    if not g then
        return nil
    end
    local m = g.municion or {}
    local dias = Municion.diasDe(g)
    local sin = {}
    for tropa, tipo in pairs(DE_TROPA) do
        sin[tropa] = (g[tropa] or 0) > 0 and (m[tipo] or 0) <= 0
    end
    return { balas = m.balas or 0, misiles = m.misiles or 0, dias = dias, sin = sin }
end

-- Convoyes de munición ----------------------------------------------------------------------------

--- ¿Va ya un convoy de munición de `nid` hacia el grupo `gid`?
function Municion:convoyHacia(nid, gid)
    for _, g in ipairs(self:gruposHacia(gid)) do
        if g.nacion == nid and g.mision == 'abasto' then
            return true
        end
    end
    return false
end

--- Manda munición del polvorín de la ciudad `desdeId` al grupo `gid` (ver la
-- cabecera). Devuelve el id del convoy, o false y el motivo.
function Municion:abastecer(nid, desdeId, gid, balas, misiles)
    local e = self.estado
    local desde = e.ciudades[desdeId]
    if not desde or desde.nacion ~= nid then
        return false, 'noEsSuya'
    end
    local g = e.grupos[gid]
    if not g or g.nacion ~= nid or g.mision == 'abasto' then
        return false, 'grupo'
    end
    local convoy = {
        id = e.siguienteGrupo,
        nacion = nid,
        mision = 'abasto',
        desde = desde.id,
        objetivo = gid,
        destinoX = g.x,
        destinoY = g.y,
        x = desde.x,
        y = desde.y,
        antesX = desde.x,
        antesY = desde.y,
        soldados = 0,
    }
    self:dotar(convoy, desde, { balas = balas, misiles = misiles })
    local m = convoy.municion
    if m.balas + m.misiles <= 0 then
        convoy.municion = nil
        return false, 'nada'
    end
    e.siguienteGrupo = convoy.id + 1
    convoy.ruta = self:trazar(desde.x, desde.y, g.x, g.y) or { desde.x, desde.y, g.x, g.y }
    convoy.largo = Simulacion.largoRuta(convoy.ruta)
    -- Sale al final del día (o entre dos días): llega como pronto al siguiente.
    convoy.recorrido = 0
    convoy.antesRecorrido = 0
    e.grupos[convoy.id] = convoy
    self:medir('convoyes', 1, nid)
    return convoy.id
end

--- Llega un convoy de munición: se la da a su grupo si sigue en pie y es
-- suyo; si no, vuelve con ella a su ciudad.
function Municion:llegadaAbasto(convoy)
    local e = self.estado
    local g = e.grupos[convoy.objetivo]
    if g and g.nacion == convoy.nacion and g.mision ~= 'abasto' then
        g.municion = g.municion or Simulacion.municionVacia()
        for _, m in ipairs(MUNICIONES) do
            g.municion[m] = g.municion[m] + (convoy.municion and convoy.municion[m] or 0)
        end
        g.avisoMunicion = nil
        e.grupos[convoy.id] = nil
        return
    end
    self:volver(convoy)
end

--- Grupos de `nid` en batalla con menos de `umbralAbasto` días de alguna
-- munición, en orden de id (ver la cabecera).
function Municion:avisosMunicion(nid)
    local umbral = Simulacion.produccion.umbralAbasto
    local out = {}
    for _, g in ipairs(self:gruposDe(nid)) do
        if g.batalla then
            local dias = Municion.diasDe(g)
            local falta, menos
            for _, m in ipairs(MUNICIONES) do
                if dias[m] < umbral and (not menos or dias[m] < menos) then
                    falta, menos = m, dias[m]
                end
            end
            if falta then
                out[#out + 1] = { grupo = g.id, batalla = g.batalla, falta = falta, dias = menos }
            end
        end
    end
    return out
end

local NOMBRE = { balas = 'balas', misiles = 'misiles' }
local TROPA_NOMBRE = { balas = 'Soldados', misiles = 'Lanzacohetes' }

--- Noticia al jugador, una vez por grupo, cuando uno suyo en batalla baja de
-- `umbralAbasto` días de alguna munición (decisión del dueño: los convoyes
-- del jugador son a mano, con aviso).
function Municion:avisarMunicion()
    local e = self.estado
    for _, n in ipairs(self:jugadores()) do
        for _, aviso in ipairs(self:avisosMunicion(n.id)) do
            local g = e.grupos[aviso.grupo]
            if not g.avisoMunicion then
                g.avisoMunicion = true
                local b = e.batallas[aviso.batalla]
                local texto
                if aviso.dias <= 0 then
                    texto = string.format('%s sin %s', TROPA_NOMBRE[aviso.falta], NOMBRE[aviso.falta])
                else
                    texto = string.format('queda menos de %d días de %s', math.ceil(aviso.dias), NOMBRE[aviso.falta])
                end
                self:noticia(
                    string.format(
                        'Tu ejército en %s: %s. Mándale un convoy de munición',
                        b and self:nombreBatalla(b) or 'batalla',
                        texto
                    ),
                    { 1, 0.6, 0.3 }
                )
            end
        end
    end
end

--- El presidente NPC abastece a sus grupos en batalla con menos de
-- `umbralAbasto` días de alguna munición: les manda `dotacion.atacar` días de
-- lo que les falte desde la ciudad a la que pertenecen (si no va ya un convoy).
function Municion:planearAbastos(n)
    local reglas = Simulacion.produccion
    for _, aviso in ipairs(self:avisosMunicion(n.id)) do
        local g = self.estado.grupos[aviso.grupo]
        local c = self:ciudadDeGrupo(g)
        if c and not self:convoyHacia(n.id, g.id) then
            local dias = Municion.diasDe(g)
            local quiere = Municion.dotacion(g, reglas.dotacion.atacar)
            local pide = {}
            for _, m in ipairs(MUNICIONES) do
                pide[m] = dias[m] < reglas.umbralAbasto and quiere[m] or 0
            end
            self:ejecutar({
                tipo = 'abastecer',
                nacion = n.id,
                desde = c.id,
                grupo = g.id,
                balas = pide.balas,
                misiles = pide.misiles,
            })
        end
    end
end

--- ¿Tiene el polvorín del sitio `s` al menos `dias` días de batalla para
-- esas unidades? (la IA no manda grupos sin dotación).
function Municion:alcanzaMunicion(s, unidades, dias)
    local polvorin = self:polvorinDe(s)
    local quiere = Municion.dotacion(unidades, dias)
    for _, m in ipairs(MUNICIONES) do
        if quiere[m] > 0 and (not polvorin or polvorin[m] < quiere[m]) then
            return false
        end
    end
    return true
end

--- Suma de la munición de una lista de polvorines o grupos, por tipo.
function Municion.sumar(lista)
    local out = Simulacion.municionVacia()
    for _, m in ipairs(lista) do
        for _, tipo in ipairs(MUNICIONES) do
            out[tipo] = out[tipo] + (m[tipo] or 0)
        end
    end
    return out
end

local publicas = {
    'polvorinDe',
    'polvorin',
    'dotar',
    'devolverMunicion',
    'perderMunicion',
    'municionGrupo',
    'convoyHacia',
    'abastecer',
    'llegadaAbasto',
    'avisosMunicion',
    'avisarMunicion',
    'planearAbastos',
    'alcanzaMunicion',
}

--- Cuelga de la clase Simulacion las funciones de munición.
function Municion.instalar(clase)
    Simulacion = clase
    clase.MUNICIONES = MUNICIONES
    clase.municionDeTropa = DE_TROPA
    clase.dotacion = Municion.dotacion
    clase.municionNecesaria = Municion.necesita
    clase.partesMunicion = Municion.partes
    clase.gastarMunicionDia = Municion.gastarDia
    clase.diasMunicion = Municion.diasDe
    clase.sumarMunicion = Municion.sumar
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Municion[nombre]
    end
end

return Municion
