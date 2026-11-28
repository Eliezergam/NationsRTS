-- Dónde crece cada cosa en la batalla (ESTILO-TERRENO.md §4). Todo sale de la
-- semilla por hash, en este orden:
--   0  plantas del mapa como anclas, en su sitio exacto (Plantas.enTrozo)
--   1  bosque y árboles sueltos según la máscara de bosque
--   3  arbustos en la orla del bosque
--   6  rocas en lo empinado, afloramientos en las crestas y peñas sueltas
-- Las matas de hierba y las flores (capas 4 y 5) no se generan al entrar:
-- `hierbaDeBaldosa` las da por baldosas de 200 m cuando la cámara se acerca.
--
-- Cada copia es una tabla con la especie, la variante, la posición en px, su
-- matriz (giro por escala, en columnas, en ejes del juego), el tono y un
-- número de hash para aclarar de lejos.

local Ruido = require('mundo.ruido')
local Plantas = require('mundo.plantas')
local Terreno = require('mundo.terreno')
local Vegetacion = require('batalla.vegetacion')
local ColorTerreno = require('batalla.color_terreno')

local Colocacion = {}
Colocacion.__index = Colocacion

local M = 10
local DOS_PI = math.pi * 2
local suave = ColorTerreno.suave

Colocacion.baldosa = 2000 -- px de lado de una baldosa (200 m)
Colocacion.celda = 40 -- px de la rejilla de choques (4 m)

-- Radio de ocupación de cada árbol (m).
local RADIO_ARBOL = { Pino = 4.0, Abeto = 5.0, AbetoNevado = 5.0, Roble = 7.0, Alamo = 3.6, Abedul = 3.8 }
-- Altura de la copa (m) para colisiones y línea de visión.
local ALTO_ARBOL = { Pino = 12.0, Abeto = 13.5, AbetoNevado = 13.5, Roble = 10.5, Alamo = 13.5, Abedul = 9.5 }
-- Radio del tronco (m): el choque de un tanque es contra el tronco.
local RADIO_TRONCO = { Pino = 0.36, Abeto = 0.32, AbetoNevado = 0.32, Roble = 0.55, Alamo = 0.36, Abedul = 0.22 }
Colocacion.arboles = RADIO_ARBOL

local TROZO = Terreno.celda * Terreno.celdasPorTrozo

-- Los generadores (`U`) son `Ruido.generador`: la misma secuencia que
-- `Ruido.azar`, sin cierres, para que LuaJIT compile la colocación.

--- U(0, 1) de un hash.
local function azar01(semilla, a, b, c)
    return (Ruido.hash(semilla, a, b, c) % 1000003) / 1000003
end

--- Especie de un árbol. `r` = U(0, 1) del hash del punto.
local function especieArbol(r, zRel, bosque, juntoAgua, aislado)
    if juntoAgua then
        return r < 0.55 and 'Alamo' or (r < 0.75 and 'Abedul' or 'Roble')
    end
    if aislado then
        if r < 0.55 then
            return 'Roble'
        elseif r < 0.88 then
            return 'Abedul'
        elseif r < 0.96 then
            return 'Pino'
        end
        return 'Abeto'
    end
    local alto = suave(8, 26, zRel)
    if r < 0.15 + 0.4 * alto then
        return 'Abeto'
    elseif r < 0.35 + 0.45 * alto then
        return 'Pino'
    elseif bosque < 0.55 and r < 0.8 then
        return 'Abedul'
    end
    return r < 0.88 and 'Roble' or 'Abedul'
end
Colocacion.especieArbol = especieArbol

--- Matriz Rz(rz) * Rx(rx) * Ry(ry) * escala (s, s, sz), por filas. Escrita
-- a mano (antes eran tres tablas y dos productos por copia): las mismas
-- sumas y productos, en el mismo orden, sin los términos que valen 0.
local function matriz(rz, rx, ry, s, sz)
    local cz, sn = math.cos(rz), math.sin(rz)
    local cx, sx = math.cos(rx), math.sin(rx)
    local cy, sy = math.cos(ry), math.sin(ry)
    -- A = Rz * Rx
    local a1, a2, a3 = cz, -sn * cx, -sn * -sx
    local a4, a5, a6 = sn, cz * cx, cz * -sx
    local a7, a8, a9 = 0, sx, cx
    -- A * Ry y la escala por columnas.
    return {
        (a1 * cy + a3 * -sy) * s,
        a2 * s,
        (a1 * sy + a3 * cy) * sz,
        (a4 * cy + a6 * -sy) * s,
        a5 * s,
        (a4 * sy + a6 * cy) * sz,
        (a7 * cy + a9 * -sy) * s,
        a8 * s,
        (a7 * sy + a9 * cy) * sz,
    }
end

function Colocacion.nueva(suelo)
    local self = setmetatable({}, Colocacion)
    self.suelo = suelo
    self.rejilla = suelo.relieve
    self.semilla = suelo.terreno.semilla
    self.copias = {}
    self.celdas = {}
    self.cuenta = {}
    self.manchas = {}
    self.afloramientos = {}
    self.anclas = {}
    self.hierbas = {}
    self.medio = suelo.medioPlantas
    self.baldosas = math.ceil(suelo.lado / Colocacion.baldosa)
    self:buscarAnclas()
    self:buscarManchas()
    return self
end

--- ¿Cae (x, y) dentro de la zona con plantas (sin el borde de niebla)?
function Colocacion:dentro(x, y)
    local s = self.suelo
    return math.abs(x - s.cx) < self.medio and math.abs(y - s.cy) < self.medio
end

-- Choques ----------------------------------------------------------------------------------

--- ¿Choca un objeto de radio `r` m en (x, y) con lo ya puesto?
function Colocacion:choca(x, y, r)
    local c = Colocacion.celda
    local ci, cj = math.floor(x / c), math.floor(y / c)
    for j = cj - 2, cj + 2 do
        for i = ci - 2, ci + 2 do
            local lista = self.celdas[i * 131072 + j]
            if lista then
                for _, o in ipairs(lista) do
                    local dx, dy = o[1] - x, o[2] - y
                    local d = math.sqrt(dx * dx + dy * dy) / M
                    if d < (o[3] + r) * 0.5 then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--- Apunta un objeto de radio `r` m en la rejilla de choques.
function Colocacion:ocupar(x, y, r)
    local c = Colocacion.celda
    local clave = math.floor(x / c) * 131072 + math.floor(y / c)
    local lista = self.celdas[clave]
    if not lista then
        lista = {}
        self.celdas[clave] = lista
    end
    lista[#lista + 1] = { x, y, r }
end

-- Copias -------------------------------------------------------------------------------------

--- Crea una copia de `nombre` en (x, y). `o` lleva: escala, hundir (m),
-- libre (giro en los tres ejes), alinear, inclinar, roca (tono de roca),
-- tono (multiplicador extra) y lista (dónde guardarla; por defecto, las
-- copias fijas).
function Colocacion:copia(nombre, x, y, U, o)
    local h, nx, ny, nz = self.rejilla:alturaNormal(x, y)
    local especie = Vegetacion.porNombre[nombre]
    local escala = o.escala
    local rz = U(0, DOS_PI)
    if o.giro then
        rz = o.giro
    end
    local rx, ry
    if o.libre then
        rx, ry = U(0, DOS_PI), U(0, DOS_PI)
    else
        local alinear = o.alinear or 0
        local inclinar = o.inclinar or 0.04
        rx = -math.atan2(ny, nz) * alinear + U(-inclinar, inclinar)
        ry = math.atan2(nx, nz) * alinear + U(-inclinar, inclinar)
    end
    local sz = escala * U(0.92, 1.1)
    local t1, t2, t3
    if o.roca then
        local b, c = U(0.82, 1.12), U(-0.05, 0.06)
        t1, t2, t3 = b * (1 + c), b, b * (1 - c)
    else
        local u, brillo = U(-1, 1), U(0.88, 1.1)
        t1, t2, t3 = brillo * (1 + 0.08 * u), brillo * (1 + 0.02 * u), brillo * (1 - 0.1 * u)
    end
    if o.tono then
        t1, t2, t3 = t1 * o.tono[1], t2 * o.tono[2], t3 * o.tono[3]
    end
    local s = self.suelo
    local c = {
        e = especie.indice,
        v = math.floor(U() * especie.variantes) + 1,
        x = x,
        y = y,
        z = h - (o.hundir or 0) * escala * M,
        m = matriz(rz, rx, ry, escala, sz),
        t1 = t1,
        t2 = t2,
        t3 = t3,
        hash = math.floor(U() * 100),
        bx = math.max(0, math.min(self.baldosas - 1, math.floor((x - s.x0) / Colocacion.baldosa))),
        by = math.max(0, math.min(self.baldosas - 1, math.floor((y - s.y0) / Colocacion.baldosa))),
        escala = escala,
        escalaZ = sz,
    }
    local lista = o.lista or self.copias
    lista[#lista + 1] = c
    self.cuenta[nombre] = (self.cuenta[nombre] or 0) + 1
    return c
end

--- Pone un árbol y lo apunta para la física y para las formaciones.
-- Solo árboles del pack StyleHex (el dueño, 19-nov: «quita todo lo generado
-- por código, esos poligonales raros»): los pinos y abetos de ramas de planos
-- y los álamos pasan a frondosos y abedules.
Colocacion.sustituto = { Pino = 'Roble', Abeto = 'Abedul', AbetoNevado = 'Abedul', Alamo = 'Abedul' }

function Colocacion:arbol(nombre, x, y, U, escala)
    nombre = Colocacion.sustituto[nombre] or nombre
    local c = self:copia(nombre, x, y, U, { escala = escala, hundir = 0.3 })
    self:ocupar(x, y, RADIO_ARBOL[nombre] or 4)
    self.suelo:apuntarPlanta({
        x = x,
        y = y,
        z = c.z,
        arbol = true,
        radio = (RADIO_TRONCO[nombre] or 0.36) * escala * M,
        alto = (ALTO_ARBOL[nombre] or 12) * c.escalaZ * M,
        -- Copa y copia para los impactos (batalla/impactos.lua).
        copa = (RADIO_ARBOL[nombre] or 4) * escala * M,
        copia = c,
    })
end

--- ¿Se puede poner algo que estorbe (árbol, arbusto, roca grande) en (x, y)?
function Colocacion:estorbaAqui(x, y)
    local s = self.suelo
    -- De los pasillos de avance solo se despejan 20 m a cada lado del eje
    -- (antes los 50 m enteros más un margen: el camino del robot no tenía ni
    -- un árbol a la vista; el dueño, 19-nov: «faltan los árboles»).
    -- Dentro de una ciudad o una mina (batalla/sitios/plano.lua), árboles
    -- donde no estorben (el dueño, 27-nov: «árboles tiene que haber en todos
    -- lados»): ni en edificios, calles, muro ni en la franja de la pista.
    if s.plano and s.plano:dentro(x, y, 80) then
        return s.plano:estorbaArbol(x, y)
    end
    return s:pesoExplanada(x, y) > 0.5 or s:ocupado(x, y, 40) or require('batalla.pasillos').distancia(s, x, y) < 200
end

-- Capas --------------------------------------------------------------------------------------

--- Capa 0: las plantas del mapa del área, en su sitio.
function Colocacion:buscarAnclas()
    local s = self.suelo
    local medio = self.medio
    local tx0, ty0 = math.floor((s.cx - medio) / TROZO), math.floor((s.cy - medio) / TROZO)
    local tx1, ty1 = math.floor((s.cx + medio) / TROZO), math.floor((s.cy + medio) / TROZO)
    for ty = ty0, ty1 do
        for tx = tx0, tx1 do
            local filtro = s.mundo:sinPlantas(tx, ty)
            for _, p in ipairs(Plantas.enTrozo(s.terreno, tx, ty, filtro)) do
                if self:dentro(p.x, p.y) then
                    if p.tipo == 'flores' then
                        local U = Ruido.generador(p.semilla)
                        self.manchas[#self.manchas + 1] = {
                            x = p.x,
                            y = p.y,
                            r = U(6, 9),
                            color = p.semilla % 4 + 1,
                            semilla = p.semilla,
                        }
                    elseif p.tipo == 'roca' then
                        self.afloramientos[#self.afloramientos + 1] = { x = p.x, y = p.y, semilla = p.semilla }
                    else
                        self.anclas[#self.anclas + 1] = p
                    end
                end
            end
        end
    end
end

--- Manchas de flores sueltas en la pradera: una por celda de 60 m con
-- probabilidad 0,15, donde no hay bosque ni hierba seca.
function Colocacion:buscarManchas()
    local s = self.suelo
    local rej = self.rejilla
    local celda = 600
    local i0, j0 = math.floor((s.cx - self.medio) / celda), math.floor((s.cy - self.medio) / celda)
    local i1, j1 = math.floor((s.cx + self.medio) / celda), math.floor((s.cy + self.medio) / celda)
    for j = j0, j1 do
        for i = i0, i1 do
            local U = Ruido.generador(Ruido.hash(self.semilla, i, j, 5501))
            if U() < 0.15 then
                local x, y = (i + U()) * celda, (j + U()) * celda
                if self:dentro(x, y) then
                    local k = rej:cercano(x, y)
                    if rej.bosque[k] < 0.3 and rej.n2[k] <= 0.25 and rej.h[k] > rej.nivelAgua[k] + 5 then
                        self.manchas[#self.manchas + 1] = {
                            x = x,
                            y = y,
                            r = U(6, 9),
                            color = math.floor(U() * 4) + 1,
                            semilla = Ruido.hash(self.semilla, i, j, 5502),
                        }
                    end
                end
            end
        end
    end
    -- Rejilla de manchas (celdas de 60 m) para teñir el suelo deprisa.
    self.rejillaManchas = {}
    for _, f in ipairs(self.manchas) do
        local clave = math.floor(f.x / celda) * 131072 + math.floor(f.y / celda)
        local lista = self.rejillaManchas[clave] or {}
        lista[#lista + 1] = f
        self.rejillaManchas[clave] = lista
    end
end

--- Manchas de flores cuya celda de 60 m toca la de (x, y) (o nil).
function Colocacion:manchasCerca(x, y)
    local celda = 600
    local ci, cj = math.floor(x / celda), math.floor(y / celda)
    -- Se guarda por celda: el terreno pregunta unas 400 000 veces.
    self.cacheManchas = self.cacheManchas or {}
    local guardado = self.cacheManchas[ci * 131072 + cj]
    if guardado ~= nil then
        return guardado or nil
    end
    local resultado
    for j = cj - 1, cj + 1 do
        for i = ci - 1, ci + 1 do
            local lista = self.rejillaManchas[i * 131072 + j]
            if lista then
                resultado = resultado or {}
                for _, f in ipairs(lista) do
                    resultado[#resultado + 1] = f
                end
            end
        end
    end
    self.cacheManchas[ci * 131072 + cj] = resultado or false
    return resultado
end

--- Capa 0 (árboles, arbustos y cactus del mapa).
function Colocacion:plantarAnclas()
    local s = self.suelo
    local rej = self.rejilla
    for _, p in ipairs(self.anclas) do
        local U = Ruido.generador(p.semilla)
        local k = rej:cercano(p.x, p.y)
        local seco = rej.h[k] > rej.nivelAgua[k] + 2
        if seco and not self:estorbaAqui(p.x, p.y) then
            local zRel = (rej.h[k] - s.hRef) / 10 / (s.escalaMundo or 1)
            if p.tipo == 'pino' then
                self:arbol(especieArbol(U(), zRel, 1, false, false), p.x, p.y, U, U(0.8, 1.25))
            elseif p.tipo == 'pinoNevado' then
                self:arbol('AbetoNevado', p.x, p.y, U, U(0.8, 1.25))
            elseif p.tipo == 'copa' then
                local junto = rej.dAgua[k] < 10
                self:arbol(especieArbol(U(), zRel, 0, junto, not junto), p.x, p.y, U, U(0.8, 1.25))
            elseif p.tipo == 'arbusto' or p.tipo == 'matorral' then
                local tono = p.tipo == 'matorral' and { 1.12, 0.98, 0.62 } or nil
                local c = self:copia('Arbusto', p.x, p.y, U, { escala = U(0.8, 1.4), hundir = 0.25, tono = tono })
                self:ocupar(p.x, p.y, 1.6)
                -- Derribo (Valeria): los vehículos lo tumban al pasar (batalla/derribo.lua).
                s:apuntarPlanta({ x = p.x, y = p.y, arbusto = true, copia = c })
            elseif p.tipo == 'cactus' then
                self:copia('Cactus', p.x, p.y, U, { escala = U(0.8, 1.3), hundir = 0.05 })
                s:apuntarPlanta({ x = p.x, y = p.y })
            end
        end
    end
end

--- Recorre una rejilla de `paso` px desplazada `desplazar` px por hash
-- sobre la zona con plantas y llama a `fn(x, y, k, U)` en cada candidato
-- cuya probabilidad (`prob(k)` con k el vértice cercano) supere su hash.
function Colocacion:recorrer(paso, desplazar, sal, prob, fn)
    local s = self.suelo
    local rej = self.rejilla
    local i0, j0 = math.floor((s.cx - self.medio) / paso), math.floor((s.cy - self.medio) / paso)
    local i1, j1 = math.floor((s.cx + self.medio) / paso), math.floor((s.cy + self.medio) / paso)
    local semilla = self.semilla
    local lado = rej.lado
    -- El vértice cercano es separable: cada columna y cada fila se buscan una vez.
    local columnas = {}
    for i = i0, i1 do
        columnas[i - i0] = rej:cercanoEje('x', i * paso)
    end
    for j = j0, j1 do
        local fila = rej:cercanoEje('y', j * paso) * lado
        for i = i0, i1 do
            local k = fila + columnas[i - i0]
            local p = prob(k, i * paso, j * paso)
            if p > 0 then
                local h = Ruido.hash(semilla, i, j, sal)
                if (h % 1000003) / 1000003 < p then
                    local U = Ruido.generador(h)
                    local x = i * paso + U(-desplazar, desplazar)
                    local y = j * paso + U(-desplazar, desplazar)
                    fn(x, y, k, U)
                end
            end
        end
    end
end

--- Capa 1: bosque y árboles sueltos.
function Colocacion:plantarBosque()
    local rej = self.rejilla
    local s = self.suelo
    local candidatos = {}
    -- Fuera del bosque, arboledas de frondosos y abedules por la pradera
    -- (el dueño, 19-nov: «faltan los árboles», como la batalla de Unreal; 27-nov:
    -- «el terreno muy pobre de árboles»): una arboleda (de 18 a 45 m de radio)
    -- en 7 de cada 10 cuadros de 60 m, con un árbol cada pocos metros, y el
    -- doble de árboles sueltos que antes por la pradera.
    local semilla = self.semilla
    local CUADRO = 600
    local function arboleda(x, y)
        local ci, cj = math.floor(x / CUADRO), math.floor(y / CUADRO)
        local mejor = 0
        for dj = -1, 1 do
            for di = -1, 1 do
                local U = Ruido.generador(Ruido.hash(semilla, ci + di, cj + dj, 7304))
                if U() < 0.7 then
                    local ax, ay = (ci + di + U()) * CUADRO, (cj + dj + U()) * CUADRO
                    local r = U(180, 450)
                    local d = math.sqrt((x - ax) ^ 2 + (y - ay) ^ 2) / r
                    if d < 1 then
                        mejor = math.max(mejor, 1 - d * d)
                    end
                end
            end
        end
        return mejor
    end
    local function prob(k, x, y)
        local b = rej.bosque[k]
        if b > 0.25 then
            return 0.75 * b
        end
        return 0.008 + 0.42 * arboleda(x, y)
    end
    self:recorrer(46, 20, 7301, prob, function(x, y, k, U)
        candidatos[#candidatos + 1] = { x = x, y = y, k = k, orden = U(), U = U }
    end)
    -- Orden barajado: ninguna especie gana siempre en los choques. Se
    -- ordenan números sin comparador (con una función de Lua, `table.sort`
    -- se llevaba el 10 % de la colocación); los empates, por orden de llegada.
    local ordenes, porOrden = {}, {}
    for _, c in ipairs(candidatos) do
        local lista = porOrden[c.orden]
        if not lista then
            lista = {}
            porOrden[c.orden] = lista
            ordenes[#ordenes + 1] = c.orden
        end
        lista[#lista + 1] = c
    end
    table.sort(ordenes)
    local barajados = {}
    for _, orden in ipairs(ordenes) do
        for _, c in ipairs(porOrden[orden]) do
            barajados[#barajados + 1] = c
        end
    end
    for _, c in ipairs(barajados) do
        local k = c.k
        if rej.dAgua[k] >= 2.5 and rej.h[k] > rej.nivelAgua[k] + 3 and not self:estorbaAqui(c.x, c.y) then
            local _, _, _, nz = rej:alturaNormal(c.x, c.y)
            if nz >= 0.82 then
                local b = rej.bosque[k]
                local zRel = (rej.h[k] - s.hRef) / 10 / (s.escalaMundo or 1)
                local especie = especieArbol(c.U(), zRel, b, false, b <= 0.25)
                -- 700 px es una altura del mapa: a tamaño real se compara sin ampliar.
                local hMapa = s.nivelMar + (rej.h[k] - s.nivelMar) / (s.escalaMundo or 1)
                if zRel > 0 and hMapa > 700 and especie == 'Abeto' then
                    especie = 'AbetoNevado'
                end
                if not self:choca(c.x, c.y, RADIO_ARBOL[especie]) then
                    self:arbol(especie, c.x, c.y, c.U, c.U(0.8, 1.25))
                end
            end
        end
    end
end

--- Capa 3: arbustos en la orla del bosque y alguno suelto.
function Colocacion:plantarArbustos()
    local rej = self.rejilla
    local function prob(k)
        local b = rej.bosque[k]
        return 0.35 * suave(0.05, 0.3, b) * suave(0.7, 0.35, b) + 0.004
    end
    self:recorrer(32, 15, 7302, prob, function(x, y, k, U)
        if rej.dAgua[k] >= 2.0 and rej.h[k] > rej.nivelAgua[k] + 2 and not self:estorbaAqui(x, y) then
            local _, _, _, nz = rej:alturaNormal(x, y)
            if nz >= 0.8 and not self:choca(x, y, 1.6) then
                local c = self:copia('Arbusto', x, y, U, { escala = U(0.8, 1.4), hundir = 0.25 })
                self:ocupar(x, y, 1.6)
                -- Derribo (Valeria): los vehículos lo tumban al pasar (batalla/derribo.lua).
                self.suelo:apuntarPlanta({ x = x, y = y, arbusto = true, copia = c })
            end
        end
    end)
end

--- Una roca de escala `escala`; las grandes estorban a las formaciones.
function Colocacion:roca(x, y, U, escala, hundir)
    if escala > 0.8 and self:estorbaAqui(x, y) then
        return
    end
    -- En los pasillos de avance, ni las piedras pequeñas: solo hierba y flores.
    if self.suelo:enCamino(x, y, 0) then
        return
    end
    local c = self:copia('Roca', x, y, U, { escala = escala, hundir = hundir, libre = true, roca = true })
    if escala > 1.4 then
        self.suelo:apuntarPlanta({
            x = x,
            y = y,
            z = c.z,
            arbol = true,
            roca = true,
            radio = 1.1 * escala * M,
            alto = escala * M,
        })
    end
end

--- Capa 6: rocas en lo empinado, afloramientos y peñas sueltas.
function Colocacion:plantarRocas()
    local rej = self.rejilla
    local s = self.suelo
    -- Rocas sueltas solo donde el suelo ya es casi todo roca: con los umbrales
    -- del documento salían más de 50 000 en la semilla 42 (1 millón de
    -- triángulos visibles).
    local desde = s.rocaDesde + 0.06
    local hasta = desde + 0.14
    -- En lo empinado: probabilidad 0,6 * suave(desde, hasta, pendiente). El
    -- 0,6 se decide con el hash del candidato; la pendiente, con la de su cara.
    local function prob(k)
        if rej.pendiente[k] < desde - 0.06 then
            return 0
        end
        return 0.4
    end
    self:recorrer(28, 13, 7303, prob, function(x, y, k, U)
        local _, _, _, nz = rej:alturaNormal(x, y)
        local p = 1 - nz
        if p >= desde and rej.dAgua[k] >= 0.5 and rej.h[k] < 950 and U() < suave(desde, hasta, p) then
            self:roca(x, y, U, U(0.8, 2.6), 0.3)
        end
    end)
    -- Afloramientos: crestas por curvatura y las rocas del mapa.
    for _, a in ipairs(self:crestas()) do
        self.afloramientos[#self.afloramientos + 1] = a
    end
    for _, a in ipairs(self.afloramientos) do
        local U = Ruido.generador(a.semilla)
        local radio = U(5, 8)
        for _ = 1, math.floor(U(4, 7.99)) do
            local ang = U(0, DOS_PI)
            local d = radio * math.sqrt(U()) * M
            local x, y = a.x + math.cos(ang) * d, a.y + math.sin(ang) * d
            local k = rej:cercano(x, y)
            if rej.dAgua[k] >= 0.5 and rej.h[k] > rej.nivelAgua[k] then
                self:roca(x, y, U, U(1.4, 3.4), 0.35)
            end
        end
    end
    -- Peñas sueltas: unas 4 por hectárea (una por celda de 50 m).
    self:recorrer(500, 240, 7304, function()
        return 1
    end, function(x, y, k, U)
        if rej.dAgua[k] >= 1.5 and rej.h[k] > rej.nivelAgua[k] + 2 then
            self:roca(x, y, U, U(0.5, 1.6), 0.3)
        end
    end)
end

--- Centros de afloramiento: en celdas de 40 m, el vértice más alto si su
-- curvatura pasa de 0,8 m y está a más de 4 m sobre el fondo del valle, con
-- probabilidad 0,5.
function Colocacion:crestas()
    local rej = self.rejilla
    local s = self.suelo
    local celda = 400
    local mejor = {}
    for k = 0, rej.total - 1 do
        local x, y = rej.x[k], rej.y[k]
        if self:dentro(x, y) then
            local clave = math.floor(x / celda) * 131072 + math.floor(y / celda)
            local m = mejor[clave]
            if not m or rej.h[k] > rej.h[m] then
                mejor[clave] = k
            end
        end
    end
    local centros = {}
    for clave, k in pairs(mejor) do
        local x, y, h = rej.x[k], rej.y[k], rej.h[k]
        local media = (s:altura(x + 200, y) + s:altura(x - 200, y) + s:altura(x, y + 200) + s:altura(x, y - 200)) / 4
        local curvatura = (h - media) / 10
        local zRel = (h - s.hRef) / 10 / (s.escalaMundo or 1)
        if
            curvatura > 0.8
            and zRel > 4
            and azar01(self.semilla, clave % 131072, math.floor(clave / 131072), 7305) < 0.5
        then
            centros[#centros + 1] =
                { x = x, y = y, semilla = Ruido.hash(self.semilla, math.floor(x), math.floor(y), 7306) }
        end
    end
    -- `pairs` no tiene orden fijo: se ordena para que salga siempre igual.
    table.sort(centros, function(a, b)
        return a.semilla < b.semilla
    end)
    return centros
end

--- Planta todo lo fijo (capas 0, 1, 3 y 6).
function Colocacion:plantar()
    self:plantarAnclas()
    self:plantarBosque()
    self:plantarArbustos()
    self:plantarRocas()
    self:plantarRestos()
end

-- Restos abandonados (el dueño, 19-nov: «que se sienta un poco vivo el
-- terreno»; el primer reparto, sueltos y torcidos, «se ven horribles, muy
-- cerca sin sentido»). Ahora como los deja alguien: pocos sitios, en llano,
-- asentados en el suelo y alineados:
--   * un contenedor solo, a veces con la puerta abierta;
--   * o un depósito: 2 o 3 contenedores en fila, lado a lado;
--   * junto a ellos, los bidones juntos en un bloque (como en un palé) y las
--     cajas apiladas de dos en dos.
-- Un sitio en 1 de cada 5 cuadros de 500 m y en 1 de cada 4 tramos de 600 m
-- junto a los pasillos de avance. Estorban como las rocas grandes.
Colocacion.cuadroRestos = 5000
Colocacion.coloresContenedor = {
    -- Pintura de contenedor real, saturada y algo oscura (a pleno sol los
    -- tonos claros se leían como madera).
    { 0.62, 0.12, 0.08 }, -- rojo óxido
    { 0.1, 0.24, 0.5 }, -- azul
    { 0.16, 0.34, 0.2 }, -- verde
    { 0.85, 0.36, 0.06 }, -- naranja
    { 0.62, 0.63, 0.6 }, -- gris
    { 0.36, 0.2, 0.12 }, -- marrón
}
Colocacion.coloresBidon = { { 0.25, 0.4, 0.75 }, { 0.8, 0.2, 0.15 }, { 0.9, 0.7, 0.15 }, { 0.3, 0.45, 0.3 } }

function Colocacion:plantarRestos()
    local s = self.suelo
    local rej = self.rejilla
    local c = Colocacion.cuadroRestos
    local i0, j0 = math.floor((s.cx - self.medio) / c), math.floor((s.cy - self.medio) / c)
    local i1, j1 = math.floor((s.cx + self.medio) / c), math.floor((s.cy + self.medio) / c)
    local sitios = {}
    for j = j0, j1 do
        for i = i0, i1 do
            local U = Ruido.generador(Ruido.hash(self.semilla, i, j, 7501))
            if U() < 0.2 then
                sitios[#sitios + 1] = { (i + U(0.2, 0.8)) * c, (j + U(0.2, 0.8)) * c, U }
            end
        end
    end
    for np, p in ipairs(s.pasillos or {}) do
        local tramo, hecho = 0, 0
        for k = 2, #p.x do
            tramo = tramo + math.sqrt((p.x[k] - p.x[k - 1]) ^ 2 + (p.y[k] - p.y[k - 1]) ^ 2)
            if tramo >= 6000 then
                tramo = 0
                hecho = hecho + 1
                local U = Ruido.generador(Ruido.hash(self.semilla, np, hecho, 7502))
                if U() < 0.25 then
                    local dx, dy = p.x[k] - p.x[k - 1], p.y[k] - p.y[k - 1]
                    local l = math.max(1e-6, math.sqrt(dx * dx + dy * dy))
                    local d = U(330, 450) * (U() < 0.5 and -1 or 1)
                    sitios[#sitios + 1] = { p.x[k] - dy / l * d, p.y[k] + dx / l * d, U }
                end
            end
        end
    end
    -- `BATALLA_RESTOS_EN=x,y` (px): un sitio más ahí, para revisarlos.
    local en = os.getenv('BATALLA_RESTOS_EN')
    if en then
        local ex, ey = en:match('([%-%d%.]+),([%-%d%.]+)')
        sitios[#sitios + 1] = { tonumber(ex), tonumber(ey), Ruido.generador(7777), prueba = true }
    end
    local prueba = false
    local function llano(x, y, r)
        if prueba then
            return true
        end
        if not self:dentro(x, y) then
            return false
        end
        local k = rej:cercano(x, y)
        if rej.dAgua[k] < 6 or rej.h[k] < rej.nivelAgua[k] + 3 or self:estorbaAqui(x, y) then
            return false
        end
        local _, _, _, nz = rej:alturaNormal(x, y)
        return nz > 0.95 and not self:choca(x, y, r)
    end
    local function poner(nombre, x, y, U, giro, radio, tono, variante, alzar)
        -- Asentados en el suelo (pendiente de 18° como mucho).
        local co = self:copia(nombre, x, y, U, { escala = 1, hundir = 0.03, alinear = 1, inclinar = 0, giro = giro, tono = tono })
        if variante then
            co.v = variante
        end
        if alzar then
            co.z = co.z + alzar
        end
        self:ocupar(x, y, radio)
        s:apuntarPlanta({ x = x, y = y, z = co.z, arbol = true, roca = true, radio = radio * M * 0.8, alto = 26 })
    end
    local RECTO = math.pi / 2
    for _, sitio in ipairs(sitios) do
        local cx, cy, U = sitio[1], sitio[2], sitio[3]
        prueba = sitio.prueba
        -- Los ejes del sitio, a 0/90/180/270° con un pelín de desvío: el
        -- largo de los contenedores va por `largo` y la fila por `lado`.
        local giro = math.floor(U(0, 4)) * RECTO + U(-0.04, 0.04)
        local largo = { math.cos(giro), math.sin(giro) }
        local lado = { -largo[2], largo[1] }
        local n = U() < 0.45 and 1 or math.floor(U(2, 3.99))
        if llano(cx, cy, 4) and llano(cx + lado[1] * 30 * (n - 1), cy + lado[2] * 30 * (n - 1), 4) then
            local col = Colocacion.coloresContenedor[math.floor(U() * #Colocacion.coloresContenedor) + 1]
            for k = 0, n - 1 do
                -- Lado a lado (2,9 m entre ejes), algo desparejos a lo largo.
                local f = U(-6, 6)
                local x = cx + lado[1] * 29 * k + largo[1] * f
                local y = cy + lado[2] * 29 * k + largo[2] * f
                if k > 0 and U() < 0.6 then
                    col = Colocacion.coloresContenedor[math.floor(U() * #Colocacion.coloresContenedor) + 1]
                end
                poner('Contenedor', x, y, U, giro + (U() < 0.5 and 0 or math.pi), 3.4, col, (n == 1 and U() < 0.5) and 2 or 1)
            end
            -- Bloque de bidones al otro lado de la fila (o del único contenedor).
            if U() < 0.75 then
                local bx = cx - lado[1] * 32 + largo[1] * U(-15, 15)
                local by = cy - lado[2] * 32 + largo[2] * U(-15, 15)
                local filas, cols = math.floor(U(2, 3.99)), math.floor(U(2, 4.99))
                local colB = Colocacion.coloresBidon[math.floor(U() * #Colocacion.coloresBidon) + 1]
                for a = 0, filas - 1 do
                    for b = 0, cols - 1 do
                        if U() < 0.88 then
                            local x = bx + largo[1] * b * 6.2 - lado[1] * a * 6.2
                            local y = by + largo[2] * b * 6.2 - lado[2] * a * 6.2
                            if llano(x, y, 0.3) then
                                poner('Bidon', x, y, U, U(0, 6.28), 0.3, colB)
                            end
                        end
                    end
                end
                -- Uno volcado no: los modelos van de pie; uno suelto algo apartado.
                if U() < 0.5 then
                    local x, y = bx + lado[1] * -14 + largo[1] * U(-10, 10), by + lado[2] * -14 + largo[2] * U(-10, 10)
                    if llano(x, y, 0.3) then
                        poner('Bidon', x, y, U, U(0, 6.28), 0.3, colB)
                    end
                end
            end
            -- Cajas en una pila de dos junto al extremo de la fila.
            if U() < 0.6 then
                local x = cx + largo[1] * 46 + lado[1] * U(-5, 5)
                local y = cy + largo[2] * 46 + lado[2] * U(-5, 5)
                if llano(x, y, 0.8) then
                    local g = giro + U(-0.1, 0.1)
                    poner('Caja', x, y, U, g, 0.8, nil)
                    if U() < 0.6 then
                        poner('Caja', x, y, U, g + U(-0.15, 0.15), 0.8, nil, nil, 8)
                    end
                    if U() < 0.5 then
                        poner('Caja', x + lado[1] * 9, y + lado[2] * 9, U, g + U(-0.1, 0.1), 0.8, nil)
                    end
                end
            end
        end
    end
end

-- Hierba y flores por baldosas ------------------------------------------------------------

--- El centro de tierra del camino queda visible, sin matas ni flores.
function Colocacion:fueraDeCamino(x, y, k)
    local rej = self.rejilla
    -- Ni una mata en la pista del aeródromo (asfalto, arcenes y el pie del
    -- terraplén: 21 m a cada lado del eje), el dueño, 20-nov.
    local plano = self.suelo.plano
    local pista = plano and plano.pista
    if pista and math.abs(y - pista.y) < 210 and math.abs(x - pista.x) < pista.medioLargo * 10 + 300 then
        return false
    end
    if not rej.dPasillo then
        return true
    end
    local distancia = rej:interpolar(rej.dPasillo, x, y)
    return ColorTerreno.pesoCamino(distancia, rej.n1[k]) < 0.25
end

--- Matas y flores de la baldosa (bx, by), generadas la primera vez que se
-- piden. Salen del hash: dan siempre lo mismo.
function Colocacion:hierbaDeBaldosa(bx, by)
    local clave = bx * 1000 + by
    if self.hierbas[clave] then
        return self.hierbas[clave]
    end
    local lista = {}
    local s = self.suelo
    local rej = self.rejilla
    local lado = Colocacion.baldosa
    local x0, y0 = s.x0 + bx * lado, s.y0 + by * lado
    -- Una mata por celda de 3,8 m (antes 5 m, que dejaba el suelo desnudo
    -- entre matas). Cada mata lleva menos hojas (vegetacion.lua) para que los
    -- triángulos no suban tanto como la cantidad.
    local celda = 15 -- (antes 38) las matas del pack son más pequeñas y la hierba debe tapar el suelo
    local i0, j0 = math.floor(x0 / celda), math.floor(y0 / celda)
    local i1, j1 = math.floor((x0 + lado) / celda) - 1, math.floor((y0 + lado) / celda) - 1
    for j = j0, j1 do
        for i = i0, i1 do
            local U = Ruido.generador(Ruido.hash(self.semilla, i, j, 7401))
            local x, y = (i + U()) * celda, (j + U()) * celda
            if self:dentro(x, y) then
                local k = rej:cercano(x, y)
                if
                    rej.dAgua[k] >= 0.8
                    and rej.h[k] > rej.nivelAgua[k] + 1
                    and rej.pendiente[k] < 0.2
                    and self:fueraDeCamino(x, y, k)
                    and not (s.plano and s.plano:estorbaPlanta(x, y))
                then
                    local zRel = (rej.h[k] - s.hRef) / 10 / (s.escalaMundo or 1)
                    local seca = zRel > 14 or rej.n2[k] > 0.25 or rej.humedad[k] < -0.25
                    local nombre = (seca and U() < 0.25) and 'MataSeca' or 'Mata'
                    -- Tono entre el verde y el seco (y algo más claro): la
                    -- hierba se funde con el suelo en vez de verse oscura
                    -- sobre él. El mismo hash da siempre el mismo tono.
                    local t = U(0, 0.55) + (seca and 0.25 or 0)
                    local claro = U(1.05, 1.25)
                    -- Del verde del pack hacia el amarillo (no hacia el gris).
                    local tono = { claro * (1 + 0.45 * t), claro * (1 + 0.1 * t), claro * (1 - 0.3 * t) }
                    self:copia(nombre, x, y, U, {
                        -- La mata ya mide 1 m (Matas.altoHierba): de 0,8 a 1,2 m.
                        escala = U(0.8, 1.2),
                        hundir = 0.08,
                        alinear = 0.7,
                        lista = lista,
                        tono = tono,
                    })
                end
            end
        end
    end
    -- Flores de las manchas cuyo centro cae en la baldosa.
    for _, f in ipairs(self.manchas) do
        local fx, fy = math.floor((f.x - s.x0) / lado), math.floor((f.y - s.y0) / lado)
        if fx == bx and fy == by then
            local U = Ruido.generador(Ruido.hash(f.semilla, 1, 2, 7402))
            for _ = 1, math.floor(f.r * f.r * 0.9) do
                local ang = U(0, DOS_PI)
                local d = f.r * math.sqrt(U()) * 0.95 * M
                local x, y = f.x + math.cos(ang) * d, f.y + math.sin(ang) * d
                local k = rej:cercano(x, y)
                if rej.dAgua[k] >= 1 and rej.h[k] > rej.nivelAgua[k] + 1 and self:fueraDeCamino(x, y, k) and not (s.plano and s.plano:estorbaPlanta(x, y)) then
                    self:copia(
                        'Flor' .. f.color,
                        x,
                        y,
                        U,
                        { escala = U(0.9, 1.3), hundir = 0.05, alinear = 0.7, lista = lista }
                    )
                end
            end
        end
    end
    self.hierbas[clave] = lista
    return lista
end

return Colocacion
