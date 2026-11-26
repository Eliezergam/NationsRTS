--- Exploradores e informes: lo único que una nación sabe del poder de sus enemigos.
--
-- El poder y el arsenal de lo ajeno (ciudades, bases, campamentos, banderas y
-- ejércitos en el mapa) no se conocen: hay que mandar un explorador
-- (`ejecutar{ tipo = 'explorar', nacion, desde, objetivo }`). Paga
-- `exploracion.coste` de dinero al salir, nunca lo interceptan y llega en
-- `ceil(distancia / exploracion.velocidad)` días (al menos uno). Al llegar,
-- al final de ese día, deja un INFORME fechado con lo que había allí: el
-- poder, las tropas por tipo, las defensas y la vida. El informe no se
-- actualiza solo: envejece hasta que llega otro explorador. El de un
-- ejército se pierde si el grupo se disuelve; el de un sitio, si el sitio
-- cae o pasa a ser propio.
--
-- Los NPC siguen la misma regla: deciden con sus informes y mandan
-- exploradores con la misma acción (`informeFresco`, desde diplomacia.lua y
-- recoleccionIA.lua).
--
-- Estado (solo datos):
--   e.exploradores[id] = { id, nacion, desde, objetivo, salioDia, llegaDia }
--   e.siguienteExplorador
--   e.informes[nid] = { sitios = { [idSitio] = informe }, grupos = { [idGrupo] = informe } }
--
-- Módulo de `mundo/simulacion.lua`: `Exploracion.instalar(Simulacion)` cuelga sus
-- funciones y `Simulacion.exploracion` (las reglas) de la clase. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')
local Armamento = require('mundo.simulacion.armamento')

local ordenadas = Ayudas.ordenadas
local distancia = Ayudas.distancia
local esCiudad = Ayudas.esCiudad

local Exploracion = {}

-- Se fija en `instalar`: la clase.
local Simulacion

--- Reglas de la exploración.
Exploracion.reglas = {
    coste = 20, -- dinero que cuesta cada explorador (lo mismo que una bandera)
    velocidad = 24000, -- px por día: unas 2,7 veces un ejército (`velocidadEjercito`)
    -- IA de los NPC: un informe más viejo que esto ya no le sirve para decidir.
    caducidadSitio = 30, -- días
    caducidadGrupo = 10, -- días: un ejército cambia mucho antes que un sitio
    -- Al declarar una guerra: lo que no ven sus informes (los ejércitos del
    -- rival en el mapa) lo estima a ciegas como esta parte de lo que sí ven.
    margenCiego = 0.2,
    -- Poder que el presidente supone, a ciegas, a un grupo de recolectores del
    -- que no tiene informe: por lo alto (la mitad de ellos no llega a 150).
    ciegoRecolector = 500,
    -- Poder que el presidente supone, a ciegas, a un ejército enemigo del que
    -- no tiene informe al decidir si se defiende (retirar recolectores,
    -- defender una bandera): por lo alto, como un bando mediano de las
    -- batallas medidas con la economía cerrada (unos 500 soldados y 7 vehículos).
    ciegoEjercito = 3000,
    candidatos = 3,
    -- Ataca un sitio si el poder que manda ≥ su defensa según el informe ×
    -- (umbralSitio − agresividad), como F12 con los recolectores.
    umbralSitio = 1.6, -- sitios enemigos que mira el presidente cada día de ofensiva (`ofensiva`)
}

local DEFENSAS = { 'misiles', 'interceptores', 'aviones', 'baterias', 'fortificacion' }

--- Lo que se explora con ese id: un grupo (id numérico) o un sitio (ciudad o
-- instalación), y si es un grupo.
local function cosaExplorada(self, objetivo)
    if type(objetivo) == 'number' then
        return self.estado.grupos[objetivo], true
    end
    return self:sitio(objetivo), false
end

--- Informes de `nid` (se crean al llegar el primero).
local function informesDe(e, nid, crear)
    local t = e.informes[nid]
    if not t and crear then
        t = { sitios = {}, grupos = {} }
        e.informes[nid] = t
    end
    return t
end

--- Foto de `s` (un sitio o un grupo) el día de hoy.
local function foto(self, s, esGrupo)
    local e = self.estado
    local inf = {
        dia = e.dia,
        nacion = s.nacion,
        x = s.x,
        y = s.y,
        tropas = {
            soldados = s.soldados or 0,
            lanzacohetes = s.lanzacohetes or 0,
        },
        defensas = {},
    }
    -- Los modelos que vio (una copia).
    for _, tipo in ipairs(Armamento.TIPOS) do
        if inf.tropas[tipo] > 0 then
            inf.tropas[Armamento.POR[tipo]] = Armamento.porModelo(s, tipo)
        end
    end
    if esGrupo then
        inf.tipo = 'grupo'
        inf.poder = Simulacion.poder(s)
        inf.vida = Simulacion.vidaGrupo(s)
        inf.vidaMax = s.vidaMax or inf.vida
        return inf
    end
    for _, campo in ipairs(DEFENSAS) do
        inf.defensas[campo] = s[campo] or 0
    end
    inf.poder = Simulacion.poderSitio(s)
    if esCiudad(s) then
        inf.tipo = 'ciudad'
        inf.vida = s.vida or Simulacion.vidaCiudad.maxima
        inf.vidaMax = Simulacion.vidaCiudad.maxima
    else
        inf.tipo = s.tipo
        inf.vida = s.salud or 0
        inf.vidaMax = Simulacion.saludMaxima[s.tipo] or inf.vida
    end
    return inf
end

--- ¿Tiene `nid` un explorador en camino hacia `objetivo`? (sin orden: solo sí o no)
function Exploracion:explorandoA(nid, objetivo)
    for _, x in pairs(self.estado.exploradores) do
        if x.nacion == nid and x.objetivo == objetivo then
            return true
        end
    end
    return false
end

--- Manda un explorador de `nid` desde su sitio `desdeId` hacia `objetivo`
-- (id de un sitio ajeno o de un grupo ajeno). Paga al salir. Devuelve el id
-- del explorador, o false y el motivo: 'nacion', 'origen', 'objetivo',
-- 'propio', 'enCamino' (ya va uno suyo) o 'coste'.
function Exploracion:explorar(nid, desdeId, objetivo)
    local e = self.estado
    local n = e.naciones[nid]
    if not n then
        return false, 'nacion'
    end
    local desde = desdeId and self:sitio(desdeId)
    if not desde or desde.nacion ~= nid then
        return false, 'origen'
    end
    local cosa = objetivo and cosaExplorada(self, objetivo)
    if not cosa then
        return false, 'objetivo'
    end
    if cosa.nacion == nid then
        return false, 'propio'
    end
    if self:explorandoA(nid, objetivo) then
        return false, 'enCamino'
    end
    local reglas = Simulacion.exploracion
    if not Simulacion.pagar(n, { dinero = reglas.coste }) then
        return false, 'coste'
    end
    local id = e.siguienteExplorador
    e.siguienteExplorador = id + 1
    e.exploradores[id] = {
        id = id,
        nacion = nid,
        desde = desdeId,
        objetivo = objetivo,
        salioDia = e.dia,
        llegaDia = e.dia + math.max(1, math.ceil(distancia(desde, cosa) / reglas.velocidad)),
    }
    return id
end

--- Llegan los exploradores de hoy (en orden de id): cada uno deja su informe
-- con lo que hay ahora en su objetivo. Si el objetivo ya no existe (el sitio
-- cayó, el grupo se disolvió) vuelve sin nada y se borra lo que se sabía.
function Exploracion:llegadaExploradores()
    local e = self.estado
    for _, id in ipairs(ordenadas(e.exploradores)) do
        local x = e.exploradores[id]
        if x.llegaDia <= e.dia then
            e.exploradores[id] = nil
            local cosa, esGrupo = cosaExplorada(self, x.objetivo)
            local suyos = informesDe(e, x.nacion, true)
            local tabla = type(x.objetivo) == 'number' and suyos.grupos or suyos.sitios
            if cosa and cosa.nacion ~= x.nacion then
                tabla[x.objetivo] = foto(self, cosa, esGrupo)
            else
                tabla[x.objetivo] = nil
            end
        end
    end
end

--- Borra los informes que ya no sirven: de grupos disueltos y de sitios que
-- cayeron o que ahora son de quien los tenía. Una vez al día.
function Exploracion:olvidarInformes()
    local e = self.estado
    for _, nid in ipairs(ordenadas(e.informes)) do
        local suyos = e.informes[nid]
        for _, gid in ipairs(ordenadas(suyos.grupos)) do
            if not e.grupos[gid] then
                suyos.grupos[gid] = nil
            end
        end
        for _, sid in ipairs(ordenadas(suyos.sitios)) do
            local s = self:sitio(sid)
            if not s or s.nacion == nid then
                suyos.sitios[sid] = nil
            end
        end
    end
end

--- El informe de `nid` sobre `objetivo` (id de sitio o de grupo), o nil si no
-- tiene. Es la tabla guardada: la vista la lee y no la cambia.
-- { dia, tipo, nacion, x, y, poder, tropas = { soldados, lanzacohetes },
--   defensas = { misiles, interceptores, aviones, baterias, fortificacion }, vida, vidaMax }
-- (los grupos traen `defensas` vacía).
function Exploracion:informe(nid, objetivo)
    local suyos = informesDe(self.estado, nid, false)
    if not suyos or objetivo == nil then
        return nil
    end
    local cosa = cosaExplorada(self, objetivo)
    if not cosa or cosa.nacion == nid then
        return nil
    end
    if type(objetivo) == 'number' then
        return suyos.grupos[objetivo]
    end
    return suyos.sitios[objetivo]
end

--- ¿Conoce `nid` el poder de `objetivo`? Lo propio, siempre; lo ajeno, si
-- tiene un informe (de cualquier día).
function Exploracion:conoce(nid, objetivo)
    local cosa = objetivo ~= nil and cosaExplorada(self, objetivo)
    if not cosa then
        return false
    end
    return cosa.nacion == nid or self:informe(nid, objetivo) ~= nil
end

--- Exploradores de `nid` en camino, en orden de id:
-- { { id, objetivo, desde, salioDia, llegaDia } }.
function Exploracion:exploradoresEnCamino(nid)
    local e = self.estado
    local out = {}
    for _, id in ipairs(ordenadas(e.exploradores)) do
        local x = e.exploradores[id]
        if x.nacion == nid then
            out[#out + 1] = {
                id = x.id,
                objetivo = x.objetivo,
                desde = x.desde,
                salioDia = x.salioDia,
                llegaDia = x.llegaDia,
            }
        end
    end
    return out
end

-- IA de los NPC ------------------------------------------------------------------------------

--- Informe de `nid` sobre `objetivo` que aún le sirve para decidir (no más
-- viejo que su caducidad), o nil. No manda a nadie.
function Exploracion:informeVigente(nid, objetivo)
    local reglas = Simulacion.exploracion
    local inf = self:informe(nid, objetivo)
    local caducidad = type(objetivo) == 'number' and reglas.caducidadGrupo or reglas.caducidadSitio
    if inf and self.estado.dia - inf.dia <= caducidad then
        return inf
    end
    return nil
end

--- Como `informeVigente`, pero sin él manda un explorador (con la acción
-- `explorar`, desde su sitio más cercano) si no va ya uno.
function Exploracion:informeFresco(nid, objetivo)
    local inf = self:informeVigente(nid, objetivo)
    if inf then
        return inf
    end
    if self:explorandoA(nid, objetivo) then
        return nil
    end
    local cosa = cosaExplorada(self, objetivo)
    local desde, desdeD
    for _, s in ipairs(self:sitiosDe(nid)) do
        local d = distancia(s, cosa)
        if not desde or d < desdeD then
            desde, desdeD = s, d
        end
    end
    if desde then
        self:ejecutar({ tipo = 'explorar', nacion = nid, desde = desde.id, objetivo = objetivo })
    end
    return nil
end

--- Fuerza de un informe con la misma cuenta que `fuerzaDe` (tropas y
-- defensas fijas): la de aquel día.
function Exploracion.fuerzaInforme(inf)
    local d = inf.defensas
    return Simulacion.fuerzaDe({
        soldados = inf.tropas.soldados,
        misiles = d.misiles,
        interceptores = d.interceptores,
        aviones = d.aviones,
    })
end

--- Poder con el que defiende un sitio según el informe: sus tropas, más las
-- baterías de una ciudad (con el peso que tienen en combate) y × el efecto
-- de su vida; una instalación, × (1 + fortificación).
function Exploracion.defensaInforme(inf)
    local d = inf.defensas
    local poder = inf.poder
    if inf.tipo == 'ciudad' then
        poder = poder + (d.baterias or 0) * Simulacion.vidaCiudad.pesos.baterias * Simulacion.escalaPoder
        return poder * Simulacion.efectoVida(inf.vida)
    end
    return poder * (1 + (d.fortificacion or 0))
end

--- Fuerza de la nación `b` como la conoce `a`, para decidir una guerra: la
-- tecnología (sale en las noticias) y lo que dicen sus informes de las
-- ciudades y bases de `b`, más `margenCiego` por lo que no ven (los
-- ejércitos en el mapa). Si le falta un informe fresco de alguno de esos
-- sitios, manda exploradores y devuelve nil: aún no decide.
function Exploracion:fuerzaConocida(a, b)
    local total = Simulacion.tecnologiasQueCuentan(self.estado.naciones[b]) * 12
    local completa = true
    for _, s in ipairs(self:sitiosDe(b)) do
        local inf = self:informeFresco(a, s.id)
        if inf then
            total = total + Exploracion.fuerzaInforme(inf)
        else
            completa = false
        end
    end
    if not completa then
        return nil
    end
    return total * (1 + Simulacion.exploracion.margenCiego)
end

local publicas = {
    'explorandoA',
    'explorar',
    'llegadaExploradores',
    'olvidarInformes',
    'informe',
    'conoce',
    'exploradoresEnCamino',
    'informeVigente',
    'informeFresco',
    'fuerzaInforme',
    'defensaInforme',
    'fuerzaConocida',
}

--- Cuelga de la clase Simulacion las funciones y `Simulacion.exploracion` (las reglas).
function Exploracion.instalar(clase)
    Simulacion = clase
    clase.exploracion = Exploracion.reglas
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Exploracion[nombre]
    end
end

return Exploracion
