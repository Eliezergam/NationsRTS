-- Articulación del camión lanzamisiles de 4 misiles (Valeria): el árbol de
-- piezas y cómo se componen sus matrices. Lo usa batalla/lanzamisiles.lua
-- cuando el modelo tiene `rampaLanzador`. El contrato es el de Camila
-- (assets/modelos3d/CAMION_MISILES_CONTRATO.md, tablas del .lua): px del
-- juego (1 px = 10 cm, x hacia la cabina, z arriba, la y del juego es la de
-- Blender cambiada de signo), pivotes relativos al padre y mallas en reposo.
--
-- Lo que se mueve lo deciden los scripts del vehículo (batalla/vehiculos,
-- especializaciones `suspension`, `estremecimiento`, `ruedas`,
-- `hidraulicos`, `ventiladores`, `gatos`, `rampa`, `misiles`...). Aquí solo
-- se compone lo que ellos piden:
--
--   chasis visual  el casco de la física (Modelos3d.postura) con lo que le
--                  ponen (Vehiculo:setInclinacionChasis): altura, cabeceo y
--                  balanceo sobre el centro entre los ejes extremos.
--   cada pieza     su pivote, relativo a su padre, por su ajuste
--                  (Pieza:setGiro / Pieza:setDesplazamiento): sus hijas la siguen. Las que
--                  apuntan (Pieza:setApuntarA) miran a su destino de este mismo
--                  cuadro y se calculan después de él.
--
-- Hay una `ArticulacionCamion` por modelo (`ArticulacionCamion.de`); por
-- camión, solo matrices que se crean una vez.
--
-- Con un filtro (las piezas que tiene el nivel de detalle que se dibuja,
-- `u.piezasVista`, batalla/dream/escena.lua), `matrices` solo compone esas,
-- sus padres y los destinos de las que apuntan; la rampa y los misiles
-- siempre (bocas y misil en vuelo). De lejos, el LOD3 son siete piezas de 49.

local Matriz = require('batalla.matriz')

local ArticulacionCamion = {}
ArticulacionCamion.__index = ArticulacionCamion

-- Orden de disparo de los misiles: alterna los lados para que la rampa no
-- quede cargada de uno solo.
ArticulacionCamion.ordenMisiles = {
    'misilExteriorIzquierdo',
    'misilExteriorDerecho',
    'misilInteriorIzquierdo',
    'misilInteriorDerecho',
}

local porModelo = setmetatable({}, { __mode = 'k' })

--- La articulación del modelo de vértices `modelo` (Modelos3d.modelo), una
-- vez por modelo; nil si no es el camión de 4 misiles (sin `rampaLanzador`).
function ArticulacionCamion.de(modelo)
    if not modelo or not modelo.piezas or not modelo.piezas.rampaLanzador then
        return nil
    end
    local articulacion = porModelo[modelo]
    if not articulacion then
        articulacion = ArticulacionCamion.nuevo(modelo)
        porModelo[modelo] = articulacion
    end
    return articulacion
end

local function normalizar(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if l < 1e-9 then
        return 1, 0, 0
    end
    return x / l, y / l, z / l
end

--- Giro que lleva la dirección unitaria (ax, ay, az) a (bx, by, bz), con la
-- traslación (tx, ty, tz), en `r` (fórmula de Rodrigues).
local function girarHacia(ax, ay, az, bx, by, bz, tx, ty, tz, r)
    local vx, vy, vz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
    local c = ax * bx + ay * by + az * bz
    local k = 1 / math.max(1 + c, 1e-6)
    r[1], r[2], r[3], r[4] = vx * vx * k + c, vx * vy * k - vz, vx * vz * k + vy, tx
    r[5], r[6], r[7], r[8] = vx * vy * k + vz, vy * vy * k + c, vy * vz * k - vx, ty
    r[9], r[10], r[11], r[12] = vx * vz * k - vy, vy * vz * k + vx, vz * vz * k + c, tz
    r[13], r[14], r[15], r[16] = 0, 0, 0, 1
    return r
end

--- Giro `angulo` sobre el eje x con la traslación (x, y, z), en `r`.
local function alabear(angulo, x, y, z, r)
    local c, s = math.cos(angulo), math.sin(angulo)
    r[1], r[2], r[3], r[4] = 1, 0, 0, x
    r[5], r[6], r[7], r[8] = 0, c, -s, y
    r[9], r[10], r[11], r[12] = 0, s, c, z
    r[13], r[14], r[15], r[16] = 0, 0, 0, 1
    return r
end

local function trasladar(x, y, z, r)
    return Matriz.colocar(x, y, z, 0, 1, r)
end

--- Pivote de cada pieza en el sistema del chasis (los del .lua son
-- relativos a su padre).
local function pivotesAbsolutos(modelo)
    local absolutos = {}
    local function absoluto(nombre)
        local hecho = absolutos[nombre]
        if hecho then
            return hecho
        end
        local pieza = modelo.piezas[nombre]
        local p = pieza.pivote
        local r = { p[1], p[2], p[3] }
        if pieza.padre and modelo.piezas[pieza.padre] then
            local padre = absoluto(pieza.padre)
            r[1], r[2], r[3] = r[1] + padre[1], r[2] + padre[2], r[3] + padre[3]
        end
        absolutos[nombre] = r
        return r
    end
    for nombre in pairs(modelo.piezas) do
        absoluto(nombre)
    end
    return absolutos
end

function ArticulacionCamion.nuevo(modelo)
    local self = setmetatable({}, ArticulacionCamion)
    local abs = pivotesAbsolutos(modelo)
    self.modelo = modelo
    self.abs = abs
    -- Los demás módulos (daño, destrucción) leen el pivote en el chasis.
    for nombre, pieza in pairs(modelo.piezas) do
        pieza.pivoteAbsoluto = abs[nombre]
    end
    -- El contenedor de los demás camiones es aquí la rampa (bocas, daño).
    modelo.piezas.contenedor = modelo.piezas.contenedor or modelo.piezas.rampaLanzador
    -- Qué hace cada pieza (`tipo`) y sus datos del contrato.
    local tipos = {}
    local datosRuedas = modelo.ruedas or {}
    self.ruedas = {}
    local nombres = {}
    for nombre in pairs(modelo.piezas) do
        if nombre ~= 'contenedor' then
            nombres[#nombres + 1] = nombre
        end
    end
    table.sort(nombres)
    for _, nombre in ipairs(nombres) do
        if nombre:sub(1, 5) == 'rueda' then
            self.ruedas[#self.ruedas + 1] = nombre
            tipos[nombre] = { tipo = 'rueda' }
        end
    end
    tipos.rampaLanzador = { tipo = 'rampa' }
    local rampa = modelo.rampa or {}
    self.elevacion = modelo.elevacion or math.deg(-(rampa.rotYDesplegado or math.rad(-35)))
    self.gatos = {}
    for _, g in ipairs(modelo.gatos or {}) do
        if modelo.piezas[g.pieza] then
            self.gatos[#self.gatos + 1] = g
            tipos[g.pieza] = { tipo = 'gato' }
        end
    end
    self.ventiladores = {}
    for _, v in ipairs(modelo.ventiladores or {}) do
        if modelo.piezas[v.pieza] then
            self.ventiladores[#self.ventiladores + 1] = v.pieza
            tipos[v.pieza] = { tipo = 'ventilador' }
        end
    end
    -- Misiles en orden de disparo, con su sitio en la rampa y su boca: la
    -- cola (el origen del misil en vuelo, assets/modelos3d/misil_synty4, es
    -- su cola: al salir coincide con el de la rampa).
    local datosMisil = {}
    for _, m in ipairs(modelo.misiles or {}) do
        datosMisil[m.pieza] = m
    end
    self.misiles = {}
    self.ordenMisiles = {}
    self.bocas = {}
    local rp = abs.rampaLanzador
    for _, nombre in ipairs(ArticulacionCamion.ordenMisiles) do
        if modelo.piezas[nombre] then
            local p = abs[nombre]
            local rel = { p[1] - rp[1], p[2] - rp[2], p[3] - rp[3] }
            local cola = datosMisil[nombre] and datosMisil[nombre].cola or { 0, 0, 0 }
            self.misiles[nombre] = true
            self.ordenMisiles[#self.ordenMisiles + 1] = { nombre = nombre, rel = rel }
            self.bocas[#self.bocas + 1] = { rel[1] + cola[1], rel[2] + cola[2], rel[3] + cola[3] }
        end
    end
    -- Orden de cálculo: de los padres a los hijos, y los que apuntan después
    -- de su destino (ArticulacionCamion:ordenar).
    local orden = {}
    for _, nombre in ipairs(nombres) do
        local t = tipos[nombre] or { tipo = 'fija' }
        local pieza = modelo.piezas[nombre]
        t.nombre = nombre
        t.padre = pieza.padre and modelo.piezas[pieza.padre] and pieza.padre or nil
        t.rel = pieza.pivote
        t.despues = {}
        tipos[nombre] = t
        orden[#orden + 1] = t
    end
    self.orden = orden
    self.tipos = tipos
    self:ordenar()
    -- Las piezas, en el orden en que se dibujan: las ruedas al final
    -- (Destruccion las busca desde `primeraRueda`).
    local piezas = {}
    for _, t in ipairs(orden) do
        if t.tipo ~= 'rueda' then
            piezas[#piezas + 1] = t.nombre
        end
    end
    self.primeraRueda = #piezas + 1
    for _, nombre in ipairs(self.ruedas) do
        piezas[#piezas + 1] = nombre
    end
    self.piezas = piezas
    -- Ruedas: radio y distancia entre ejes.
    local delantera = abs.ruedaDelanteraIzquierda or abs[self.ruedas[1]]
    local ultima = abs.ruedaUltimaIzquierda or abs[self.ruedas[#self.ruedas]]
    self.radioRueda = datosRuedas.radio or delantera[3]
    self.entreEjes = delantera[1] - ultima[1]
    -- Centro del chasis para cabecear y balancear (entre los ejes extremos).
    self.centroX = (delantera[1] + ultima[1]) / 2
    -- Salida del humo del escape (en el chasis).
    local escape = modelo.puntos and modelo.puntos.escapeSalidaHumo
    if escape and abs[escape.pieza] then
        local p = abs[escape.pieza]
        self.escape = { p[1] + escape.punto[1], p[2] + escape.punto[2], p[3] + escape.punto[3] }
    end
    -- Órdenes de cálculo por filtro (ArticulacionCamion:ordenFiltrado) y las
    -- piezas que se componen siempre.
    self.ordenes = setmetatable({}, { __mode = 'k' })
    self.siempre = { rampaLanzador = true }
    for _, m in ipairs(self.ordenMisiles) do
        self.siempre[m.nombre] = true
    end
    -- Tablas de trabajo.
    self.a, self.b, self.c, self.d = {}, {}, {}, {}
    self.identidad = Matriz.identidad()
    return self
end

--- Ordena `self.orden`: cada pieza después de su padre y de las que tiene en
-- `despues` (sus anclas). Por nivel y, en el mismo nivel, por nombre.
function ArticulacionCamion:ordenar()
    local tipos = self.tipos
    local nivel = {}
    local function nivelDe(nombre)
        if nivel[nombre] then
            return nivel[nombre]
        end
        nivel[nombre] = 0
        local t = tipos[nombre]
        local n = 0
        if t.padre then
            n = math.max(n, nivelDe(t.padre) + 1)
        end
        for _, otra in ipairs(t.despues) do
            if tipos[otra] then
                n = math.max(n, nivelDe(otra) + 1)
            end
        end
        nivel[nombre] = n
        return n
    end
    for _, t in ipairs(self.orden) do
        t.profundidad = nivelDe(t.nombre)
    end
    table.sort(self.orden, function(a, b)
        if a.profundidad ~= b.profundidad then
            return a.profundidad < b.profundidad
        end
        return a.nombre < b.nombre
    end)
    -- Los órdenes filtrados ya hechos dejan de valer.
    if self.ordenes then
        for clave in pairs(self.ordenes) do
            self.ordenes[clave] = nil
        end
    end
end

--- La pieza `nombre` se calcula después de `otra` (Pieza:setApuntarA). Es del
-- modelo: vale para todos los camiones de este modelo.
function ArticulacionCamion:despuesDe(nombre, otra)
    local t = self.tipos[nombre]
    for _, ya in ipairs(t.despues) do
        if ya == otra then
            return
        end
    end
    t.despues[#t.despues + 1] = otra
    self:ordenar()
end

--- Matrices del camión `u`, la primera vez.
function ArticulacionCamion:inicializar(u)
    u.chasisVisual = {}
    u.localesCamion = {}
    for _, t in ipairs(self.orden) do
        u.localesCamion[t.nombre] = {}
    end
end

--- Misiles que le quedan en la rampa: `u.cargados`, el mismo número que
-- Tropas.misilesCargados (aquí no se puede pedir a Tropas: lo requiere
-- Lanzamisiles); sin él, todos mientras tenga el misil cargado. Las ranuras
-- salen en el orden de `ordenMisiles` (Tropas.ranuraCargada).
function ArticulacionCamion:cargados(u)
    if u.cargados then
        return math.max(0, math.min(#self.ordenMisiles, u.cargados))
    end
    return u.misilCargado and #self.ordenMisiles or 0
end

--- El índice (en el orden de disparo) del siguiente misil que saldrá.
function ArticulacionCamion:siguiente(u)
    return #self.ordenMisiles - self:cargados(u) + 1
end

--- Matriz del chasis que se dibuja: `base` (el casco) con lo que le ponen
-- las especializaciones, en `u.chasisVisual`.
function ArticulacionCamion:chasis(u, base)
    -- Lo que le ponen las especializaciones (Vehiculo:setInclinacionChasis).
    local s = u.chasisScript
    local cabeceo = s and s.cabeceo or 0
    local balanceo = s and s.balanceo or 0
    local altura = s and s.altura or 0
    -- Giro alrededor del centro del chasis: T(centro + altura) * Ry * Rx * T(-centro).
    Matriz.cabecear(cabeceo, self.centroX, 0, altura, self.a)
    alabear(balanceo, 0, 0, 0, self.b)
    Matriz.multiplicar(self.a, self.b, self.c)
    trasladar(-self.centroX, 0, 0, self.a)
    Matriz.multiplicar(self.c, self.a, self.b)
    Matriz.multiplicar(base, self.b, u.chasisVisual)
    return u.chasisVisual
end

--- Matriz local (en el chasis) de la pieza `t` del camión `u`, en `destino`:
-- su pivote por su ajuste (Pieza:setGiro / Pieza:setDesplazamiento), o mirando a su
-- destino si apunta (Pieza:setApuntarA).
function ArticulacionCamion:matrizLocal(u, t, destino)
    local locales = u.localesCamion
    local padre = t.padre and locales[t.padre] or self.identidad
    local rel = t.rel
    local ajuste = u.ajustesPiezas and u.ajustesPiezas[t.nombre]
    local apunte = u.apuntes and u.apuntes[t.nombre]
    if apunte then
        -- Su pivote (lo mueve su padre) mira al punto de su destino.
        local px, py, pz = Matriz.aplicar(padre, rel[1], rel[2], rel[3])
        local p = apunte.punto
        local ax, ay, az = Matriz.aplicar(locales[apunte.pieza], p[1], p[2], p[3])
        local dx, dy, dz = normalizar(ax - px, ay - py, az - pz)
        local q = apunte.reposo
        girarHacia(q[1], q[2], q[3], dx, dy, dz, px, py, pz, self.c)
        if ajuste then
            return Matriz.multiplicar(self.c, ajuste, destino)
        end
        for i = 1, 16 do
            destino[i] = self.c[i]
        end
        return destino
    end
    local m = trasladar(rel[1], rel[2], rel[3], self.a)
    if ajuste then
        Matriz.multiplicar(m, ajuste, self.d)
        m = self.d
    end
    return Matriz.multiplicar(padre, m, destino)
end

--- Orden de cálculo con el filtro `filtro` (conjunto de nombres; nil, todas):
-- las piezas de `orden` que hacen falta (las del filtro, las de `siempre`,
-- sus padres y las anclas de las que apuntan), cada una con `componer` si
-- su matriz final se usa. Una vez por filtro.
function ArticulacionCamion:ordenFiltrado(filtro)
    local clave = filtro or self
    local hecho = self.ordenes[clave]
    if hecho then
        return hecho
    end
    local tipos = self.tipos
    local necesarias = {}
    local function marcar(nombre)
        local t = nombre and tipos[nombre]
        if not t or necesarias[nombre] then
            return
        end
        necesarias[nombre] = true
        marcar(t.padre)
        for _, otra in ipairs(t.despues) do
            marcar(otra)
        end
    end
    for _, t in ipairs(self.orden) do
        if not filtro or filtro[t.nombre] or self.siempre[t.nombre] then
            marcar(t.nombre)
        end
    end
    local lista = {}
    for _, t in ipairs(self.orden) do
        if necesarias[t.nombre] then
            local componer = not filtro or filtro[t.nombre] or self.siempre[t.nombre] or false
            lista[#lista + 1] = { t = t, componer = componer }
        end
    end
    self.ordenes[clave] = lista
    return lista
end

--- Todas las matrices de las piezas de `u` en `matrices` (con `filtro`, solo
-- las de ArticulacionCamion:ordenFiltrado). `base`: el casco (o el de la
-- destrucción); `restos`: las ruedas sueltas de la destrucción.
function ArticulacionCamion:matrices(u, base, matrices, restos, filtro)
    local chasis = self:chasis(u, base)
    local locales = u.localesCamion
    for _, paso in ipairs(self:ordenFiltrado(filtro)) do
        local t = paso.t
        local nombre = t.nombre
        local loc = self:matrizLocal(u, t, locales[nombre])
        if paso.componer then
            local resto = restos and restos[nombre]
            if resto then
                matrices[nombre] = resto.matriz
            else
                Matriz.multiplicar(chasis, loc, matrices[nombre])
            end
        end
    end
    matrices.contenedor = matrices.rampaLanzador
end

--- Lo que mueve la articulación además del suelo y el estremecimiento:
-- rampa, gatos y misiles cargados, en un número.
function ArticulacionCamion:firma(u)
    -- Con los ajustes de las especializaciones (batalla/vehiculos/pieza.lua).
    return (u.versionAjustes or 0) * 1048576 + (u.elevacion or 0) * 4096 + (u.gatos or 0) * 8 + self:cargados(u)
end

--- Solo los ventiladores (el camión asentado: lo demás no se ha movido); con
-- `filtro`, si están en él.
function ArticulacionCamion:matricesVentiladores(u, matrices, filtro)
    local locales = u.localesCamion
    for _, nombre in ipairs(self.ventiladores) do
        if not filtro or filtro[nombre] then
            local loc = self:matrizLocal(u, self.tipos[nombre], locales[nombre])
            Matriz.multiplicar(u.chasisVisual, loc, matrices[nombre])
        end
    end
end

--- Boca del siguiente misil del camión `u` (su cola, en el sistema de la
-- rampa) o nil si no le queda ninguno.
function ArticulacionCamion:bocaSiguiente(u)
    return self.bocas[self:siguiente(u)]
end

--- Matriz del siguiente misil en la rampa (para el lado del misil en vuelo).
function ArticulacionCamion:matrizSiguiente(u)
    local m = self.ordenMisiles[self:siguiente(u)]
    return m and u.matricesLanza[m.nombre]
end

--- Salida del humo del escape en el mundo (x, y, z) del camión `u`, o nil.
function ArticulacionCamion:escapeEnMundo(u)
    local e = self.escape
    if not e or not u.chasisVisual[1] then
        return nil
    end
    return Matriz.aplicar(u.chasisVisual, e[1], e[2], e[3])
end

return ArticulacionCamion
