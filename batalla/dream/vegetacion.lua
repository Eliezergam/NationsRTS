-- Dibujo de la vegetación y las rocas de la batalla con 3DreamEngine, con el
-- estilo y las optimizaciones de la prueba de estrés de Camila
-- (batalla/pruebas_estilo/vegetacion_grande.lua):
--
-- - Pinos y abetos: los pinos de ramas de planos (estilo/pino.lua) con tres
--   detalles: completo hasta `calidad.pinoCompleto` m, simplificado hasta
--   `calidad.pinoSimple` m e impostor horneado (estilo/impostor.lua) hasta
--   `calidad.impostor` m.
-- - Rocas (estilo/roca.lua, tres detalles), matas de hierba (estilo/matas.lua,
--   dos detalles) y arbustos (Matas.arbusto).
-- - Los demás árboles (roble, álamo, abedul, abeto nevado), las flores, las
--   cañas, los nenúfares y los cactus, con sus mallas de antes
--   (batalla/vegetacion.lua) y sus tres detalles.
--
-- Las copias salen de `suelo.copias` (batalla/colocacion.lua) y de la hierba
-- que se genera por baldosas al acercarse la cámara. Cada copia se escribe una
-- vez, en memoria FFI, con su giro, su posición y su tono (15 flotantes, el
-- formato de instancias_tono.lua). Se reparten en celdas de 30 m; en cada
-- cuadro en que la cámara se mueve, las celdas se recortan por distancia y
-- por el frustum de la cámara (planos normalizados, como visibilidad.lua) y
-- las que quedan copian sus copias a los lotes FFI (estilo/lote_rapido.lua)
-- del detalle que toca. Con la cámara quieta no se rehace nada.
--
-- Sombras: solo las copias a menos de `calidad.sombra` m proyectan sombra, y
-- lo hacen desde lotes aparte que no se dibujan (soloSombra), ordenados por
-- la cascada del sol en que caen (estilo/sombra_cascadas.lua). Los
-- impostores, las matas, las flores y los arbustos no proyectan sombra.
--
-- Los árboles derribados (Suelo:derribarArbol) cambian su matriz y su tono en
-- la copia: se reescribe esa copia y se amplía el volumen de su celda.

local ffi = require('ffi')
local Vegetacion = require('batalla.vegetacion')
local Conversor = require('batalla.dream.conversor')
local Colocacion = require('batalla.colocacion')
local InstanciasTono = require('batalla.dream.instancias_tono')
local LoteRapido = require('batalla.dream.estilo.lote_rapido')
local Recursos = require('batalla.dream.estilo.recursos')
local Calidad = require('batalla.dream.calidad')
local ArbolesPack = require('batalla.dream.estilo.arboles_pack')

-- Dos lotes (tronco y copa) que se copian juntos, como uno: los árboles del
-- pack (arboles_pack.lua) tienen dos materiales.
local Par = {}
Par.__index = Par
function Par:copiar(fuente, indice)
    self.a:copiar(fuente, indice)
    self.b:copiar(fuente, indice)
end
function Par:copiarBloque(ptr, n)
    self.a:copiarBloque(ptr, n)
    self.b:copiarBloque(ptr, n)
end
function Par:clase(c)
    self.a:clase(c)
    self.b:clase(c)
end
--- Multiplica por `f` el giro y la escala de la última copia (los 9 primeros flotantes).
function Par:escalarUltima(f, ancho)
    for _, l in ipairs({ self.a, self.b }) do
        local destino = l.puntero + (l.cantidad - 1) * ancho
        for k = 0, 8 do
            destino[k] = destino[k] * f
        end
    end
end

local VegetacionDream = {}
VegetacionDream.__index = VegetacionDream

-- Hierba sin «spawn» (el dueño, 19-nov: «se ven como que spawnean las
-- cosas»), como la hierba de los motores (Unreal, Ghost of Tsushima): nunca
-- sale ni se va de golpe. Más allá del detalle de cerca cada mata tiene su
-- propia distancia (de su hash): queda menos hierba cuanto más lejos, hasta
-- `mataQuedaLejos`, y cada una se encoge hasta cero antes de irse
-- (`mataFundido`, en fracción de densidad); las que quedan crecen un poco
-- (`mataCompensa`) para que la densidad parezca la misma. En el último
-- `bordeFundido` de su alcance, matas y flores se encogen hasta cero.
VegetacionDream.mataQuedaLejos = 0.125
VegetacionDream.mataFundido = 0.1
VegetacionDream.mataCompensa = 0.35
VegetacionDream.bordeFundido = 0.2

local function suave(x)
    if x <= 0 then
        return 0
    elseif x >= 1 then
        return 1
    end
    return x * x * (3 - 2 * x)
end

--- Multiplica por `f` el giro y la escala de la última copia de `lote`.
local function encogerUltima(lote, f, ancho)
    if lote.escalarUltima then
        lote:escalarUltima(f, ancho)
        return
    end
    local destino = lote.puntero + (lote.cantidad - 1) * ancho
    for k = 0, 8 do
        destino[k] = destino[k] * f
    end
end

local M = 10 -- px por metro
local ANCHO = InstanciasTono.flotantes

VegetacionDream.celda = 300 -- px (30 m)
-- Celdas por lado de un bloque (240 m): lo lejano se copia por bloques.
VegetacionDream.celdasPorBloque = 8

-- Grupo de dibujo de cada especie.
local GRUPO = {
    Pino = 'pino',
    Abeto = 'pino',
    AbetoNevado = 'arbol',
    Roble = 'arbol',
    Alamo = 'arbol',
    Abedul = 'arbol',
    Arbusto = 'arbusto',
    Mata = 'mata',
    MataSeca = 'mata',
    Flor1 = 'flor',
    Flor2 = 'flor',
    Flor3 = 'flor',
    Flor4 = 'flor',
    Canas = 'canas',
    Roca = 'roca',
    Nenufar = 'fijo',
    Cactus = 'fijo',
    Contenedor = 'fijo',
    Bidon = 'fijo',
    Caja = 'fijo',
}
VegetacionDream.grupo = GRUPO
-- `seco`: los árboles muertos (la copia lleva `forma`, batalla/colocacion.lua).
local GRUPOS = { 'pino', 'seco', 'arbol', 'roca', 'arbusto', 'mata', 'flor', 'canas', 'fijo' }

-- Hasta dónde (m) se ven los grupos que no dependen de la calidad.
local HASTA = { canas = 250, fijo = 400 }
-- Rocas grandes (escala > 1,4): hasta 180 m. Antes llegaban a 900 m y se
-- veían (con el detalle más simple) sobre las montañas, donde parecían
-- manchas horribles (el dueño, 2026-11-14). Ahora se cortan junto con
-- las rocas normales.
local ROCA_GRANDE_HASTA = 180
-- Detalle de las rocas: completo hasta 40 m, medio hasta 150 m.
local ROCA_DETALLE = { 40, 150 }
-- Árboles de antes lejos (detalle 2): queda uno de cada tres, algo mayores.
local ARBOL_LEJOS_QUEDAN = 35
local ARBOL_LEJOS_ESCALA = 1.15

--- Radio (m, antes de la escala de la copia) que abarca cada grupo desde su
-- base: la altura del árbol más alto (de pie o caído).
local ALCANCE = { pino = 14.5, seco = 18, arbol = 15, roca = 2, arbusto = 2.2, mata = 1.8, flor = 1.2, canas = 2.4, fijo = 3.6 }
VegetacionDream.alcance = ALCANCE

function VegetacionDream.nueva(dream, conversor, suelo, opciones)
    opciones = opciones or {}
    local self = setmetatable({}, VegetacionDream)
    local inicio = love.timer.getTime()
    self.dream = dream
    self.conversor = conversor
    self.suelo = suelo
    self.colocacion = suelo.colocacion
    self.calidad = opciones.calidad or Calidad.actual()
    self.sombras = opciones.sombras
    self.recursos = Recursos.de(dream, suelo.terreno.semilla)
    self.lotes = {}
    self.cuenta = {}
    self:crearLotes()
    self:crearCeldas()
    self:crearAlmacen(#suelo.copias + 4096)
    for _, c in ipairs(suelo.copias) do
        self:agregar(c)
    end
    self.hierbaHecha = {}
    -- Toda la hierba de una vez, al cargar: generarla al acercarse la cámara
    -- costaba de 6 a 27 ms por baldosa en el cuadro en que tocaba.
    self:prepararHierba(opciones.informar)
    self:cerrarCeldas()
    self.sucio = true
    self.rehechos = 0
    self.msRehacer = 0
    self.dibujos = 0
    self.planos = {}
    print(
        string.format(
            'VEGETACION %d copias en %d celdas (%d baldosas de hierba en %.2f s), lotes en %.2f s',
            self.n,
            self.celdasPorLado * self.celdasPorLado,
            self.baldosasHierba or 0,
            self.segundosHierba or 0,
            love.timer.getTime() - inicio
        )
    )
    return self
end

--- Matas y flores de todas las baldosas al alcance de las matas desde
-- algún punto del límite (la cámara no sale de él). Las copias se escriben
-- en la memoria FFI y sus tablas se sueltan: no las vuelve a pedir nadie.
-- `informar(t)` (opcional) recibe la fracción hecha.
function VegetacionDream:prepararHierba(informar)
    local inicio = love.timer.getTime()
    local colocacion = self.colocacion
    local s = self.suelo
    local lado = Colocacion.baldosa
    local alcance = (self.calidad.matas + 20) * M
    local limite = s.limite
    local pendientes = {}
    for by = 0, colocacion.baldosas - 1 do
        for bx = 0, colocacion.baldosas - 1 do
            local x0, y0 = s.x0 + bx * lado, s.y0 + by * lado
            local dx = math.max(x0 - limite.cx, 0, limite.cx - (x0 + lado))
            local dy = math.max(y0 - limite.cy, 0, limite.cy - (y0 + lado))
            if math.sqrt(dx * dx + dy * dy) < limite.radio + alcance then
                pendientes[#pendientes + 1] = bx * 1000 + by
            end
        end
    end
    for n, clave in ipairs(pendientes) do
        local lista = colocacion:hierbaDeBaldosa(math.floor(clave / 1000), clave % 1000)
        for _, c in ipairs(lista) do
            self:agregar(c)
        end
        colocacion.hierbas[clave] = nil
        self.hierbaHecha[clave] = true
        if informar and n % 8 == 0 then
            informar(n / #pendientes)
        end
    end
    self.baldosasHierba = #pendientes
    self.segundosHierba = love.timer.getTime() - inicio
end

-- Lotes ---------------------------------------------------------------------------------------

--- Lote nuevo de la malla `malla` (de Dream). `tipo` es para la cuenta.
function VegetacionDream:lote(malla, triangulos, tipo, sombra)
    local l = LoteRapido.nuevo(self.dream, malla, 64, {
        sinSombra = not sombra,
        soloSombra = sombra,
        triangulos = triangulos,
        tipo = sombra and 'sombra' or tipo,
    })
    self.lotes[#self.lotes + 1] = l
    return l
end

--- Par de lotes (tronco y follaje) de un pino, para dibujar o para sombra.
function VegetacionDream:lotePino(pieza, tipo, sombra)
    local triangulos = pieza.tronco.triangulos + pieza.follaje.triangulos
    return {
        tronco = self:lote(pieza.tronco.malla, 0, tipo, sombra),
        follaje = self:lote(pieza.follaje.malla, triangulos, tipo, sombra),
    }
end

function VegetacionDream:crearLotes()
    local r = self.recursos
    -- Pinos: índice de variante 1..3 = Pino y 4..6 = Abeto.
    self.pino = { completo = {}, simple = {}, impostor = {}, sombraCompleto = {}, sombraSimple = {} }
    for especieIndice, especie in ipairs({ 'Pino', 'Abeto' }) do
        for v, variante in ipairs(r.pinos[especie]) do
            local k = (especieIndice - 1) * Recursos.variantesPino + v
            local p = self.pino
            p.completo[k] = self:lotePino(variante[1], 'pino completo')
            p.simple[k] = self:lotePino(variante[2], 'pino simple')
            p.sombraCompleto[k] = self:lotePino(variante[1], 'sombra', true)
            p.sombraSimple[k] = self:lotePino(variante[2], 'sombra', true)
            p.impostor[k] = self:lote(variante.impostor.malla, variante.impostor.triangulos, 'impostor')
        end
    end
    self.roca = {}
    self.rocaSombra = {}
    for v = 1, Recursos.variantesRoca do
        self.roca[v], self.rocaSombra[v] = {}, {}
        for detalle = 1, 3 do
            local pieza = r.rocas[v][detalle]
            self.roca[v][detalle] = self:lote(pieza.malla, pieza.triangulos, 'roca')
            self.rocaSombra[v][detalle] = self:lote(pieza.malla, 0, 'sombra', true)
        end
    end
    self.mata = {}
    for detalle = 1, 2 do
        self.mata[detalle] = {}
        for v = 1, Recursos.variantesMata do
            local pieza = r.matas[detalle][v]
            self.mata[detalle][v] = self:lote(pieza.malla, pieza.triangulos, 'mata')
        end
    end
    -- Árboles muertos: por forma y variante, dos detalles, impostor (los de
    -- pie) y lotes de sombra.
    self.seco = {}
    for k, entrada in pairs(r.muertos) do
        local lotes = {}
        for detalle = 1, 2 do
            local pieza = entrada[detalle]
            lotes[detalle] = self:lote(pieza.malla, pieza.triangulos, 'seco')
            lotes['sombra' .. detalle] = self:lote(pieza.malla, 0, 'sombra', true)
        end
        if entrada.impostor then
            lotes.impostor = self:lote(entrada.impostor.malla, entrada.impostor.triangulos, 'impostor seco')
        end
        self.seco[k] = lotes
    end
    self.arbusto = {}
    for v = 1, Recursos.variantesArbusto do
        local pieza = r.arbustos[v]
        self.arbusto[v] = self:lote(pieza.malla, pieza.triangulos, 'arbusto')
    end
    -- Especies de antes: un lote por especie, detalle y variante (y otro de
    -- sombra para los árboles).
    self.antiguos = {}
    self.antiguosSombra = {}
    for _, e in ipairs(Vegetacion.especies) do
        local grupo = GRUPO[e.nombre]
        local pack = ArbolesPack.especies[e.nombre]
        if pack then
            -- Árboles del pack StyleHex: variante v -> modelo del pack.
            self.antiguos[e.indice] = {}
            self.antiguosSombra[e.indice] = {}
            for lod = 0, e.lods - 1 do
                self.antiguos[e.indice][lod] = {}
                self.antiguosSombra[e.indice][lod] = {}
                for v = 1, e.variantes do
                    local pieza = r.arbolesPack[pack.modelos[(v - 1) % #pack.modelos + 1]][lod + 1]
                    local tri = pieza.tronco.triangulos + pieza.copa.triangulos
                    self.antiguos[e.indice][lod][v] = setmetatable({
                        a = self:lote(pieza.tronco.malla, 0, grupo),
                        b = self:lote(pieza.copa.malla, tri, grupo),
                    }, Par)
                    self.antiguosSombra[e.indice][lod][v] = setmetatable({
                        a = self:lote(pieza.tronco.malla, 0, 'sombra', true),
                        b = self:lote(pieza.copa.malla, 0, 'sombra', true),
                    }, Par)
                end
            end
        elseif ArbolesPack.restos[e.nombre] then
            -- Restos abandonados: un detalle, con sombra.
            self.antiguos[e.indice] = { [0] = {} }
            self.antiguosSombra[e.indice] = { [0] = {} }
            for v = 1, e.variantes do
                local pieza = r.restos[e.nombre][v]
                self.antiguos[e.indice][0][v] = self:lote(pieza.malla, pieza.triangulos, grupo)
                self.antiguosSombra[e.indice][0][v] = self:lote(pieza.malla, 0, 'sombra', true)
            end
        elseif ArbolesPack.flores[e.nombre] then
            -- Flores del pack StyleHex en lugar de las de polígonos.
            local pieza = r.floresPack[ArbolesPack.flores[e.nombre]]
            self.antiguos[e.indice] = { [0] = {} }
            self.antiguosSombra[e.indice] = { [0] = {} }
            for v = 1, e.variantes do
                self.antiguos[e.indice][0][v] = self:lote(pieza.malla, pieza.triangulos, grupo)
            end
        elseif not e.estilo then
            local proto = self.suelo.prototipos[e.nombre]
            self.antiguos[e.indice] = {}
            self.antiguosSombra[e.indice] = {}
            for lod = 0, e.lods - 1 do
                self.antiguos[e.indice][lod] = {}
                self.antiguosSombra[e.indice][lod] = {}
                for v = 1, e.variantes do
                    local malla = self.conversor:desdeMallaLocal(proto[lod][v], {
                        nombre = 'vegetacion_' .. e.nombre,
                        rugosidad = 0.88,
                    })
                    local triangulos = proto[lod][v]:getVertexCount() / 3
                    self.antiguos[e.indice][lod][v] = self:lote(malla, triangulos, grupo)
                    if grupo == 'arbol' or grupo == 'fijo' then
                        self.antiguosSombra[e.indice][lod][v] = self:lote(malla, 0, 'sombra', true)
                    end
                end
            end
        end
    end
    if self.sombras then
        self.sombras:registrar(self.lotes)
    end
end

-- Almacén de copias ---------------------------------------------------------------------------

--- Memoria de las copias: 15 flotantes de dibujo y los datos del recorte.
function VegetacionDream:crearAlmacen(capacidad)
    self.n = 0
    self.capacidadCopias = capacidad
    self.datos = ffi.new('float[?]', capacidad * ANCHO)
    self.px = ffi.new('float[?]', capacidad)
    self.py = ffi.new('float[?]', capacidad)
    self.variante = ffi.new('uint8_t[?]', capacidad)
    self.hash = ffi.new('uint8_t[?]', capacidad)
    self.grande = ffi.new('uint8_t[?]', capacidad)
    self.especie = ffi.new('uint8_t[?]', capacidad)
end

local function ampliar(viejo, tipo, cantidad, nueva)
    local nuevo = ffi.new(tipo .. '[?]', nueva)
    ffi.copy(nuevo, viejo, cantidad * ffi.sizeof(tipo))
    return nuevo
end

function VegetacionDream:crecerAlmacen()
    local nueva = self.capacidadCopias * 2
    local n = self.n
    self.datos = ampliar(self.datos, 'float', n * ANCHO, nueva * ANCHO)
    self.px = ampliar(self.px, 'float', n, nueva)
    self.py = ampliar(self.py, 'float', n, nueva)
    self.variante = ampliar(self.variante, 'uint8_t', n, nueva)
    self.hash = ampliar(self.hash, 'uint8_t', n, nueva)
    self.grande = ampliar(self.grande, 'uint8_t', n, nueva)
    self.especie = ampliar(self.especie, 'uint8_t', n, nueva)
    self.capacidadCopias = nueva
end

--- Escribe la copia `c` en la posición `k` del almacén: columnas del giro en
-- ejes de Dream (y arriba), posición y tono. Las rocas del estilo solo giran
-- sobre la vertical (son semiesferas asentadas en el suelo).
function VegetacionDream:escribir(k, c, grupo)
    local p = self.datos + k * ANCHO
    local m = c.m
    local escala = Conversor.escala
    if grupo == 'roca' then
        local giro = math.atan2(m[4], m[1])
        local s = c.escala * 1.1
        local cg, sg = math.cos(giro) * s, math.sin(giro) * s
        p[0], p[1], p[2] = cg, 0, -sg
        p[3], p[4], p[5] = 0, s, 0
        p[6], p[7], p[8] = sg, 0, cg
    else
        -- P(c0), P(c2), P(c1): el cambio de ejes del conversor a cada lado.
        p[0], p[1], p[2] = m[1], m[7], m[4]
        p[3], p[4], p[5] = m[3], m[9], m[6]
        p[6], p[7], p[8] = m[2], m[8], m[5]
    end
    p[9], p[10], p[11] = (c.x - self.suelo.cx) * escala, c.z * escala, (c.y - self.suelo.cy) * escala
    local t1, t2, t3 = c.t1, c.t2, c.t3
    if grupo == 'mata' then
        -- La hierba del estilo ya trae su brillo: del tono solo el matiz.
        local media = (t1 + t2 + t3) / 3
        t1, t2, t3 = t1 / media, t2 / media, t3 / media
    end
    p[12], p[13], p[14] = t1, t2, t3
end

--- Grupo de dibujo de la copia `c` (los árboles muertos, `seco`).
local function grupoDe(c)
    if c.forma then
        return 'seco'
    end
    return GRUPO[Vegetacion.especies[c.e].nombre]
end
VegetacionDream.grupoDe = grupoDe

--- Añade la copia `c` al almacén y a su celda.
function VegetacionDream:agregar(c)
    local especie = Vegetacion.especies[c.e]
    local grupo = grupoDe(c)
    -- Del grupo `arbol` solo se dibujan los del pack StyleHex (Roble ->
    -- frondoso, Abedul -> abedul; arboles_pack.lua). Álamo y AbetoNevado usan
    -- los prototipos antiguos (bolas poligonales): siguen sin dibujarse.
    -- Sin el pack, Roble y Abedul con su prototipo (ArbolesPack.respaldo).
    local delPack = ArbolesPack.especies[especie.nombre] or ArbolesPack.respaldo[especie.nombre]
    if grupo == 'arbol' and not delPack then
        return
    end
    -- Sin el pack tampoco las flores: las de polígonos de antes parecían
    -- cristales (las quitó el pack, el dueño 19-nov).
    if grupo == 'flor' and not ArbolesPack.hayArbustos then
        return
    end
    -- Plantas de polígonos hechas por código sin sustituto del pack (cañas,
    -- nenúfares y cactus): no se dibujan (el dueño, 19-nov: «quitamos toda
    -- planta rara»).
    if grupo == 'canas' or (grupo == 'fijo' and especie.nombre ~= 'Roca' and not ArbolesPack.restos[especie.nombre]) then
        return
    end
    if self.n >= self.capacidadCopias then
        self:crecerAlmacen()
    end
    local k = self.n
    self.n = k + 1
    self:escribir(k, c, grupo)
    self.px[k], self.py[k] = c.x, c.y
    self.hash[k] = c.hash
    self.especie[k] = c.e
    self.grande[k] = (grupo == 'roca' and c.escala > 1.4) and 1 or 0
    local v = c.v
    if grupo == 'pino' then
        v = (especie.nombre == 'Abeto' and Recursos.variantesPino or 0) + (c.v - 1) % Recursos.variantesPino + 1
    elseif grupo == 'seco' then
        v = (Vegetacion.porForma[c.forma].indice - 1) * Vegetacion.variantesForma + c.fv
    elseif grupo == 'roca' then
        v = (c.v - 1) % Recursos.variantesRoca + 1
    elseif grupo == 'mata' then
        v = (especie.nombre == 'MataSeca' and 1 or 2) + ((c.v - 1) % 2) * 2
    elseif grupo == 'arbusto' then
        v = (c.v - 1) % Recursos.variantesArbusto + 1
    end
    self.variante[k] = v
    c.indiceDream = k
    self.cuenta[grupo] = (self.cuenta[grupo] or 0) + 1
    local celda = self:celdaDe(c.x, c.y)
    local lista = celda[grupo]
    lista[#lista + 1] = k
    celda.sucia = true
    celda.zMin = math.min(celda.zMin, c.z)
    celda.zMax = math.max(celda.zMax, c.z)
    local escala = math.max(c.escala or 1, c.escalaZ or 1)
    celda.alcance = math.max(celda.alcance, ALCANCE[grupo] * escala * M)
    celda.hay[grupo] = true
end

-- Celdas --------------------------------------------------------------------------------------

function VegetacionDream:crearCeldas()
    local s = self.suelo
    local tam = VegetacionDream.celda
    local n = math.ceil(s.lado / tam)
    self.celdasPorLado = n
    self.celdas = {}
    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local celda = {
                i = i,
                j = j,
                x = s.x0 + (i + 0.5) * tam,
                y = s.y0 + (j + 0.5) * tam,
                zMin = math.huge,
                zMax = -math.huge,
                alcance = 0,
                hay = {},
            }
            for _, grupo in ipairs(GRUPOS) do
                celda[grupo] = {}
            end
            self.celdas[j * n + i + 1] = celda
        end
    end
end

function VegetacionDream:celdaDe(x, y)
    local s = self.suelo
    local tam = VegetacionDream.celda
    local n = self.celdasPorLado
    local i = math.max(0, math.min(n - 1, math.floor((x - s.x0) / tam)))
    local j = math.max(0, math.min(n - 1, math.floor((y - s.y0) / tam)))
    return self.celdas[j * n + i + 1]
end

--- Esfera de cada celda (px): su columna de copias con el alcance de la
-- planta más grande, de pie o caída. Solo quedan en la lista las que tienen
-- algo. Las celdas se juntan en bloques de 8 x 8 (240 m) con su esfera y las
-- copias de todas sus celdas. Solo se rehace lo que cambió (`sucia`).
function VegetacionDream:cerrarCeldas()
    local medio = VegetacionDream.celda * 0.5 * math.sqrt(2)
    local porBloque = VegetacionDream.celdasPorBloque
    local nb = math.ceil(self.celdasPorLado / porBloque)
    local tam = VegetacionDream.celda * porBloque
    local s = self.suelo
    self.llenas = self.llenas or {}
    self.bloques = self.bloques or {}
    self.bloquesLlenos = self.bloquesLlenos or {}
    local sucios = {}
    for _, celda in ipairs(self.celdas) do
        if celda.sucia and celda.zMax >= celda.zMin then
            celda.sucia = false
            local h = medio + celda.alcance
            local v = (celda.zMax - celda.zMin) * 0.5 + celda.alcance
            celda.z = (celda.zMin + celda.zMax) * 0.5
            celda.radio = math.sqrt(h * h + v * v)
            celda.paquetes = nil
            local b = math.floor(celda.j / porBloque) * nb + math.floor(celda.i / porBloque) + 1
            local bloque = self.bloques[b]
            if not bloque then
                local bi, bj = (b - 1) % nb, math.floor((b - 1) / nb)
                bloque = {
                    hay = {},
                    celdas = {},
                    orden = b,
                    x = s.x0 + (bi + 0.5) * tam,
                    y = s.y0 + (bj + 0.5) * tam,
                }
                self.bloques[b] = bloque
                self.bloquesLlenos[#self.bloquesLlenos + 1] = bloque
            end
            if not celda.bloque then
                celda.bloque = bloque
                bloque.celdas[#bloque.celdas + 1] = celda
                self.llenas[#self.llenas + 1] = celda
            end
            sucios[bloque] = true
        end
    end
    table.sort(self.bloquesLlenos, function(x, y)
        return x.orden < y.orden
    end)
    local medioBloque = tam * 0.5 * math.sqrt(2)
    for _, bloque in ipairs(self.bloquesLlenos) do
        if sucios[bloque] then
            bloque.zMin, bloque.zMax, bloque.alcance = math.huge, -math.huge, 0
            bloque.paquetes = nil
            for _, grupo in ipairs(GRUPOS) do
                bloque[grupo] = {}
                bloque.hay[grupo] = nil
            end
            for _, celda in ipairs(bloque.celdas) do
                bloque.zMin = math.min(bloque.zMin, celda.zMin)
                bloque.zMax = math.max(bloque.zMax, celda.zMax)
                bloque.alcance = math.max(bloque.alcance, celda.alcance)
                for _, grupo in ipairs(GRUPOS) do
                    if celda.hay[grupo] then
                        bloque.hay[grupo] = true
                        local destino = bloque[grupo]
                        for _, k in ipairs(celda[grupo]) do
                            destino[#destino + 1] = k
                        end
                    end
                end
            end
            local h = medioBloque + bloque.alcance
            local v = (bloque.zMax - bloque.zMin) * 0.5 + bloque.alcance
            bloque.z = (bloque.zMin + bloque.zMax) * 0.5
            bloque.radio = math.sqrt(h * h + v * v)
        end
    end
end

-- Recorte -------------------------------------------------------------------------------------

--- Planos del frustum (px del juego, normalizados) de la matriz de vista y
-- proyección `m` (por filas): izquierda, derecha, abajo, arriba y cerca. El
-- lejano no hace falta: cada grupo tiene su distancia.
function VegetacionDream:actualizarPlanos(m)
    local planos = self.planos
    local k = 0
    for fila = 0, 2 do
        for _, signo in ipairs({ 1, -1 }) do
            if not (fila == 2 and signo == -1) then
                local a = m[13] + signo * m[fila * 4 + 1]
                local b = m[14] + signo * m[fila * 4 + 2]
                local c = m[15] + signo * m[fila * 4 + 3]
                local d = m[16] + signo * m[fila * 4 + 4]
                local largo = math.sqrt(a * a + b * b + c * c)
                if largo > 1e-12 then
                    k = k + 1
                    planos[k] = planos[k] or {}
                    local p = planos[k]
                    p[1], p[2], p[3], p[4] = a / largo, b / largo, c / largo, d / largo
                end
            end
        end
    end
    for extra = k + 1, #planos do
        planos[extra] = nil
    end
end

--- ¿Toca la esfera (x, y, z, radio) en px el frustum? Con `self.margen`
-- (seno de un ángulo), cada plano se abre ese ángulo hacia fuera: la esfera
-- se agranda en proporción a su distancia al ojo (`self.ojo`).
function VegetacionDream:enVista(x, y, z, radio)
    local margen = self.margen
    if margen and margen > 0 then
        local o = self.ojo
        local dx, dy, dz = x - o[1], y - o[2], z - o[3]
        radio = radio + margen * math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    for _, p in ipairs(self.planos) do
        if p[1] * x + p[2] * y + p[3] * z + p[4] < -radio then
            return false
        end
    end
    return true
end

-- Cada cuadro ---------------------------------------------------------------------------------

--- Hierba y flores: la baldosa de 200 m más cercana a la cámara que aún no
-- tenga, si está a menos del alcance de las matas (una por cuadro).
function VegetacionDream:hierbaPendiente(x, y)
    local colocacion = self.colocacion
    local baldosas = colocacion.baldosas
    local lado = Colocacion.baldosa
    local alcance = (self.calidad.matas + 20) * M
    local mejor, mejorD
    for by = 0, baldosas - 1 do
        for bx = 0, baldosas - 1 do
            local clave = bx * 1000 + by
            if not self.hierbaHecha[clave] then
                local x0, y0 = self.suelo.x0 + bx * lado, self.suelo.y0 + by * lado
                local dx = math.max(x0 - x, 0, x - (x0 + lado))
                local dy = math.max(y0 - y, 0, y - (y0 + lado))
                local d = math.sqrt(dx * dx + dy * dy)
                if d < alcance and (not mejorD or d < mejorD) then
                    mejor, mejorD = clave, d
                end
            end
        end
    end
    if not mejor then
        return false
    end
    self.hierbaHecha[mejor] = true
    local lista = colocacion:hierbaDeBaldosa(math.floor(mejor / 1000), mejor % 1000)
    for _, c in ipairs(lista) do
        self:agregar(c)
    end
    self:cerrarCeldas()
    return true
end

--- Árboles derribados desde el último cuadro: se reescriben sus copias.
function VegetacionDream:aplicarDerribos()
    local cambios = self.suelo.cambiosVegetacion
    if not cambios or #cambios == 0 then
        return false
    end
    for _, c in ipairs(cambios) do
        local k = c.indiceDream
        if k then
            local grupo = grupoDe(c)
            self:escribir(k, c, grupo)
            -- Caído, el árbol se tiende: su celda ya abarca su altura en
            -- horizontal (ALCANCE), pero la base puede bajar por la ladera.
            local celda = self:celdaDe(c.x, c.y)
            celda.zMin = math.min(celda.zMin, c.z - ALCANCE[grupo] * M)
            celda.sucia = true
        end
    end
    self.suelo.cambiosVegetacion = {}
    self:cerrarCeldas()
    return true
end

--- Rellena los lotes para la cámara. `matriz` es la de vista y proyección
-- de la cámara de la batalla (Camara:matrices) y (ex, ey, ez) el ojo en px.
--
-- El relleno cubre un frustum más ancho que la pantalla (`margenGiro` a cada
-- lado) y guarda desde dónde y hacia dónde se hizo: mientras la cámara no se
-- mueva más de `pasoOjo` ni gire más de la mitad del margen, lo rellenado
-- sigue cubriendo la pantalla y no se rehace (girar la vista cuesta poco).
function VegetacionDream:actualizar(ex, ey, ez, matriz)
    if matriz then
        self:medirGiro(matriz)
    end
    local cambio = self.sucio
    if self:aplicarDerribos() then
        cambio = true
    end
    if self:hierbaPendiente(ex, ey) then
        cambio = true
    end
    if matriz and self:camaraSeAleja(ex, ey, ez, matriz) then
        cambio = true
    end
    -- Un cuadro más tras rehacer: 3Dream recoloca las cascadas del sol un
    -- cuadro después, y las copias de sombra se clasifican con ellas.
    if cambio then
        self.otraVez = true
    elseif self.otraVez then
        self.otraVez = false
        cambio = true
    end
    if not cambio then
        return
    end
    self.sucio = false
    if matriz then
        -- Por delante del giro: el relleno mira hacia donde va la cámara y
        -- se ensancha lo mismo (batalla/dream/README.md, «Visibilidad»).
        local adelanto = math.max(
            -VegetacionDream.adelantoMaximo,
            math.min(VegetacionDream.adelantoMaximo, (self.giro or 0) * VegetacionDream.adelanto)
        )
        self.margenActual = VegetacionDream.margenGiro + math.abs(adelanto)
        self:actualizarPlanos(matriz)
        self:girarPlanos(adelanto, ex, ey, ez)
        self:guardarVista(ex, ey, ez, matriz, adelanto)
    end
    self:rellenar(ex, ey, ez)
end

VegetacionDream.margenGiro = math.rad(6)
VegetacionDream.pasoOjo = 15 -- px (1,5 m)
VegetacionDream.adelanto = 0.12 -- s de giro que se adelanta el relleno
VegetacionDream.adelantoMaximo = math.rad(12)

--- Velocidad de giro de la cámara alrededor de la vertical (rad/s, suavizada).
function VegetacionDream:medirGiro(m)
    local ahora = love.timer.getTime()
    local rumbo = math.atan2(m[14], m[13])
    if self.rumboPrevio and ahora > self.tiempoPrevio then
        local d = (rumbo - self.rumboPrevio + math.pi) % (2 * math.pi) - math.pi
        local giro = d / (ahora - self.tiempoPrevio)
        self.giro = (self.giro or 0) * 0.6 + giro * 0.4
    end
    self.rumboPrevio, self.tiempoPrevio = rumbo, ahora
end

--- Gira los planos del recorte `angulo` rad alrededor de la vertical que
-- pasa por el ojo (ex, ey, ez).
function VegetacionDream:girarPlanos(angulo, ex, ey, ez)
    if angulo == 0 then
        return
    end
    local c, s = math.cos(angulo), math.sin(angulo)
    for _, p in ipairs(self.planos) do
        local a, b = p[1], p[2]
        local na, nb = a * c - b * s, a * s + b * c
        p[4] = p[4] + (a - na) * ex + (b - nb) * ey
        p[1], p[2] = na, nb
    end
end

--- Dirección de la mirada de la matriz de vista y proyección (su fila de w).
local function mirada(m)
    local fx, fy, fz = m[13], m[14], m[15]
    local largo = math.sqrt(fx * fx + fy * fy + fz * fz)
    return fx / largo, fy / largo, fz / largo
end

function VegetacionDream:guardarVista(ex, ey, ez, m, adelanto)
    local v = self.vista or {}
    self.vista = v
    v.x, v.y, v.z = ex, ey, ez
    v.fx, v.fy, v.fz = mirada(m)
    -- La dirección que cubre el relleno: la de la cámara girada el adelanto.
    adelanto = adelanto or 0
    local c, s = math.cos(adelanto), math.sin(adelanto)
    v.fx, v.fy = v.fx * c - v.fy * s, v.fx * s + v.fy * c
    v.margen = self.margenActual or VegetacionDream.margenGiro
    -- La proyección (campo y aspecto): si cambia la ventana, se rehace.
    v.px, v.py = m[1] * m[1] + m[2] * m[2] + m[3] * m[3], m[5] * m[5] + m[6] * m[6] + m[7] * m[7]
end

--- ¿Se ha salido la cámara de lo que cubre el último relleno?
function VegetacionDream:camaraSeAleja(ex, ey, ez, m)
    local v = self.vista
    if not v then
        return true
    end
    local dx, dy, dz = ex - v.x, ey - v.y, ez - v.z
    if dx * dx + dy * dy + dz * dz > VegetacionDream.pasoOjo ^ 2 then
        return true
    end
    -- Se rehace cuando a la vista le queda menos de medio margen fijo por
    -- cubrir (sin adelanto, como antes: al girar la mitad del margen).
    local fx, fy, fz = mirada(m)
    local holgura = (v.margen or VegetacionDream.margenGiro) - VegetacionDream.margenGiro * 0.5
    if fx * v.fx + fy * v.fy + fz * v.fz < math.cos(holgura) then
        return true
    end
    local px, py = m[1] * m[1] + m[2] * m[2] + m[3] * m[3], m[5] * m[5] + m[6] * m[6] + m[7] * m[7]
    return math.abs(px - v.px) > 1e-9 * px or math.abs(py - v.py) > 1e-9 * py
end

-- Paquetes por celda -------------------------------------------------------------------------

--- Paquetes de las copias de `grupo` en la celda: por especie y variante,
-- sus copias seguidas en memoria FFI, para copiarlas a un lote de una vez
-- cuando toda la celda cae en el mismo detalle. Los árboles de antes llevan
-- además el paquete de los que quedan lejos (ya agrandados) y las rocas el de
-- las grandes que se ven más allá de las pequeñas.
function VegetacionDream:paquetes(celda, grupo)
    local guardados = celda.paquetes
    if not guardados then
        guardados = {}
        celda.paquetes = guardados
    end
    local lista = guardados[grupo]
    if lista then
        return lista
    end
    local especie, variante, hash, grande = self.especie, self.variante, self.hash, self.grande
    local porClave, orden = {}, {}
    for _, k in ipairs(celda[grupo]) do
        local clave = especie[k] * 256 + variante[k]
        local p = porClave[clave]
        if not p then
            p = { e = especie[k], v = variante[k], n = 0, nLejos = 0, indices = {} }
            porClave[clave] = p
            orden[#orden + 1] = p
        end
        p.indices[#p.indices + 1] = k
        p.n = p.n + 1
        if
            (grupo == 'arbol' and hash[k] < ARBOL_LEJOS_QUEDAN) or (grupo == 'roca' and grande[k] == 1 and hash[k] < 50)
        then
            p.nLejos = p.nLejos + 1
        end
    end
    local datos = self.datos
    for _, p in ipairs(orden) do
        p.ptr = ffi.new('float[?]', p.n * ANCHO)
        if p.nLejos > 0 then
            p.lejos = ffi.new('float[?]', p.nLejos * ANCHO)
        end
        local j, l = 0, 0
        for _, k in ipairs(p.indices) do
            ffi.copy(p.ptr + j * ANCHO, datos + k * ANCHO, ANCHO * 4)
            j = j + 1
            local lejos = (grupo == 'arbol' and hash[k] < ARBOL_LEJOS_QUEDAN)
                or (grupo == 'roca' and grande[k] == 1 and hash[k] < 50)
            if lejos then
                local destino = p.lejos + l * ANCHO
                ffi.copy(destino, datos + k * ANCHO, ANCHO * 4)
                if grupo == 'arbol' then
                    for f = 0, 8 do
                        destino[f] = destino[f] * ARBOL_LEJOS_ESCALA
                    end
                end
                l = l + 1
            end
        end
        p.indices = nil
    end
    guardados[grupo] = orden
    return orden
end

--- ¿Cae todo el intervalo de distancias [d0, d1] entre los mismos cortes?
local function uniforme(cortes, d0, d1, grupo, c)
    if grupo == 'mata' and d1 > c.mataCerca then
        return false
    end
    -- Las flores del borde, una a una (se encogen al irse).
    if grupo == 'flor' and d1 > c.flor * (1 - VegetacionDream.bordeFundido) then
        return false
    end
    for _, c in ipairs(cortes) do
        if c > d0 and c <= d1 then
            return false
        end
    end
    return true
end

-- Cada cuadro: relleno -------------------------------------------------------------------------

--- Distancias (px) de este relleno y sus cuadrados.
function VegetacionDream:prepararDistancias()
    local q = self.calidad
    local c = self.distancias or {}
    self.distancias = c
    c.completo, c.simple, c.impostor = q.pinoCompleto * M, q.pinoSimple * M, q.impostor * M
    c.sombra = q.sombra * M
    -- Árboles del pack (el dueño, 19-nov: «igual que la hierba»): todo el
    -- detalle solo hasta 40 m; hasta 150 m su LOD2; más allá su LOD3 y solo
    -- uno de cada tres (ARBOL_LEJOS_QUEDAN).
    c.arbol0, c.arbol1 = math.min(q.arboles[1], 40) * M, math.min(q.arboles[2], 150) * M
    c.roca = q.rocas * M
    c.rocaGrande = ROCA_GRANDE_HASTA * M
    c.rocaDetalle1, c.rocaDetalle2 = ROCA_DETALLE[1] * M, ROCA_DETALLE[2] * M
    c.arbusto = q.arbustos * M
    c.matas = q.matas * M
    -- Solo de cerca con todo el detalle (el dueño, 19-nov); lejos, menos
    -- hojas por mata y menos matas (`mataRala`, `mataMuyRala`).
    c.mataCerca = math.min(q.matas * 0.32, 12) * M
    c.mataRala = q.matas * 0.4 * M
    c.mataMuyRala = q.matas * 0.7 * M
    c.flor = q.matas * 0.9 * M
    c.canas, c.fijo = HASTA.canas * M, HASTA.fijo * M
    c.lejos = math.max(c.impostor, c.rocaGrande, c.arbol1 * 3)
    -- Hasta dónde se ve cada grupo y los cortes de sus detalles.
    c.hasta = {
        pino = c.impostor,
        seco = c.impostor,
        arbol = c.lejos,
        roca = c.rocaGrande,
        arbusto = c.arbusto,
        mata = c.matas,
        flor = c.flor,
        canas = c.canas,
        fijo = c.fijo,
    }
    c.cortes = {
        pino = { c.completo, c.simple, c.impostor, c.sombra },
        seco = { c.completo, c.simple, c.impostor, c.sombra },
        arbol = { c.arbol0, c.arbol1, c.sombra },
        roca = { c.rocaDetalle1, c.rocaDetalle2, c.roca, c.rocaGrande, c.sombra },
        arbusto = { c.arbusto },
        -- Entre mataCerca y mataRala va entero; más allá, rala: una a una
        -- (ver `uniforme`), para saltarse matas.
        mata = { c.mataCerca, c.mataRala, c.matas },
        flor = { c.flor },
        canas = { c.canas, c.sombra },
        fijo = { c.fijo, c.sombra },
    }
    c.cuadrados = {}
    for clave, valor in pairs(c) do
        if type(valor) == 'number' then
            c.cuadrados[clave] = valor * valor
        end
    end
    return c
end

--- Todas las copias de `grupo` de `objeto` (una celda o un bloque) caen en el
-- mismo detalle, el de la distancia `d0` (px): se copian sus paquetes.
-- `clase` es la cascada de sombra del objeto entero.
function VegetacionDream:copiarUniforme(objeto, grupo, d0, clase)
    local c = self.distancias
    local sombra = d0 < c.sombra
    local paquetes = self:paquetes(objeto, grupo)
    if grupo == 'pino' then
        local p = self.pino
        local detallada = self.calidad.sombraDetallada and d0 < c.completo
        for _, paquete in ipairs(paquetes) do
            local v, ptr, n = paquete.v, paquete.ptr, paquete.n
            local pieza = d0 < c.completo and p.completo[v] or (d0 < c.simple and p.simple[v])
            if pieza then
                pieza.tronco:copiarBloque(ptr, n)
                pieza.follaje:copiarBloque(ptr, n)
            else
                p.impostor[v]:copiarBloque(ptr, n)
            end
            if sombra then
                local s = detallada and p.sombraCompleto[v] or p.sombraSimple[v]
                s.tronco:clase(clase)
                s.follaje:clase(clase)
                s.tronco:copiarBloque(ptr, n)
                s.follaje:copiarBloque(ptr, n)
            end
        end
    elseif grupo == 'seco' then
        local detalle = d0 < c.completo and 1 or (d0 < c.simple and 2 or nil)
        local detallada = self.calidad.sombraDetallada and d0 < c.completo
        for _, paquete in ipairs(paquetes) do
            local lotes = self.seco[paquete.v]
            if detalle then
                lotes[detalle]:copiarBloque(paquete.ptr, paquete.n)
            elseif lotes.impostor then
                lotes.impostor:copiarBloque(paquete.ptr, paquete.n)
            end
            if sombra then
                local s = detallada and lotes.sombra1 or lotes.sombra2
                s:clase(clase)
                s:copiarBloque(paquete.ptr, paquete.n)
            end
        end
    elseif grupo == 'arbol' then
        local lod = d0 < c.arbol0 and 0 or (d0 < c.arbol1 and 1 or 2)
        for _, paquete in ipairs(paquetes) do
            local e, v = paquete.e, paquete.v
            if lod < 2 then
                self.antiguos[e][lod][v]:copiarBloque(paquete.ptr, paquete.n)
            elseif paquete.nLejos > 0 then
                self.antiguos[e][2][v]:copiarBloque(paquete.lejos, paquete.nLejos)
            end
            if sombra then
                local s = self.antiguosSombra[e][math.max(lod, 1)][v]
                s:clase(clase)
                s:copiarBloque(paquete.ptr, paquete.n)
            end
        end
    elseif grupo == 'roca' then
        local detalle = d0 < c.rocaDetalle1 and 1 or (d0 < c.rocaDetalle2 and 2 or 3)
        for _, paquete in ipairs(paquetes) do
            local v = paquete.v
            if d0 < c.roca then
                self.roca[v][detalle]:copiarBloque(paquete.ptr, paquete.n)
                if sombra then
                    local s = self.rocaSombra[v][math.max(detalle, 2)]
                    s:clase(clase)
                    s:copiarBloque(paquete.ptr, paquete.n)
                end
            elseif paquete.nLejos > 0 then
                self.roca[v][detalle]:copiarBloque(paquete.lejos, paquete.nLejos)
            end
        end
    elseif grupo == 'arbusto' then
        for _, paquete in ipairs(paquetes) do
            self.arbusto[paquete.v]:copiarBloque(paquete.ptr, paquete.n)
        end
    elseif grupo == 'mata' then
        local detalle = d0 < c.mataCerca and 1 or 2
        for _, paquete in ipairs(paquetes) do
            self.mata[detalle][paquete.v]:copiarBloque(paquete.ptr, paquete.n)
        end
    else
        -- Flores, cañas y fijos: un solo detalle; cañas y fijos con sombra.
        for _, paquete in ipairs(paquetes) do
            local e, v = paquete.e, paquete.v
            self.antiguos[e][0][v]:copiarBloque(paquete.ptr, paquete.n)
            local s = self.antiguosSombra[e][0][v]
            if s and sombra then
                s:clase(clase)
                s:copiarBloque(paquete.ptr, paquete.n)
            end
        end
    end
end

--- Cascada del sol de la copia `k` con radio `radio` (m). Fuera del bucle:
-- una función creada dentro corta las trazas de LuaJIT (FNEW).
local function cascada(sombras, datos, k, radio)
    if not sombras then
        return 3
    end
    local base = k * ANCHO
    return sombras:clase(datos[base + 9] * 10, datos[base + 10] * 10, datos[base + 11] * 10, radio)
end

--- Las copias de `grupo` de la celda, una a una con su distancia a (ex, ey).
function VegetacionDream:copiarUnaAUna(celda, grupo, ex, ey)
    local c = self.distancias
    local q2 = c.cuadrados
    local datos, px, py = self.datos, self.px, self.py
    local variante, especie, hash, grande = self.variante, self.especie, self.hash, self.grande
    local sombras = self.sombras
    if grupo == 'pino' then
        local p = self.pino
        local detallada = self.calidad.sombraDetallada
        for _, k in ipairs(celda.pino) do
            local ax, ay = px[k] - ex, py[k] - ey
            local d2 = ax * ax + ay * ay
            local v = variante[k]
            if d2 < q2.completo then
                p.completo[v].tronco:copiar(datos, k)
                p.completo[v].follaje:copiar(datos, k)
            elseif d2 < q2.simple then
                p.simple[v].tronco:copiar(datos, k)
                p.simple[v].follaje:copiar(datos, k)
            elseif d2 < q2.impostor then
                p.impostor[v]:copiar(datos, k)
            end
            if d2 < q2.sombra then
                local s = (detallada and d2 < q2.completo) and p.sombraCompleto[v] or p.sombraSimple[v]
                local clase = cascada(sombras, datos, k, 12)
                s.tronco:clase(clase)
                s.follaje:clase(clase)
                s.tronco:copiar(datos, k)
                s.follaje:copiar(datos, k)
            end
        end
    elseif grupo == 'seco' then
        local detallada = self.calidad.sombraDetallada
        for _, k in ipairs(celda.seco) do
            local ax, ay = px[k] - ex, py[k] - ey
            local d2 = ax * ax + ay * ay
            local lotes = self.seco[variante[k]]
            if d2 < q2.completo then
                lotes[1]:copiar(datos, k)
            elseif d2 < q2.simple then
                lotes[2]:copiar(datos, k)
            elseif d2 < q2.impostor and lotes.impostor then
                lotes.impostor:copiar(datos, k)
            end
            if d2 < q2.sombra then
                local s = (detallada and d2 < q2.completo) and lotes.sombra1 or lotes.sombra2
                s:clase(cascada(sombras, datos, k, 12))
                s:copiar(datos, k)
            end
        end
    elseif grupo == 'arbol' then
        for _, k in ipairs(celda.arbol) do
            local ax, ay = px[k] - ex, py[k] - ey
            local d2 = ax * ax + ay * ay
            local e, v = especie[k], variante[k]
            local lod = d2 < q2.arbol0 and 0 or (d2 < q2.arbol1 and 1 or 2)
            if lod < 2 or hash[k] < ARBOL_LEJOS_QUEDAN then
                local lote = self.antiguos[e][lod][v]
                lote:copiar(datos, k)
                if lod == 2 then
                    -- Lejos quedan menos: los que quedan, algo mayores.
                    if lote.escalarUltima then
                        lote:escalarUltima(ARBOL_LEJOS_ESCALA, ANCHO)
                    else
                        local destino = lote.puntero + (lote.cantidad - 1) * ANCHO
                        for f = 0, 8 do
                            destino[f] = destino[f] * ARBOL_LEJOS_ESCALA
                        end
                    end
                end
            end
            if d2 < q2.sombra then
                local s = self.antiguosSombra[e][math.max(lod, 1)][v]
                s:clase(cascada(sombras, datos, k, 10))
                s:copiar(datos, k)
            end
        end
    elseif grupo == 'roca' then
        for _, k in ipairs(celda.roca) do
            local ax, ay = px[k] - ex, py[k] - ey
            local d2 = ax * ax + ay * ay
            local visible = d2 < q2.roca
            if not visible and grande[k] == 1 and d2 < q2.rocaGrande then
                visible = hash[k] < 50
            end
            if visible then
                local detalle = d2 < q2.rocaDetalle1 and 1 or (d2 < q2.rocaDetalle2 and 2 or 3)
                local v = variante[k]
                self.roca[v][detalle]:copiar(datos, k)
                if d2 < q2.sombra then
                    local s = self.rocaSombra[v][math.max(detalle, 2)]
                    s:clase(cascada(sombras, datos, k, 4))
                    s:copiar(datos, k)
                end
            end
        end
    elseif grupo == 'arbusto' then
        for _, k in ipairs(celda.arbusto) do
            local ax, ay = px[k] - ex, py[k] - ey
            if ax * ax + ay * ay < q2.arbusto then
                self.arbusto[variante[k]]:copiar(datos, k)
            end
        end
    elseif grupo == 'mata' then
        for _, k in ipairs(celda.mata) do
            local ax, ay = px[k] - ex, py[k] - ey
            local d2 = ax * ax + ay * ay
            if d2 < q2.mataCerca then
                self.mata[1][variante[k]]:copiar(datos, k)
            elseif d2 < q2.matas then
                local d = math.sqrt(d2)
                local f = (d - c.mataCerca) / (c.matas - c.mataCerca)
                local queda = 1 - (1 - VegetacionDream.mataQuedaLejos) * suave(f)
                local umbral = (hash[k] + 0.5) / 100
                if umbral < queda then
                    local lote = self.mata[2][variante[k]]
                    lote:copiar(datos, k)
                    local escala = math.min(1, (queda - umbral) / VegetacionDream.mataFundido)
                    escala = escala * (1 + VegetacionDream.mataCompensa * (1 - queda))
                    local borde = (d / c.matas - 1 + VegetacionDream.bordeFundido) / VegetacionDream.bordeFundido
                    escala = escala * (1 - suave(borde))
                    if escala ~= 1 then
                        encogerUltima(lote, escala, ANCHO)
                    end
                end
            end
        end
    else
        local limite2 = q2[grupo]
        for _, k in ipairs(celda[grupo]) do
            local ax, ay = px[k] - ex, py[k] - ey
            local d2 = ax * ax + ay * ay
            if d2 < limite2 then
                local e, v = especie[k], variante[k]
                local lote = self.antiguos[e][0][v]
                lote:copiar(datos, k)
                if grupo == 'flor' then
                    local borde = (math.sqrt(d2 / limite2) - 1 + VegetacionDream.bordeFundido) / VegetacionDream.bordeFundido
                    if borde > 0 then
                        encogerUltima(lote, 1 - suave(borde), ANCHO)
                    end
                end
                local s = self.antiguosSombra[e][0][v]
                if s and d2 < q2.sombra then
                    s:clase(cascada(sombras, datos, k, 4))
                    s:copiar(datos, k)
                end
            end
        end
    end
end

--- ¿Está la esfera (x, y, z, radio) en px entera dentro del frustum?
function VegetacionDream:enteraEnVista(x, y, z, radio)
    local margen = self.margen
    if margen and margen > 0 then
        local o = self.ojo
        local dx, dy, dz = x - o[1], y - o[2], z - o[3]
        radio = radio - margen * math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    for _, p in ipairs(self.planos) do
        if p[1] * x + p[2] * y + p[3] * z + p[4] < radio then
            return false
        end
    end
    return true
end

--- Cascada del sol de un objeto (celda o bloque) entero.
function VegetacionDream:claseDe(objeto)
    local sombras = self.sombras
    if not sombras then
        return 3
    end
    local e = Conversor.escala * 10
    local s = self.suelo
    return sombras:clase((objeto.x - s.cx) * e, objeto.z * e, (objeto.y - s.cy) * e, objeto.radio * e)
end

--- Rellena los lotes: los bloques de 240 m enteros en vista y en un solo
-- detalle copian sus paquetes de una vez; los demás bajan a sus celdas de
-- 30 m, y las celdas que tampoco caen en un solo detalle, copia a copia.
function VegetacionDream:rellenar(ex, ey, ez)
    local inicio = love.timer.getTime()
    for _, l in ipairs(self.lotes) do
        l:vaciar()
    end
    local sombras = self.sombras
    if sombras then
        local e = Conversor.escala * 10
        sombras:actualizar({ x = (ex - self.suelo.cx) * e, y = ez * e, z = (ey - self.suelo.cy) * e })
    end
    local c = self:prepararDistancias()
    local cortes, hasta = c.cortes, c.hasta
    self.ojo = self.ojo or {}
    self.ojo[1], self.ojo[2], self.ojo[3] = ex, ey, ez
    self.margen = math.sin(self.margenActual or VegetacionDream.margenGiro)
    local medioCelda = VegetacionDream.celda * 0.7072
    local medioBloque = medioCelda * VegetacionDream.celdasPorBloque
    local pendientes = {}
    for _, bloque in ipairs(self.bloquesLlenos) do
        local dx, dy = bloque.x - ex, bloque.y - ey
        local dh = math.sqrt(dx * dx + dy * dy)
        if dh - bloque.radio < c.lejos and self:enVista(bloque.x, bloque.y, bloque.z, bloque.radio) then
            local entero = self:enteraEnVista(bloque.x, bloque.y, bloque.z, bloque.radio)
            local d0, d1 = math.max(0, dh - medioBloque), dh + medioBloque
            local n = 0
            for _, grupo in ipairs(GRUPOS) do
                if bloque.hay[grupo] and d0 < hasta[grupo] then
                    if entero and uniforme(cortes[grupo], d0, d1, grupo, c) then
                        self:copiarUniforme(bloque, grupo, d0, 3)
                    else
                        n = n + 1
                        pendientes[n] = grupo
                    end
                end
            end
            if n > 0 then
                for _, celda in ipairs(bloque.celdas) do
                    local cx, cy = celda.x - ex, celda.y - ey
                    local ch = math.sqrt(cx * cx + cy * cy)
                    if ch - celda.radio < c.lejos and self:enVista(celda.x, celda.y, celda.z, celda.radio) then
                        local e0, e1 = math.max(0, ch - medioCelda), ch + medioCelda
                        local clase
                        for g = 1, n do
                            local grupo = pendientes[g]
                            if celda.hay[grupo] and e0 < hasta[grupo] then
                                if uniforme(cortes[grupo], e0, e1, grupo, c) then
                                    if not clase and e0 < c.sombra then
                                        clase = self:claseDe(celda)
                                    end
                                    self:copiarUniforme(celda, grupo, e0, clase or 3)
                                else
                                    self:copiarUnaAUna(celda, grupo, ex, ey)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local finBucle = love.timer.getTime()
    local copias, triangulos = 0, 0
    local porTipo = {}
    for _, l in ipairs(self.lotes) do
        l:subir()
        if l.cantidad > 0 then
            porTipo[l.tipo] = (porTipo[l.tipo] or 0) + l.cantidad
            if l.tipo ~= 'sombra' then
                copias = copias + l.cantidad
                triangulos = triangulos + l:triangulos()
            end
        end
    end
    self.porTipo = porTipo
    self.copiasVisibles = copias
    self.triangulosVisibles = triangulos
    self.msRehacer = (love.timer.getTime() - inicio) * 1000
    self.msBucle = (finBucle - inicio) * 1000
    self.rehechos = self.rehechos + 1
    if self.rehechos <= 2 or os.getenv('DEMOMUNDO_VEGETACION') then
        print(
            string.format(
                'VEGETACION %d copias visibles, %d triángulos, rellenada en %.2f ms',
                copias,
                triangulos,
                self.msRehacer
            )
        )
    end
end

--- Dibuja los lotes con copias (y los de sombra, que solo van a las sombras).
function VegetacionDream:dibujar()
    local dibujos = 0
    for _, l in ipairs(self.lotes) do
        if l.cantidad > 0 then
            self.dream:draw(l.malla)
            dibujos = dibujos + 1
        end
    end
    self.dibujos = dibujos
end

return VegetacionDream
