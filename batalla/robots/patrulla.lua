-- Patrulla de varios robots por un recinto (el dueño, 27-nov: «mete varios
-- robots que cubran toda la zona, que la patrullen»; en las minas se libran
-- las batallas y el que gana se queda con la mina).
--
-- Como la patrulla multiagente por abandono (Machado et al., «Multi-Agent
-- Patrolling: an Empirical Analysis of Alternative Architectures», 2002;
-- Portugal y Rocha, «A Survey on Multi-robot Patrolling Algorithms», 2011):
-- el recinto se parte en celdas y cada celda guarda cuándo la vio un robot por
-- última vez. Al llegar a su destino, cada robot elige la celda más
-- abandonada, descontando lo que tarda en llegar, y nunca una que esté cerca
-- del destino de otro: así se reparten solos y no queda ningún rincón sin
-- mirar mucho rato.
--
-- Todo en m, en el sistema de los robots (x al este, y al norte).

local Patrulla = {}
Patrulla.__index = Patrulla

Patrulla.celda = 40 -- m de lado de cada celda
Patrulla.vista = 35 -- m alrededor de un robot que da por vistos
Patrulla.separacion = 90 -- m como poco entre el destino de un robot y el de otro
Patrulla.velocidad = 6 -- m/s con los que pasa la distancia a segundos
Patrulla.pesoDistancia = 0.5 -- lo que pesa el camino frente al abandono
Patrulla.porRobot = 60000 -- m² que cubre cada robot (6 ha)
Patrulla.minimoRobots = 3
Patrulla.maximoRobots = 8
Patrulla.nunca = 100000 -- s de abandono de una celda que nadie ha visto aún
Patrulla.evitarFallo = 60 -- s que se aparta una celda a la que no hubo ruta

--- Las celdas del rectángulo (x0, y0)-(x1, y1) en las que hay un punto donde
-- puede ir un robot: `vale(x, y)` lo dice (dentro del muro, fuera de los
-- edificios, en tierra transitable y sin un árbol encima).
function Patrulla.nueva(x0, y0, x1, y1, vale)
    local self = setmetatable({}, Patrulla)
    self.celdas = {}
    self.destinos = {}
    local c = Patrulla.celda
    local cuarto = c / 4
    -- Del centro de la celda hacia fuera: el primer sitio que valga.
    local pruebas = { { 0, 0 } }
    for _, r in ipairs({ cuarto, 2 * cuarto * 0.9 }) do
        for k = 0, 7 do
            local a = k / 8 * 2 * math.pi
            pruebas[#pruebas + 1] = { math.cos(a) * r, math.sin(a) * r }
        end
    end
    local columnas = math.max(1, math.floor((x1 - x0) / c))
    local filas = math.max(1, math.floor((y1 - y0) / c))
    local anchoCelda, altoCelda = (x1 - x0) / columnas, (y1 - y0) / filas
    for i = 0, columnas - 1 do
        for j = 0, filas - 1 do
            local cx, cy = x0 + (i + 0.5) * anchoCelda, y0 + (j + 0.5) * altoCelda
            for _, p in ipairs(pruebas) do
                local x, y = cx + p[1], cy + p[2]
                if vale(x, y) then
                    self.celdas[#self.celdas + 1] = { cx = cx, cy = cy, x = x, y = y }
                    break
                end
            end
        end
    end
    return self
end

--- Cuántos robots hacen falta para cubrirla.
function Patrulla:robots()
    local area = #self.celdas * Patrulla.celda * Patrulla.celda
    local n = math.floor(area / Patrulla.porRobot + 0.5)
    return math.max(Patrulla.minimoRobots, math.min(Patrulla.maximoRobots, n))
end

--- `n` sitios de salida repartidos por todo el recinto (cada uno, el más
-- lejos de los ya elegidos), empezando por el más cercano a (x, y). Con
-- `filtro(celda)`, solo entre las celdas que lo cumplan.
function Patrulla:salidas(n, x, y, filtro)
    local celdas = {}
    for _, c in ipairs(self.celdas) do
        if not filtro or filtro(c) then
            celdas[#celdas + 1] = c
        end
    end
    local elegidas = {}
    local cerca
    for _, c in ipairs(celdas) do
        local d = (c.x - x) ^ 2 + (c.y - y) ^ 2
        if not cerca or d < cerca then
            cerca = d
            elegidas[1] = c
        end
    end
    while #elegidas < n and #elegidas < #celdas do
        local mejor, mejorD
        for _, c in ipairs(celdas) do
            local minimo = math.huge
            for _, e in ipairs(elegidas) do
                minimo = math.min(minimo, (c.x - e.x) ^ 2 + (c.y - e.y) ^ 2)
            end
            if not mejorD or minimo > mejorD then
                mejor, mejorD = c, minimo
            end
        end
        elegidas[#elegidas + 1] = mejor
    end
    return elegidas
end

--- El robot que está en (x, y) ve lo que tiene alrededor en el instante `reloj`.
function Patrulla:ver(x, y, reloj)
    local r2 = Patrulla.vista * Patrulla.vista
    for _, c in ipairs(self.celdas) do
        if (c.cx - x) ^ 2 + (c.cy - y) ^ 2 < r2 then
            c.visto = reloj
        end
    end
end

--- El siguiente destino de `quien` (en (x, y), en el instante `reloj`): la
-- celda más abandonada, descontando el camino, entre `minimo` y `maximo` m
-- de él (si no hay ninguna tan cerca, la mejor de todas) y lejos del destino
-- de los demás. A lo lejano llega por tramos: una ruta de 600 m costaba más
-- de 100 ms de calcular. Devuelve x, y, o nil si no hay ninguna.
function Patrulla:elegir(quien, x, y, reloj, minimo, maximo)
    self.destinos[quien] = nil
    local separacion2 = Patrulla.separacion * Patrulla.separacion
    local minimo2 = (minimo or 0) ^ 2
    local maximo2 = (maximo or math.huge) ^ 2
    local mejor, mejorPuntos
    local lejos, lejosPuntos
    for _, c in ipairs(self.celdas) do
        local d2 = (c.x - x) ^ 2 + (c.y - y) ^ 2
        local libre = d2 >= minimo2 and not (c.evitarHasta and reloj < c.evitarHasta)
        if libre then
            for _, otro in pairs(self.destinos) do
                if (c.x - otro.x) ^ 2 + (c.y - otro.y) ^ 2 < separacion2 then
                    libre = false
                    break
                end
            end
        end
        if libre then
            local abandono = c.visto and (reloj - c.visto) or Patrulla.nunca
            local puntos = abandono - Patrulla.pesoDistancia * math.sqrt(d2) / Patrulla.velocidad
                + love.math.random() * 3
            if d2 <= maximo2 then
                if not mejorPuntos or puntos > mejorPuntos then
                    mejor, mejorPuntos = c, puntos
                end
            elseif not lejosPuntos or puntos > lejosPuntos then
                lejos, lejosPuntos = c, puntos
            end
        end
    end
    mejor = mejor or lejos
    if mejor then
        self.destinos[quien] = mejor
        return mejor.x, mejor.y
    end
end

--- No hubo ruta hasta el destino de `quien`: esa celda se aparta un rato.
function Patrulla:fallo(quien, reloj)
    local c = self.destinos[quien]
    if c then
        c.evitarHasta = reloj + Patrulla.evitarFallo
        self.destinos[quien] = nil
    end
end

--- La parte del recinto que alguien ha visto en los últimos `segundos`
-- (0-1), lo más que lleva sin que nadie la vea una celda ya vista, y cuántas
-- no ha visto nadie todavía.
function Patrulla:cubierto(reloj, segundos)
    local vistas, peor, nunca = 0, 0, 0
    for _, c in ipairs(self.celdas) do
        if not c.visto then
            nunca = nunca + 1
        else
            if reloj - c.visto <= segundos then
                vistas = vistas + 1
            end
            peor = math.max(peor, reloj - c.visto)
        end
    end
    return vistas / math.max(1, #self.celdas), peor, nunca
end

return Patrulla
