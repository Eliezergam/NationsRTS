--- Ataques y órdenes a los grupos: aviso de ataques, retirar, redirigir, ir a un punto y llegada a minas y sitios.
--
-- Módulo de `mundo/simulacion.lua`: `Ataques.instalar(Simulacion)` cuelga sus
-- funciones de la clase, así que la API pública no cambia. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')

local ordenadas = Ayudas.ordenadas
local nacionesBando = Ayudas.nacionesBando
local OTRO_LADO = Ayudas.OTRO_LADO
local esCiudad = Ayudas.esCiudad
local ponerAlMando = Ayudas.ponerAlMando

local Ataques = {}

-- Se fija en `instalar`: la clase.
local Simulacion

-- Aviso de ataques (3.8.1) -----------------------------------------------------------------------

--- Lo que ataca un grupo: { tipo = 'sitio' | 'mina', id, naciones = { nid =
-- true } } (las naciones atacadas: la del sitio o las de los recolectores de
-- la mina), o nil.
function Ataques:blancoDe(g)
    local e = self.estado
    local s = e.ciudades[g.objetivo] or e.instalaciones[g.objetivo]
    if s then
        return { tipo = 'sitio', id = s.id, x = s.x, y = s.y, naciones = { [s.nacion] = true } }
    end
    local d = e.depositos[g.objetivo]
    if d then
        local naciones = {}
        for _, o in ipairs(self:recolectoresEn(d.id)) do
            if o.nacion ~= g.nacion then
                naciones[o.nacion] = true
            end
        end
        return { tipo = 'mina', id = d.id, x = d.x, y = d.y, naciones = naciones }
    end
    return nil
end

--- Ataques que van hacia algo de `nid` (un sitio suyo o una mina con sus
-- recolectores) y llegan en `avisoDias` o menos: { grupo, nacion, objetivo =
-- { tipo, id }, x, y, dias, poder }, en orden de grupo. `poder` es el real:
-- la vista lo enseña solo con informe (`poderConocido`, el del informe, o nil).
function Ataques:avisosAtaque(nid)
    local out = {}
    for _, g in ipairs(self:gruposConMision('atacar')) do
        if g.mision == 'atacar' and g.nacion ~= nid and not g.batalla and not g.detenido and g.ruta then
            local dias = (g.largo - g.recorrido) / Simulacion.velocidadEjercito
            if dias <= Simulacion.recoleccion.avisoDias and dias > 0 then
                local blanco = self:blancoDe(g)
                if blanco and blanco.naciones[nid] then
                    out[#out + 1] = {
                        grupo = g.id,
                        nacion = g.nacion,
                        objetivo = { tipo = blanco.tipo, id = blanco.id },
                        x = blanco.x,
                        y = blanco.y,
                        dias = math.ceil(dias),
                        poder = Simulacion.poderRedondeado(Simulacion.poder(g)),
                        poderConocido = self:poderConocido(nid, g.id),
                    }
                end
            end
        end
    end
    return out
end

--- Poder de `objetivo` (un grupo o un sitio ajeno) que conoce `nid` por su
-- informe, redondeado, o nil si no tiene informe.
function Ataques:poderConocido(nid, objetivo)
    local inf = self:informe(nid, objetivo)
    return inf and Simulacion.poderRedondeado(inf.poder) or nil
end

--- Noticia (una vez por grupo) de cada ataque que llega pronto a algo de un
-- jugador: «El ejército de X va hacia Y: llega en N días» y, solo si tiene
-- informe de ese ejército, «, poder P (informe)». Se mira en cada paso de
-- marcha, así que solo los ataques en camino que aún no avisaron, en orden de
-- grupo; con varios jugadores atacados, avisa al de id menor.
function Ataques:avisarAtaques()
    local e = self.estado
    local atacan = self:indiceGrupos().porMision.atacar
    if not atacan then
        return
    end
    local hayJugador
    for i = 1, #atacan do
        local g = atacan[i]
        if
            e.grupos[g.id] == g
            and g.mision == 'atacar'
            and not g.avisado
            and not g.batalla
            and not g.detenido
            and g.ruta
            and (g.largo - g.recorrido) / Simulacion.velocidadEjercito <= Simulacion.recoleccion.avisoDias
            and g.recorrido < g.largo
        then
            if hayJugador == nil then
                hayJugador = false
                for _, n in pairs(e.naciones) do
                    if n.jugador then
                        hayJugador = true
                        break
                    end
                end
            end
            if not hayJugador then
                return
            end
            local blanco = self:blancoDe(g)
            for _, nid in ipairs(blanco and ordenadas(blanco.naciones) or {}) do
                local n = e.naciones[nid]
                if not g.avisado and n and n.jugador and nid ~= g.nacion then
                    self:avisarAtaque(n.id, g)
                end
            end
        end
    end
end

--- La noticia del ataque `g` que llega pronto a algo de `nid` (un jugador).
function Ataques:avisarAtaque(nid, g)
    local e = self.estado
    for _, aviso in ipairs(self:avisosAtaque(nid)) do
        if aviso.grupo == g.id then
            g.avisado = true
            local blanco = aviso.objetivo.tipo == 'sitio'
                    and Simulacion.nombreBlanco(self, self:sitio(aviso.objetivo.id))
                or 'tus recolectores de ' .. Simulacion.recursos[e.depositos[aviso.objetivo.id].tipo].nombre
            local poder = ''
            if aviso.poderConocido then
                poder = string.format(', poder %d (informe)', aviso.poderConocido)
            end
            self:noticia(
                string.format(
                    'El ejército de %s va hacia %s: llega en %d día%s%s',
                    e.naciones[g.nacion].nombre,
                    blanco,
                    aviso.dias,
                    aviso.dias == 1 and '' or 's',
                    poder
                ),
                { 1, 0.5, 0.3 }
            )
            return
        end
    end
end

--- Pone en marcha a `g` hacia (x, y), desde donde está.
local function encaminar(self, g, x, y)
    g.destinoX, g.destinoY = x, y
    g.ruta = self:trazar(g.x, g.y, x, y) or { g.x, g.y, x, y }
    g.largo = Simulacion.largoRuta(g.ruta)
    g.recorrido, g.antesRecorrido = 0, 0
    g.detenido, g.detenidoDesde = nil, nil
end

--- Saca a `g` de su batalla como una retirada (pierde la carga) antes de una
-- orden que lo lleva a otra parte.
local function dejarBatalla(self, g)
    local b = g.batalla and self.estado.batallas[g.batalla]
    if b then
        local lado = self:ladoDe(b, g.nacion)
        self:repartirCarga(b, g, OTRO_LADO[lado or 'atacante'])
    end
    g.batalla = nil
end

--- Orden de volver a casa (3.1.7) para un grupo propio que está fuera: con la
-- carga que lleve (en una batalla, la pierde: es una retirada). Devuelve true
-- o false.
function Ataques:retirarGrupo(nid, gid)
    local g = self.estado.grupos[gid]
    if not g or g.nacion ~= nid or g.mision == 'regreso' or g.mision == 'entrega' or g.mision == 'construir' then
        return false, 'noPuede'
    end
    if g.batalla then
        local b = self.estado.batallas[g.batalla]
        dejarBatalla(self, g)
        self:retirar(g, b and self:nombreBatalla(b) or 'la batalla')
    else
        self:volver(g)
    end
    return true
end

--- ¿Se le pueden dar órdenes de marcha? Las obras, las entregas, los
-- convoyes de munición y los remolques siguen su camino.
function Ataques.mandable(g)
    return g.mision ~= 'entrega' and g.mision ~= 'construir' and g.mision ~= 'abasto' and not g.remolque
end

--- Manda a un grupo propio que está fuera a otro sitio propio (una ciudad, un
-- campamento o una base terminados) o a una batalla en la que pelea su
-- nación (3.1.9, 3.8.4): conserva la carga y la entrega al llegar si es una
-- ciudad o un campamento; en una batalla se suma a su bando. Si estaba en una
-- batalla, sale de ella como en una retirada. Devuelve true o false.
function Ataques:redirigir(nid, gid, destinoId)
    local e = self.estado
    local g = e.grupos[gid]
    if not g or g.nacion ~= nid or not Ataques.mandable(g) then
        return false, 'noPuede'
    end
    local b = type(destinoId) == 'number' and e.batallas[destinoId]
    local sitio = not b and destinoId and self:sitio(destinoId)
    if b then
        if not self:ladoDe(b, nid) or g.batalla == b.id then
            return false, 'batalla'
        end
    elseif
        not sitio
        or sitio.nacion ~= nid
        or not (esCiudad(sitio) or ((sitio.tipo == 'campamento' or sitio.tipo == 'base') and sitio.progreso >= 1))
    then
        return false, 'destino'
    end
    -- Defender una bandera cuenta para su tope de guarnición (F5).
    if b and b.lugar.tipo == 'sitio' and Simulacion.leerIdBandera(b.lugar.id) and self:ladoDe(b, nid) == 'defensor' then
        if self:cargaGuarnicion(b.lugar.id, g) + Simulacion.vidaGrupo(g) > self:topeGuarnicion(nid) then
            return false, 'llena'
        end
    end
    local destino = b or sitio
    if not self:trazar(g.x, g.y, destino.x, destino.y) then
        return false, 'sinCamino'
    end
    if g.batalla then
        dejarBatalla(self, g)
    end
    if g.tipoCarga then
        g.fase = 'vuelta'
    end
    g.bandera, g.alerta = nil, nil
    if b then
        g.mision, g.apoyo = 'apoyo', b.id
        self:reindexarGrupo(g)
    else
        g.mision, g.desde, g.apoyo = 'regreso', sitio.id, nil
        self:reindexarGrupo(g)
    end
    encaminar(self, g, destino.x, destino.y)
    return true
end

--- Manda a un ejército propio que está fuera a guarnecer una bandera suya
-- del borde (diseno/banderas-borde.md, 3.12.2): marcha hasta ella y se queda
-- (misión 'guarnicion'). Valida, en este orden: la bandera es suya y de
-- borde ('destino'), el grupo se puede mandar y es un ejército ('noPuede'),
-- hay camino ('sinCamino') y cabe en el tope ('llena', F5). Si estaba en una
-- batalla, sale como en una retirada. Devuelve true o false y el motivo.
function Ataques:guarnecer(nid, gid, banderaId)
    local g = self.estado.grupos[gid]
    local bandera = self:banderaDeBorde(nid, banderaId)
    if not bandera then
        return false, 'destino'
    end
    if not g or g.nacion ~= nid or not Ataques.mandable(g) or not g.lider or g.bandera == banderaId then
        return false, 'noPuede'
    end
    if not self:trazar(g.x, g.y, bandera.x, bandera.y) then
        return false, 'sinCamino'
    end
    local cabe, motivo = self:admiteGuarnicion(nid, banderaId, Simulacion.vidaGrupo(g), g)
    if not cabe then
        return false, motivo
    end
    if g.batalla then
        dejarBatalla(self, g)
    end
    if g.tipoCarga then
        g.fase = 'vuelta'
    end
    g.mision, g.objetivo, g.apoyo, g.bandera = 'guarnicion', banderaId, nil, nil
    self:reindexarGrupo(g)
    encaminar(self, g, bandera.x, bandera.y)
    return true
end

--- Manda a un grupo propio a un punto del mapa (dueño 2026-09-29): camina
-- libre por el mundo sin necesidad de tener una ciudad propia como destino.
-- Si el punto cae sobre una ciudad/batalla enemiga, el grupo pasa a la
-- misión 'atacar' contra ese objetivo y entra a la batalla al llegar; si
-- cae en cualquier otro lado, la misión es 'mover' y el grupo se queda en
-- ese punto esperando nuevas órdenes. Si el grupo tenía carga, la pierde.
function Ataques:irAPunto(nid, gid, x, y)
    local e = self.estado
    local g = e.grupos[gid]
    if not g or g.nacion ~= nid then
        return false, 'noPuede'
    end
    -- Las construcciones, entregas, convoyes de munición y remolques no se
    -- pueden llevar a un punto libre.
    if not Ataques.mandable(g) then
        return false, 'noPuede'
    end
    -- Sale de una batalla como una retirada.
    if g.batalla then
        local b = e.batallas[g.batalla]
        dejarBatalla(self, g)
        if b then
            self:retirar(g, self:nombreBatalla(b))
        end
    end
    -- ¿El punto cae sobre una instalación o ciudad enemiga? Si sí, atacarla.
    local blanco = self:blancoEn(x, y)
    if blanco and blanco.nacion ~= nid then
        local ruta = self:trazar(g.x, g.y, blanco.x, blanco.y)
        if not ruta then
            return false, 'sinCamino'
        end
        -- Atacar una bandera del borde la guarda (banderas.lua).
        if blanco.tipo == 'bandera' then
            blanco = self:guardarBandera(blanco.id)
        end
        g.mision, g.objetivo, g.apoyo, g.bandera = 'atacar', blanco.id, nil, nil
        self:reindexarGrupo(g)
        if g.tipoCarga then
            g.fase = 'vuelta'
        end
        encaminar(self, g, blanco.x, blanco.y)
    else
        -- Punto libre: el grupo se queda ahí esperando nuevas órdenes.
        local ruta = self:trazar(g.x, g.y, x, y)
        if not ruta then
            return false, 'sinCamino'
        end
        g.mision, g.objetivo, g.apoyo, g.desde, g.bandera = 'mover', nil, nil, nil, nil
        self:reindexarGrupo(g)
        if g.tipoCarga then
            g.fase = 'vuelta'
        end
        encaminar(self, g, x, y)
    end
    return true
end

--- Busca el primer objetivo atacable bajo el punto (x, y): una ciudad o
-- una instalación (campamento, base, bandera guardada, huerto) cercana al
-- click o, si no hay, la bandera del borde del bloque del punto.
-- Tolerancia 200 m. Solo se usa para que el jugador le diga al grupo
-- "atacá esa cosa" sin tener que dar el (x, y) exacto. Devuelve el objeto
-- o nil.
function Ataques:blancoEn(x, y)
    local e = self.estado
    local tolerancia = 200 -- px de mundo (1 px = 1 m)
    local mejor, mejorDist
    for _, c in pairs(e.ciudades) do
        local d = math.sqrt((c.x - x) ^ 2 + (c.y - y) ^ 2)
        if d <= tolerancia and (not mejorDist or d < mejorDist) then
            mejor, mejorDist = c, d
        end
    end
    for _, id in ipairs(Simulacion.ordenadas(e.instalaciones)) do
        local i = e.instalaciones[id]
        local radio = i.radio or 80
        local d = math.sqrt((i.x - x) ^ 2 + (i.y - y) ^ 2)
        if d <= radio + tolerancia and (not mejorDist or d < mejorDist) then
            mejor, mejorDist = i, d
        end
    end
    return mejor or self:banderaCerca(x, y, 80 + tolerancia)
end

--- Un grupo que va a atacar llega a una mina (3.5): pelea contra los
-- recolectores de las naciones hostiles. Si solo hay recolectores de naciones
-- en paz, atacar declara la guerra a la que más trabaja allí (decisión 3 de
-- El dueño); con un alto el fuego no se ataca. Si no hay nadie, vuelve a casa
-- (no se queda esperando: eso sería patrullar). Si ya hay una batalla en la
-- mina, se suma a su bando.
function Ataques:llegarAMina(g, d)
    local b = self:batallaEn('mina', d.id)
    if b then
        local lado = self:ladoDe(b, g.nacion)
        if not lado then
            for _, nid in ipairs(ordenadas(nacionesBando(self, b, 'defensor'))) do
                if self:hostiles(g.nacion, nid) then
                    lado = 'atacante'
                end
            end
        end
        if lado then
            return self:unirBatalla(b, g, lado)
        end
        return self:volver(g)
    end
    local enemigos, enPaz = {}, {}
    for _, o in ipairs(self:recolectoresEn(d.id)) do
        if o.nacion ~= g.nacion then
            if self:hostiles(g.nacion, o.nacion) then
                enemigos[#enemigos + 1] = o
            elseif not self:guerraEntre(g.nacion, o.nacion) then
                enPaz[o.nacion] = (enPaz[o.nacion] or 0) + Simulacion.trabajo(o)
            end
        end
    end
    if #enemigos == 0 then
        local contra, mas
        for _, nid in ipairs(ordenadas(enPaz)) do
            if not contra or enPaz[nid] > mas then
                contra, mas = nid, enPaz[nid]
            end
        end
        if contra then
            local recurso = Simulacion.recursos[d.tipo]
            self:ejecutar({
                tipo = 'declararGuerra',
                nacion = g.nacion,
                contra = contra,
                motivo = 'sus recolectores de ' .. recurso.articulo .. ' ' .. recurso.nombre,
            })
            for _, o in ipairs(self:recolectoresEn(d.id)) do
                if o.nacion == contra then
                    enemigos[#enemigos + 1] = o
                end
            end
        end
    end
    if #enemigos == 0 then
        return self:volver(g)
    end
    self:crearBatalla({ tipo = 'mina', id = d.id }, d.x, d.y, { g }, enemigos)
end

--- Un grupo que va a atacar llega a un sitio (ciudad, campamento, base o
-- bandera): empieza la batalla o se suma a la que ya hay. Si no hay guerra,
-- atacar la declara; con un alto el fuego, espera.
function Ataques:llegarASitio(g, s)
    local b = self:batallaEn('sitio', s.id)
    if b then
        return self:unirBatalla(b, g, self:ladoDe(b, g.nacion) or 'atacante')
    end
    if not self:guerraEntre(g.nacion, s.nacion) then
        self:ejecutar({ tipo = 'declararGuerra', nacion = g.nacion, contra = s.nacion, motivo = 'un ataque' })
    end
    if not self:hostiles(g.nacion, s.nacion) then
        g.detenido, g.detenidoDesde = true, g.detenidoDesde or self.estado.dia
        return
    end
    -- En una bandera, su guarnición pelea en el bando defensor (3.12.4).
    local defensores = s.tipo == 'bandera' and self:defensoresBandera(s) or {}
    self:crearBatalla({ tipo = 'sitio', id = s.id }, s.x, s.y, { g }, defensores, s.id)
end

--- Un grupo que ya recolecta en una mina recibe la orden de atacar allí
-- (3.5.5): pasa a ser un ejército (con un líder libre) y la batalla empieza
-- al día siguiente sin moverse. Devuelve su id o false.
function Ataques:atacarDesdeMina(nid, gid, yacimientoId, liderId)
    local e = self.estado
    local g = e.grupos[gid]
    if not g or g.nacion ~= nid or g.mision ~= 'recolectar' or g.fase ~= 'recolectando' then
        return false
    end
    if g.yacimiento ~= yacimientoId or g.batalla then
        return false
    end
    local jefe = self:liderParaSalir(nid, liderId)
    if not jefe then
        return false
    end
    ponerAlMando(e, g, jefe)
    g.mision, g.objetivo, g.fase = 'atacar', yacimientoId, nil
    self:reindexarGrupo(g)
    encaminar(self, g, g.x, g.y)
    return gid
end

local publicas = {
    'poderConocido',
    'blancoDe',
    'avisosAtaque',
    'avisarAtaques',
    'avisarAtaque',
    'retirarGrupo',
    'redirigir',
    'irAPunto',
    'guarnecer',
    'blancoEn',
    'llegarAMina',
    'llegarASitio',
    'atacarDesdeMina',
}

local datos = {}

--- Cuelga de la clase Simulacion las funciones y datos de este módulo.
function Ataques.instalar(clase)
    Simulacion = clase
    for _, nombre in ipairs(datos) do
        clase[nombre] = Ataques[nombre]
    end
    clase.mandable = Ataques.mandable
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Ataques[nombre]
    end
end

return Ataques
