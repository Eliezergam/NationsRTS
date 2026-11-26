--- Banderas del borde (diseno/banderas-borde.md): tierra de bandera, bloques de borde, banderas guardadas, mantenimiento, guarnición y la IA que la manda.
--
-- Una bandera no es un objeto de la partida: sale de las celdas. El mundo se
-- parte en bloques de `Simulacion.bloques.bandera` x `Simulacion.bloques.bandera`
-- celdas alineados a la rejilla (bx = floor(cx / 6), los de los rebeldes).
--
--   * Tierra de bandera de N: una celda de N fuera del bloque de sus ciudades y
--     de sus campamentos terminados (`esTierraBandera`).
--   * Bloque de borde de N: uno con una celda que es tierra de bandera de N y
--     tiene un vecino por un lado que no es de N (tierra o agua sin dueño, u
--     otra nación). Cada bloque de borde tiene una bandera de N, con id
--     'f:<nación>:<bx>,<by>' (`idBandera`).
--   * Solo se GUARDA la bandera que tiene algo: en obra, con vida < 100,
--     atacada en los últimos `diasGuardada` días o con un ataque en camino. Va
--     en `e.instalaciones[id]` = { id, tipo = 'bandera', nacion, x, y,
--     progreso, salud, inicio, atacadaDia, atacadaPor }. Una bandera no guarda
--     nada más: ni tropas, ni munición, ni recursos.
--   * La guarnición son grupos del ejército con misión 'guarnicion' y
--     `objetivo` = id de la bandera (`g.bandera` = id cuando ya están en ella).
--     Siguen siendo de su ciudad. Mientras quede alguno en el bando defensor,
--     la bandera no pierde vida (`danarSitio`).
--
-- El índice de bordes (qué bloques son de borde de cada nación y cuántas
-- celdas de tierra de bandera tiene) no es estado: se rehace de las celdas al
-- cargar y se corrige cuando cambia una celda (`celdaCambiada`, desde
-- `ponerCelda`) o el bloque de un sitio (`bloqueSitioCambiado`).
--
-- API PARA LA VISTA (mundo.lua, instalaciones.lua, plantar.lua, pendon.lua) -------------------
--
--   sim:banderas(nid)            las GUARDADAS (en obra, dañadas o atacadas), como
--                                antes: { id, nacion, x, y, vida, enObra, progreso,
--                                atacada, atacadaPor }. Es lo que se dibuja de lejos.
--   sim:banderasEn(x0, y0, x1, y1, nid)
--                                todas las banderas de borde cuyo bloque cae en el
--                                rectángulo de mundo (px), guardadas o no, con el
--                                mismo formato (+ bx, by, guardada). De cerca.
--   sim:banderaPorId(id)         la bandera con ese id (guardada, o una tabla
--                                nueva con vida 100 si su bloque es de borde), o nil.
--   Simulacion.bloqueBandera(x, y)  cx0, cy0, cx1, cy1 del bloque alineado de (x, y).
--   sim:guarnicion(id)           grupos de guarnición en la bandera (en ella o en camino),
--                                y `sim:cargaGuarnicion(id)`, `sim:topeGuarnicion(nid)`.
--   sim:tropasFuera(nid)         una fila por grupo fuera, para el panel de tropas.
--   Comandos: 'guarnecer' { nacion, grupo, bandera }, 'enviarGrupo' con
--   mision = 'guarnicion' y objetivo = id de la bandera, 'regresarGrupo'
--   { nacion, grupo } (lo mismo que 'retirar') y 'regresarTodos' { nacion,
--   batalla = true para retirar también a los que pelean }.
--
-- Módulo de `mundo/simulacion.lua`: `Banderas.instalar(Simulacion)` cuelga sus
-- funciones de la clase. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')
local Armamento = require('mundo.simulacion.armamento')

local ordenadas = Ayudas.ordenadas
local hipotenusa = Ayudas.hipotenusa
local claveCelda = Ayudas.claveCelda
local VECINOS = Ayudas.VECINOS

local Banderas = {}

-- Se fijan en `instalar`: la clase, el lado de la celda (px) y el del bloque (celdas).
local Simulacion
local CELDA
local LADO

-- Desplazamiento de `claveCelda` (para sacar bx, by de la clave de un bloque).
local DESPLAZA = 1048576
local FILA = 2097152

--- bx, by de la clave de un bloque.
local function deClave(kb)
    local bx = math.floor(kb / FILA)
    return bx - DESPLAZA, kb - bx * FILA - DESPLAZA
end

--- Id de la bandera de `nid` en el bloque (bx, by).
function Banderas.idBandera(nid, bx, by)
    return 'f:' .. nid .. ':' .. bx .. ',' .. by
end

--- Nación y bloque de un id de bandera ('f:<nación>:<bx>,<by>'), o nil.
function Banderas.leerId(id)
    if type(id) ~= 'string' or id:sub(1, 2) ~= 'f:' then
        return nil
    end
    local nid, bx, by = id:match('^f:(.+):(%-?%d+),(%-?%d+)$')
    if not nid then
        return nil
    end
    return nid, tonumber(bx), tonumber(by)
end

--- Bloque alineado (bx, by) de la celda (cx, cy).
local function bloqueDeCelda(cx, cy)
    return math.floor(cx / LADO), math.floor(cy / LADO)
end

--- Bloque alineado de 6 x 6 celdas que contiene el punto (x, y): cx0, cy0, cx1, cy1.
function Banderas.bloqueBandera(x, y)
    local bx, by = bloqueDeCelda(math.floor(x / CELDA), math.floor(y / CELDA))
    return bx * LADO, by * LADO, bx * LADO + LADO - 1, by * LADO + LADO - 1
end

--- ¿Tiene la celda (cx, cy) de `nid` un vecino por un lado que no es de `nid`?
local function celdaDeBorde(mapa, nid, cx, cy)
    for _, v in ipairs(VECINOS) do
        if mapa[claveCelda(cx + v[1], cy + v[2])] ~= nid then
            return true
        end
    end
    return false
end

-- Índice de bordes ----------------------------------------------------------------------------

--- Apunta que (bx, by) es bloque de borde de `nid`.
local function ponerBorde(ib, nid, kb)
    local suyos = ib.porNacion[nid]
    if not suyos then
        suyos = {}
        ib.porNacion[nid] = suyos
    end
    if not suyos[kb] then
        suyos[kb] = true
        ib.cuenta[nid] = (ib.cuenta[nid] or 0) + 1
        ib.lista[nid] = nil
    end
    local deBloque = ib.deBloque[kb]
    if not deBloque then
        deBloque = {}
        ib.deBloque[kb] = deBloque
    end
    deBloque[nid] = true
end

--- Rehace el bloque (bx, by) en el índice: para cada nación con celdas en
-- él, ¿tiene una celda de tierra de bandera en su borde?
local function rehacerBloque(self, ib, bx, by)
    local kb = claveCelda(bx, by)
    local antes = ib.deBloque[kb]
    if antes then
        for nid in pairs(antes) do
            local suyos = ib.porNacion[nid]
            if suyos and suyos[kb] then
                suyos[kb] = nil
                ib.cuenta[nid] = ib.cuenta[nid] - 1
                ib.lista[nid] = nil
            end
        end
        ib.deBloque[kb] = nil
    end
    local mapa = ib.mapa
    local hallados
    for cy = by * LADO, by * LADO + LADO - 1 do
        for cx = bx * LADO, bx * LADO + LADO - 1 do
            local nid = mapa[claveCelda(cx, cy)]
            if
                nid
                and not (hallados and hallados[nid])
                and celdaDeBorde(mapa, nid, cx, cy)
                and not self:cubre(nid, cx, cy)
            then
                hallados = hallados or {}
                hallados[nid] = true
                ponerBorde(ib, nid, kb)
            end
        end
    end
end

--- Índice de bordes al día: se rehace entero si cambió el mapa de celdas (al
-- cargar) y, si no, solo los bloques marcados. El resultado solo depende de
-- las celdas y de los sitios, no de cuándo se pregunte.
local function indiceBordes(self)
    local mapa = self:mapaTerritorio()
    local ib = self.indiceBordes
    if not ib or ib.mapa ~= mapa then
        ib = { mapa = mapa, porNacion = {}, cuenta = {}, deBloque = {}, lista = {}, sucios = {}, tierra = {} }
        self.indiceBordes = ib
        -- Cada celda de borde que no cubre un sitio marca su bloque (el orden no
        -- cambia el resultado: es un conjunto).
        for nid, filas in pairs(self.estado.territorio) do
            for cy, tramos in pairs(filas) do
                for k = 1, #tramos, 2 do
                    for cx = tramos[k], tramos[k + 1] do
                        local kb = claveCelda(bloqueDeCelda(cx, cy))
                        local suyos = ib.porNacion[nid]
                        if
                            not (suyos and suyos[kb])
                            and celdaDeBorde(mapa, nid, cx, cy)
                            and not self:cubre(nid, cx, cy)
                        then
                            ponerBorde(ib, nid, kb)
                        end
                    end
                end
            end
        end
        return ib
    end
    if next(ib.sucios) then
        local sucios = ib.sucios
        ib.sucios = {}
        for kb in pairs(sucios) do
            rehacerBloque(self, ib, deClave(kb))
        end
    end
    return ib
end

--- Las distancias guardadas `suyas` (ver `distanciaYacimiento`) con el
-- rectángulo [x0, x1] x [y0, y1] (px) ya propio. Se compara el cuadrado (la
-- raíz no cambia el orden): la misma cifra que `distanciaTerritorio`, que es
-- la raíz del menor.
local function acercar(suyas, x0, y0, x1, y1)
    for _, v in pairs(suyas) do
        local dx = v.x < x0 and x0 - v.x or (v.x > x1 and v.x - x1 or 0)
        local dy = v.y < y0 and y0 - v.y or (v.y > y1 and v.y - y1 or 0)
        local q = dx * dx + dy * dy
        if not v.q or q < v.q then
            v.q, v.d = q, nil
        end
    end
end

--- Gancho de `ponerCelda`: la celda (cx, cy) pasó de `antes` a `nid`. Se
-- corrigen las distancias de los yacimientos, se marcan su bloque y los de
-- sus cuatro vecinas, y se corrige la cuenta de tierra de bandera de las dos
-- naciones.
function Banderas:celdaCambiada(cx, cy, antes, nid)
    -- Distancias de los yacimientos (`distanciaYacimiento`).
    local c = self.distancias
    if c and c.mapa == self.mapaCeldas then
        if antes then
            c.porNacion[antes] = nil
        end
        if nid and c.porNacion[nid] then
            if self.loteCeldas then
                -- Una bandera que se termina: se corrigen todas juntas (`terminarBandera`).
                table.insert(self.loteCeldas, cx)
                table.insert(self.loteCeldas, cy)
            else
                acercar(c.porNacion[nid], cx * CELDA, cy * CELDA, (cx + 1) * CELDA, (cy + 1) * CELDA)
            end
        end
    end
    local ib = self.indiceBordes
    if not ib or ib.mapa ~= self.mapaCeldas then
        return
    end
    ib.sucios[claveCelda(bloqueDeCelda(cx, cy))] = true
    for _, v in ipairs(VECINOS) do
        ib.sucios[claveCelda(bloqueDeCelda(cx + v[1], cy + v[2]))] = true
    end
    if antes and ib.tierra[antes] and not self:cubre(antes, cx, cy) then
        ib.tierra[antes] = ib.tierra[antes] - 1
    end
    if nid and ib.tierra[nid] and not self:cubre(nid, cx, cy) then
        ib.tierra[nid] = ib.tierra[nid] + 1
    end
end

--- Gancho de `reclamarBloque` y `soltarBloque`: un sitio (ciudad o
-- campamento) empieza o deja de cubrir [cx0, cx1] x [cy0, cy1] para `nid`.
-- Esas celdas cambian de tierra de bandera a no serlo (o al revés).
function Banderas:bloqueSitioCambiado(cx0, cy0, cx1, cy1, nid)
    local ib = self.indiceBordes
    if not ib or ib.mapa ~= self.mapaCeldas then
        return
    end
    ib.tierra[nid] = nil
    local bx0, by0 = bloqueDeCelda(cx0 - 1, cy0 - 1)
    local bx1, by1 = bloqueDeCelda(cx1 + 1, cy1 + 1)
    for by = by0, by1 do
        for bx = bx0, bx1 do
            ib.sucios[claveCelda(bx, by)] = true
        end
    end
end

--- ¿Es (bx, by) un bloque de borde de `nid`?
function Banderas:esBorde(nid, bx, by)
    local suyos = indiceBordes(self).porNacion[nid]
    return suyos ~= nil and suyos[claveCelda(bx, by)] == true
end

--- Claves de los bloques de borde de `nid`, de menor a mayor (una lista del
-- índice: no se cambia).
function Banderas:bordesDe(nid)
    local ib = indiceBordes(self)
    local l = ib.lista[nid]
    if not l then
        l = {}
        for kb in pairs(ib.porNacion[nid] or {}) do
            l[#l + 1] = kb
        end
        table.sort(l)
        ib.lista[nid] = l
    end
    return l
end

--- Cuántos bloques de borde (banderas del borde) tiene `nid`.
function Banderas:numeroBordes(nid)
    return indiceBordes(self).cuenta[nid] or 0
end

--- ¿Es (cx, cy) tierra de bandera de `nid`?
function Banderas:esTierraBandera(nid, cx, cy)
    return self:duenoCelda(cx, cy) == nid and not self:cubre(nid, cx, cy)
end

--- Celdas de tierra de bandera de `nid` (F1): las suyas menos las que cubren
-- sus ciudades y sus campamentos terminados.
function Banderas:celdasBandera(nid)
    local ib = indiceBordes(self)
    local n = ib.tierra[nid]
    if n then
        return n
    end
    local cubiertas = {}
    local suyas = 0
    local function contar(sitio)
        local cx0, cy0, cx1, cy1 = Simulacion.bloqueDe(sitio)
        if not cx0 then
            return
        end
        for cy = cy0, cy1 do
            for cx = cx0, cx1 do
                local k = claveCelda(cx, cy)
                if not cubiertas[k] then
                    cubiertas[k] = true
                    if ib.mapa[k] == nid then
                        suyas = suyas + 1
                    end
                end
            end
        end
    end
    for _, c in ipairs(self:ciudadesDe(nid)) do
        contar(c)
    end
    for _, i in ipairs(self:instalacionesDe(nid, 'campamento')) do
        contar(i)
    end
    n = self:celdasDe(nid) - suyas
    ib.tierra[nid] = n
    return n
end

-- Banderas: posición, las guardadas y las de borde ----------------------------------------------

--- Punto de la bandera de `nid` en (bx, by): la celda de tierra de bandera
-- de su borde más cercana al centro del bloque (en empate, fila menor y
-- columna menor), en su centro. Si no hay (bloque que no es de borde), el
-- centro del bloque.
function Banderas:posicionBandera(nid, bx, by)
    local mapa = self:mapaTerritorio()
    local centro = bx * LADO + LADO / 2
    local centroY = by * LADO + LADO / 2
    local mejor, mx, my
    for cy = by * LADO, by * LADO + LADO - 1 do
        for cx = bx * LADO, bx * LADO + LADO - 1 do
            if mapa[claveCelda(cx, cy)] == nid then
                local dx, dy = cx + 0.5 - centro, cy + 0.5 - centroY
                local d = dx * dx + dy * dy
                if (not mejor or d < mejor) and celdaDeBorde(mapa, nid, cx, cy) and not self:cubre(nid, cx, cy) then
                    mejor, mx, my = d, cx, cy
                end
            end
        end
    end
    if not mejor then
        return centro * CELDA, centroY * CELDA
    end
    return (mx + 0.5) * CELDA, (my + 0.5) * CELDA
end

--- La bandera `id`: la guardada o, si su bloque es de borde de su nación,
-- una tabla nueva con la vida entera (no se guarda: ver `guardarBandera`).
function Banderas:banderaPorId(id)
    local guardada = self.estado.instalaciones[id]
    if guardada then
        return guardada
    end
    local nid, bx, by = Banderas.leerId(id)
    if not nid or not self.estado.naciones[nid] or not self:esBorde(nid, bx, by) then
        return nil
    end
    local x, y = self:posicionBandera(nid, bx, by)
    return {
        id = id,
        tipo = 'bandera',
        nacion = nid,
        x = x,
        y = y,
        progreso = 1,
        salud = Simulacion.saludMaxima.bandera,
    }
end

--- Guarda la bandera `id` (una de borde) para que pueda tener estado: la
-- atacan, la dañan o está en obra. Devuelve la guardada, o nil si no existe.
function Banderas:guardarBandera(id)
    local e = self.estado
    local b = e.instalaciones[id]
    if b then
        return b
    end
    local suelta = self:banderaPorId(id)
    if not suelta then
        return nil
    end
    b = {
        id = id,
        tipo = 'bandera',
        nacion = suelta.nacion,
        x = suelta.x,
        y = suelta.y,
        progreso = 1,
        salud = suelta.salud,
        inicio = e.dia,
    }
    e.instalaciones[id] = b
    self:anotarInstalacion(b)
    return b
end

--- Lo que la vista sabe de una bandera (formato de `sim:banderas`).
local function datosBandera(b, dia, bx, by, guardada)
    local atacada = (b.atacadaDia or -math.huge) >= dia - 1
    return {
        id = b.id,
        nacion = b.nacion,
        x = b.x,
        y = b.y,
        vida = Simulacion.vidaSitio(b),
        enObra = b.progreso < 1,
        progreso = b.progreso,
        atacada = atacada,
        atacadaPor = atacada and b.atacadaPor or nil,
        bx = bx,
        by = by,
        guardada = guardada,
    }
end

--- Banderas guardadas de una nación (o de todas, sin `nid`), en orden de id:
-- las que están en obra, dañadas o atacadas. Ver la cabecera.
function Banderas:banderas(nid)
    local out = {}
    local dia = self.estado.dia
    for _, i in ipairs(self:todasInstalaciones()) do
        if i.tipo == 'bandera' and (not nid or i.nacion == nid) then
            local _, bx, by = Banderas.leerId(i.id)
            out[#out + 1] = datosBandera(i, dia, bx, by, true)
        end
    end
    return out
end

--- Todas las banderas de borde (y las guardadas) cuyo bloque cae en el
-- rectángulo de mundo [x0, x1] x [y0, y1] (px), de una nación o de todas, en
-- orden fijo (por fila de bloques, columna y nación). Ver la cabecera.
function Banderas:banderasEn(x0, y0, x1, y1, nid)
    local ib = indiceBordes(self)
    local e = self.estado
    local out = {}
    local bx0, by0 = bloqueDeCelda(math.floor(x0 / CELDA), math.floor(y0 / CELDA))
    local bx1, by1 = bloqueDeCelda(math.floor(x1 / CELDA), math.floor(y1 / CELDA))
    for by = by0, by1 do
        for bx = bx0, bx1 do
            local deBloque = ib.deBloque[claveCelda(bx, by)]
            local naciones = {}
            for otra in pairs(deBloque or {}) do
                naciones[#naciones + 1] = otra
            end
            table.sort(naciones)
            for _, otra in ipairs(naciones) do
                if not nid or otra == nid then
                    local id = Banderas.idBandera(otra, bx, by)
                    local guardada = e.instalaciones[id]
                    local b = guardada or self:banderaPorId(id)
                    out[#out + 1] = datosBandera(b, e.dia, bx, by, guardada ~= nil)
                end
            end
        end
    end
    -- Las guardadas que no son de borde (obras en un bloque nuevo).
    for _, i in ipairs(self:todasInstalaciones()) do
        if i.tipo == 'bandera' and (not nid or i.nacion == nid) then
            local otra, bx, by = Banderas.leerId(i.id)
            local dentro = bx and bx >= bx0 and bx <= bx1 and by >= by0 and by <= by1
            if dentro and not self:esBorde(otra, bx, by) then
                out[#out + 1] = datosBandera(i, e.dia, bx, by, true)
            end
        end
    end
    return out
end

--- La bandera `inst` (guardada) cae: se borra y, si estaba terminada, la
-- tierra de bandera de su nación en su bloque queda sin dueño (P2 A). Los
-- bloques que quedan expuestos tienen bandera desde ya, con vida 100 (P3 A:
-- salen de las celdas). Su guarnición vuelve a casa (P9 B). Devuelve las
-- celdas que se soltaron.
function Banderas:caerBandera(inst)
    local e = self.estado
    e.instalaciones[inst.id] = nil
    self:desanotarInstalacion(inst)
    local nid, bx, by = Banderas.leerId(inst.id)
    local sueltas = 0
    if nid and inst.progreso >= 1 then
        for cy = by * LADO, by * LADO + LADO - 1 do
            for cx = bx * LADO, bx * LADO + LADO - 1 do
                if self:esTierraBandera(nid, cx, cy) then
                    self:ponerCelda(cx, cy, nil)
                    sueltas = sueltas + 1
                end
            end
        end
        if sueltas > 0 then
            self:territorioCambiado()
        end
    end
    for _, g in ipairs(self:gruposHacia(inst.id)) do
        if g.mision == 'guarnicion' and g.nacion == inst.nacion and not g.batalla then
            self:volver(g)
        end
    end
    return sueltas
end

--- Termina la obra de la bandera `inst`: toma las celdas sin dueño de su
-- bloque (las de otra nación no se pisan) y se pone en su borde.
function Banderas:terminarBandera(inst)
    local nid, bx, by = Banderas.leerId(inst.id)
    if not nid then
        return 0
    end
    local nuevas = 0
    self.loteCeldas = {}
    for cy = by * LADO, by * LADO + LADO - 1 do
        for cx = bx * LADO, bx * LADO + LADO - 1 do
            if self:duenoCelda(cx, cy) == nil and self:ponerCelda(cx, cy, nid) then
                nuevas = nuevas + 1
            end
        end
    end
    -- Las distancias de los yacimientos: con el bloque entero si ya es todo
    -- suyo (el mismo número que celda a celda); si no, celda a celda.
    local lote = self.loteCeldas
    self.loteCeldas = nil
    local c = self.distancias
    local suyas = #lote > 0 and c and c.mapa == self.mapaCeldas and c.porNacion[nid]
    if suyas then
        local entero = true
        for cy = by * LADO, by * LADO + LADO - 1 do
            for cx = bx * LADO, bx * LADO + LADO - 1 do
                entero = entero and self:duenoCelda(cx, cy) == nid
            end
        end
        if entero then
            acercar(suyas, bx * LADO * CELDA, by * LADO * CELDA, (bx + 1) * LADO * CELDA, (by + 1) * LADO * CELDA)
        else
            for k = 1, #lote, 2 do
                acercar(suyas, lote[k] * CELDA, lote[k + 1] * CELDA, (lote[k] + 1) * CELDA, (lote[k + 1] + 1) * CELDA)
            end
        end
    end
    if nuevas > 0 then
        self:territorioCambiado()
    end
    if self:esBorde(nid, bx, by) then
        inst.x, inst.y = self:posicionBandera(nid, bx, by)
    end
    return nuevas
end

--- ¿Va algún grupo a atacar la bandera `id`?
local function atacantesEnCamino(self, id)
    for _, g in ipairs(self:gruposHacia(id)) do
        if g.mision == 'atacar' then
            return true
        end
    end
    return false
end

--- Revisión de fin de día (después de las batallas):
--   * una bandera guardada y terminada que ya no es de borde (el dueño plantó
--     delante) deja de existir; si la atacaban, la batalla acaba sin victoria
--     y todos vuelven (3.3.4);
--   * una guardada que ya está normal (vida 100, terminada, sin ataque en
--     `diasGuardada` días, sin batalla ni ataque en camino) deja de guardarse;
--   * la guarnición de una bandera que ya no es de borde vuelve a casa (P9 B).
function Banderas:revisarBanderas()
    local e = self.estado
    local reglas = Simulacion.bandera
    local enBatalla = {}
    for _, bid in ipairs(ordenadas(e.batallas)) do
        local b = e.batallas[bid]
        if b.lugar.tipo == 'sitio' then
            enBatalla[b.lugar.id] = b
        end
    end
    -- Las guardadas, nación a nación (una copia: se borran mientras se recorren).
    local guardadas = {}
    for _, nid in ipairs(ordenadas(e.naciones)) do
        for _, i in ipairs(self:instalacionesDe(nid, 'bandera')) do
            if e.instalaciones[i.id] == i then
                guardadas[#guardadas + 1] = i
            end
        end
    end
    local quitadas = {}
    for _, i in ipairs(guardadas) do
        local nid, bx, by = Banderas.leerId(i.id)
        if nid and i.progreso >= 1 then
            local b = enBatalla[i.id]
            if not self:esBorde(nid, bx, by) then
                if b then
                    e.batallas[b.id] = nil
                    for _, lado in ipairs(Ayudas.LADOS) do
                        for _, g in ipairs(self:gruposBando(b, lado)) do
                            g.batalla = nil
                            self:volver(g)
                        end
                    end
                end
                e.instalaciones[i.id] = nil
                quitadas[#quitadas + 1] = i
            elseif
                not b
                and i.salud >= Simulacion.saludMaxima.bandera
                and (i.atacadaDia or -math.huge) < e.dia - reglas.diasGuardada
                and not atacantesEnCamino(self, i.id)
            then
                e.instalaciones[i.id] = nil
                quitadas[#quitadas + 1] = i
            end
        end
    end
    self:desanotarInstalaciones(quitadas)
    for _, g in ipairs(self:gruposConMision('guarnicion')) do
        if not g.batalla then
            local nid, bx, by = Banderas.leerId(g.objetivo)
            if not nid or nid ~= g.nacion or not self:esBorde(nid, bx, by) then
                self:volver(g)
            end
        end
    end
end

-- Mantenimiento (3.6, F1 y F2) ---------------------------------------------------------------------

--- Paga el mantenimiento de la tierra de bandera de `n` (F1). Si no alcanza,
-- paga lo que haya y los k bloques de borde más lejanos de su capital (F2;
-- en empate, el de clave de bloque menor) pierden `desabasto` de vida; a 0
-- caen, sin atacante.
function Banderas:mantenerBanderas(n)
    local reglas = Simulacion.bandera
    local porCelda = reglas.mantenimiento / (LADO * LADO)
    local gasto = porCelda * self:celdasBandera(n.id)
    if gasto <= 0 then
        return
    end
    local hay = math.max(0, Simulacion.disponible(n, 'dinero'))
    if hay >= gasto then
        Simulacion.gastar(n, 'dinero', gasto)
        return
    end
    if hay > 0 then
        Simulacion.gastar(n, 'dinero', hay)
    end
    local k = math.ceil((gasto - hay) / reglas.mantenimiento - 1e-9)
    local e = self.estado
    local capital = e.ciudades[n.capital] or self:ciudadesDe(n.id)[1]
    local cola = {}
    for _, kb in ipairs(self:bordesDe(n.id)) do
        local bx, by = deClave(kb)
        local x, y = (bx * LADO + LADO / 2) * CELDA, (by * LADO + LADO / 2) * CELDA
        cola[#cola + 1] = {
            clave = kb,
            bx = bx,
            by = by,
            distancia = capital and hipotenusa(x - capital.x, y - capital.y) or 0,
        }
    end
    -- De la más lejana a la más cercana; en empate, la de clave de bloque menor.
    table.sort(cola, function(a, b)
        if a.distancia ~= b.distancia then
            return a.distancia > b.distancia
        end
        return a.clave < b.clave
    end)
    for j = 1, math.min(k, #cola) do
        local b = self:guardarBandera(Banderas.idBandera(n.id, cola[j].bx, cola[j].by))
        if b then
            b.salud = b.salud - reglas.desabasto
            if b.salud <= 0 then
                self:noticia(
                    string.format('Una bandera de %s se pierde por falta de mantenimiento', n.nombre),
                    { 1, 0.7, 0.4 }
                )
                self:caerBandera(b)
            end
        end
    end
end

-- Distancias al territorio (F12) ---------------------------------------------------------------------

--- Distancia (px) de (x, y) a la celda más cercana de `nid` (0 si está
-- dentro) y su cuadrado; nil si no tiene celdas. Mira las filas de tramos
-- desde la del punto hacia fuera y para cuando ninguna fila más lejana puede
-- estar más cerca.
function Banderas:distanciaTerritorio(nid, x, y)
    local filas = self.estado.territorio[nid]
    if not filas then
        return nil
    end
    -- Primera y última fila de la nación, guardadas mientras no cambie ninguna celda.
    local version = self.estado.versionTerritorio
    local rangos = self.rangosFilas
    if not rangos or rangos.version ~= version then
        rangos = { version = version }
        self.rangosFilas = rangos
    end
    local rango = rangos[nid]
    if not rango then
        rango = {}
        for cy in pairs(filas) do
            rango[1] = math.min(rango[1] or cy, cy)
            rango[2] = math.max(rango[2] or cy, cy)
        end
        rangos[nid] = rango
    end
    local primera, ultima = rango[1], rango[2]
    if not primera then
        return nil
    end
    local fila = math.floor(y / CELDA)
    local mejor -- el cuadrado de la menor distancia
    local function mirar(cy)
        local tramos = filas[cy]
        if not tramos then
            return
        end
        local y0, y1 = cy * CELDA, (cy + 1) * CELDA
        local dy = y < y0 and y0 - y or (y > y1 and y - y1 or 0)
        for k = 1, #tramos, 2 do
            local x0, x1 = tramos[k] * CELDA, (tramos[k + 1] + 1) * CELDA
            local dx = x < x0 and x0 - x or (x > x1 and x - x1 or 0)
            local q = dx * dx + dy * dy
            if not mejor or q < mejor then
                mejor = q
            end
        end
    end
    local r = 0
    while fila - r >= primera or fila + r <= ultima do
        -- Una fila a r de la del punto está como poco a (r - 1) filas enteras.
        local cerca = (r - 1) * CELDA
        if mejor and r > 1 and cerca * cerca > mejor then
            break
        end
        mirar(fila - r)
        if r > 0 then
            mirar(fila + r)
        end
        r = r + 1
    end
    return mejor and math.sqrt(mejor), mejor
end

--- Distancia (px) del yacimiento `d` al territorio de `nid`
-- (`distanciaTerritorio`), guardada fuera del estado: cuando `nid` gana una
-- celda solo puede bajar y se corrige (`celdaCambiada`); cuando pierde una,
-- se vuelven a medir todas las suyas. Da el mismo número que medirla.
function Banderas:distanciaYacimiento(nid, d)
    local mapa = self:mapaTerritorio()
    local c = self.distancias
    if not c or c.mapa ~= mapa then
        c = { mapa = mapa, porNacion = {} }
        self.distancias = c
    end
    local suyas = c.porNacion[nid]
    if not suyas then
        suyas = {}
        c.porNacion[nid] = suyas
    end
    local v = suyas[d.id]
    if not v then
        local dist, q = self:distanciaTerritorio(nid, d.x, d.y)
        v = { x = d.x, y = d.y, d = dist, q = q }
        suyas[d.id] = v
    elseif not v.d and v.q then
        v.d = math.sqrt(v.q)
    end
    return v.d
end

-- Objetivos de la IA y blancos del jugador --------------------------------------------------------

--- Banderas de `enemiga` que puede atacar `nid` (objetivos de la IA): las de
-- los bloques de borde con una celda de tierra de bandera pegada por un lado
-- a una celda de `nid`, y en un trozo que toca lo suyo, en orden de bloque.
function Banderas:banderasFrente(enemiga, nid)
    local out = {}
    if not self:hayFrontera(enemiga, nid) then
        return out
    end
    local mapa = self:mapaTerritorio()
    for _, kb in ipairs(self:bordesDe(enemiga)) do
        local bx, by = deClave(kb)
        local toca = false
        for cy = by * LADO, by * LADO + LADO - 1 do
            for cx = bx * LADO, bx * LADO + LADO - 1 do
                if not toca and mapa[claveCelda(cx, cy)] == enemiga then
                    for _, v in ipairs(VECINOS) do
                        if mapa[claveCelda(cx + v[1], cy + v[2])] == nid then
                            toca = true
                        end
                    end
                end
            end
        end
        if toca then
            local b = self:banderaPorId(Banderas.idBandera(enemiga, bx, by))
            if b and self:tocaTrozo(nid, b) then
                out[#out + 1] = b
            end
        end
    end
    return out
end

--- El blanco de un punto: la bandera de borde del bloque de (x, y), si su
-- mástil está a menos de `tolerancia` px. Para `blancoEn`.
function Banderas:banderaCerca(x, y, tolerancia)
    local cx, cy = math.floor(x / CELDA), math.floor(y / CELDA)
    local nid = self:duenoCelda(cx, cy)
    if not nid then
        return nil
    end
    local bx, by = bloqueDeCelda(cx, cy)
    local b = self:banderaPorId(Banderas.idBandera(nid, bx, by))
    if b and hipotenusa(b.x - x, b.y - y) <= tolerancia then
        return b
    end
    return nil
end

-- Migración de la versión 25 (banderas instalación) ---------------------------------------------

--- Grupo nuevo de `nid` con lo que tenía la bandera vieja `i` (sus soldados y
-- vehículos, con sus modelos, y su munición): de guarnición en la bandera
-- `id` si su bloque es de borde; si no, de vuelta a `casa`. No se crea ni se
-- destruye nada.
local function tropaDeBandera(migra, i, casa, id)
    local e = migra.estado
    local gid = e.siguienteGrupo
    e.siguienteGrupo = gid + 1
    local g = {
        id = gid,
        nacion = i.nacion,
        desde = casa.id,
        origen = casa.id,
        x = i.x,
        y = i.y,
        antesX = i.x,
        antesY = i.y,
        recorrido = 0,
        antesRecorrido = 0,
        soldados = i.soldados or 0,
        -- Los tanques de una partida vieja pasan tal cual: la migración a la
        -- v30 (guardado.lua) los devuelve en dinero.
        tanques = i.tanques,
        tanquesPor = i.tanquesPor,
        lanzacohetes = 0,
        heridos = Ayudas.tropasVacias(),
        resto = Ayudas.tropasVacias(),
        municion = i.municion,
    }
    i.tanques, i.tanquesPor = nil, nil
    Armamento.meterPor(g, 'lanzacohetes', Armamento.vaciar(i, 'lanzacohetes'))
    local b = id and migra:banderaDeBorde(i.nacion, id)
    if b then
        g.mision, g.objetivo, g.bandera, g.alerta = 'guarnicion', id, id, e.dia
        g.x, g.y, g.antesX, g.antesY = b.x, b.y, b.x, b.y
        g.destinoX, g.destinoY = b.x, b.y
        g.ruta = { b.x, b.y, b.x, b.y }
    else
        g.mision = 'regreso'
        g.destinoX, g.destinoY = casa.x, casa.y
        g.ruta = migra:trazar(i.x, i.y, casa.x, casa.y) or { i.x, i.y, casa.x, casa.y }
    end
    g.largo = Simulacion.largoRuta(g.ruta)
    g.vidaMax = Simulacion.vidaGrupo(g)
    e.grupos[gid] = g
end

--- Sube las banderas de una partida de la versión 25 (diseno/banderas-borde.md,
-- 5, «Partida de la versión 25»): se borran todas las banderas instalación
-- (sus celdas no cambian); las que estaban en obra siguen en obra en el
-- bloque alineado que contiene su mástil; las dañadas o atacadas pasan su
-- vida (la menor) a los bloques de borde que tocaba su bloque de antes; lo
-- que guardaban (soldados, vehículos, munición) pasa a un grupo (de
-- guarnición si su bloque es de borde; si no, de vuelta a casa); los ataques
-- y las batallas contra ellas siguen contra la bandera del borde de su bloque.
function Banderas.migrar(estado)
    local viejas = {}
    for _, id in ipairs(ordenadas(estado.instalaciones)) do
        local i = estado.instalaciones[id]
        -- Las que ya son del bloque ('f:<nación>:<bx>,<by>') se quedan como están.
        local nid = Banderas.leerId(id)
        if i.tipo == 'bandera' and not (nid and estado.naciones[nid]) then
            viejas[#viejas + 1] = i
            estado.instalaciones[id] = nil
        end
    end
    if #viejas == 0 then
        return
    end
    local migra = setmetatable({ estado = estado, cambios = 0, eventos = {} }, Simulacion)
    local maxima = Simulacion.saludMaxima.bandera
    local nuevas = {} -- id viejo -> id de la bandera de su bloque
    for _, i in ipairs(viejas) do
        local nid = i.nacion
        if estado.naciones[nid] then
            local bx, by = bloqueDeCelda(math.floor(i.x / CELDA), math.floor(i.y / CELDA))
            local id = Banderas.idBandera(nid, bx, by)
            nuevas[i.id] = id
            if i.progreso < 1 then
                local b = estado.instalaciones[id]
                if not b then
                    b = {
                        id = id,
                        tipo = 'bandera',
                        nacion = nid,
                        x = (bx * LADO + LADO / 2) * CELDA,
                        y = (by * LADO + LADO / 2) * CELDA,
                        progreso = i.progreso,
                        salud = i.salud,
                        inicio = i.inicio,
                    }
                    estado.instalaciones[id] = b
                    migra:ensuciar()
                end
                b.progreso = math.min(b.progreso, i.progreso)
                b.salud = math.min(b.salud, i.salud)
            elseif i.salud < maxima or i.atacadaDia then
                local cx0, cy0, cx1, cy1 = Simulacion.bloque(i.x, i.y, LADO)
                local bx0, by0 = bloqueDeCelda(cx0, cy0)
                local bx1, by1 = bloqueDeCelda(cx1, cy1)
                for yb = by0, by1 do
                    for xb = bx0, bx1 do
                        local otro = Banderas.idBandera(nid, xb, yb)
                        local b = migra:esBorde(nid, xb, yb) and migra:guardarBandera(otro)
                        if b then
                            b.salud = math.min(b.salud, i.salud)
                            if i.atacadaDia and (b.atacadaDia or -math.huge) <= i.atacadaDia then
                                b.atacadaDia, b.atacadaPor = i.atacadaDia, i.atacadaPor
                            end
                        end
                    end
                end
            end
            -- Lo que guardaba: a un grupo; las defensas fijas, a su ciudad.
            local casa = migra:ciudadDuena(nid, i.x, i.y)
            if casa then
                casa.interceptores = (casa.interceptores or 0) + (i.interceptores or 0)
                casa.aviones = (casa.aviones or 0) + (i.aviones or 0)
                if (i.misiles or 0) > 0 then
                    casa.municion = casa.municion or Simulacion.municionVacia()
                    casa.municion.misiles = casa.municion.misiles + i.misiles
                end
                if (i.soldados or 0) + (i.tanques or 0) + (i.lanzacohetes or 0) > 0 then
                    tropaDeBandera(migra, i, casa, id)
                elseif i.municion then
                    migra:devolverMunicion(i, casa)
                end
            end
        end
    end
    -- Los ataques y las batallas contra una bandera vieja siguen contra la de su bloque.
    for _, gid in ipairs(ordenadas(estado.grupos)) do
        local g = estado.grupos[gid]
        local id = g.objetivo ~= nil and nuevas[g.objetivo]
        if id and g.mision == 'atacar' and migra:guardarBandera(id) then
            g.objetivo = id
        end
    end
    for _, bid in ipairs(ordenadas(estado.batallas)) do
        local b = estado.batallas[bid]
        local id = nuevas[b.lugar.id]
        if b.lugar.tipo == 'sitio' and id and migra:guardarBandera(id) then
            b.lugar.id = id
            if b.bandos.defensor.sitio then
                b.bandos.defensor.sitio = id
            end
        end
    end
    for _, xid in ipairs(ordenadas(estado.exploradores or {})) do
        local x = estado.exploradores[xid]
        if nuevas[x.objetivo] then
            x.objetivo = nuevas[x.objetivo]
        end
    end
end

local publicas = {
    'celdaCambiada',
    'bloqueSitioCambiado',
    'esBorde',
    'bordesDe',
    'numeroBordes',
    'esTierraBandera',
    'celdasBandera',
    'posicionBandera',
    'banderaPorId',
    'guardarBandera',
    'banderas',
    'banderasEn',
    'caerBandera',
    'terminarBandera',
    'revisarBanderas',
    'mantenerBanderas',
    'distanciaTerritorio',
    'distanciaYacimiento',
    'banderasFrente',
    'banderaCerca',
}

--- Cuelga de la clase Simulacion las funciones de las banderas del borde.
function Banderas.instalar(clase)
    Simulacion = clase
    CELDA = clase.celda
    LADO = clase.bloques.bandera
    clase.idBandera = Banderas.idBandera
    clase.leerIdBandera = Banderas.leerId
    clase.bloqueBandera = Banderas.bloqueBandera
    clase.migrarBanderas = Banderas.migrar
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Banderas[nombre]
    end
end

return Banderas
