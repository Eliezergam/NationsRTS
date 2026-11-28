--- Diplomacia y guerra: tensión, ataques de los presidentes, negociaciones, altos el fuego y paz.
--
-- Módulo de `mundo/simulacion.lua`: `Diplomacia.instalar(Simulacion)` cuelga sus
-- funciones de la clase, así que la API pública no cambia. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')
local Armamento = require('mundo.simulacion.armamento')

local distancia = Ayudas.distancia
local claveGuerra = Ayudas.claveGuerra
local cambiarRelacion = Ayudas.cambiarRelacion
local grupoEnCamino = Ayudas.grupoEnCamino
local esCiudad = Ayudas.esCiudad

local Diplomacia = {}

-- Se fija en `instalar`: la clase.
local Simulacion

-- Diplomacia y guerra -----------------------------------------------------------------------

function Diplomacia:frente(a, b)
    local mejor, mejorD
    for _, c in ipairs(self:ciudadesDe(a)) do
        for _, o in ipairs(self:ciudadesDe(b)) do
            local d = distancia(c, o)
            if not mejor or d < mejorD then
                mejor, mejorD = { c, o }, d
            end
        end
    end
    return mejor and mejor[1], mejor and mejor[2]
end

--- Minas de una nación: las que conoce (a menos de `alcanceMeta` de su
-- capital) en su territorio, en orden fijo. Se calcula una vez al día.
function Diplomacia:minasDe(nid)
    local dia = self.estado.dia
    if not self.cacheMinas or self.cacheMinas.dia ~= dia then
        self.cacheMinas = { dia = dia }
    end
    local out = self.cacheMinas[nid]
    if not out then
        out = {}
        for _, d in ipairs(self:yacimientosConocidos(nid)) do
            if self:duenoDeposito(d) == nid then
                out[#out + 1] = d
            end
        end
        self.cacheMinas[nid] = out
    end
    return out
end

--- Lo que `a` codicia de `b`: la riqueza de las minas de `b` (en su
-- territorio) a su alcance (a menos de `alcanceCodicia` de una ciudad o un
-- campamento terminado de `a`; cada una cuenta una vez), pesada por cuánto
-- necesita `a` cada recurso. Quien va sobrado no codicia nada. Devuelve el
-- total y el recurso que más pesa.
function Diplomacia:recursosEnDisputa(a, b)
    -- Las minas de `b` están a menos de `alcanceMeta` de su capital: con las
    -- capitales muy lejos no hay nada que codiciar (y no se recorre nada).
    local e = self.estado
    local ca = e.ciudades[e.naciones[a].capital]
    local cb = e.ciudades[e.naciones[b].capital]
    if ca and cb and distancia(ca, cb) > 2 * Simulacion.campamento.alcanceMeta + Simulacion.alcanceCodicia then
        return 0, nil
    end
    local necesidad = self:necesidades(a)
    local valor, porTipo = 0, {}
    local propios
    for _, d in ipairs(self:minasDe(b)) do
        local peso = d.riqueza * (necesidad[d.tipo] or 0)
        if peso > 0 then
            if not propios then
                propios = {}
                for _, c in ipairs(self:ciudadesDe(a)) do
                    propios[#propios + 1] = c
                end
                for _, k in ipairs(self:instalacionesDe(a, 'campamento')) do
                    if k.progreso >= 1 then
                        propios[#propios + 1] = k
                    end
                end
            end
            for _, c in ipairs(propios) do
                if distancia(c, d) < Simulacion.alcanceCodicia then
                    valor = valor + peso
                    porTipo[d.tipo] = (porTipo[d.tipo] or 0) + peso
                    break
                end
            end
        end
    end
    local principal
    for _, tipo in ipairs({ 'petroleo', 'comida', 'metal', 'oro' }) do
        if porTipo[tipo] and (not principal or porTipo[tipo] > porTipo[principal]) then
            principal = tipo
        end
    end
    return valor, principal
end

local NOMBRE_CODICIA = { metal = 'el metal', petroleo = 'el petróleo', comida = 'la comida', oro = 'el oro' }

function Diplomacia:diplomacia(a, b, azar)
    local e = self.estado
    local c1, c2 = self:frente(a.id, b.id)
    local d = c1 and distancia(c1, c2) or math.huge
    local cambio = 0
    if a.orden == b.orden then
        cambio = cambio + 0.5
    elseif Simulacion.ordenes[a.orden].opuesto == b.orden then
        cambio = cambio - 0.4
    end
    if d < Simulacion.alcanceGuerra then
        cambio = cambio - 0.25 * (1 - d / Simulacion.alcanceGuerra)
    end
    local disputa, codiciado = self:recursosEnDisputa(a.id, b.id)
    cambio = cambio - 0.15 * disputa * (0.5 + a.gobernante.agresividad)
    -- En guerra las relaciones las mueven los hechos (ataques, conversaciones), no la deriva.
    if self:guerraEntre(a.id, b.id) then
        cambio = 0
    end
    local suceso = azar()
    if suceso < 0.002 then
        cambio = cambio - 15
        self:noticia(string.format('Incidente fronterizo entre %s y %s', a.nombre, b.nombre), { 1, 0.7, 0.4 })
        self:hecho('incidente', a.id, b.id)
    elseif suceso > 0.998 then
        cambio = cambio + 15
        self:noticia(string.format('%s y %s firman un acuerdo comercial', a.nombre, b.nombre), { 0.6, 1, 0.6 })
        self:hecho('acuerdo', a.id, b.id)
    end
    cambiarRelacion(self, a.id, b.id, cambio)
    if a.jugador then
        -- Declarar la guerra o lanzar misiles lo decide el jugador con comandos.
        return
    end

    local tregua = a.treguas[b.id]
    -- Un presidente no abre otra guerra si ya está en una (salvo los muy agresivos,
    -- que aguantan dos frentes).
    -- Lo barato primero: contar guerras recorre todas.
    local frentes = a.gobernante.agresividad > 0.85 and 2 or 1
    if
        d < Simulacion.alcanceGuerra
        and self:relacion(a.id, b.id) < -60
        and not (tregua and tregua > e.dia)
        and not self:guerraEntre(a.id, b.id)
        and self:numeroGuerras(a.id) < frentes
        and self:numeroGuerras(b.id) < 2
    then
        -- Lo propio lo sabe; lo del rival, solo por sus informes (sin ellos
        -- manda exploradores y aún no decide).
        local fa, fb = self:fuerza(a.id), self:fuerzaConocida(a.id, b.id)
        -- La necesidad hace al presidente más atrevido: con lo básico en crisis
        -- se arriesga contra un rival más fuerte.
        local apuro = codiciado and self:necesidades(a.id)[codiciado] or 0
        local umbral = 1.3
            - a.gobernante.agresividad * 0.5
            + a.gobernante.prudencia * 0.25
            - math.min(0.3, disputa * 0.05)
            - apuro * 0.25
        local ganas = (0.05 + a.gobernante.agresividad * 0.08)
            * (codiciado and 1 or Simulacion.necesidad.guerraSinMotivo)
        if fb and fa > fb * umbral and azar() < ganas then
            local motivo = codiciado and (NOMBRE_CODICIA[codiciado] .. ' de ' .. b.nombre)
                or 'diferencias irreconciliables'
            self:ejecutar({ tipo = 'declararGuerra', nacion = a.id, contra = b.id, motivo = motivo })
        end
    end
end

--- Sitios enemigos a los que atacar por tierra, del que más apetece al que
-- menos, cada uno con el sitio propio más cercano: { { blanco, sitio, d } }.
-- Instalaciones, banderas del borde (solo las de los bloques pegados a lo
-- suyo y en un trozo que lo toca, y con más ganas: arrancarlas quita tierra;
-- banderas.lua) y ciudades (apetecen más cuanto más
-- nivel tienen), a menos de `alcanceAtaque`. Las minas con recolectores
-- enemigos van aparte (`atacarRecolectores`).
function Diplomacia:objetivos(nid, enemiga)
    local out = {}
    local sitios = self:sitiosDe(nid)
    local function probar(blanco, factor)
        local mejor, mejorD
        for _, s in ipairs(sitios) do
            local d = distancia(s, blanco) * factor
            if d < Simulacion.alcanceAtaque and (not mejor or d < mejorD) then
                mejor, mejorD = s, d
            end
        end
        if mejor then
            out[#out + 1] = { blanco = blanco, sitio = mejor, d = mejorD, orden = #out + 1 }
        end
    end
    for _, i in ipairs(self:instalacionesDe(enemiga)) do
        if i.tipo ~= 'bandera' then
            probar(i, 1)
        end
    end
    for _, b in ipairs(self:banderasFrente(enemiga, nid)) do
        probar(b, Simulacion.bandera.atractivo)
    end
    local reglas = Simulacion.conquista
    for _, c in ipairs(self:ciudadesDe(enemiga)) do
        probar(c, reglas.distanciaCiudad * (1 - reglas.atractivoNivel * math.min(5, c.nivel or 1)))
    end
    table.sort(out, function(x, y)
        if x.d ~= y.d then
            return x.d < y.d
        end
        return x.orden < y.orden
    end)
    return out
end

--- El sitio enemigo que más apetece y el propio más cercano (ver `objetivos`).
function Diplomacia:objetivo(nid, enemiga)
    local primero = self:objetivos(nid, enemiga)[1]
    return primero and primero.blanco, primero and primero.sitio
end

--- El atacado manda refuerzos por tierra a sus instalaciones atacadas (por
-- `ejecutar`, como toda decisión NPC).
function Diplomacia:refuerzos(nid)
    local e = self.estado
    for _, i in ipairs(self:instalacionesDe(nid)) do
        if i.refuerzo and not e.grupos[i.refuerzo] then
            i.refuerzo = nil
        end
        -- Una bandera no guarda nada: se defiende con guarnición (`defenderBanderas`).
        if i.tipo ~= 'bandera' and (i.atacadaDia or 0) >= e.dia - 1 and not i.refuerzo then
            local desde = self:sitioCercano(nid, i.x, i.y, 60)
            if desde and desde.id ~= i.id then
                local gid = self:ejecutar({
                    tipo = 'enviarGrupo',
                    nacion = nid,
                    desde = desde.id,
                    mision = 'refuerzo',
                    objetivo = i.id,
                    soldados = math.floor(desde.soldados * 0.3),
                })
                if gid then
                    i.refuerzo = gid
                    self:noticia(
                        string.format(
                            '%s manda refuerzos a %s atacada',
                            e.naciones[nid].nombre,
                            i.tipo == 'base' and 'su base' or 'su instalación'
                        ),
                        e.naciones[nid].color
                    )
                end
            end
        end
    end
end

--- Lo que `n` mandaría desde `sitio` contra `blanco`: soldados,
-- lanzacohetes, su poder (el de los modelos que saldrían, como en
-- `enviarGrupo`) y esas unidades con su desglose. Se lleva parte de los
-- lanzacohetes de su ciudad o su base: más contra una ciudad, menos cuanto
-- más prudente es el presidente.
local function fuerzaAtaque(n, sitio, blanco)
    local parte = Simulacion.recuperacion.parteLanzacohetes
    local contraCiudad = esCiudad(blanco)
    local lanzacohetes = math.floor(
        (sitio.lanzacohetes or 0)
            * (contraCiudad and parte.ciudad or parte.instalacion)
            * (1 - 0.5 * n.gobernante.prudencia)
    )
    local soldados = math.floor(sitio.soldados * (contraCiudad and Simulacion.conquista.asalto.soldados or 0.35))
    -- Sin combustible no salen vehículos (enviarGrupo): no cuentan.
    if n.sinCombustible then
        lanzacohetes = 0
    end
    local unidades = Armamento.salen(sitio, lanzacohetes)
    unidades.soldados = soldados
    local poder = soldados * Simulacion.poderUnidad('soldados') + Armamento.poderDe(unidades, 'lanzacohetes')
    return soldados, lanzacohetes, poder, unidades
end

--- Acciones de un bando en un día de tensión: en el mapa no hay ataques a
-- distancia, así que solo manda ejércitos por tierra, a las minas con
-- recolectores enemigos (`atacarRecolectores`) o a un sitio enemigo.
-- Decide con sus informes (exploracion.lua): de los `candidatos` sitios que
-- más le apetecen, ataca el primero cuyo informe fresco dice que puede con él
-- (como F12: poder propio ≥ defensa × (umbralSitio − agresividad)) y para el
-- que tiene munición; a los que no conoce les manda un explorador (uno al
-- día) y los deja para otro día.
function Diplomacia:ofensiva(nid, enemiga, azar)
    local e = self.estado
    local n = e.naciones[nid]
    self:atacarRecolectores(n, enemiga)
    if grupoEnCamino(self, nid, 'atacar') or azar() >= 0.35 then
        return
    end
    local reglas = Simulacion.exploracion
    local umbral = reglas.umbralSitio - n.gobernante.agresividad
    local exploro = false
    local blanco, sitio, soldados, lanzacohetes
    -- Sitios que no conoce: les manda un explorador (uno al día) para que
    -- otro día pueda atacar. Sin esto la IA nunca ataca nada y el jugador
    -- nunca tiene una batalla 3D a la que entrar (2026-11-14).
    local desconocido
    for k, cand in ipairs(self:objetivos(nid, enemiga)) do
        if k > reglas.candidatos then
            break
        end
        local desde = self:sitioCercano(nid, cand.blanco.x, cand.blanco.y, 120)
        if desde then
            local inf
            if exploro then
                inf = self:informeVigente(nid, cand.blanco.id)
            else
                inf = self:informeFresco(nid, cand.blanco.id)
                exploro = inf == nil
            end
            if inf then
                local s, l, poder, unidades = fuerzaAtaque(n, desde, cand.blanco)
                -- Sin munición para `umbralAbasto` días no sale (diseno/economia.md, §10).
                local armado = self:alcanzaMunicion(desde, unidades, Simulacion.produccion.umbralAbasto)
                if armado and poder >= self.defensaInforme(inf) * umbral then
                    blanco, sitio, soldados, lanzacohetes = cand.blanco, desde, s, l
                    break
                end
            elseif not desconocido and not self:explorandoA(nid, cand.blanco.id) then
                -- Todavía no hay informe de este sitio: a explorarlo.
                desconocido = { desde = desde, objetivo = cand.blanco.id }
            end
        end
    end
    if not blanco then
        -- Todavía no puede atacar: manda un explorador y lo deja para otro día.
        if desconocido then
            self:explorar(nid, desconocido.desde.id, desconocido.objetivo)
        end
        return
    end
    local gid = self:ejecutar({
        tipo = 'enviarGrupo',
        nacion = nid,
        desde = sitio.id,
        mision = 'atacar',
        objetivo = blanco.id,
        soldados = soldados,
        lanzacohetes = lanzacohetes,
    })
    if gid then
        self:noticia(
            string.format(
                '%s manda un grupo a por %s de %s',
                n.nombre,
                Simulacion.nombreBlanco(self, blanco),
                e.naciones[enemiga].nombre
            ),
            n.color
        )
    end
end

function Diplomacia:altoElFuego(g, dias)
    local e = self.estado
    g.fase, g.faseHasta = 'calma', e.dia + dias
    cambiarRelacion(self, g.atacante, g.defensor, 18)
    -- Los ejércitos se detienen donde están; si se rompe la tregua, siguen.
    for _, gr in ipairs(self:gruposDeAmbas(g.atacante, g.defensor)) do
        if gr.mision == 'atacar' and not gr.detenido then
            gr.detenido, gr.detenidoDesde = true, e.dia
        end
    end
    return true
end

function Diplomacia:firmarPaz(g, concesion)
    local e = self.estado
    local a, b = e.naciones[g.atacante], e.naciones[g.defensor]
    e.guerras[claveGuerra(g.atacante, g.defensor)] = nil
    a.treguas[b.id], b.treguas[a.id] = e.dia + 90, e.dia + 90
    cambiarRelacion(self, a.id, b.id, 35)
    for _, gr in ipairs(self:gruposDeAmbas(a.id, b.id)) do
        if gr.mision == 'atacar' then
            self:volver(gr)
        end
    end
    self:noticia(string.format('%s y %s firman la paz%s', a.nombre, b.nombre, concesion or ''), { 0.7, 1, 0.8 })
    self:hecho('paz', a.id, b.id)
    return true
end

--- Conversaciones entre presidentes: según los daños y su carácter.
function Diplomacia:negociar(g, azar)
    local e = self.estado
    local a, b = e.naciones[g.atacante], e.naciones[g.defensor]
    local prudencia = (a.gobernante.prudencia + b.gobernante.prudencia) / 2
    local probabilidad = 0.02 + (a.cansancio + b.cansancio) * 0.006 + prudencia * 0.03
    if g.dias < 4 or azar() > probabilidad then
        return
    end
    local cansado, fresco = a, b
    if b.cansancio > a.cansancio then
        cansado, fresco = b, a
    end
    local tirada = azar()
    if cansado.cansancio > fresco.cansancio * 2 + 4 and g.dias > 20 and tirada < 0.5 then
        -- Paz con concesión: el más castigado cede una instalación o, si está
        -- muy agotado, una ciudad que no sea su capital.
        local concesion = ''
        local cedida
        if cansado.cansancio > 20 then
            for _, c in ipairs(self:ciudadesDe(cansado.id)) do
                if c.id ~= cansado.capital then
                    cedida = c
                end
            end
        end
        if cedida and self:cederCiudad(cedida, fresco.id) then
            -- Sus unidades, su munición, su taller y sus fábricas vuelven a la
            -- capital del que cede: nada pasa al rival.
            -- Su bloque deja de ser del que cede (salvo lo que cubra otro sitio
            -- suyo) y el que la recibe toma lo que quede libre.
            self:soltarBloque(cedida, cansado.id)
            self:reclamarBloque(cedida)
            concesion = string.format(': %s cede la ciudad de %s', cansado.nombre, cedida.nombre)
        else
            local inst = self:instalacionesDe(cansado.id, 'extraccion')[1]
            if inst then
                inst.nacion = fresco.id
                self:ensuciar()
                concesion = string.format(': %s cede %s', cansado.nombre, Simulacion.nombreInstalacion(self, inst))
            end
        end
        self:ensuciar()
        self:firmarPaz(g, concesion)
    elseif tirada < 0.8 then
        local dias = math.floor(azar(5, 30))
        self:altoElFuego(g, dias)
        self:noticia(
            string.format(
                'Los presidentes %s y %s acuerdan un alto el fuego de %d días',
                a.gobernante.nombre,
                b.gobernante.nombre,
                dias
            ),
            { 0.75, 0.9, 1 }
        )
        self:hecho('altoFuego', a.id, b.id)
    else
        self:noticia(
            string.format('Fracasan las conversaciones entre %s y %s', a.gobernante.nombre, b.gobernante.nombre),
            { 1, 0.65, 0.5 }
        )
        self:hecho('fracaso', a.id, b.id)
    end
end

function Diplomacia:guerra(g, azar)
    local e = self.estado
    g.dias = g.dias + 1
    local a, b = e.naciones[g.atacante], e.naciones[g.defensor]
    if #self:ciudadesDe(a.id) == 0 or #self:ciudadesDe(b.id) == 0 then
        e.guerras[claveGuerra(a.id, b.id)] = nil
        return
    end
    if g.fase == 'calma' then
        a.cansancio, b.cansancio = a.cansancio * 0.97, b.cansancio * 0.97
        if e.dia >= g.faseHasta then
            -- Se rompe si siguen muy enfrentados y algún presidente es agresivo.
            -- Con un jugador en la guerra, romper la calma lo decide el NPC.
            local agresivo =
                math.max(a.jugador and 0 or a.gobernante.agresividad, b.jugador and 0 or b.gobernante.agresividad)
            if self:relacion(a.id, b.id) < -45 and azar() < agresivo * 0.8 then
                g.fase = 'tension'
                for _, gr in ipairs(self:gruposDeAmbas(a.id, b.id)) do
                    gr.detenido, gr.detenidoDesde = nil, nil
                end
                self:noticia(
                    string.format('Se rompe el alto el fuego entre %s y %s', a.nombre, b.nombre),
                    { 1, 0.45, 0.35 }
                )
                -- Lo cuenta el más agresivo (el que la rompe).
                local rompe = (a.jugador and 0 or a.gobernante.agresividad) >= (b.jugador and 0 or b.gobernante.agresividad)
                self:hecho('rotura', rompe and a.id or b.id, rompe and b.id or a.id)
            else
                self:firmarPaz(g, ': la calma se consolida')
            end
        end
        return
    end
    -- Días tensos y días tranquilos: no todos los días hay ataques.
    local intensidad = azar()
    if intensidad > 0.35 then
        if not a.jugador then
            self:ofensiva(a.id, b.id, azar)
        end
        if azar() < 0.4 + b.gobernante.agresividad * 0.4 and not b.jugador then
            self:ofensiva(b.id, a.id, azar)
        end
    end
    for _, n in ipairs({ a, b }) do
        if not n.jugador then
            self:refuerzos(n.id)
        end
    end
    -- La paz y el alto el fuego con un jugador los firma él (comandos
    -- `altoElFuego` y `firmarPaz`), no la IA.
    if not a.jugador and not b.jugador then
        self:negociar(g, azar)
    end
end

local publicas = {
    'frente',
    'minasDe',
    'recursosEnDisputa',
    'diplomacia',
    'objetivos',
    'objetivo',
    'refuerzos',
    'ofensiva',
    'altoElFuego',
    'firmarPaz',
    'negociar',
    'guerra',
}

local datos = {}

--- Cuelga de la clase Simulacion las funciones y datos de este módulo.
function Diplomacia.instalar(clase)
    Simulacion = clase
    for _, nombre in ipairs(datos) do
        clase[nombre] = Diplomacia[nombre]
    end
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Diplomacia[nombre]
    end
end

return Diplomacia
