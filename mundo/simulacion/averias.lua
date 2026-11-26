--- Averías por zona de los vehículos (decisión del dueño del 2026-10-01): qué
-- se rompió, cuánto cuesta y cuánto tarda el taller en cada zona, y las
-- averías y bajas de tripulación de la batalla simulada.
--
-- Zonas (batalla/DANO-REAL.md §5.4): orugas (en el camión, las ruedas),
-- torreta, cañón (en el camión, el lanzador), motor y tripulación. Además, el
-- casco: los agujeros (`estructura`, de 0 a 1). La tripulación no se repara en
-- el taller: sus bajas son personas (muertos y heridos de la nación,
-- poblacion.lua y taller.lua).
--
-- Cada vehículo averiado guarda un CÓDIGO entero junto a su daño y su modelo
-- (`averias.zonas[tipo][k]`, en el mismo orden que `averias[tipo]` y
-- `averias.modelos[tipo]`):
--   código = máscara + 16 × estructura en milésimas
--   máscara = orugas 1 + torreta 2 + cañón 4 + motor 8
-- Ejemplo: oruga y motor rotos con 0,3 de casco = 1 + 8 + 16 × 300 = 4809.
-- El número de la lista de daños (`averias[tipo][k]`) pasa a ser el TRABAJO de
-- taller del vehículo (Σ trabajo de sus zonas), en los puntos de siempre: el
-- taller repara `Armamento.ritmo(modelo) × nivel` puntos al día.
--
-- Una avería de antes (solo un daño d) es casco d: cuesta y tarda lo mismo que
-- antes (las partidas viejas no cambian de golpe).
--
-- Solo datos, sin LÖVE y sin azar propio: la batalla simulada recibe su
-- generador (Ruido.azar de la semilla, el día y la batalla).

local Averias = {}

local ZONAS = { 'orugas', 'torreta', 'canon', 'motor' }
Averias.ZONAS = ZONAS

local BIT = { orugas = 1, torreta = 2, canon = 4, motor = 8 }
Averias.BIT = BIT

local MASCARA = 16
local MILESIMAS = 1000

--- Perillas. Coste de cada zona en partes de la reparación de daño 1 del
-- modelo (`Armamento.reparacion`: T-72B 12 de dinero y 2 de metal; Scud-B 16
-- y 3) y trabajo en puntos de taller (T-72B: 0,5 al día por nivel; Scud-B,
-- 0,4). Días de un T-72B en un taller de nivel 1 = trabajo / 0,5.
Averias.reglas = {
    zonas = {
        -- Eslabones y ruedas: se cambian en el sitio. Rápida y barata.
        orugas = { trabajo = 0.15, dinero = 0.15, metal = 0.1 }, -- T-72B: 0,3 días, 1,8 y 0,2
        -- Anillo y mecanismo de giro atascados: piezas pequeñas, mucho ajuste.
        torreta = { trabajo = 0.5, dinero = 0.5, metal = 0.3 }, -- 1 día, 6 y 0,6
        -- Tubo nuevo: una pieza grande de acero. Caro en metal.
        canon = { trabajo = 0.8, dinero = 0.9, metal = 1.5 }, -- 1,6 días, 10,8 y 3
        -- Cambio del grupo motor: lo más largo y lo más caro en dinero.
        motor = { trabajo = 1.0, dinero = 1.2, metal = 1.0 }, -- 2 días, 14,4 y 2
    },
    -- Por cada 1,0 de estructura (casco agujereado): lo mismo que el daño 1 de
    -- antes, para que una avería vieja (casco d) cueste y tarde lo de antes.
    casco = { trabajo = 1, dinero = 1, metal = 1 },
    estructuraMaxima = 1, -- el casco deshecho no cuesta más que rehacerlo
    -- Batalla simulada (F8): por vehículo que cae, probabilidad de cada avería,
    -- de agujeros en el casco (`casco`) y su media (`estructura`, repartida
    -- entre la mitad y 1,5 veces, con tope 1) y de bajas en la tripulación
    -- (`tripulacion`); con bajas, cae entera (`entera`) o de 1 a `parcial`
    -- tripulantes (sin llegar a todos). Medidas en la batalla 3D con el daño
    -- real (pruebas_dano, semillas 42, 7 y 1234, 900 s, onda × 3): 58
    -- lanzacohetes averiados (los tanques se quitaron el 19-nov).
    simulada = {
        lanzacohetes = {
            orugas = 0.59,
            torreta = 0,
            canon = 0.12,
            motor = 0.21,
            casco = 0.97,
            estructura = 0.59,
            tripulacion = 0.83,
            entera = 0.25,
            parcial = 3,
        },
    },
    muerteTripulante = 0.4, -- un tripulante que cae muere (la de los soldados, F11b; DANO-REAL.md §5.6)
}

local REGLAS = Averias.reglas

-- Códigos ------------------------------------------------------------------------------------------

--- Código de unas zonas `{ orugas = true, ..., estructura = 0 a 1 }` (las de la
-- batalla 3D, `Blindaje.zonas`). La tripulación no entra: va aparte.
function Averias.codificar(z)
    local mascara = 0
    for _, zona in ipairs(ZONAS) do
        if z and z[zona] then
            mascara = mascara + BIT[zona]
        end
    end
    local estructura = math.max(0, math.min(REGLAS.estructuraMaxima, tonumber(z and z.estructura) or 0))
    return mascara + MASCARA * math.floor(estructura * MILESIMAS + 0.5)
end

--- Zonas de un código: `{ orugas, torreta, canon, motor (true o false), estructura }`.
function Averias.decodificar(codigo)
    local mascara = codigo % MASCARA
    local z = { estructura = math.floor(codigo / MASCARA) / MILESIMAS }
    for _, zona in ipairs(ZONAS) do
        z[zona] = math.floor(mascara / BIT[zona]) % 2 == 1
    end
    return z
end

--- ¿Tiene el código esa zona rota?
function Averias.tiene(codigo, zona)
    return math.floor((codigo % MASCARA) / BIT[zona]) % 2 == 1
end

--- Código de una avería de antes, que solo tenía su daño `d`: casco d.
function Averias.deDano(d)
    return Averias.codificar({ estructura = d or 1 })
end

--- Suma de `campo` ('trabajo', 'dinero' o 'metal') de las zonas del código.
local function sumar(codigo, campo)
    local s = 0
    for _, zona in ipairs(ZONAS) do
        if Averias.tiene(codigo, zona) then
            s = s + REGLAS.zonas[zona][campo]
        end
    end
    return s + math.floor(codigo / MASCARA) / MILESIMAS * REGLAS.casco[campo]
end

--- Puntos de taller de un código (el número de la lista de daños).
function Averias.trabajo(codigo)
    return sumar(codigo, 'trabajo')
end

--- Lo que cuesta reparar un código en un modelo cuya reparación de daño 1
-- es `reparacion` ({ dinero, metal }, `Armamento.reparacion`).
function Averias.coste(codigo, reparacion)
    return { dinero = reparacion.dinero * sumar(codigo, 'dinero'), metal = reparacion.metal * sumar(codigo, 'metal') }
end

-- Listas -------------------------------------------------------------------------------------------

--- Lista de códigos de `tipo` de unas averías, completa: crea la de
-- `averias.zonas` si falta y rellena lo que no tenga código con el de su
-- daño (una avería de antes: casco d).
function Averias.zonasDe(averias, tipo)
    averias.zonas = averias.zonas or { lanzacohetes = {} }
    local zonas = averias.zonas[tipo]
    local danos = averias[tipo] or {}
    for k = #zonas + 1, #danos do
        zonas[k] = Averias.deDano(danos[k])
    end
    return zonas
end

--- Código del vehículo `k` de `tipo` de unas averías (el de su daño si no tiene).
function Averias.codigo(averias, tipo, k)
    local zonas = averias and averias.zonas and averias.zonas[tipo]
    local c = zonas and zonas[k]
    if c then
        return c
    end
    local danos = averias and averias[tipo]
    return Averias.deDano(danos and danos[k] or 1)
end

-- Batalla simulada ---------------------------------------------------------------------------------

--- Avería de un vehículo de `tipo` con `tripulantes` tripulantes que cae en la
-- batalla simulada, con el generador `azar` (Ruido.azar). Devuelve su código,
-- sus bajas de tripulación y cuántas de ellas mueren. Nunca sale vacía: sin
-- nada roto, el casco con lo mínimo de una penetración (0,15).
function Averias.simular(azar, tipo, tripulantes)
    local p = REGLAS.simulada[tipo]
    local z = {}
    for _, zona in ipairs(ZONAS) do
        z[zona] = azar() < p[zona]
    end
    if azar() < p.casco then
        z.estructura = p.estructura * (0.5 + azar())
    end
    local codigo = Averias.codificar(z)
    if codigo == 0 then
        codigo = Averias.codificar({ estructura = 0.15 })
    end
    local bajas = 0
    tripulantes = tripulantes or 3
    if azar() < p.tripulacion then
        if azar() < p.entera then
            bajas = tripulantes
        else
            bajas = math.min(tripulantes, 1 + math.floor(azar() * math.min(p.parcial, tripulantes - 1)))
        end
    end
    local muertos = 0
    for _ = 1, bajas do
        if azar() < REGLAS.muerteTripulante then
            muertos = muertos + 1
        end
    end
    return codigo, bajas, muertos
end

return Averias
