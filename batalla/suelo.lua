-- Suelo de la escena de batalla: el sitio real del mapa en 3D low-poly.
--
-- Se genera una sola vez al entrar, a partir de la semilla (como el mapa):
--   terreno   rejilla sobre `lado` px alrededor del centro: fina (`paso`) en
--             el medio, donde se pelea, y cada vez más gruesa hacia el borde
--             (hasta `pasoBorde`), con una altura táctica que suaviza el
--             Terreno:altura real y abre explanadas suaves para desplegar
--             formaciones sin que los vehículos salten
--   agua      un plano al nivel del mar, translúcido, donde el terreno baja
--   cauce     en algunas batallas, un río o un cañón (batalla/cauces.lua),
--             tallado después de los pasillos, con vados o rampas donde los cruza
--   plantas   las mismas plantas del mapa (Plantas.enTrozo) en 3D: pinos de
--             conos, copas de icosaedros, rocas, matorrales y cactus; lejos
--             del centro, más sencillas y menos (siempre las mismas)
--   edificio  la torre de la ciudad con sus ventanas, o la losa y las
--             casetas de una base, un campamento o una extracción; en campo
--             abierto (`sitio = nil`) no se genera edificio

local ffi = require('ffi')
local bit = require('bit')
local Ruido = require('mundo.ruido')
local Terreno = require('mundo.terreno')
local Ciudades = require('mundo.ciudades')
local Malla = require('batalla.malla')
local Rejilla = require('batalla.rejilla')
local ColorTerreno = require('batalla.color_terreno')
local Vegetacion = require('batalla.vegetacion')
local Colocacion = require('batalla.colocacion')
local Limite = require('batalla.limite')
local Pasillos = require('batalla.pasillos')
local Agua = require('batalla.agua')
local Cauces = require('batalla.cauces')

local Suelo = {}
Suelo.__index = Suelo

Suelo.lado = 30000 -- px de lado del área (3 km)
Suelo.escalaMundo = 10 -- el mapa, ampliado en la batalla (tamaño real)
Suelo.paso = 40 -- px entre vértices de la rejilla en el centro (4 m)
Suelo.fino = 4200 -- px del centro hasta los que la rejilla es fina
Suelo.pasoMedio = 96 -- px entre vértices a `medio` px del centro
Suelo.medio = 11000
Suelo.pasoBorde = 280 -- px entre vértices en el borde del área
Suelo.sinPlantas = 0.93 -- fracción del medio lado a partir de la que no hay plantas (la niebla del borde)
-- Sin aplanar (el dueño, 19-nov: «se ve muy plano»; eligió quitar el
-- aplanado): ni suavizado, ni altura táctica, ni explanadas de formación; el
-- relieve del mapa tal cual. `BATALLA_APLANAR=1` vuelve a lo de antes.
Suelo.aplanar = os.getenv('BATALLA_APLANAR') == '1'
Suelo.suavizado = 260 -- px de radio de muestra para quitar ruido pequeño del mapa
-- Sigma (px) del filtro gaussiano de la altura antes de hacer la malla: 4 m,
-- unos 9 m de ancho a media altura. Quita los picos pequeños y conserva las
-- lomas y valles del mapa (que miden cientos de metros).
Suelo.sigmaSuavizado = 40
-- Peso de la normal suavizada por vértice frente a la plana de la cara: las
-- lomas se ven redondas y conservan algo de faceta low-poly.
Suelo.normalSuave = 0.7
Suelo.explanadaLargo = 2200 -- px: zona larga donde forma cada bando
Suelo.explanadaAncho = 950 -- px: zona lateral limpia para filas de vehículos
Suelo.explanadaBorde = 0.35 -- parte exterior donde la explanada se funde con el terreno
Suelo.maxDesnivelVehiculo = 42 -- px de diferencia bajo el casco antes de rechazar un punto
Suelo.rocaBajadaMaxima = 0.12 -- lo más que se bajan los umbrales de roca en relieves suaves

-- Faldón: anillos cuadrados alrededor del área que prolongan el terreno hasta
-- el horizonte (la cámara ve hasta 9 km). Medio lado de cada anillo en px; el
-- primero es el borde del área y comparte sus vértices. Cada vez más gruesos.
Suelo.anillosFaldon = { 15000, 15800, 16900, 18400, 20500, 23300, 27000, 33000, 42000, 56000, 76000, 104000, 140000 }
-- Vértices por anillo (múltiplos de 4: las esquinas son vértices); el primero
-- lleva todos los del borde de la rejilla.
Suelo.verticesFaldon = { 0, 512, 512, 512, 512, 256, 256, 256, 256, 128, 128, 128, 128 }
Suelo.fusionFaldon = 18000 -- px desde el borde en los que el mapa real se funde con la llanura
Suelo.bajadaLlanura = 40 -- px que la llanura queda por debajo del borde típico (4 m)

local suave = ColorTerreno.suave

--- Suelo alrededor de (cx, cy). `sitio` es lo que se ataca (para el edificio)
-- o nil en una batalla de campo abierto:
-- { tipo = 'ciudad' | 'base' | 'campamento' | 'extraccion', x, y, z, color }.
function Suelo.nuevo(mundo, cx, cy, sitio, combate, carga)
    local self = setmetatable({}, Suelo)
    self.mundo = mundo
    -- A tamaño real (batalla/terreno_escalado.lua): el mapa ampliado
    -- `escalaMundo` veces alrededor del combate. 1: el de antes (maqueta).
    self.escalaMundo = tonumber(os.getenv('BATALLA_ESCALA') or '') or Suelo.escalaMundo
    if self.escalaMundo ~= 1 then
        self.terreno = require('batalla.terreno_escalado').nuevo(mundo.terreno, cx, cy, self.escalaMundo)
    else
        self.terreno = mundo.terreno
    end
    self.cx, self.cy = cx, cy
    self.lado = Suelo.lado
    self.x0, self.y0 = cx - Suelo.lado / 2, cy - Suelo.lado / 2
    self.medioPlantas = Suelo.lado / 2 * Suelo.sinPlantas
    -- Límite del campo de batalla (batalla/limite.lua): de él no sale nada.
    self.limite = Limite.nuevo(cx, cy)
    self.sitio = sitio
    self.carga = carga
    self.ruidoDetalle = Ruido.nuevo(self.terreno.semilla + 14891)
    self.plantasFisicas = {}
    self.celdasPlantas = {}
    self.tiempos = {}
    -- Dirección horizontal hacia el sol (la luz del mapa), para la solana.
    self.solX, self.solY = -0.633, -0.774
    self.nivelMar = self.terreno.nivelMar
    self.combate = combate
    self:prepararExplanadas(combate)
    local inicio = love.timer.getTime()
    self:informarCarga('Modelando el relieve', 0.04, true)
    self:generarTerreno()
    self.tiempos.terreno = love.timer.getTime() - inicio
    local paso = love.timer.getTime()
    self:informarCarga('Llenando ríos y lagos', 0.55, true)
    self:generarAgua()
    self.tiempos.agua = love.timer.getTime() - paso
    paso = love.timer.getTime()
    self:informarCarga('Abriendo pasillos de avance', 0.6, true)
    Pasillos.generar(self, combate)
    -- Río o cañón (batalla/cauces.lua): se traza después de los pasillos,
    -- cruzándolos por lo corto, y donde los cruza se vuelve vado o rampa.
    self.cauces = Cauces.nuevo(self)
    self.cauces:tallar()
    self:construirAgua()
    self:calcularNormales()
    self:despejarPasillos()
    self:medirRelieve()
    -- Agua no transitable y sus bordes para la física (batalla/agua.lua).
    self.agua = Agua.nuevo(self)
    if self.agua.charcos > 0 then
        self:calcularNormales()
    end
    self.tiempos.pasillos = love.timer.getTime() - paso
    -- Ciudad o mina armada con las piezas del kit (batalla/sitios/plano.lua),
    -- antes de las plantas: dentro no crecen árboles y las calles son tierra.
    self:informarCarga('Trazando las calles y los edificios', 0.61, true)
    self.plano = require('batalla.sitios.plano').generar(self, self.sitio)
    -- El límite de la batalla se abre lo justo para que el muro quede dentro.
    if self.plano and self.plano.recinto then
        local r = self.plano.recinto
        local lejos = 0
        for _, x in ipairs({ r[1], r[3] }) do
            for _, y in ipairs({ r[2], r[4] }) do
                lejos = math.max(lejos, math.sqrt((x - self.cx) ^ 2 + (y - self.cy) ^ 2))
            end
        end
        self.limite.radio = math.max(self.limite.radio, math.min(require('batalla.sitios.plano').limiteMaximo, lejos + 250))
        print(string.format('LIMITE radio %.0f px; esquina del muro más lejana a %.0f px', self.limite.radio, lejos))
    end
    if self.plano then
        -- Las explanadas de los edificios cambian el relieve.
        self:calcularNormales()
        self:marcarCalles()
    end
    paso = love.timer.getTime()
    self.colocacion = Colocacion.nueva(self)
    self.tiempos.anclas = love.timer.getTime() - paso
    paso = love.timer.getTime()
    self:colorearTerreno()
    self.tiempos.colores = love.timer.getTime() - paso
    self:informarCarga('Plantando bosques y vegetación', 0.76, true)
    self:generarPlantas()
    self:informarCarga('Construyendo el lugar del combate', 0.93, true)
    self:generarEdificio()
    paso = love.timer.getTime()
    self:informarCarga('Midiendo por dónde pasan los vehículos', 0.94, true)
    self:prepararTransito()
    self.tiempos.transito = love.timer.getTime() - paso
    self.segundos = love.timer.getTime() - inicio
    self:imprimirTiempos()
    return self
end

--- Línea `SUELO` con el tiempo de cada paso y las copias por especie.
function Suelo:imprimirTiempos()
    local t = self.tiempos
    local especies = {}
    for _, e in ipairs(Vegetacion.especies) do
        local n = self.colocacion.cuenta[e.nombre]
        if n then
            especies[#especies + 1] = e.nombre .. ' ' .. n
        end
    end
    print(
        string.format(
            'SUELO terreno %.3f s, agua %.3f s, pasillos %.3f s (%d), anclas %.3f s, colores %.3f s, prototipos %.3f s, colocar %.3f s, tránsito %.3f s, total %.3f s; '
                .. '%d triángulos de terreno; pendiente p90 %.3f p97 %.3f, roca %.2f-%.2f; hRef %.0f px; %s; %s',
            t.terreno or 0,
            t.agua or 0,
            t.pasillos or 0,
            #(self.pasillos or {}),
            t.anclas or 0,
            t.colores or 0,
            t.prototipos or 0,
            t.colocar or 0,
            t.transito or 0,
            self.segundos,
            self.triangulos,
            self.pendienteP90,
            self.pendienteP97,
            self.rocaDesde,
            self.rocaHasta,
            self.hRef,
            table.concat(especies, ', '),
            self.cauces:resumen()
        )
    )
end

function Suelo:informarCarga(etapa, progreso, forzar)
    if self.carga then
        self.carga(etapa, progreso, forzar)
    end
end

--- Altura original del mundo en (x, y), sin filtros de batalla.
function Suelo:alturaReal(x, y)
    return self.terreno:altura(x, y)
end

--- Altura suavizada: la batalla conserva la forma grande del mapa, pero quita
-- picos pequeños para que los tanques y las formaciones caminen tranquilos.
function Suelo:alturaSuave(x, y)
    if not Suelo.aplanar then
        return self:alturaReal(x, y)
    end
    local r = Suelo.suavizado
    local centro = self:alturaReal(x, y)
    local h = centro * 4
    h = h + self:alturaReal(x + r, y)
    h = h + self:alturaReal(x - r, y)
    h = h + self:alturaReal(x, y + r)
    h = h + self:alturaReal(x, y - r)
    return h / 8
end

--- Ondulación grande de la superficie (170 m): evita explanadas del todo
-- lisas. Sin el ruido fino ni las crestas de antes, que hacían picos.
function Suelo:detalleAltura(x, y)
    return self.ruidoDetalle:fbm(x / 1700, y / 1700, 3) * 8
end

--- Filtro gaussiano separable de `alturas` (array por vértice) sobre la
-- rejilla, con la distancia real entre líneas: en el centro (paso fino)
-- promedia unos 9 m; hacia el borde, donde el paso ya es mayor que el filtro,
-- apenas cambia nada (la rejilla gruesa ya es suave).
function Suelo:suavizarGauss(alturas)
    local rej = self.relieve
    local lado = rej.lado
    local sigma = Suelo.sigmaSuavizado
    local alcance = sigma * 3
    local factor = -1 / (2 * sigma * sigma)
    local temporal = Rejilla.array(rej.total)
    -- Una pasada por eje: `lineas` son las coordenadas del eje, `paso` el salto
    -- de índice entre vecinos de ese eje y `otro` el del eje contrario.
    local function pasada(origen, destino, lineas, paso, otro)
        for fila = 0, lado - 1 do
            local base = fila * otro
            for i = 0, lado - 1 do
                local xi = lineas[i + 1]
                local suma, pesos = 0, 0
                local desde, hasta = i, i
                while desde > 0 and xi - lineas[desde] <= alcance do
                    desde = desde - 1
                end
                while hasta < lado - 1 and lineas[hasta + 2] - xi <= alcance do
                    hasta = hasta + 1
                end
                for v = desde, hasta do
                    local d = lineas[v + 1] - xi
                    local w = math.exp(d * d * factor)
                    suma = suma + origen[base + v * paso] * w
                    pesos = pesos + w
                end
                destino[base + i * paso] = suma / pesos
            end
        end
    end
    pasada(alturas, temporal, rej.xs, 1, lado)
    pasada(temporal, alturas, rej.ys, lado, 1)
end

local function suavizarPaso(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

--- Prepara las dos explanadas de formación. No inventan un mapa nuevo: solo
-- funden el terreno suavizado hacia una cota estable alrededor de cada bando.
function Suelo:prepararExplanadas(combate)
    self.explanadas = {}
    if not combate then
        return
    end

    local separacion = combate.separacion or 17000
    local ca = math.cos(combate.angulo or 0)
    local sa = math.sin(combate.angulo or 0)
    for _, lado in ipairs({ -1, 1 }) do
        local x = self.cx + ca * separacion * lado
        local y = self.cy + sa * separacion * lado
        local h = self:alturaSuave(x, y)
        if h > self.terreno.nivelMar + 4 then
            self.explanadas[#self.explanadas + 1] = {
                x = x,
                y = y,
                ca = ca,
                sa = sa,
                h = h,
            }
        end
    end
end

--- Aplica las explanadas sobre una altura ya suavizada. `generarTerreno` lo usa
-- con la rejilla ya muestreada para no llamar al terreno cinco veces por vértice.
function Suelo:aplicarExplanadas(x, y, h)
    if not Suelo.aplanar then
        return h
    end
    for _, e in ipairs(self.explanadas or {}) do
        local dx = x - e.x
        local dy = y - e.y
        local frente = (dx * e.ca + dy * e.sa) / Suelo.explanadaLargo
        local lado = (-dx * e.sa + dy * e.ca) / Suelo.explanadaAncho
        local d = math.sqrt(frente * frente + lado * lado)
        if d < 1 then
            local borde = 1 - Suelo.explanadaBorde
            local peso = 1 - suavizarPaso((d - borde) / Suelo.explanadaBorde)
            h = h * (1 - peso) + e.h * peso
        end
    end
    return h
end

--- Altura táctica de la batalla en (x, y): la de la rejilla final del terreno
-- (mapa suavizado, explanadas, detalle y cauces tallados), interpolada en su
-- triángulo. Es exactamente la superficie que se dibuja: nada flota.
function Suelo:altura(x, y)
    local rejilla = self.relieve
    if rejilla then
        local medio = Suelo.lado / 2
        if math.abs(x - self.cx) > medio or math.abs(y - self.cy) > medio then
            -- Fuera del área: el faldón (un misil que cae fuera explota ahí).
            return self:alturaFaldon(x, y)
        end
        return rejilla:interpolar(rejilla.h, x, y)
    end
    local altura = self:aplicarExplanadas(x, y, self:alturaSuave(x, y))
    return altura + self:detalleAltura(x, y)
end

Suelo.rampaLosa = 6 -- px (0,6 m) en los que una rueda sube el canto de una losa

--- Altura (px) que pisa lo que va sobre el suelo en (x, y): el terreno o,
-- encima de una losa de patio (batalla/sitios/plano.lua), su cara de
-- arriba. En el canto, una rampa de `rampaLosa` px: sube y baja como una
-- rueda que monta un bordillo, sin saltos (el dueño, 19-nov: el robot
-- atravesaba las losas).
function Suelo:alturaPisable(x, y)
    local h = self:altura(x, y)
    local plano = self.plano
    if not plano then
        return h
    end
    local rampa = Suelo.rampaLosa
    for _, e in ipairs(plano.edificios) do
        if e.patio then
            local tope = e[5]
            if tope > h then
                local dx, dy = x - e.cx, y - e.cy
                local c, s = math.cos(e.ang), math.sin(e.ang)
                local u, v = dx * c + dy * s, -dx * s + dy * c
                local fuera = math.max(math.abs(u) - e.hx, math.abs(v) - e.hy, 0)
                if fuera < rampa then
                    h = math.max(h, tope - (tope - h) * fuera / rampa)
                end
            end
        end
    end
    return h
end

--- Desnivel bajo un casco de vehículo. Se usa para no formar en laderas rotas.
function Suelo:desnivel(x, y, radio)
    local h0 = self:altura(x, y)
    local h1 = self:altura(x + radio, y)
    local h2 = self:altura(x - radio, y)
    local h3 = self:altura(x, y + radio)
    local h4 = self:altura(x, y - radio)
    local minimo = math.min(h0, h1, h2, h3, h4)
    local maximo = math.max(h0, h1, h2, h3, h4)
    return maximo - minimo
end

--- Peso (0 a 1) de las explanadas de formación en (x, y).
function Suelo:pesoExplanada(x, y)
    local peso = 0
    for _, e in ipairs(self.explanadas or {}) do
        local dx = x - e.x
        local dy = y - e.y
        local frente = (dx * e.ca + dy * e.sa) / Suelo.explanadaLargo
        local lado = (-dx * e.sa + dy * e.ca) / Suelo.explanadaAncho
        local d = math.sqrt(frente * frente + lado * lado)
        if d < 1 then
            local borde = 1 - Suelo.explanadaBorde
            peso = math.max(peso, 1 - suavizarPaso((d - borde) / Suelo.explanadaBorde))
        end
    end
    return peso
end

--- ¿Cae (x, y) en un pasillo de avance (o a menos de `margen` px de su
-- borde)? Ahí no crecen árboles, arbustos ni rocas (batalla/pasillos.lua).
function Suelo:enCamino(x, y, margen)
    return Pasillos.distancia(self, x, y) < Pasillos.mitad + (margen or 0)
end

--- Pendiente del terreno en (x, y), en grados (la de la cara que se dibuja).
function Suelo:pendiente(x, y)
    local rej = self.relieve
    local _, _, _, nz = rej:alturaNormal(x, y)
    return math.deg(math.acos(math.max(-1, math.min(1, nz))))
end

Suelo.pendienteTransitable = 25 -- grados que un vehículo aún puede subir
Suelo.celdaTransito = 20 -- px entre las esquinas de la rejilla de tránsito

--- ¿Puede pisar un vehículo o un soldado (x, y)? No en el agua (mar, lagos y
-- ríos, salvo sobre un puente) ni en pendientes de más de 25°. Con la
-- rejilla de tránsito hecha, casi siempre sale de ella (ver `prepararTransito`).
function Suelo:transitable(x, y)
    local t = self.transito
    if t then
        local r = self:consultarTransito(x, y, 1)
        if r ~= nil then
            return r
        end
    end
    return self:transitableExacto(x, y)
end

--- Rejilla de tránsito: en cada esquina de una rejilla de `celdaTransito` px
-- sobre el límite, si se puede pisar (bit 1) y si es agua (bit 2), con las
-- cuentas exactas. Todo es del terreno, que ya no cambia: la física y las
-- tropas preguntan miles de veces por cuadro y casi siempre lejos de un borde.
function Suelo:prepararTransito()
    self.transito = nil
    local c = Suelo.celdaTransito
    local r = self.limite.radio + 800
    local n = math.floor(2 * r / c) + 2
    local x0, y0 = self.cx - r, self.cy - r
    local bits = ffi.new('uint8_t[?]', n * n)
    local agua = self.agua
    for j = 0, n - 1 do
        local y = y0 + j * c
        for i = 0, n - 1 do
            local x = x0 + i * c
            local b = 0
            if self:transitableExacto(x, y) then
                b = 1
            end
            if agua and agua:aguaEn(x, y) then
                b = b + 2
            end
            bits[j * n + i] = b
        end
        if j % 64 == 0 then
            self:informarCarga('Midiendo por dónde pasan los vehículos', 0.94 + 0.03 * j / n)
        end
    end
    self.transito = { bits = bits, n = n, x0 = x0, y0 = y0, c = c }
end

--- Lo que dice la rejilla de tránsito del bit `bitPedido` (1: se pisa, 2: es
-- agua) en (x, y): true o false si las cuatro esquinas de su celda coinciden;
-- nil si no (un borde: hay que hacer la cuenta) o si cae fuera.
function Suelo:consultarTransito(x, y, bitPedido)
    local t = self.transito
    local fi, fj = (x - t.x0) / t.c, (y - t.y0) / t.c
    local i, j = math.floor(fi), math.floor(fj)
    local n = t.n
    if i < 0 or j < 0 or i >= n - 1 or j >= n - 1 then
        return nil
    end
    local bits = t.bits
    local k = j * n + i
    local a, b, c, d = bits[k], bits[k + 1], bits[k + n], bits[k + n + 1]
    if bit.band(a, b, c, d, bitPedido) ~= 0 then
        return true
    end
    if bit.band(bit.bor(a, b, c, d), bitPedido) == 0 then
        return false
    end
    return nil
end

--- `transitable` con las cuentas exactas.
function Suelo:transitableExacto(x, y)
    if self.agua and self.agua:puenteEn(x, y) then
        return true
    end
    if self:altura(x, y) < self.nivelMar + 3 then
        return false
    end
    if self.agua and self.agua:enAgua(x, y) then
        return false
    end
    return self:pendiente(x, y) <= Suelo.pendienteTransitable
end

--- Paso de la rejilla a `d` px del centro (en un eje): fino donde se pelea y
-- más grueso hacia el borde, sin saltos.
function Suelo.pasoA(d)
    if d <= Suelo.fino then
        return Suelo.paso
    elseif d <= Suelo.medio then
        local t = (d - Suelo.fino) / (Suelo.medio - Suelo.fino)
        return Suelo.paso + (Suelo.pasoMedio - Suelo.paso) * t
    end
    local t = math.min(1, (d - Suelo.medio) / (Suelo.lado / 2 - Suelo.medio))
    return Suelo.pasoMedio + (Suelo.pasoBorde - Suelo.pasoMedio) * t
end

--- Coordenadas de las líneas de la rejilla en un eje, de `centro - lado / 2`
-- a `centro + lado / 2`, más juntas en el medio.
function Suelo.lineas(centro)
    local medio = Suelo.lado / 2
    local mitad = { 0 }
    while mitad[#mitad] < medio do
        local d = mitad[#mitad]
        mitad[#mitad + 1] = math.min(medio, d + Suelo.pasoA(d))
    end
    local lineas = {}
    for k = #mitad, 2, -1 do
        lineas[#lineas + 1] = centro - mitad[k]
    end
    for k = 1, #mitad do
        lineas[#lineas + 1] = centro + mitad[k]
    end
    return lineas
end

--- Ciudades que pueden aplanar alguna parte del área (casi siempre ninguna
-- o una: las capitales están a varios kilómetros). Se buscan una vez, para no
-- recorrer las nueve regiones vecinas en cada vértice.
function Suelo:ciudadesDelArea()
    local ciudades = self.terreno.ciudades
    local lista = {}
    if not ciudades then
        return lista
    end
    local region = Ciudades.region
    local margen = 2000
    local x1, y1 = self.x0 + Suelo.lado, self.y0 + Suelo.lado
    for ry = math.floor((self.y0 - margen) / region) - 1, math.floor((y1 + margen) / region) + 1 do
        for rx = math.floor((self.x0 - margen) / region) - 1, math.floor((x1 + margen) / region) + 1 do
            local ciudad = ciudades:deRegion(rx, ry)
            if ciudad then
                local ex = math.max(self.x0 - ciudad.x, 0, ciudad.x - x1)
                local ey = math.max(self.y0 - ciudad.y, 0, ciudad.y - y1)
                if ex * ex + ey * ey < (ciudad.radio + 300) ^ 2 then
                    lista[#lista + 1] = ciudad
                end
            end
        end
    end
    return lista
end

--- `Terreno:altura` con la lista de `ciudadesDelArea`: las mismas cuentas,
-- sin buscar las ciudades cercanas en cada punto.
function Suelo:alturaMapa(x, y, ciudades)
    local terreno = self.terreno
    local h = terreno:base(x, y)
    for indice = 1, #ciudades do
        local ciudad = ciudades[indice]
        local dx, dy = x - ciudad.x, y - ciudad.y
        local d = math.sqrt(dx * dx + dy * dy)
        local casco = Ciudades.borde(ciudad, math.atan2(dy, dx))
        local borde = casco + 260
        if d < borde then
            local t = math.max(0, math.min(1, (borde - d) / (borde - casco * 0.95)))
            t = t * t * (3 - 2 * t)
            h = h + (ciudad.altura - h) * t
        end
    end
    return h
end

--- Rejilla del terreno: vértices desplazados, altura táctica y los campos
-- por vértice (ruidos del estilo, humedad del mapa, pendiente y bosque).
function Suelo:generarTerreno()
    local terreno = self.terreno
    local semilla = terreno.semilla
    local xs, ys = Suelo.lineas(self.cx), Suelo.lineas(self.cy)
    local rej = Rejilla.nueva(xs, ys)
    self.relieve = rej
    local lado = rej.lado
    local px, py, ph = rej.x, rej.y, rej.h
    local crudas = Rejilla.array(rej.total)
    local ciudades = self:ciudadesDelArea()
    -- 1. Altura del mapa en cada vértice. Sin desplazar los vértices: el
    -- desplazamiento aleatorio (antes ±0,3 del paso) dejaba triángulos
    -- torcidos que se leían como picos.
    for j = 0, lado - 1 do
        for i = 0, lado - 1 do
            local k = j * lado + i
            local x, y = xs[i + 1], ys[j + 1]
            px[k], py[k] = x, y
            crudas[k] = self:alturaMapa(x, y, ciudades)
        end
        if j % 16 == 0 then
            self:informarCarga('Muestreando el terreno', 0.04 + 0.2 * j / lado)
        end
    end
    -- 2. Suavizado gaussiano, explanadas y ondulación grande.
    self:informarCarga('Suavizando valles y explanadas', 0.24, true)
    if Suelo.aplanar then
        self:suavizarGauss(crudas)
    end
    for k = 0, rej.total - 1 do
        local h = self:aplicarExplanadas(px[k], py[k], crudas[k])
        ph[k] = h + self:detalleAltura(px[k], py[k])
    end
    -- 3. Campos por vértice. El agua (dAgua, nivelAgua) la rellena generarAgua.
    rej.n1 = Rejilla.array(rej.total)
    rej.n2 = Rejilla.array(rej.total)
    rej.fino = Rejilla.array(rej.total)
    rej.humedad = Rejilla.array(rej.total)
    rej.pendiente = Rejilla.array(rej.total)
    rej.bosque = Rejilla.array(rej.total)
    rej.dAgua = Rejilla.array(rej.total)
    rej.nivelAgua = Rejilla.array(rej.total)
    local r1 = Ruido.nuevo(semilla + 27101)
    local r2 = Ruido.nuevo(semilla + 27102)
    local r3 = Ruido.nuevo(semilla + 27103)
    local r4 = Ruido.nuevo(semilla + 27104)
    local r5 = Ruido.nuevo(semilla + 27105)
    -- Un bucle por campo: bucles pequeños que LuaJIT compila siempre (el
    -- bucle único, con todos los ruidos, a veces se quedaba interpretado).
    local total = rej.total
    local n1, n2, fino, humedad = rej.n1, rej.n2, rej.fino, rej.humedad
    for k = 0, total - 1 do
        n1[k] = r1:simplex(px[k] / 200, py[k] / 200)
    end
    for k = 0, total - 1 do
        n2[k] = r2:simplex(px[k] / 600, py[k] / 600)
    end
    for k = 0, total - 1 do
        fino[k] = r3:simplex(px[k] / 50, py[k] / 50)
    end
    self:informarCarga('Leyendo humedad y bosques', 0.47, true)
    for k = 0, total - 1 do
        humedad[k] = terreno:humedadEn(px[k], py[k])
    end
    local pendientes = rej.pendiente
    self:calcularNormales()
    self:informarCarga('Leyendo humedad y bosques', 0.5, true)
    local bosque, dAgua, nivelAgua = rej.bosque, rej.dAgua, rej.nivelAgua
    local nivelMar = terreno.nivelMar
    for k = 0, total - 1 do
        local x, y = px[k], py[k]
        local borde = r4:simplex(x / 300, y / 300)
        local claros = r5:simplex(x / 700, y / 700)
        local h = humedad[k]
        -- Los mismos bosquecillos que el mapa (Plantas.enTrozo): solo donde el
        -- ruido de manchas es alto; el resto es llanura abierta.
        local mancha = terreno.detalle:simplex(x / 620 + 90, y / 620)
        local b = suave(0.12, 0.3, h + 0.12 * borde) * suave(0.0, 0.3, mancha)
        b = math.max(b, 0.85 * suave(0.62, 0.8, claros) * suave(-0.35, 0.0, h) * suave(0.38, 0.68, mancha))
        b = b * suave(-0.75, -0.45, claros)
        b = b * (1 - suave(0.28, 0.4, pendientes[k]))
        -- En la roca alta y en la nieve del mapa no hay bosque denso.
        b = b * (1 - suave(170, 230, ph[k]))
        bosque[k] = b
        dAgua[k] = 1e6
        nivelAgua[k] = nivelMar
    end
    -- En las explanadas de formación no se plantan árboles: tampoco se pinta
    -- suelo de bosque (quedaría una mancha oscura sin árboles).
    for k = 0, total - 1 do
        local peso = self:pesoExplanada(px[k], py[k])
        if peso > 0 then
            bosque[k] = bosque[k] * (1 - peso)
        end
    end
    rej.nivelMar = terreno.nivelMar
    self:medirRelieve()
    self:medirLlanura()
end

--- Pendiente (1 - nz) y normal suavizada de cada vértice (diferencias
-- centradas). Se rehace después de tallar el agua y aplanar los pasillos.
function Suelo:calcularNormales()
    local rej = self.relieve
    local lado = rej.lado
    local px, py, ph = rej.x, rej.y, rej.h
    rej.nx = rej.nx or Rejilla.array(rej.total)
    rej.ny = rej.ny or Rejilla.array(rej.total)
    rej.nz = rej.nz or Rejilla.array(rej.total)
    local pendientes = rej.pendiente
    local vnx, vny, vnz = rej.nx, rej.ny, rej.nz
    for j = 0, lado - 1 do
        for i = 0, lado - 1 do
            local k = j * lado + i
            local ka, kb = i > 0 and k - 1 or k, i < lado - 1 and k + 1 or k
            local kc, kd = j > 0 and k - lado or k, j < lado - 1 and k + lado or k
            local gx = (ph[kb] - ph[ka]) / math.max(1, px[kb] - px[ka])
            local gy = (ph[kd] - ph[kc]) / math.max(1, py[kd] - py[kc])
            local l = math.sqrt(1 + gx * gx + gy * gy)
            pendientes[k] = 1 - 1 / l
            vnx[k], vny[k], vnz[k] = -gx / l, -gy / l, 1 / l
        end
    end
end

--- En los pasillos no hay bosque: tampoco se pinta suelo de bosque (quedaría
-- una franja oscura sin árboles).
function Suelo:despejarPasillos()
    local rej = self.relieve
    local d, bosque = rej.dPasillo, rej.bosque
    local mitad, transicion = Pasillos.mitad, Pasillos.transicion
    for k = 0, rej.total - 1 do
        if d[k] < mitad + transicion then
            bosque[k] = bosque[k] * suavizarPaso((d[k] - mitad) / transicion)
        end
    end
end

--- hRef (percentil 20 de las alturas sobre el mar: el fondo del valle) y el
-- umbral de roca. Si la roca plena (pendiente sobre `rocaHasta`) queda en
-- menos del 3 % del área en tierra, el relieve del juego es más suave que el
-- del script: se bajan los dos umbrales por igual hasta que el percentil 97
-- de la pendiente sea roca plena (ESTILO-TERRENO.md §2.3).
function Suelo:medirRelieve()
    local rej = self.relieve
    local alturas, pendientes = {}, {}
    for k = 0, rej.total - 1, 5 do
        if rej.h[k] > self.terreno.nivelMar then
            alturas[#alturas + 1] = rej.h[k]
            pendientes[#pendientes + 1] = rej.pendiente[k]
        end
    end
    table.sort(alturas)
    table.sort(pendientes)
    self.hRef = alturas[math.max(1, math.floor(#alturas * 0.2))] or self.terreno.nivelMar
    local p97 = pendientes[math.max(1, math.floor(#pendientes * 0.97))] or 1
    self.pendienteP97 = p97
    self.pendienteP90 = pendientes[math.max(1, math.floor(#pendientes * 0.9))] or 1
    local desde, hasta = ColorTerreno.rocaDesde, ColorTerreno.rocaHasta
    if p97 < hasta then
        local bajar = math.min(hasta - p97, Suelo.rocaBajadaMaxima)
        desde, hasta = desde - bajar, hasta - bajar
    end
    self.rocaDesde, self.rocaHasta = desde, hasta
end

--- Malla del terreno con color por vértice (interpolado en cada triángulo:
-- las zonas se funden en degradados, sin parches por cara) y normal mezclada
-- (`normalSuave` de la suavizada del vértice, el resto de la plana de la
-- cara). Va después del agua: la orilla y el fondo dependen de ella.
function Suelo:colorearTerreno()
    local rej = self.relieve
    local lado = rej.lado
    local total = rej.total
    local px, py, ph = rej.x, rej.y, rej.h
    local vnx, vny, vnz = rej.nx, rej.ny, rej.nz
    local n1, n2, fino, humedad, bosque = rej.n1, rej.n2, rej.fino, rej.humedad, rej.bosque
    local dAgua, nivelAgua = rej.dAgua, rej.nivelAgua
    local colocacion = self.colocacion
    local cara = {}
    local anterior = { ColorTerreno.rocaDesde, ColorTerreno.rocaHasta }
    ColorTerreno.rocaDesde, ColorTerreno.rocaHasta = self.rocaDesde, self.rocaHasta

    -- 1. Color de cada vértice, con su normal suavizada, y el peso de cada
    -- capa del suelo (12 bytes por vértice: Suelo.guardarPesos).
    local cr, cg, cb = Rejilla.array(total), Rejilla.array(total), Rejilla.array(total)
    local pesos = ffi.new('uint8_t[?]', total * 12)
    rej.pesos = pesos
    local manchas = {}
    for k = 0, total - 1 do
        local x, y = px[k], py[k]
        cara.x, cara.y, cara.h = x, y, ph[k]
        cara.nx, cara.ny, cara.nz = vnx[k], vny[k], vnz[k]
        cara.n1, cara.n2, cara.fino = n1[k], n2[k], fino[k]
        cara.humedad, cara.bosque = humedad[k], bosque[k]
        cara.dAgua, cara.nivelAgua = dAgua[k], nivelAgua[k]
        cara.dPasillo = rej.dPasillo and rej.dPasillo[k] or math.huge
        -- Manchas de flores por celda de 60 m (como `manchasCerca`).
        local clave = math.floor(x / 600) * 131072 + math.floor(y / 600)
        local lista = manchas[clave]
        if lista == nil then
            lista = colocacion and colocacion:manchasCerca(x, y) or false
            manchas[clave] = lista
        end
        cara.manchas = lista or nil
        cr[k], cg[k], cb[k] = ColorTerreno.cara(self, cara)
        Suelo.guardarPesos(pesos, k * 12, cara)
        if k % 16384 == 0 then
            self:informarCarga('Pintando hierba, tierra y roca', 0.56 + 0.08 * k / total)
        end
    end
    ColorTerreno.rocaDesde, ColorTerreno.rocaHasta = anterior[1], anterior[2]
    -- Los trozos con niveles de detalle de la escena 3D (batalla/dream/terreno_trozos.lua)
    -- se hacen con estos mismos colores.
    rej.cr, rej.cg, rej.cb = cr, cg, cb

    -- 2. Triángulos. Cada vértice lleva su color y la normal mezclada.
    local malla = Malla.nueva((lado - 1) * (lado - 1) * 6)
    local suaveN = Suelo.normalSuave
    local planaN = 1 - suaveN

    local function vertice(k, fx, fy, fz)
        local nx = vnx[k] * suaveN + fx * planaN
        local ny = vny[k] * suaveN + fy * planaN
        local nz = vnz[k] * suaveN + fz * planaN
        local l = math.sqrt(nx * nx + ny * ny + nz * nz)
        malla:vertice(px[k], py[k], ph[k], nx / l, ny / l, nz / l, cr[k], cg[k], cb[k])
    end

    local function triangulo(a, b, c)
        local ax, ay, az = px[a], py[a], ph[a]
        local ux, uy, uz = px[b] - ax, py[b] - ay, ph[b] - az
        local vx, vy, vz = px[c] - ax, py[c] - ay, ph[c] - az
        local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        local l = math.sqrt(nx * nx + ny * ny + nz * nz)
        if l < 1e-9 then
            return
        end
        if nz < 0 then
            l = -l
            b, c = c, b
        end
        nx, ny, nz = nx / l, ny / l, nz / l
        vertice(a, nx, ny, nz)
        vertice(b, nx, ny, nz)
        vertice(c, nx, ny, nz)
    end

    local minimo = math.huge
    for j = 0, lado - 2 do
        for i = 0, lado - 2 do
            -- Los dos triángulos de `Rejilla:triangulosCuadro`, escritos aquí:
            -- una función con seis resultados impedía a LuaJIT compilar el bucle.
            local a = j * lado + i
            local c = a + lado
            if (i + j) % 2 == 0 then
                triangulo(a, a + 1, c + 1)
                triangulo(a, c + 1, c)
            else
                triangulo(a, a + 1, c)
                triangulo(a + 1, c + 1, c)
            end
            minimo = math.min(minimo, ph[a])
        end
        if j % 32 == 0 then
            self:informarCarga('Pintando hierba, tierra y roca', 0.64 + 0.08 * j / lado)
        end
    end
    self.minimo = minimo
    local antes = malla.n
    self:generarFaldon(malla, cr, cg, cb)
    self.triangulosFaldon = (malla.n - antes) / 3
    self.mallaTerreno = malla:crear()
    self.triangulos = malla.n / 3
    -- El faldón solo (la escena 3D dibuja el área por trozos y esto aparte),
    -- con sus triángulos apuntados para batalla/dream/terreno_trozos.lua.
    local faldon = Malla.nueva(self.triangulosFaldon * 3)
    self.faldonTriangulos = {}
    self:generarFaldon(faldon, cr, cg, cb, self.faldonTriangulos)
    self.mallaFaldon = faldon:crear()
end

--- Pesos de las capas del suelo que ColorTerreno.cara dejó en `c`, en
-- `destino[o .. o + 11]` (bytes de 0 a 255), en el orden de los atributos de
-- batalla/dream/terreno_pbr.lua: seca, bosque, pedregoso, camino; arena,
-- barro, roca, nieve; fondo y tres libres.
function Suelo.guardarPesos(destino, o, c)
    local function byte(v)
        return math.floor(math.max(0, math.min(1, v or 0)) * 255 + 0.5)
    end
    destino[o] = byte(c.pSeca)
    destino[o + 1] = byte(c.pBosque)
    destino[o + 2] = byte(c.pPedregoso)
    destino[o + 3] = byte(c.pCamino)
    destino[o + 4] = byte(c.pArena)
    destino[o + 5] = byte(c.pBarro)
    destino[o + 6] = byte(c.pRoca)
    destino[o + 7] = byte(c.pNieve)
    destino[o + 8] = byte(c.pFondo)
    destino[o + 9], destino[o + 10], destino[o + 11] = 0, 0, 0
end

-- Faldón -------------------------------------------------------------------------------------

--- Posición en el perímetro de un cuadrado centrado de (u, v), con u y v de
-- -1 a 1 y alguno de los dos en el borde: de 0 a 4, en sentido antihorario
-- desde la esquina (-1, -1).
local function parametroPerimetro(u, v)
    if math.abs(v) >= math.abs(u) and v < 0 then
        return (u / -v + 1) / 2
    elseif math.abs(u) >= math.abs(v) and u > 0 then
        return 1 + (v / u + 1) / 2
    elseif math.abs(v) >= math.abs(u) then
        return 2 + (1 - u / v) / 2
    end
    return 3 + (1 + v / u) / 2
end

--- Punto (u, v) del perímetro del cuadrado unidad en la posición `p` (0 a 4).
local function puntoPerimetro(p)
    local lado = math.floor(p) % 4
    local t = p - math.floor(p)
    if lado == 0 then
        return -1 + 2 * t, -1
    elseif lado == 1 then
        return 1, -1 + 2 * t
    elseif lado == 2 then
        return 1 - 2 * t, 1
    end
    return -1, 1 - 2 * t
end

--- Cota de la gran llanura del faldón: algo por debajo de la altura típica
-- del borde del área (percentil 30 de su tierra firme), nunca bajo el mar.
function Suelo:medirLlanura()
    local rej = self.relieve
    local lado = rej.lado
    local alturas = {}
    for k = 0, lado - 1 do
        for _, indice in ipairs({ k, (lado - 1) * lado + k, k * lado, k * lado + lado - 1 }) do
            local h = rej.h[indice]
            if h > self.nivelMar then
                alturas[#alturas + 1] = h
            end
        end
    end
    table.sort(alturas)
    local tipica = alturas[math.max(1, math.floor(#alturas * 0.3))] or self.nivelMar
    self.llanura = math.max(self.nivelMar + 25, tipica - Suelo.bajadaLlanura)
end

--- Altura del faldón en (x, y), fuera del área: el mapa real (sus lomas,
-- lagos y orillas siguen con su forma), fundido con la llanura a lo largo de
-- `fusionFaldon` px desde el borde. Sin paredes: todo es suave.
function Suelo:alturaFaldon(x, y)
    local h = self:alturaFaldonBase(x, y)
    if self.cauces and self.cauces.hay then
        h = self.cauces:alturaFaldon(x, y, h)
    end
    return h
end

--- Altura del faldón sin el río ni el cañón (con ella se traza el cauce).
function Suelo:alturaFaldonBase(x, y)
    local medio = Suelo.lado / 2
    local m = math.max(math.abs(x - self.cx), math.abs(y - self.cy), medio)
    local peso = suavizarPaso((m - medio) / Suelo.fusionFaldon)
    local mapa = self.terreno:altura(x, y) + self:detalleAltura(x, y)
    return mapa + (self.llanura - mapa) * peso
end

--- Anillos del faldón en `malla` (la del terreno: el mismo material y el
-- mismo dibujo). El primer anillo son los vértices del borde de la rejilla,
-- con su color y su normal: no hay costura. Hacia fuera, el mapa real
-- fundido con la llanura (Suelo:alturaFaldon), con los colores de
-- ESTILO-TERRENO sin bosque ni flores, poco detalle y anillos cada vez más
-- gruesos; el horizonte lo funde el shader (dream/textura_terreno.lua).
function Suelo:generarFaldon(malla, cr, cg, cb, registro)
    local rej = self.relieve
    local lado = rej.lado
    local medio = Suelo.lado / 2
    local cx, cy = self.cx, self.cy
    local terreno = self.terreno
    local semilla = terreno.semilla
    local r1 = Ruido.nuevo(semilla + 27111)
    local r2 = Ruido.nuevo(semilla + 27112)
    local cara = {}
    local anterior = { ColorTerreno.rocaDesde, ColorTerreno.rocaHasta }
    ColorTerreno.rocaDesde, ColorTerreno.rocaHasta = self.rocaDesde, self.rocaHasta

    -- Anillo 0: el borde de la rejilla en el orden del perímetro.
    local indices = {}
    for i = 0, lado - 2 do
        indices[#indices + 1] = i
    end
    for j = 0, lado - 2 do
        indices[#indices + 1] = j * lado + lado - 1
    end
    for i = lado - 1, 1, -1 do
        indices[#indices + 1] = (lado - 1) * lado + i
    end
    for j = lado - 1, 1, -1 do
        indices[#indices + 1] = j * lado
    end
    local anillos = {}
    local primero = { p = {}, x = {}, y = {}, h = {}, nx = {}, ny = {}, nz = {}, r = {}, g = {}, b = {} }
    primero.pesos = ffi.new('uint8_t[?]', #indices * 12)
    for n, k in ipairs(indices) do
        local x, y = rej.x[k], rej.y[k]
        primero.p[n] = parametroPerimetro((x - cx) / medio, (y - cy) / medio)
        primero.x[n], primero.y[n], primero.h[n] = x, y, rej.h[k]
        primero.nx[n], primero.ny[n], primero.nz[n] = rej.nx[k], rej.ny[k], rej.nz[k]
        primero.r[n], primero.g[n], primero.b[n] = cr[k], cg[k], cb[k]
        if rej.pesos then
            ffi.copy(primero.pesos + (n - 1) * 12, rej.pesos + k * 12, 12)
        end
    end
    anillos[1] = primero

    -- Anillos de fuera: posiciones uniformes en el perímetro.
    for a = 2, #Suelo.anillosFaldon do
        local m = Suelo.anillosFaldon[a]
        local cuantos = Suelo.verticesFaldon[a]
        local anillo = { p = {}, x = {}, y = {}, h = {}, nx = {}, ny = {}, nz = {}, r = {}, g = {}, b = {} }
        anillo.pesos = ffi.new('uint8_t[?]', cuantos * 12)
        local e = (m - Suelo.anillosFaldon[a - 1]) * 0.5
        for n = 1, cuantos do
            local p = (n - 1) * 4 / cuantos
            local u, v = puntoPerimetro(p)
            local x, y = cx + u * m, cy + v * m
            local h = self:alturaFaldon(x, y)
            local gx = (self:alturaFaldon(x + e, y) - self:alturaFaldon(x - e, y)) / (2 * e)
            local gy = (self:alturaFaldon(x, y + e) - self:alturaFaldon(x, y - e)) / (2 * e)
            local l = math.sqrt(1 + gx * gx + gy * gy)
            anillo.p[n], anillo.x[n], anillo.y[n], anillo.h[n] = p, x, y, h
            anillo.nx[n], anillo.ny[n], anillo.nz[n] = -gx / l, -gy / l, 1 / l
            -- Pradera con muy poco detalle: ruidos grandes, sin bosque ni flores.
            cara.x, cara.y, cara.h = x, y, h
            cara.nx, cara.ny, cara.nz = anillo.nx[n], anillo.ny[n], anillo.nz[n]
            cara.n1 = r1:simplex(x / 4000, y / 4000)
            cara.n2 = r2:simplex(x / 9000, y / 9000)
            cara.fino = 0
            cara.humedad = terreno:humedadEn(x, y)
            cara.bosque = 0
            cara.dAgua, cara.nivelAgua = 1e6, self.nivelMar
            cara.manchas = nil
            anillo.r[n], anillo.g[n], anillo.b[n] = ColorTerreno.cara(self, cara)
            Suelo.guardarPesos(anillo.pesos, (n - 1) * 12, cara)
        end
        anillos[a] = anillo
    end
    ColorTerreno.rocaDesde, ColorTerreno.rocaHasta = anterior[1], anterior[2]

    local suaveN = Suelo.normalSuave
    local planaN = 1 - suaveN
    local function vertice(anillo, n, fx, fy, fz)
        local nx = anillo.nx[n] * suaveN + fx * planaN
        local ny = anillo.ny[n] * suaveN + fy * planaN
        local nz = anillo.nz[n] * suaveN + fz * planaN
        local l = math.sqrt(nx * nx + ny * ny + nz * nz)
        malla:vertice(
            anillo.x[n],
            anillo.y[n],
            anillo.h[n],
            nx / l,
            ny / l,
            nz / l,
            anillo.r[n],
            anillo.g[n],
            anillo.b[n]
        )
    end
    local function triangulo(aa, na, ab, nb, ac, nc)
        local ax, ay, az = aa.x[na], aa.y[na], aa.h[na]
        local ux, uy, uz = ab.x[nb] - ax, ab.y[nb] - ay, ab.h[nb] - az
        local vx, vy, vz = ac.x[nc] - ax, ac.y[nc] - ay, ac.h[nc] - az
        local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        local l = math.sqrt(nx * nx + ny * ny + nz * nz)
        if l < 1e-9 then
            return
        end
        if nz < 0 then
            l = -l
            ab, nb, ac, nc = ac, nc, ab, nb
        end
        nx, ny, nz = nx / l, ny / l, nz / l
        vertice(aa, na, nx, ny, nz)
        vertice(ab, nb, nx, ny, nz)
        vertice(ac, nc, nx, ny, nz)
        if registro then
            registro[#registro + 1] = { aa, na, ab, nb, ac, nc, nx, ny, nz }
        end
    end

    -- Cada par de anillos se cose avanzando por el perímetro por el que
    -- tenga el siguiente vértice más atrás: sirve con cuentas distintas.
    for a = 1, #anillos - 1 do
        local dentro, fuera = anillos[a], anillos[a + 1]
        local nd, nf = #dentro.p, #fuera.p
        local i, j = 0, 0
        while i < nd or j < nf do
            local pd = i + 1 < nd and dentro.p[i + 2] or 4
            local pf = j + 1 < nf and fuera.p[j + 2] or 4
            local ia, ja = i % nd + 1, j % nf + 1
            if i < nd and (j >= nf or pd <= pf) then
                triangulo(dentro, ia, dentro, (i + 1) % nd + 1, fuera, ja)
                i = i + 1
            else
                triangulo(dentro, ia, fuera, (j + 1) % nf + 1, fuera, ja)
                j = j + 1
            end
        end
    end
end

--- ¿Hay mar? Solo si alguna parte del área está bajo su nivel (antes de los
-- pasillos y del cauce, que la cambian). La malla va en `construirAgua`.
function Suelo:generarAgua()
    local minimo = math.huge
    local rej = self.relieve
    for k = 0, rej.total - 1 do
        minimo = math.min(minimo, rej.h[k])
    end
    self.hayMar = minimo < self.terreno.nivelMar
end

--- Malla del agua: el mar, un plano a su nivel, y la cinta del río
-- (batalla/cauces.lua) con el mismo material.
function Suelo:construirAgua()
    local hayRio = self.cauces and self.cauces.rio
    if not self.hayMar and not hayRio then
        return
    end
    local malla = Malla.nueva(6)
    if hayRio then
        self.cauces:agregarAgua(malla)
    end
    if not self.hayMar then
        if malla.n > 0 then
            self.mallaAgua = malla:crear()
        end
        return
    end
    -- Hasta el último anillo del faldón: donde el borde es agua, sigue siéndolo.
    local medio = Suelo.anillosFaldon[#Suelo.anillosFaldon]
    local x0, y0 = self.cx - medio, self.cy - medio
    local x1, y1 = self.cx + medio, self.cy + medio
    local z = self.terreno.nivelMar
    local agua = Terreno.colores.agua
    malla:triangulo(x0, y0, z, x1, y0, z, x1, y1, z, agua)
    malla:triangulo(x0, y0, z, x1, y1, z, x0, y1, z, agua)
    self.mallaAgua = malla:crear()
end

-- Vegetación ----------------------------------------------------------------------------------

--- Prototipos y copias de la vegetación y las rocas (batalla/vegetacion.lua
-- y batalla/colocacion.lua). Aquí solo se colocan: la escena los dibuja por
-- instancias (batalla/dream/vegetacion.lua).
function Suelo:generarPlantas()
    local inicio = love.timer.getTime()
    self.prototipos, self.triangulosPrototipos = Vegetacion.construir(self.terreno.semilla)
    self.tiempos.prototipos = love.timer.getTime() - inicio
    inicio = love.timer.getTime()
    self.colocacion:plantar()
    self.tiempos.colocar = love.timer.getTime() - inicio
    self.copias = self.colocacion.copias
    self.plantas = #self.copias
    self.triangulosPlantas = 0
end

--- ¿Cae (x, y) sobre el edificio del sitio (donde no crecen plantas ni se
-- ponen vehículos)? `margen` en px.
function Suelo:ocupado(x, y, margen)
    local s = self.sitio
    if not s then
        return false
    end
    if self.plano then
        return self.plano:ocupado(x, y, margen)
    end
    local r = self:radioEdificio() + (margen or 0)
    return math.abs(x - s.x) < r and math.abs(y - s.y) < r
end

function Suelo:radioEdificio()
    local sitio = self.sitio
    local r = self.plano and self.plano.recinto
    if r then
        return math.max(r[3] - r[1], r[4] - r[2]) / 2
    end
    if sitio and sitio.tipo == 'ciudad' then
        return Ciudades.lado * 0.5
    end
    return 200
end

Suelo.celdaPlantas = 128 -- px de la rejilla donde se apuntan las plantas

--- Apunta una planta { x, y, arbol, radio, alto } en la rejilla (para no
-- poner vehículos encima). Los árboles y las rocas grandes (`arbol = true`)
-- van también a la física.
function Suelo:apuntarPlanta(p)
    -- Clave numérica (no de texto): se apuntan decenas de miles al entrar.
    local clave = math.floor(p.x / Suelo.celdaPlantas) * 131072 + math.floor(p.y / Suelo.celdaPlantas)
    local lista = self.celdasPlantas[clave] or {}
    lista[#lista + 1] = p
    self.celdasPlantas[clave] = lista
    if p.arbol then
        self.plantasFisicas[#self.plantasFisicas + 1] = p
    end
end

--- Colisiones del terreno de esta batalla (batalla/colisiones.lua): cada
-- planta grande y cada sólido del plano declara su forma y sus etiquetas. Se
-- hacen una vez, al pedirlas, con todo ya generado.
function Suelo:getColisiones()
    if self.colisiones then
        return self.colisiones
    end
    local col = require('batalla.colisiones').nueva()
    self.colisiones = col
    for _, p in ipairs(self.plantasFisicas) do
        if not p.caido then
            local z0 = (p.z or self:altura(p.x, p.y)) / 10 - 0.5
            local alto = (p.alto or 80) / 10
            local r = (p.radio or 4) / 10
            local etiquetas = { solido = true, cobertura = true }
            if not p.roca then
                etiquetas.derribable = true
                etiquetas.copa = { z0 = z0 + alto * 0.35, r = math.max(r + 0.5, alto * 0.35) }
            end
            p.colision = col:poner(p, { tipo = 'cilindro', x = p.x / 10, y = -p.y / 10, r = r, z0 = z0, z1 = z0 + 0.5 + alto }, etiquetas)
        end
    end
    if self.plano then
        for _, h in ipairs(self.plano.listaHuellas or {}) do
            if h.solido then
                h.colision = col:poner(h, {
                    tipo = 'caja', x = h.cx / 10, y = -h.cy / 10, hx = h.hx / 10, hy = h.hy / 10, rumbo = -h.ang,
                    z0 = h.z0 / 10, z1 = h.z1 / 10,
                }, { solido = true, cobertura = true })
            end
        end
    end
    return col
end

--- Un árbol alcanzado por un proyectil cae hacia (dx, dy) (la dirección del
-- disparo) y, con `quemado`, se oscurece. Deja de estorbar a la física y a
-- las balas, y la vegetación rehace su baldosa (batalla/dream/vegetacion.lua).
function Suelo:derribarArbol(p, dx, dy, quemado)
    if p.caido or p.roca or not p.copia then
        return false
    end
    p.caido = true
    -- Deja de ocupar sitio (sensores, ojos y cuerpo de los robots).
    if self.colisiones and p.colision then
        self.colisiones:quitar(p.colision)
    end
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 1e-6 then
        dx, dy, l = 1, 0, 1
    end
    dx, dy = dx / l, dy / l
    -- Giro de 84° alrededor del eje horizontal (-dy, dx, 0) (Rodrigues): la
    -- copa, que apuntaba arriba, queda tendida hacia (dx, dy).
    local ax, ay = -dy, dx
    local a = math.rad(84)
    local c, s = math.cos(a), math.sin(a)
    local t = 1 - c
    local r = {
        c + ax * ax * t,
        ax * ay * t,
        ay * s,
        ay * ax * t,
        c + ay * ay * t,
        -ax * s,
        -ay * s,
        ax * s,
        c,
    }
    local m = p.copia.m
    local n = {}
    for fila = 0, 2 do
        for columna = 0, 2 do
            n[fila * 3 + columna + 1] = r[fila * 3 + 1] * m[columna + 1]
                + r[fila * 3 + 2] * m[columna + 4]
                + r[fila * 3 + 3] * m[columna + 7]
        end
    end
    p.copia.m = n
    if quemado then
        p.copia.t1, p.copia.t2, p.copia.t3 = 0.2, 0.17, 0.15
    else
        p.copia.t1, p.copia.t2, p.copia.t3 = p.copia.t1 * 0.85, p.copia.t2 * 0.8, p.copia.t3 * 0.7
    end
    if p.fixture and not p.fixture:isDestroyed() then
        p.fixture:destroy()
    end
    self.cambiosVegetacion = self.cambiosVegetacion or {}
    self.cambiosVegetacion[#self.cambiosVegetacion + 1] = p.copia
    return true
end

--- Quita una planta del mapa (la pista del avión de carga se abre en el
-- bosque, como un aeródromo): su copia pasa a escala casi nula y deja la
-- física y las colisiones, como un árbol derribado (derribarArbol).
function Suelo:quitarPlanta(p)
    if p.quitada then
        return false
    end
    p.quitada, p.caido = true, true
    if self.colisiones and p.colision then
        self.colisiones:quitar(p.colision)
    end
    if p.copia then
        self:encogerCopia(p.copia)
    end
    if p.fixture and not p.fixture:isDestroyed() then
        p.fixture:destroy()
    end
    return true
end

--- La copia de una planta, a escala casi nula (deja de verse).
function Suelo:encogerCopia(copia)
    if copia.encogida then
        return
    end
    copia.encogida = true
    local n = {}
    for k = 1, 9 do
        n[k] = copia.m[k] * 1e-4
    end
    copia.m = n
    -- (Las rocas se dibujan con su escala, no con la matriz.)
    copia.escala = (copia.escala or 1) * 1e-4
    self.cambiosVegetacion = self.cambiosVegetacion or {}
    self.cambiosVegetacion[#self.cambiosVegetacion + 1] = copia
end

--- Quita las plantas de un rectángulo girado: centro (x, y) px, rumbo,
-- medio largo y medio ancho (px). Devuelve cuántas.
function Suelo:despejarFranja(x, y, rumbo, medioLargo, medioAncho)
    local c, s = math.cos(rumbo), math.sin(rumbo)
    local r = math.sqrt(medioLargo * medioLargo + medioAncho * medioAncho)
    local celda = Suelo.celdaPlantas
    local cuantas = 0
    for i = math.floor((x - r) / celda), math.floor((x + r) / celda) do
        for j = math.floor((y - r) / celda), math.floor((y + r) / celda) do
            for _, p in ipairs(self.celdasPlantas[i * 131072 + j] or {}) do
                local dx, dy = p.x - x, p.y - y
                local a, l = dx * c + dy * s, -dx * s + dy * c
                if math.abs(a) < medioLargo and math.abs(l) < medioAncho and self:quitarPlanta(p) then
                    cuantas = cuantas + 1
                end
            end
        end
    end
    -- Las copias que no se apuntan (piedras, matas, hierba): todas.
    for _, co in ipairs(self.copias or {}) do
        local dx, dy = co.x - x, co.y - y
        if dx * dx + dy * dy < r * r then
            local a, l = dx * c + dy * s, -dx * s + dy * c
            if math.abs(a) < medioLargo and math.abs(l) < medioAncho and not co.encogida then
                self:encogerCopia(co)
                cuantas = cuantas + 1
            end
        end
    end
    return cuantas
end

--- ¿Hay alguna planta (salvo hierba y flores) a menos de `radio` px de
-- (x, y)? Con `soloArboles`, solo cuentan los árboles y las rocas grandes.
function Suelo:plantaCerca(x, y, radio, soloArboles)
    local c = Suelo.celdaPlantas
    local i0, j0 = math.floor((x - radio) / c), math.floor((y - radio) / c)
    local i1, j1 = math.floor((x + radio) / c), math.floor((y + radio) / c)
    for j = j0, j1 do
        for i = i0, i1 do
            for _, p in ipairs(self.celdasPlantas[i * 131072 + j] or {}) do
                local cuenta = not soloArboles or p.arbol
                if cuenta and (p.x - x) ^ 2 + (p.y - y) ^ 2 < radio * radio then
                    return true
                end
            end
        end
    end
    return false
end

-- Edificios ---------------------------------------------------------------------------------

local PIEDRA = { 0.78, 0.76, 0.72 }
local CRISTAL = { 0.46, 0.56, 0.64 }

--- Ventanas en las cuatro caras de un cuerpo de `lado` px centrado en (x, y),
-- de `z0` a `z1`: unas encendidas y otras no, siempre las mismas (salen de la
-- semilla del sitio).
local function ventanas(m, x, y, lado, z0, z1, azar)
    local columnas = math.max(1, math.floor(lado / 45))
    local filas = math.floor((z1 - z0) / 40)
    local ancho, alto = 18, 22
    for cara = 0, 3 do
        local rumbo = cara * math.pi / 2
        local nx, ny = math.cos(rumbo), math.sin(rumbo)
        for f = 0, filas - 1 do
            for c = 0, columnas - 1 do
                local t = ((c + 0.5) / columnas - 0.5) * lado
                local wx = x + nx * (lado / 2 + 0.8) - ny * t
                local wy = y + ny * (lado / 2 + 0.8) + nx * t
                local luz = azar() < 0.45
                local color = luz and { 1, 0.86, 0.5 } or { 0.2, 0.25, 0.34 }
                m:caja(wx, wy, z0 + 12 + f * 40, 2, ancho, alto, rumbo, color)
            end
        end
    end
end

--- Recorre los vértices de la rejilla dentro del rectángulo (px) dado y
-- llama `fn(k, x, y)`.
function Suelo:vertices(x0, y0, x1, y1, fn)
    local rej = self.relieve
    local xs, ys, lado = rej.xs, rej.ys, rej.lado
    local i0, i1, j0, j1 = lado, -1, lado, -1
    for i = 1, lado do
        if xs[i] > x0 and xs[i] < x1 then
            i0, i1 = math.min(i0, i - 1), math.max(i1, i - 1)
        end
        if ys[i] > y0 and ys[i] < y1 then
            j0, j1 = math.min(j0, i - 1), math.max(j1, i - 1)
        end
    end
    -- Un vértice más por cada lado (la rejilla está desplazada).
    i0, j0 = math.max(0, i0 - 1), math.max(0, j0 - 1)
    i1, j1 = math.min(lado - 1, i1 + 1), math.min(lado - 1, j1 + 1)
    local px, py = rej.x, rej.y
    for j = j0, j1 do
        for i = i0, i1 do
            local k = j * lado + i
            fn(k, px[k], py[k])
        end
    end
end

--- Explanada (desmonte y terraplén, como se hace en ladera) de una caja
-- girada: centro (cx, cy), medios lados (hx, hy) y giro `ang`. Dentro queda a
-- la altura `z` (o la que dé `alturaEn(u, v)`, con u y v las coordenadas
-- locales) y alrededor el terreno vuelve al suyo en `borde` px (el talud).
-- Los vértices ya explanados antes (`rej.explanado`) no se tocan, para no
-- hundir ni levantar lo construido.
function Suelo:explanarCaja(cx, cy, hx, hy, ang, z, borde, alturaEn, talud)
    local rej = self.relieve
    rej.explanado = rej.explanado or ffi.new('uint8_t[?]', rej.total)
    local fijo, ph = rej.explanado, rej.h
    local c, s = math.cos(ang), math.sin(ang)
    -- `talud` (ancho por alto): el borde crece con lo más hondo que corta o
    -- rellena la caja, para que el desmonte tenga la pendiente de un talud
    -- y no quede un paredón. Hasta 150 m de talud.
    if talud then
        local hondo = 0
        self:vertices(cx - math.abs(hx * c) - math.abs(hy * s), cy - math.abs(hx * s) - math.abs(hy * c),
            cx + math.abs(hx * c) + math.abs(hy * s), cy + math.abs(hx * s) + math.abs(hy * c), function(k, x, y)
            local dx, dy = x - cx, y - cy
            local u, v = dx * c + dy * s, -dx * s + dy * c
            if math.abs(u) <= hx and math.abs(v) <= hy then
                local zz = alturaEn and alturaEn(u, v) or z
                hondo = math.max(hondo, math.abs(zz - ph[k]))
            end
        end)
        borde = math.min(1500, math.max(borde, hondo * talud))
    end
    local r = math.abs(hx * c) + math.abs(hy * s) + borde
    local q = math.abs(hx * s) + math.abs(hy * c) + borde
    local nuevos = {}
    self:vertices(cx - r, cy - q, cx + r, cy + q, function(k, x, y)
        if fijo[k] ~= 0 then
            return
        end
        local dx, dy = x - cx, y - cy
        local u, v = dx * c + dy * s, -dx * s + dy * c
        local ex, ey = math.max(math.abs(u) - hx, 0), math.max(math.abs(v) - hy, 0)
        local d = math.sqrt(ex * ex + ey * ey)
        if d < borde then
            local w = 1 - d / borde
            w = w * w * (3 - 2 * w)
            local zz = z
            if alturaEn then
                zz = alturaEn(math.max(-hx, math.min(hx, u)), math.max(-hy, math.min(hy, v)))
            end
            ph[k] = ph[k] + (zz - ph[k]) * w
            if d == 0 then
                nuevos[#nuevos + 1] = k
            end
        end
    end)
    for _, k in ipairs(nuevos) do
        fijo[k] = 1
    end
end

--- Explanada alineada con los ejes (rectángulo x0..x1, y0..y1).
function Suelo:explanar(x0, y0, x1, y1, z, borde)
    self:explanarCaja((x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, 0, z, borde)
end

--- Explanada de un tramo de calle de (x0, y0, z0) a (x1, y1, z1): de lado a
-- lado plano (sin peralte) y a lo largo en rampa; `medio` px de ancho a cada
-- lado y talud de `borde` px.
function Suelo:explanarTramo(x0, y0, z0, x1, y1, z1, medio, borde, talud)
    local dx, dy = x1 - x0, y1 - y0
    local largo = math.sqrt(dx * dx + dy * dy)
    if largo < 1 then
        return
    end
    local ang = math.atan2(dy, dx)
    self:explanarCaja((x0 + x1) / 2, (y0 + y1) / 2, largo / 2, medio, ang, z0, borde, function(u)
        local t = (u + largo / 2) / largo
        return z0 + (z1 - z0) * t
    end, talud)
end

--- Las calles del plano como caminos de tierra: la distancia de cada vértice
-- a la calle más cercana entra en `dPasillo` (la que pinta los caminos y
-- quita la hierba de su centro: batalla/color_terreno.lua, colocacion.lua).
function Suelo:marcarCalles()
    local rej = self.relieve
    local plano = self.plano
    local r = plano.recinto
    if not r then
        return
    end
    if not rej.dPasillo then
        rej.dPasillo = Rejilla.array(rej.total)
        for k = 0, rej.total - 1 do
            rej.dPasillo[k] = 1e9
        end
    end
    local calles = plano.calles
    local px, py, d = rej.x, rej.y, rej.dPasillo
    for k = 0, rej.total - 1 do
        local x, y = px[k], py[k]
        if x > r[1] - 200 and x < r[3] + 200 and y > r[2] - 200 and y < r[4] + 200 then
            local mejor = d[k]
            for _, c in ipairs(calles) do
                local ax, ay, bx, by = c[1], c[2], c[3], c[4]
                local dx, dy = bx - ax, by - ay
                local l2 = dx * dx + dy * dy
                local t = l2 > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / l2)) or 0
                local ex, ey = ax + dx * t - x, ay + dy * t - y
                local dist = math.sqrt(ex * ex + ey * ey)
                if dist < mejor then
                    mejor = dist
                end
            end
            d[k] = mejor
        end
    end
end

function Suelo:generarEdificio()
    local s = self.sitio
    if not s or self.plano then
        return
    end
    local m = Malla.nueva(20000)
    local azar = Ruido.azar(Ruido.hash(self.terreno.semilla, math.floor(s.x), math.floor(s.y), 11))
    local z = self:altura(s.x, s.y)
    if s.tipo == 'ciudad' then
        -- La torre del mapa (Ciudades.torre) en 3D: zócalo, fuste de cristal,
        -- corona con la franja del país y aguja.
        local t = Ciudades.torre
        m:caja(s.x, s.y, z - 20, Ciudades.lado, Ciudades.lado, 22, 0, { 0.8, 0.76, 0.68 })
        m:caja(s.x, s.y, z, t.base, t.base, t.altoBase, 0, PIEDRA)
        ventanas(m, s.x, s.y, t.base, z, z + t.altoBase - 10, azar)
        m:caja(s.x, s.y, z + t.altoBase, t.fuste, t.fuste, t.alto - t.altoBase, 0, CRISTAL)
        ventanas(m, s.x, s.y, t.fuste, z + t.altoBase, z + t.alto - 20, azar)
        m:caja(s.x, s.y, z + t.alto, t.corona, t.corona, t.altoCorona, 0, PIEDRA)
        m:caja(s.x, s.y, z + t.alto + t.altoCorona - 30, t.corona + 4, t.corona + 4, 18, 0, { 1, 1, 1 }, 1)
        m:prisma(s.x, s.y, z + t.alto + t.altoCorona, 6, 3, t.aguja, 4, { 0.7, 0.72, 0.75 })
    else
        -- Losa y casetas: una base es más grande y tiene hangar; un
        -- campamento son tiendas; una extracción, su torre de bombeo.
        local radio = s.tipo == 'base' and 160 or 120
        m:prisma(s.x, s.y, z - 20, radio + 20, radio, 24, 8, { 0.62, 0.57, 0.48 }, math.pi / 8)
        if s.tipo == 'campamento' then
            for k = 0, 4 do
                local a = k / 5 * math.pi * 2
                m:prisma(s.x + math.cos(a) * 55, s.y + math.sin(a) * 55, z + 4, 26, 0, 30, 4, { 0.6, 0.55, 0.4 }, a)
            end
            m:prisma(s.x, s.y, z + 4, 3, 3, 60, 4, { 0.5, 0.45, 0.4 })
        elseif s.tipo == 'base' then
            m:caja(s.x - 40, s.y, z + 4, 150, 90, 45, 0, { 0.55, 0.58, 0.52 })
            m:caja(s.x - 40, s.y, z + 49, 150, 94, 6, 0, { 1, 1, 1 }, 1)
            m:caja(s.x + 90, s.y + 60, z + 4, 50, 50, 35, 0, PIEDRA)
            m:caja(s.x + 90, s.y - 60, z + 4, 50, 50, 25, 0, PIEDRA)
        else
            m:caja(s.x, s.y, z + 4, 70, 70, 30, 0, PIEDRA)
            m:prisma(s.x + 50, s.y + 40, z + 4, 20, 6, 110, 4, { 0.4, 0.4, 0.42 })
            m:prisma(s.x - 60, s.y - 40, z + 4, 30, 30, 50, 8, { 0.7, 0.66, 0.55 })
        end
    end
    self.mallaEdificio = m:crear()
end

return Suelo
