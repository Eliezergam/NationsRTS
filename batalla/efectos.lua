--- Efectos de la batalla (Camila): estelas de humo de los misiles, nube de
-- lanzamiento, fogonazos, impactos (misil, bala de tanque, fusil; contra el
-- suelo, un vehículo, el agua, un árbol o una roca), restos que arden,
-- destellos de luz y marcas de quemado.
--
-- Solo mira: no cambia la simulación ni el azar de `batalla/tropas.lua`
-- (lleva su propio generador). Tropas avisa de lo que pasa (ver los
-- ganchos `-- Efectos (Camila)` en tropas.lua) y aquí se decide qué
-- partículas salen. Lo que se dibuja lo hace una `salida`
-- (`batalla/dream/efectos.lua` en 3DreamEngine), con esta interfaz:
--
--   salida:particula(clase, p)     clase 'humo', 'fuego', 'chispa', 'roca',
--                                  'astilla' o 'metal'; p, la tabla de abajo
--   salida:tramoEstela(a, b)       tramo de cinta entre dos puntos de estela
--   salida:cabezaEstela(e, a, b)   tramo que va del último punto a la tobera
--   salida:soltarCabeza(e)         la estela `e` ya no tiene misil
--   salida:llama(p)                sprite de un solo cuadro (tobera, trazador)
--   salida:luz(x, y, z, r, g, b, brillo, duracion, debil)
--   salida:marca(x, y, z, radio, giro)
--
-- Unidades: posiciones en px del juego (10 px = 1 m, z arriba); velocidades,
-- tamaños y aceleraciones en metros. `p.subida` es la aceleración vertical
-- (negativa: gravedad) y `p.arrastre` el frenado del aire (1/s); con ambos
-- la salida calcula el movimiento en la GPU (ver dream/efectos/comun.lua).

local Tropas = require('batalla.tropas')

local Efectos = {}
Efectos.__index = Efectos

local M = 10 -- px por metro
local G = -9.8

-- Calidades: `cantidad` multiplica el número de partículas; la estela
-- emite un punto cada `pasoEstela` m y una bocanada cada `bocanadas` m
-- (0: sin bocanadas); `luces`, destellos a la vez.
Efectos.calidades = {
    baja = {
        cantidad = 0.45,
        pasoEstela = 9,
        bocanadas = 0,
        vidaEstela = 5.5,
        escombros = false,
        restos = 0.9,
        luces = 0,
        marcas = 12,
    },
    media = {
        cantidad = 0.7,
        pasoEstela = 6,
        bocanadas = 28,
        vidaEstela = 7,
        escombros = true,
        restos = 0.55,
        luces = 3,
        marcas = 24,
    },
    alta = {
        cantidad = 1,
        pasoEstela = 4,
        bocanadas = 16,
        vidaEstela = 9,
        escombros = true,
        restos = 0.35,
        luces = 6,
        marcas = 48,
    },
}

-- Tamaño de la explosión de un misil (escala 1) respecto a las medidas de
-- las recetas: la cabeza de un cohete de 10 m hace una bola de fuego de unos
-- 20 m y levanta polvo en 40.
Efectos.tamanoExplosion = 1.8

-- Colores (sRGB).
local C = {
    fuegoVivo = { 1, 0.95, 0.78 },
    fuego = { 1, 0.78, 0.4 },
    fuegoBola = { 1, 0.74, 0.34 },
    fuegoFrio = { 0.62, 0.14, 0.03 },
    chispa = { 1, 0.86, 0.5 },
    chispaFria = { 1, 0.42, 0.1 },
    chispaMetal = { 1, 0.95, 0.82 },
    polvo = { 0.62, 0.55, 0.45 },
    polvoClaro = { 0.76, 0.71, 0.63 },
    tierra = { 0.3, 0.24, 0.18 },
    tierraClara = { 0.46, 0.39, 0.31 },
    humoNegro = { 0.07, 0.065, 0.06 },
    humoGris = { 0.36, 0.35, 0.34 },
    humoClaro = { 0.8, 0.78, 0.74 },
    humoBlanco = { 0.93, 0.93, 0.91 },
    agua = { 0.82, 0.88, 0.94 },
    espuma = { 0.96, 0.98, 1 },
    hojas = { 0.2, 0.3, 0.12 },
    hojasClaras = { 0.34, 0.42, 0.18 },
    corteza = { 0.5, 0.38, 0.25 },
    roca = { 0.44, 0.42, 0.39 },
    terron = { 0.32, 0.25, 0.18 },
    metal = { 0.24, 0.25, 0.26 },
    luzFuego = { 1, 0.58, 0.28 },
}

--- `tropas` (para leer misiles, balas y unidades), `suelo` (alturas y
-- agua), `salida` y el nombre de la calidad.
function Efectos.nuevos(tropas, suelo, salida, calidad)
    local self = setmetatable({}, Efectos)
    self.tropas = tropas
    self.suelo = suelo
    self.salida = salida
    self.calidad = Efectos.calidades[calidad or 'alta'] or Efectos.calidades.alta
    local combate = tropas.combate
    local semilla = math.floor(math.abs(combate.cx * 3 + combate.cy * 5)) % 2147483646 + 1
    self.azar = love.math.newRandomGenerator(semilla)
    -- Viento de la batalla: flojo, de una dirección que sale del sitio.
    local a = self.azar:random() * math.pi * 2
    local fuerza = 2.2 + self.azar:random() * 1.8
    self.viento = { math.cos(a) * fuerza, math.sin(a) * fuerza }
    self.restos = {}
    self.p = {
        color0 = C.humoClaro,
        color1 = C.humoClaro,
    }
    -- Puntos de trabajo de las estelas (sin tablas por cuadro).
    self.puntoA = {}
    self.puntoB = {}
    self.llamaTrabajo = { color0 = C.fuegoVivo, color1 = C.fuego }
    return self
end

-- Utilidades -----------------------------------------------------------------------------------

local function unitario(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if l < 1e-9 then
        return 0, 0, 1
    end
    return x / l, y / l, z / l
end

--- Cuántas de `n` salen con la calidad actual (al menos `minimo`).
function Efectos:cuantas(n, minimo)
    return math.max(minimo or 1, math.floor(n * self.calidad.cantidad + 0.5))
end

function Efectos:entre(a, b)
    return a + self.azar:random() * (b - a)
end

--- Dirección al azar dentro de un cono de `apertura` rad alrededor de (x, y, z).
function Efectos:cono(x, y, z, apertura)
    local azar = self.azar
    local cosMin = math.cos(apertura)
    local c = cosMin + (1 - cosMin) * azar:random()
    local s = math.sqrt(math.max(0, 1 - c * c))
    local a = azar:random() * math.pi * 2
    -- Base ortonormal alrededor del eje.
    local ux, uy, uz
    if math.abs(z) < 0.9 then
        ux, uy, uz = unitario(-y, x, 0)
    else
        ux, uy, uz = unitario(0, -z, y)
    end
    local vx, vy, vz = y * uz - z * uy, z * ux - x * uz, x * uy - y * ux
    local ca, sa = math.cos(a) * s, math.sin(a) * s
    return x * c + ux * ca + vx * sa, y * c + uy * ca + vy * sa, z * c + uz * ca + vz * sa
end

--- Deja la partícula de trabajo en (x, y, z) px con valores neutros.
function Efectos:nueva(x, y, z)
    local p = self.p
    p.x, p.y, p.z = x, y, z
    p.vx, p.vy, p.vz = 0, 0, 0
    p.retraso = 0
    p.vida = 1
    p.tam0, p.tam1 = 1, 1
    p.arrastre = 1
    p.subida = 0
    p.suelo = nil
    p.viento = 1
    p.alfa = 1
    p.emision = 0
    p.curva = 0.25
    p.estirar = 0
    p.variante = self.azar:random(0, 3)
    p.semilla = self.azar:random(0, 255)
    p.giro0 = self.azar:random() * math.pi * 2
    p.giro = (self.azar:random() - 0.5) * 0.8
    return p
end

function Efectos:emitir(clase)
    self.salida:particula(clase, self.p)
end

--- Altura del suelo o del agua en (x, y) y si es agua.
function Efectos:superficie(x, y)
    local s = self.suelo
    local h = s:altura(x, y)
    local mar = s.nivelMar or -math.huge
    if h < mar - 2 then
        return mar, true
    end
    return h, false
end

-- Recetas -----------------------------------------------------------------------------------------

--- Fogonazo: un destello que dura unas centésimas.
function Efectos:destello(x, y, z, tam, vida, color)
    local p = self:nueva(x, y, z)
    p.vida = vida
    p.tam0, p.tam1 = tam, tam * 1.3
    p.arrastre = 5
    p.viento = 0
    p.color0, p.color1 = color or C.fuegoVivo, C.fuego
    p.curva = 0.5
    p.emision = 1
    p.alfa = 1
    self:emitir('fuego')
end

--- Bola de fuego que se abre, sube y se apaga.
function Efectos:bolaDeFuego(x, y, z, escala, n)
    for _ = 1, self:cuantas(n, 2) do
        local dx, dy, dz = self:cono(0, 0, 1, 1.4)
        local v = self:entre(3, 11) * math.sqrt(escala)
        local p = self:nueva(x + dx * 1.5 * escala * M, y + dy * 1.5 * escala * M, z + (dz * 1.2 + 0.6) * escala * M)
        p.vx, p.vy, p.vz = dx * v, dy * v, dz * v
        p.retraso = self:entre(0, 0.06)
        p.vida = self:entre(0.45, 0.85) * math.sqrt(escala)
        p.tam0, p.tam1 = self:entre(2.2, 3.4) * escala, self:entre(5.5, 8) * escala
        p.arrastre = 3
        p.subida = 3.5
        p.viento = 0.3
        p.color0, p.color1 = C.fuegoBola, C.fuegoFrio
        p.curva = 0.5
        p.emision = 0.32
        p.alfa = 0.9
        self:emitir('fuego')
    end
end

--- Chispas en un cono alrededor de (nx, ny, nz); `metal` más blancas y rápidas.
function Efectos:chispas(x, y, z, nx, ny, nz, apertura, n, rapidez, metal, sueloZ, grosor)
    for _ = 1, self:cuantas(n, 1) do
        local dx, dy, dz = self:cono(nx, ny, nz, apertura)
        local v = self:entre(0.45, 1) * rapidez
        local p = self:nueva(x, y, z)
        p.vx, p.vy, p.vz = dx * v, dy * v, dz * v
        p.vida = self:entre(0.35, 0.95)
        p.tam0, p.tam1 = (metal and 0.12 or 0.14) * (grosor or 1), 0.06 * (grosor or 1)
        p.arrastre = 0.8
        p.subida = G
        p.viento = 0.05
        p.suelo = sueloZ
        p.color0, p.color1 = metal and C.chispaMetal or C.chispa, C.chispaFria
        p.curva = 0.3
        p.emision = 0.6
        p.estirar = 0.25
        self:emitir('chispa')
    end
end

--- Tierra que salta en grumos (partículas de polvo oscuro con gravedad).
function Efectos:tierra(x, y, z, nx, ny, nz, apertura, n, rapidez, tam, sueloZ, color0, color1)
    for _ = 1, self:cuantas(n, 1) do
        local dx, dy, dz = self:cono(nx, ny, nz, apertura)
        local v = self:entre(0.5, 1) * rapidez
        local p = self:nueva(x, y, z)
        p.vx, p.vy, p.vz = dx * v, dy * v, dz * v
        p.vida = self:entre(1.1, 1.9)
        p.tam0, p.tam1 = tam * 0.45, tam * self:entre(1.1, 1.6)
        p.arrastre = 1.3
        p.subida = G * 0.8
        p.viento = 0.3
        p.suelo = sueloZ
        p.color0, p.color1 = color0 or C.tierra, color1 or C.tierraClara
        p.curva = 0.6
        p.alfa = 0.95
        self:emitir('humo')
    end
end

--- Escombros 3D (`clase` roca, astilla o metal) que saltan y ruedan.
function Efectos:escombros(clase, x, y, z, nx, ny, nz, apertura, n, rapidez, tam, sueloZ, color)
    if not self.calidad.escombros then
        return
    end
    for _ = 1, self:cuantas(n, 1) do
        local dx, dy, dz = self:cono(nx, ny, nz, apertura)
        local v = self:entre(0.4, 1) * rapidez
        local p = self:nueva(x, y, z)
        p.vx, p.vy, p.vz = dx * v, dy * v, dz * v
        p.vida = self:entre(3.5, 5.5)
        p.tam0 = tam * self:entre(0.5, 1.2)
        p.tam1 = p.tam0
        p.arrastre = 0.12
        p.subida = G
        p.viento = 0
        p.suelo = sueloZ
        p.giro = self:entre(5, 14)
        p.color0, p.color1 = color, color
        -- Metal: algo metálico (va en `estirar`, que el escombro no usa).
        p.estirar = clase == 'metal' and 0.55 or 0
        self:emitir(clase)
    end
end

--- Polvo que sale en anillo pegado al suelo (onda de la explosión).
function Efectos:ondaDePolvo(x, y, z, n, rapidez, tam, vida, color0, color1, alfa)
    local total = self:cuantas(n, 3)
    for k = 1, total do
        local a = (k + self.azar:random() * 0.8) / total * math.pi * 2
        local v = self:entre(0.7, 1) * rapidez
        local p = self:nueva(x + math.cos(a) * tam * 0.3 * M, y + math.sin(a) * tam * 0.3 * M, z + tam * 0.25 * M)
        p.vx, p.vy, p.vz = math.cos(a) * v, math.sin(a) * v, self:entre(0.3, 1.5)
        p.vida = vida * self:entre(0.8, 1.15)
        p.tam0, p.tam1 = tam * 0.45, tam * self:entre(1.3, 1.8)
        p.arrastre = 2.2
        p.subida = 0.25
        p.viento = 0.8
        p.color0, p.color1 = color0 or C.polvo, color1 or C.polvoClaro
        p.curva = 0.5
        p.alfa = alfa or 0.7
        self:emitir('humo')
    end
end

--- Columna de humo que sigue saliendo `duracion` s y sube despacio.
function Efectos:columna(x, y, z, n, duracion, tam, vida, color0, color1, alfa)
    for k = 1, self:cuantas(n, 2) do
        local p = self:nueva(x + self:entre(-1, 1) * tam * 2, y + self:entre(-1, 1) * tam * 2, z + tam * 0.3 * M)
        p.vx, p.vy, p.vz = self:entre(-1, 1), self:entre(-1, 1), self:entre(4, 8)
        p.retraso = duracion * (k - 1) / n + self:entre(0, 0.1)
        p.vida = vida * self:entre(0.8, 1.2)
        p.tam0, p.tam1 = tam * 0.5, tam * self:entre(1.6, 2.2)
        p.arrastre = 0.5
        p.subida = 0.7
        p.viento = 1
        p.color0, p.color1 = color0, color1
        p.curva = 0.7
        p.alfa = alfa or 0.8
        self:emitir('humo')
    end
end

--- Dirección de lo que sale despedido: la normal del suelo, inclinada hacia
-- el reflejo de la trayectoria cuando la bala llega rasante.
local function eyeccion(dx, dy, dz)
    local rasante = 1 - math.min(1, math.abs(dz))
    -- Reflejo sobre la normal (0, 0, 1): conserva la horizontal, invierte z.
    return unitario(dx * 0.9 * rasante, dy * 0.9 * rasante, 0.8 + math.abs(dz) * 0.3)
end

--- Explosión grande (misil, vehículo que revienta). `escala` 1 = misil.
function Efectos:explosion(x, y, z, escala, superficie, dx, dy, dz)
    local suelo, agua = self:superficie(x, y)
    local k = escala * Efectos.tamanoExplosion
    local rk = math.sqrt(k)
    if agua or superficie == 'agua' then
        return self:salpicadura(x, y, suelo, k * 0.9, true)
    end
    local ex, ey, ez = eyeccion(dx or 0, dy or 0, dz or -1)
    local z0 = math.max(z, suelo)
    self:destello(x, y, z0 + 2 * k * M, 9 * k, 0.14)
    self:bolaDeFuego(x, y, z0, k, 12)
    self:chispas(x, y, z0 + 5, ex, ey, ez, 1.1, 22, 45 * rk, false, suelo)
    self.salida:luz(x, y, z0 + 4 * M, C.luzFuego[1], C.luzFuego[2], C.luzFuego[3], 60 * k, 0.5)
    if superficie == 'arbol' then
        self:astillas(x, y, z, 1.4 * k)
    elseif superficie == 'roca' then
        self:escombros('roca', x, y, z0, ex, ey, ez, 0.9, 12, 20 * rk, 0.25 * k, suelo, C.roca)
    end
    -- Tierra, terrones, onda de polvo y marca (también bajo un vehículo o un
    -- árbol, si la explosión está cerca del suelo).
    if z - suelo < 6 * M then
        self:tierra(x, y, z0 + 5, ex, ey, ez, 0.6, 18, 20 * rk, 2.4 * k, suelo)
        self:escombros('roca', x, y, z0 + 5, ex, ey, ez, 0.8, 16, 20 * rk, 0.24 * k, suelo, C.terron)
        self:ondaDePolvo(x, y, suelo, 18, 22 * rk, 3.4 * k, 3.6, C.polvo, C.polvoClaro, 0.7)
        self.salida:marca(x, y, suelo, 2.6 * k, self.azar:random() * math.pi * 2)
    end
    self:columna(x, y, z0, 18, 2.6, 4.2 * k, 8, C.humoNegro, C.humoGris, 0.6)
end

--- Salpicadura en el agua: columna, gotas, espuma y bruma.
function Efectos:salpicadura(x, y, nivel, escala, conLuz)
    local azar = self.azar
    -- Columna: agua que sube recta y cae.
    for _ = 1, self:cuantas(18, 4) do
        local a = azar:random() * math.pi * 2
        local r = self:entre(0, 1.2) * escala
        local p = self:nueva(x + math.cos(a) * r * M, y + math.sin(a) * r * M, nivel + 0.3 * M)
        local h = self:entre(0.3, 2.5) * math.sqrt(escala)
        p.vx, p.vy, p.vz = math.cos(a) * h, math.sin(a) * h, self:entre(12, 26) * math.sqrt(escala)
        p.retraso = self:entre(0, 0.12)
        p.vida = self:entre(1.4, 2.2) * math.sqrt(escala)
        p.tam0, p.tam1 = self:entre(1.2, 2) * escala, self:entre(3.5, 5) * escala
        p.arrastre = 0.5
        p.subida = G
        p.suelo = nivel
        p.viento = 0.3
        p.color0, p.color1 = C.agua, C.espuma
        p.alfa = 0.85
        self:emitir('humo')
    end
    -- Corona de gotas que se abre en cono.
    for _ = 1, self:cuantas(26, 5) do
        local dx, dy, dz = self:cono(0, 0, 1, 0.8)
        local v = self:entre(8, 20) * math.sqrt(escala)
        local p = self:nueva(x, y, nivel + 0.5 * M)
        p.vx, p.vy, p.vz = dx * v, dy * v, dz * v
        p.vida = self:entre(1.1, 1.9)
        p.tam0, p.tam1 = 0.6 * escala, 0.35 * escala
        p.arrastre = 0.4
        p.subida = G
        p.suelo = nivel
        p.viento = 0.1
        p.color0, p.color1 = C.espuma, C.agua
        p.alfa = 0.9
        self:emitir('humo')
    end
    self:ondaDePolvo(x, y, nivel, 14, 9 * math.sqrt(escala), 3 * escala, 3.5, C.espuma, C.agua, 0.6)
    for _ = 1, self:cuantas(4, 1) do
        local p = self:nueva(x + self:entre(-1, 1) * M, y + self:entre(-1, 1) * M, nivel + 2 * escala * M)
        p.vz = self:entre(1, 2)
        p.vida = self:entre(2.5, 3.5)
        p.tam0, p.tam1 = 3 * escala, 9 * escala
        p.arrastre = 1
        p.subida = 0.2
        p.color0, p.color1 = C.espuma, C.humoBlanco
        p.alfa = 0.35
        self:emitir('humo')
    end
    if conLuz then
        self:destello(x, y, nivel + 1.5 * escala * M, 5 * escala, 0.08, C.fuegoVivo)
        self.salida:luz(x, y, nivel + 3 * M, C.luzFuego[1], C.luzFuego[2], C.luzFuego[3], 35 * escala, 0.25)
    end
end

--- Astillas y agujas de un árbol alcanzado.
function Efectos:astillas(x, y, z, escala)
    local suelo = self:superficie(x, y)
    self:escombros('astilla', x, y, z, 0, 0, 1, 1.3, 10, 16 * math.sqrt(escala), 0.5 * escala, suelo, C.corteza)
    for _ = 1, self:cuantas(20, 4) do
        local dx, dy, dz = self:cono(0, 0, 1, 1.5)
        local v = self:entre(2, 9) * math.sqrt(escala)
        local p = self:nueva(x, y, z)
        p.vx, p.vy, p.vz = dx * v, dy * v, dz * v
        p.vida = self:entre(2.5, 4)
        p.tam0, p.tam1 = 0.35, 0.45
        p.arrastre = 2.8
        p.subida = -2.2
        p.suelo = suelo
        p.viento = 0.9
        p.giro = self:entre(-3, 3)
        p.color0 = self.azar:random() < 0.5 and C.hojas or C.hojasClaras
        p.color1 = C.hojas
        p.alfa = 0.95
        self:emitir('humo')
    end
    self:tierra(x, y, z, 0, 0, 1, 1.2, 4, 5, 1.2, suelo, C.corteza, C.polvoClaro)
end

--- Impacto pequeño: bala de tanque (`canon`) o de fusil, contra el suelo,
-- un vehículo, el agua, un árbol o una roca.
function Efectos:impactoPequeno(x, y, z, arma, superficie, dx, dy, dz)
    local suelo, agua = self:superficie(x, y)
    local canon = arma == 'canon'
    local escala = canon and 1 or 0.25
    if agua and z < suelo + 1 * M then
        return self:salpicadura(x, y, suelo, canon and 0.55 or 0.15, false)
    end
    local ex, ey, ez = eyeccion(dx or 0, dy or 0, dz or -0.2)
    if superficie == 'vehiculo' then
        -- Metal: chispas blancas en abanico hacia atrás de la bala y chapas.
        local rx, ry, rz = unitario(-(dx or 0) + ex * 0.4, -(dy or 0) + ey * 0.4, 0.5)
        self:destello(x, y, z, canon and 4.5 or 0.8, 0.07, C.chispaMetal)
        self:chispas(x, y, z, rx, ry, rz, 1.3, canon and 45 or 6, canon and 55 or 30, true, suelo, canon and 1.4 or 1)
        if canon then
            self:escombros('metal', x, y, z, rx, ry, rz, 1, 7, 12, 0.35, suelo, C.metal)
            self:humoGolpe(x, y, z, 3.5, C.humoGris, C.humoClaro)
            self.salida:luz(x, y, z + 2 * M, 1, 0.8, 0.55, 18, 0.1)
        end
        return
    end
    if superficie == 'arbol' then
        self:astillas(x, y, z, canon and 0.8 or 0.2)
        if not canon then
            return
        end
    end
    if superficie == 'roca' then
        self:chispas(x, y, z, ex, ey, ez, 1, canon and 10 or 3, 35, true, suelo)
        self:escombros('roca', x, y, z, ex, ey, ez, 0.9, canon and 8 or 0, 14, 0.2, suelo, C.roca)
        self:humoGolpe(x, y, z, canon and 2 or 0.6, C.humoGris, C.polvoClaro)
        return
    end
    if canon then
        self:destello(x, y, z + 1 * M, 5, 0.08)
        self:chispas(x, y, z + 3, ex, ey, ez, 0.9, 10, 35, false, suelo)
        self:tierra(x, y, z + 3, ex, ey, ez, 0.5, 16, 18, 2.8, suelo)
        self:escombros('roca', x, y, z + 3, ex, ey, ez, 0.7, 8, 13, 0.16, suelo, C.terron)
        self:ondaDePolvo(x, y, suelo, 9, 11, 2.4, 2.6, C.polvo, C.polvoClaro, 0.6)
        self:humoGolpe(x, y, z, 4.5, C.polvo, C.polvoClaro)
        self.salida:marca(x, y, suelo, 1.8, self.azar:random() * math.pi * 2)
        self.salida:luz(x, y, z + 1.5 * M, C.luzFuego[1], C.luzFuego[2], C.luzFuego[3], 14, 0.12)
    else
        -- Fusil: un golpe de polvo y, a veces, una chispa.
        self:humoGolpe(x, y, z, 0.5 * escala * 4, C.polvo, C.polvoClaro)
        if self.azar:random() < 0.3 then
            self:chispas(x, y, z + 2, ex, ey, ez, 0.8, 1, 20, false, suelo)
        end
    end
end

--- Nubecilla de un golpe: sube un poco y se abre.
function Efectos:humoGolpe(x, y, z, tam, color0, color1)
    for _ = 1, self:cuantas(tam > 1 and 4 or 1, 1) do
        local dx, dy, dz = self:cono(0, 0, 1, 1)
        local v = self:entre(1, 3) * math.sqrt(tam)
        local p = self:nueva(x, y, z + tam * 0.3 * M)
        p.vx, p.vy, p.vz = dx * v, dy * v, dz * v
        p.vida = self:entre(1.6, 2.6) * math.min(1.6, math.sqrt(tam))
        p.tam0, p.tam1 = tam * 0.4, tam * self:entre(1.2, 1.7)
        p.arrastre = 1.5
        p.subida = 0.4
        p.color0, p.color1 = color0, color1
        p.curva = 0.5
        p.alfa = 0.7
        self:emitir('humo')
    end
end

-- Eventos (llamados desde tropas.lua) ----------------------------------------------------------

--- Un misil sale del tubo: fogonazo, llamarada hacia atrás, nube de
-- lanzamiento que se queda en el suelo, y su estela.
function Efectos:lanzamiento(m, x, y, z, dx, dy, dz)
    local suelo = self:superficie(x, y)
    local bx, by, bz = -dx, -dy, -dz
    self:destello(x, y, z, 3.4, 0.12)
    for _ = 1, self:cuantas(6, 2) do
        local cx, cy, cz = self:cono(bx, by, bz, 0.35)
        local v = self:entre(14, 30)
        local p = self:nueva(x, y, z)
        p.vx, p.vy, p.vz = cx * v, cy * v, cz * v
        p.vida = self:entre(0.22, 0.4)
        p.tam0, p.tam1 = 1.3, 3.4
        p.arrastre = 4
        p.subida = 2
        p.viento = 0.2
        p.color0, p.color1 = C.fuegoVivo, C.fuegoFrio
        p.emision = 0.7
        p.alfa = 0.9
        self:emitir('fuego')
    end
    self:chispas(x, y, z, bx, by, bz, 0.5, 6, 25, false, suelo)
    -- Chorro de humo hacia atrás que al tocar el suelo se abre.
    for _ = 1, self:cuantas(14, 4) do
        local cx, cy, cz = self:cono(bx, by, bz, 0.5)
        local v = self:entre(8, 22)
        local p = self:nueva(x - dx * 2 * M, y - dy * 2 * M, z - dz * 2 * M)
        p.vx, p.vy, p.vz = cx * v, cy * v, cz * v
        p.retraso = self:entre(0, 0.25)
        p.vida = self:entre(6, 9)
        p.tam0, p.tam1 = self:entre(1.8, 2.6), self:entre(7, 10)
        p.arrastre = 1.2
        p.subida = 0.2
        p.suelo = suelo + 1.5 * M
        p.viento = 0.9
        p.color0, p.color1 = C.humoClaro, C.humoBlanco
        p.curva = 0.4
        p.alfa = 0.62
        self:emitir('humo')
    end
    -- Polvo levantado alrededor de la trasera del camión.
    local tx, ty = x - dx * 6 * M, y - dy * 6 * M
    self:ondaDePolvo(tx, ty, self:superficie(tx, ty), 12, 14, 3.2, 8, C.polvo, C.polvoClaro, 0.55)
    self.salida:luz(x, y, z + 1 * M, C.luzFuego[1], C.luzFuego[2], C.luzFuego[3], 30, 0.4)
    -- Estela: el primer punto en la boca del tubo.
    local e = {
        misil = m,
        semilla = self.azar:random() * 50,
        escala = self:entre(0.9, 1.12),
        recorrido = 0,
        siguienteBocanada = self.calidad.bocanadas,
    }
    local a = self.puntoA
    a.x, a.y, a.z = x, y, z
    a.tx, a.ty, a.tz = unitario(dx, dy, dz)
    a.nace = self.tropas.reloj
    a.t = 0
    e.ultimo = { x = x, y = y, z = z, tx = a.tx, ty = a.ty, tz = a.tz, nace = a.nace, t = 0, recorrido = 0 }
    m.efectoEstela = e
end

--- Posición y tangente del misil `m` en la fracción `t` de su vuelo.
local function puntoMisil(m, t, punto)
    local x, y, z = Tropas.posicionMisil(m, t)
    local ax, ay, az = Tropas.posicionMisil(m, math.max(0, t - 0.002))
    local bx, by, bz = Tropas.posicionMisil(m, math.min(1, t + 0.002))
    punto.x, punto.y, punto.z = x, y, z
    punto.tx, punto.ty, punto.tz = unitario(bx - ax, by - ay, bz - az)
    return punto
end

local function copiarPunto(desde, hacia)
    hacia.x, hacia.y, hacia.z = desde.x, desde.y, desde.z
    hacia.tx, hacia.ty, hacia.tz = desde.tx, desde.ty, desde.tz
    hacia.nace, hacia.t, hacia.recorrido = desde.nace, desde.t, desde.recorrido
end

--- Bocanada de la estela: da volumen a la cinta vista de frente.
function Efectos:bocanadaEstela(e, punto)
    local p = self:nueva(punto.x, punto.y, punto.z)
    p.retraso = punto.nace - self.tropas.reloj
    p.vida = self.calidad.vidaEstela * 0.85
    p.tam0, p.tam1 = 1.2 * e.escala, 9 * e.escala
    p.arrastre = 0.4
    p.subida = 0.2
    p.viento = 1
    p.color0, p.color1 = C.humoClaro, C.humoBlanco
    p.curva = 0.3
    p.alfa = 0.12
    self:emitir('humo')
end

--- Avanza la estela `e` hasta la fracción `t` del vuelo en el instante
-- `reloj`: añade puntos cada `pasoEstela` m (a alta velocidad no se
-- deshilacha) y deja la cabeza unida a la tobera.
function Efectos:avanzarEstela(e, t, reloj, final)
    local m = e.misil
    local paso = self.calidad.pasoEstela * M
    local ultimo = e.ultimo
    local actual = puntoMisil(m, t, self.puntoB)
    actual.nace, actual.t = reloj, t
    local dx, dy, dz = actual.x - ultimo.x, actual.y - ultimo.y, actual.z - ultimo.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local pasos = 0
    while d >= paso and pasos < 64 do
        pasos = pasos + 1
        local fraccion = paso / d
        local ti = ultimo.t + (t - ultimo.t) * fraccion
        local nuevo = puntoMisil(m, ti, self.puntoA)
        nuevo.nace = ultimo.nace + (reloj - ultimo.nace) * fraccion
        nuevo.t = ti
        local ddx, ddy, ddz = nuevo.x - ultimo.x, nuevo.y - ultimo.y, nuevo.z - ultimo.z
        nuevo.recorrido = ultimo.recorrido + math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz) / M
        self.salida:tramoEstela(e, ultimo, nuevo)
        copiarPunto(nuevo, ultimo)
        if self.calidad.bocanadas > 0 and ultimo.recorrido >= e.siguienteBocanada then
            e.siguienteBocanada = ultimo.recorrido + self.calidad.bocanadas * self:entre(0.7, 1.3)
            self:bocanadaEstela(e, ultimo)
        end
        dx, dy, dz = actual.x - ultimo.x, actual.y - ultimo.y, actual.z - ultimo.z
        d = math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    actual.recorrido = ultimo.recorrido + d / M
    if final then
        if d > 1 then
            self.salida:tramoEstela(e, ultimo, actual)
        end
        self.salida:soltarCabeza(e)
    else
        self.salida:cabezaEstela(e, ultimo, actual)
    end
    return actual
end

--- El misil `m` cae (al final de su vuelo o contra una loma o un árbol).
function Efectos:impactoMisil(m, superficie)
    local e = m.efectoEstela
    local ax, ay, az = Tropas.posicionMisil(m, 0.985)
    local dx, dy, dz = unitario(m.x1 - ax, m.y1 - ay, m.z1 - az)
    if e then
        -- Último tramo hasta el punto del impacto.
        local t = math.min(1, (self.tropas.reloj - m.inicio) / m.duracion)
        self:avanzarEstela(e, t, self.tropas.reloj, true)
        m.efectoEstela = nil
    end
    self:explosion(m.x1, m.y1, m.z1, 1, superficie, dx, dy, dz)
end

--- Una bala llega a (x, y, z) contra `superficie` ('terreno', 'arbol',
-- 'roca' o 'vehiculo').
function Efectos:impactoBala(b, x, y, z, superficie)
    local dx, dy, dz = unitario(b.x1 - b.x0, b.y1 - b.y0, b.z1 - b.z0)
    self:impactoPequeno(x, y, z, b.canon and 'canon' or 'fusil', superficie, dx, dy, dz)
end

--- Disparo de `arma` ('canon' o 'fusil') desde la boca (x, y, z) hacia (dx, dy, dz).
function Efectos:disparo(arma, x, y, z, dx, dy, dz)
    dx, dy, dz = unitario(dx, dy, dz)
    if arma ~= 'canon' then
        local p = self:nueva(x + dx * 0.3 * M, y + dy * 0.3 * M, z + dz * 0.3 * M)
        p.vida = 0.05
        p.tam0, p.tam1 = 0.45, 0.3
        p.viento = 0
        p.color0, p.color1 = C.fuegoVivo, C.fuego
        p.emision = 0.8
        self:emitir('fuego')
        return
    end
    -- Llama hacia delante en tres tramos y dos chorros laterales (freno de boca).
    for k, tam in ipairs({ 3.2, 2.6, 1.8 }) do
        local d = (k - 0.6) * 1.6 * M
        self:destello(x + dx * d, y + dy * d, z + dz * d, tam, 0.08)
    end
    local lx, ly = unitario(-dy, dx, 0)
    for _, lado in ipairs({ -1, 1 }) do
        self:destello(x + lx * lado * 1 * M, y + ly * lado * 1 * M, z, 1.5, 0.06)
    end
    for _ = 1, self:cuantas(10, 3) do
        local cx, cy, cz = self:cono(dx, dy, dz, 0.35)
        local v = self:entre(5, 24)
        local p = self:nueva(x + dx * 1.5 * M, y + dy * 1.5 * M, z + dz * 1.5 * M)
        p.vx, p.vy, p.vz = cx * v, cy * v, cz * v
        p.vida = self:entre(2.4, 3.6)
        p.tam0, p.tam1 = 1.4, self:entre(5.5, 7)
        p.arrastre = 2.4
        p.subida = 0.35
        p.color0, p.color1 = C.humoGris, C.humoClaro
        p.curva = 0.4
        p.alfa = 0.6
        self:emitir('humo')
    end
    -- La onda de la boca levanta polvo si el cañón está cerca del suelo.
    local suelo = self:superficie(x, y)
    if z - suelo < 5 * M then
        local sx, sy = x + dx * 2 * M, y + dy * 2 * M
        self:ondaDePolvo(sx, sy, suelo, 8, 12, 2.6, 2.8, C.polvo, C.polvoClaro, 0.5)
    end
    self.salida:luz(x + dx * 2 * M, y + dy * 2 * M, z + 1 * M, 1, 0.72, 0.4, 20, 0.09)
end

--- Un vehículo cae: si revienta, explosión; y a partir de ahora arde.
function Efectos:destruccion(u, explota)
    if explota then
        self:explosion(u.x, u.y, u.z + 1 * M, 0.8, 'vehiculo', 0, 0, -1)
        self:escombros('metal', u.x, u.y, u.z + 2 * M, 0, 0, 1, 1, 8, 16, 0.45, u.z, C.metal)
    end
    self.restos[#self.restos + 1] = {
        u = u,
        desde = self.tropas.reloj,
        siguiente = self.tropas.reloj + 0.2,
        explota = explota,
    }
end

--- Deja de hacer humo por `u` (un averiado que se retira del campo: oleadas).
function Efectos:olvidar(u)
    for k = #self.restos, 1, -1 do
        if self.restos[k].u == u then
            table.remove(self.restos, k)
        end
    end
end

-- Cada cuadro -------------------------------------------------------------------------------------

--- Humo (y al principio fuego) de los restos.
function Efectos:arder(resto, reloj)
    local u = resto.u
    local edad = reloj - resto.desde
    local intervalo = self.calidad.restos * (edad < 30 and 1 or 2.2)
    while resto.siguiente <= reloj do
        resto.siguiente = resto.siguiente + intervalo * self:entre(0.7, 1.3)
        local p = self:nueva(u.x + self:entre(-1, 1) * M, u.y + self:entre(-1, 1) * M, u.z + 2 * M)
        p.retraso = resto.siguiente - intervalo - reloj
        p.vx, p.vy, p.vz = self:entre(-0.5, 0.5), self:entre(-0.5, 0.5), self:entre(2.5, 4.5)
        p.vida = self:entre(6, 8.5)
        p.tam0, p.tam1 = 1.8, self:entre(8, 11)
        p.arrastre = 0.45
        p.subida = 0.7
        p.viento = 1
        if edad < 30 then
            p.color0, p.color1 = C.humoNegro, C.humoGris
            p.alfa = 0.75
        else
            p.color0, p.color1 = C.humoGris, C.humoClaro
            p.alfa = 0.45
        end
        p.curva = 0.6
        self:emitir('humo')
        if edad < 22 then
            local f = self:nueva(u.x + self:entre(-1, 1) * M, u.y + self:entre(-1, 1) * M, u.z + 1.2 * M)
            f.vz = self:entre(1, 3)
            f.vida = self:entre(0.4, 0.8)
            f.tam0, f.tam1 = self:entre(1.4, 2.4), 0.8
            f.arrastre = 2
            f.subida = 3
            f.viento = 0.4
            f.color0, f.color1 = C.fuego, C.fuegoFrio
            f.emision = 0.55
            f.alfa = 0.9
            self:emitir('fuego')
            self.salida:luz(u.x, u.y, u.z + 3 * M, 1, 0.5, 0.2, 5, intervalo * 1.5, true)
        end
    end
end

--- Sprite de un cuadro: posición (px), dirección hacia la cola y largo (m),
-- ancho (m), colores y emisión.
function Efectos:llama(x, y, z, dx, dy, dz, largo, ancho, color0, emision, alfa)
    local l = self.llamaTrabajo
    l.x, l.y, l.z = x, y, z
    l.dx, l.dy, l.dz = dx, dy, dz
    l.largo, l.ancho = largo, ancho
    l.color0 = color0
    l.emision = emision
    l.alfa = alfa or 1
    self.salida:llama(l)
end

--- Avanza estelas y restos y pone las llamas de tobera y los trazadores.
function Efectos:actualizar()
    local tropas = self.tropas
    local reloj = tropas.reloj
    for _, m in ipairs(tropas.misiles) do
        local e = m.efectoEstela
        local t = math.max(0, math.min(1, (reloj - m.inicio) / m.duracion))
        if e then
            local punto = self:avanzarEstela(e, t, reloj, false)
            -- Llama de la tobera: hacia atrás, parpadea.
            local largo = self:entre(3.5, 5.5)
            self:llama(punto.x, punto.y, punto.z, -punto.tx, -punto.ty, -punto.tz, largo, 1.1, C.fuegoVivo, 0.9)
            self:llama(punto.x, punto.y, punto.z, -punto.tx, -punto.ty, -punto.tz, largo * 2.2, 2.6, C.fuego, 0.35, 0.5)
        end
    end
    for _, b in ipairs(tropas.balas) do
        local t = (reloj - b.inicio) / b.duracion
        local x, y, z = Tropas.posicionBala(b, t)
        local ax, ay, az = Tropas.posicionBala(b, math.max(0, t - 0.01))
        local dx, dy, dz = unitario(ax - x, ay - y, az - z)
        local largo = math.min((b.trazador or Tropas.largoTrazador) / M, t * b.largo / M)
        if b.canon then
            self:llama(x, y, z, dx, dy, dz, math.min(largo, 45), 0.35, C.fuego, 0.7)
        else
            self:llama(x, y, z, dx, dy, dz, math.min(largo, 9), 0.07, C.fuego, 0.45, 0.8)
        end
    end
    for k = #self.restos, 1, -1 do
        self:arder(self.restos[k], reloj)
    end
end

return Efectos
