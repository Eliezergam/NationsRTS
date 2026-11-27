--- IA de recolección de los NPC: a qué minas mandan grupos, cuándo los retiran y cómo reservan lo que gastan.
--
-- Módulo de `mundo/simulacion.lua`: `RecoleccionIA.instalar(Simulacion)` cuelga sus
-- funciones de la clase, así que la API pública no cambia. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')

local ordenadas = Ayudas.ordenadas
local distancia = Ayudas.distancia
local esCiudad = Ayudas.esCiudad
local cargaDe = Ayudas.cargaDe

local RecoleccionIA = {}

-- Se fija en `instalar`: la clase.
local Simulacion

-- IA de recolección de los NPC (diseno/recoleccion-y-batallas.md, 3.10) ----------------------------
--
-- Todo pasa por `ejecutar`, como un jugador. El presidente piensa cada día y
-- no hay tope de grupos: solo manda a los soldados que le sobran.

--- Soldados que un NPC puede sacar hoy de un puesto sin bajar de su
-- guarnición mínima (F9 de ejercitos-en-el-mapa.md: `0,2 + 0,4 × prudencia`,
-- +0,15 en la frontera, × `reservaGuerra` con una guerra abierta) de lo que
-- tiene el puesto contando a los que ya salieron de él (`fuera`).
function RecoleccionIA:libresEn(n, s, fuera, enGuerra)
    local reserva = 0.2 + 0.4 * n.gobernante.prudencia
    if esCiudad(s) and self:enFrontera(s) then
        reserva = reserva + 0.15
    end
    if enGuerra then
        reserva = reserva * Simulacion.recoleccion.reservaGuerra
    end
    reserva = math.min(0.95, reserva)
    local soldados = math.floor(s.soldados - reserva * (s.soldados + (fuera or 0)))
    return math.max(0, soldados)
end

--- Lo que le falta a una nación de cada recurso para su reserva objetivo
-- (F9): consumo diario medio × `diasReserva`, sin bajar de lo que ya pide
-- (la reserva de metal, el combustible y los campamentos, la mejora que
-- ahorra) ni pasar del almacén; menos lo que tiene y lo que ya viene. La
-- comida, la que come su gente y no cultiva, en el granero de la capital; el
-- oro, solo con el tesoro por debajo de 10 × reservaTesoro (en unidades de oro).
function RecoleccionIA:faltanRecursos(n, enCamino)
    local reglas = Simulacion.recoleccion
    local dias = reglas.diasReserva
    local plan = n.plan or {}
    local tope = self:almacen(n.id)
    local consumo = n.consumo or {}
    local fijo = self:gastoCombustible(n.id) + self:mantenimientoCampamentos(n.id)
    local objetivo = {
        metal = math.max((consumo.metal or 0) * dias, Simulacion.consumo.reservaMetal + (plan.metal or 0)),
        petroleo = math.max((consumo.petroleo or 0) * dias, fijo * dias + (plan.petroleo or 0)),
    }
    -- Con alguien esperando avión (aviones.lua), junta también lo que cuesta uno.
    local avion = self:quiereAvion(n.id) and Simulacion.aviones.coste or {}
    objetivo.metal = objetivo.metal + (avion.metal or 0)
    objetivo.petroleo = objetivo.petroleo + (avion.petroleo or 0)
    local faltan = {}
    for _, r in ipairs({ 'metal', 'petroleo' }) do
        faltan[r] = math.min(objetivo[r], tope) - Simulacion.disponible(n, r) - (enCamino[r] or 0)
    end
    local capital = self.estado.ciudades[n.capital]
    local come = 0
    for _, c in ipairs(self:ciudadesDe(n.id)) do
        come = come + math.max(0, Simulacion.faltaComida(c) - self:comidaHuerto(c))
    end
    faltan.comida = capital and (math.min(Simulacion.granero(capital), come * dias) - (capital.comida or 0)) or 0
    faltan.comida = faltan.comida - (enCamino.comida or 0)
    local minimo = 10 * Simulacion.recuperacion.reservaTesoro + (avion.dinero or 0)
    faltan.oro = (minimo - Simulacion.disponible(n, 'dinero')) / Simulacion.yacimientos.precioOro - (enCamino.oro or 0)
    return faltan
end

--- Poder de un ejército ajeno `g` para `nid`: el de su informe vigente o,
-- sin él, la estimación a ciegas (`exploracion.ciegoEjercito`, por lo alto).
-- Con `explorar`, además manda un explorador si no tiene informe. Es la
-- misma regla que tiene el jugador: lo ajeno solo se sabe por informes.
function RecoleccionIA:poderEstimado(nid, g, explorar)
    local inf
    if explorar then
        inf = self:informeFresco(nid, g.id)
    else
        inf = self:informeVigente(nid, g.id)
    end
    return inf and inf.poder or Simulacion.exploracion.ciegoEjercito
end

--- Ejércitos de las naciones hostiles a `nid` (con líder, sin retirarse),
-- en orden de id. Para no mandar recolectores a donde los esperan (F10).
local function ejercitosHostiles(self, nid)
    local out = {}
    -- Solo pueden ser hostiles las naciones con las que tiene guerra.
    for _, guerra in ipairs(self:guerrasDe(nid)) do
        local otra = guerra.atacante == nid and guerra.defensor or guerra.atacante
        for _, g in ipairs(self:gruposDe(otra)) do
            if g.lider and not g.retirada and self:hostiles(nid, g.nacion) then
                out[#out + 1] = g
            end
        end
    end
    table.sort(out, function(a, b)
        return a.id < b.id
    end)
    return out
end

--- El presidente manda a recolectar (3.10): por cada recurso que le falta,
-- a la mina de más valor (F10) de las que conoce, los soldados justos para
-- cargarlo (F11) sin bajar de la guarnición mínima, desde el puesto (capital
-- o campamento) más cercano a la mina.
function RecoleccionIA:planearRecoleccion(n)
    local e = self.estado
    local reglas = Simulacion.recoleccion
    local capital = e.ciudades[n.capital]
    if not capital or capital.nacion ~= n.id then
        return
    end
    -- Todo viaja en avión (aviones.lua): mientras alguien suyo espera avión,
    -- no manda a nadie más (se quedaría también esperando).
    for _, g in ipairs(self:gruposDe(n.id)) do
        if Simulacion.Aviones.vuela(g) and not g.vuelo then
            return
        end
    end
    -- Lo que ya viene (la carga y el hueco de sus recolectores), lo que ya
    -- pidió a cada mina y los soldados que salieron de cada puesto.
    local enCamino, pedido, fuera = {}, {}, {}
    for _, g in ipairs(self:gruposDe(n.id)) do
        if g.tipoCarga and (g.mision == 'recolectar' or g.mision == 'regreso') then
            local capacidad = Simulacion.capacidad(g)
            local viene = g.mision == 'recolectar' and capacidad or cargaDe(g)
            enCamino[g.tipoCarga] = (enCamino[g.tipoCarga] or 0) + viene
            if g.mision == 'recolectar' then
                pedido[g.yacimiento] = (pedido[g.yacimiento] or 0) + capacidad - cargaDe(g)
                fuera[g.origen] = (fuera[g.origen] or 0) + g.soldados
            end
        end
    end
    local faltan = self:faltanRecursos(n, enCamino)
    if faltan.metal <= 0 and faltan.petroleo <= 0 and faltan.comida <= 0 and faltan.oro <= 0 then
        return
    end
    local enGuerra = self:numeroGuerras(n.id) > 0
    local puestos = { capital }
    for _, k in ipairs(self:instalacionesDe(n.id, 'campamento')) do
        if k.progreso >= 1 then
            puestos[#puestos + 1] = k
        end
    end
    local libres = {}
    local alguno = false
    for k, p in ipairs(puestos) do
        local soldados = self:libresEn(n, p, fuera[p.id], enGuerra)
        libres[k] = { soldados = soldados }
        alguno = alguno or soldados >= reglas.minimoGrupo
    end
    if not alguno then
        return
    end
    local hostiles
    -- Lo que llena un robot en unos 10 días (con los aviones, 26-nov).
    local cargaSoldado = reglas.kRitmo * 10
    for _, tipo in ipairs({ 'comida', 'petroleo', 'metal', 'oro' }) do
        local falta = faltan[tipo]
        local descartadas = {}
        for _ = 1, 3 do
            if falta < 3 then
                break
            end
            -- F10 sin la seguridad: la mina de más valor y su puesto más cercano.
            local mejor, mejorValor, desde, desdeK
            for _, d in ipairs(self:yacimientosConocidosDe(n.id, tipo)) do
                if not descartadas[d.id] and not self:minaCerrada(d) then
                    local queda = self:estadoMina(d) - (pedido[d.id] or 0)
                    if queda > 0 then
                        local cerca, cercaD, cercaK
                        for k, p in ipairs(puestos) do
                            if libres[k].soldados >= reglas.minimoGrupo then
                                local dist = distancia(p, d)
                                if not cerca or dist < cercaD then
                                    cerca, cercaD, cercaK = p, dist, k
                                end
                            end
                        end
                        if cerca then
                            local ventaja = self:duenoDeposito(d) == n.id and reglas.ventajaTerritorio or 1
                            local valor = math.min(1, queda / falta)
                                * ventaja
                                / (1 + cercaD / Simulacion.velocidadEjercito)
                            if not mejor or valor > mejorValor or (valor == mejorValor and d.id < mejor.id) then
                                mejor, mejorValor, desde, desdeK = d, valor, cerca, cercaK
                            end
                        end
                    end
                end
            end
            if not mejor then
                break
            end
            local libre = libres[desdeK]
            local soldados = math.min(libre.soldados, math.max(reglas.minimoGrupo, math.ceil(falta / cargaSoldado)))
            -- F10, seguridad: no manda a una mina con un ejército hostil más
            -- fuerte que el grupo a menos de un día (su poder, el que dicen
            -- sus informes; sin informe, a ciegas).
            hostiles = hostiles or ejercitosHostiles(self, n.id)
            local poder = soldados * Simulacion.poderUnidad('soldados')
            local segura = true
            for _, h in ipairs(hostiles) do
                if
                    distancia(h, mejor) < Simulacion.velocidadEjercito
                    and self:poderEstimado(n.id, h, false) > poder
                then
                    segura = false
                    break
                end
            end
            if not segura then
                descartadas[mejor.id] = true
            else
                local gid = self:ejecutar({
                    tipo = 'recolectar',
                    nacion = n.id,
                    desde = desde.id,
                    yacimiento = mejor.id,
                    soldados = soldados,
                })
                if not gid then
                    descartadas[mejor.id] = true
                else
                    local capacidad = Simulacion.capacidad(e.grupos[gid])
                    falta = falta - capacidad
                    pedido[mejor.id] = (pedido[mejor.id] or 0) + capacidad
                    libre.soldados = libre.soldados - soldados
                end
            end
        end
    end
end

--- Ataque a recolectores (3.10, dentro de `ofensiva`): de las minas con
-- recolectores de `enemiga` a menos de `alcanceCodicia` de un sitio propio (lo
-- que ven sus fronteras), primero las que ya conoce por sus informes y, entre
-- ellas, la de más carga (y, a igual carga, la más cercana);
-- manda un ejército si su poder libre cumple F12 con el poder que dicen sus
-- informes de los recolectores (el que no conoce, estimado a ciegas por lo
-- alto). Una mina a la vez: no manda a otra donde ya va uno suyo.
function RecoleccionIA:atacarRecolectores(n, enemiga)
    local e = self.estado
    local reglas = Simulacion.recoleccion
    local porMina, ids, yaVa = {}, {}, {}
    for _, g in ipairs(self:gruposDe(enemiga)) do
        if g.mision == 'recolectar' and g.fase == 'recolectando' and not g.batalla then
            if not porMina[g.yacimiento] then
                porMina[g.yacimiento] = { grupos = {}, carga = 0 }
                ids[#ids + 1] = g.yacimiento
            end
            local m = porMina[g.yacimiento]
            m.grupos[#m.grupos + 1] = g.id
            m.carga = m.carga + cargaDe(g)
        end
    end
    for _, g in ipairs(self:gruposDe(n.id)) do
        if g.mision == 'atacar' then
            yaVa[g.objetivo] = true
        end
    end
    if #ids == 0 then
        return false
    end
    table.sort(ids)
    local sitios = self:sitiosDe(n.id)
    local mejor, mejorM, mejorD, desde
    for _, id in ipairs(ids) do
        local d = e.depositos[id]
        if d and not yaVa[id] then
            local cerca, cercaD
            for _, s in ipairs(sitios) do
                local dist = distancia(s, d)
                if dist < Simulacion.alcanceCodicia and (not cerca or dist < cercaD) then
                    cerca, cercaD = s, dist
                end
            end
            local m = porMina[id]
            if cerca then
                -- Antes las minas cuyos recolectores ya conoce (informes vigentes de todos).
                m.conocida = true
                for _, gid in ipairs(m.grupos) do
                    if not self:informeVigente(n.id, gid) then
                        m.conocida = false
                        break
                    end
                end
            end
            local antes = mejor
                and (
                    m.conocida and not mejorM.conocida
                    or m.conocida == mejorM.conocida
                        and (m.carga > mejorM.carga or (m.carga == mejorM.carga and cercaD < mejorD))
                )
            if cerca and (not mejor or antes) then
                mejor, mejorM, mejorD, desde = d, m, cercaD, cerca
            end
        end
    end
    if not mejor then
        return false
    end
    -- El poder de los recolectores solo lo sabe por sus informes. Recolectan
    -- pocos días (un explorador llegaría tarde), así que al que no conoce lo
    -- estima a ciegas por lo alto (`ciegoRecolector`) y le manda un
    -- explorador para la próxima vez.
    local conocido = 0
    for _, gid in ipairs(mejorM.grupos) do
        local inf = self:informeFresco(n.id, gid)
        conocido = conocido + (inf and inf.poder or Simulacion.exploracion.ciegoRecolector)
    end
    local necesita = conocido * (reglas.umbralAtaque - n.gobernante.agresividad)
    local soldados = self:libresEn(n, desde, 0, true)
    local unidadS = Simulacion.poderUnidad('soldados')
    if soldados * unidadS < necesita then
        return false
    end
    -- Lleva lo justo con un margen del 20 %.
    local quiere = necesita * 1.2
    soldados = math.min(soldados, math.max(1, math.ceil(quiere / unidadS)))
    -- Sin munición para `umbralAbasto` días no sale (diseno/economia.md, §10).
    local unidades = { soldados = soldados, lanzacohetes = 0 }
    if not self:alcanzaMunicion(desde, unidades, Simulacion.produccion.umbralAbasto) then
        return false
    end
    local gid = self:ejecutar({
        tipo = 'enviarGrupo',
        nacion = n.id,
        desde = desde.id,
        mision = 'atacar',
        objetivo = mejor.id,
        soldados = soldados,
    })
    if gid then
        self:noticia(
            string.format(
                '%s manda un ejército contra los recolectores de %s en %s %s',
                n.nombre,
                e.naciones[enemiga].nombre,
                Simulacion.recursos[mejor.tipo].articulo,
                Simulacion.recursos[mejor.tipo].nombre
            ),
            n.color
        )
    end
    return gid
end

--- El presidente defiende lo suyo (3.10): retira a sus recolectores de una
-- mina a la que llega en un día o menos un ejército que no pueden aguantar
-- (poder recolectores < poder atacante × (umbralRetirar + prudencia), con el
-- poder del atacante que dicen sus informes; sin informe, a ciegas, y manda
-- un explorador); y, con
-- su capital en batalla, llama a casa a sus grupos que lleguen antes de
-- `diasLlamada` días.
function RecoleccionIA:defenderLoSuyo(n)
    local e = self.estado
    local reglas = Simulacion.recoleccion
    local propios = self:gruposDe(n.id)
    -- Ataques ajenos a punto de llegar a las minas donde recolecta.
    local amenazas = {}
    for _, g in ipairs(propios) do
        local id = g.mision == 'recolectar' and g.yacimiento
        if id and amenazas[id] == nil then
            local lista = {}
            for _, o in ipairs(self:gruposHacia(id)) do
                if
                    o.nacion ~= n.id
                    and o.mision == 'atacar'
                    and not o.batalla
                    and o.ruta
                    and e.depositos[o.objetivo]
                then
                    if (o.largo - o.recorrido) <= Simulacion.velocidadEjercito * reglas.avisoDias then
                        lista[#lista + 1] = o
                    end
                end
            end
            amenazas[id] = #lista > 0 and lista or false
        end
    end
    local suyos = {}
    for _, g in ipairs(propios) do
        if g.mision == 'recolectar' and g.fase == 'recolectando' and not g.batalla and amenazas[g.yacimiento] then
            suyos[g.yacimiento] = suyos[g.yacimiento] or { poder = 0, grupos = {} }
            suyos[g.yacimiento].poder = suyos[g.yacimiento].poder + Simulacion.poder(g)
            table.insert(suyos[g.yacimiento].grupos, g)
        end
    end
    for _, id in ipairs(ordenadas(suyos)) do
        local m = suyos[id]
        local amenaza = 0
        for _, g in ipairs(amenazas[id]) do
            amenaza = amenaza + self:poderEstimado(n.id, g, true)
        end
        if m.poder < amenaza * (reglas.umbralRetirar + n.gobernante.prudencia) then
            for _, g in ipairs(m.grupos) do
                self:ejecutar({ tipo = 'retirar', nacion = n.id, grupo = g.id })
            end
        end
    end
    local capital = e.ciudades[n.capital]
    local b = capital and capital.nacion == n.id and self:batallaEn('sitio', capital.id)
    if not b then
        return
    end
    local alcance = reglas.diasLlamada * Simulacion.velocidadEjercito
    for _, g in ipairs(propios) do
        local enCasa = g.mision == 'regreso' and g.desde == capital.id
        local llamable = g.mision == 'recolectar' or g.mision == 'regreso' or g.mision == 'atacar'
        if llamable and not enCasa and not g.batalla and distancia(g, capital) <= alcance then
            self:ejecutar({ tipo = 'redirigir', nacion = n.id, grupo = g.id, destino = capital.id })
        end
    end
end

local publicas = {
    'poderEstimado',
    'libresEn',
    'faltanRecursos',
    'planearRecoleccion',
    'atacarRecolectores',
    'defenderLoSuyo',
}

local datos = {}

--- Cuelga de la clase Simulacion las funciones y datos de este módulo.
function RecoleccionIA.instalar(clase)
    Simulacion = clase
    for _, nombre in ipairs(datos) do
        clase[nombre] = RecoleccionIA[nombre]
    end
    for _, nombre in ipairs(publicas) do
        clase[nombre] = RecoleccionIA[nombre]
    end
end

return RecoleccionIA
