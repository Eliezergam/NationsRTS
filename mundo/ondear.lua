-- Paños que ondean en el mapa: banderas de las ciudades, de las bases y de
-- las banderas plantadas, y los banderines de los grupos (el dueño: «que las
-- cosas tengan movimiento para que no se sientan rígidas»).
--
-- Van con el reloj real de la interfaz (`love.timer.getTime`), no con el del
-- juego: siguen moviéndose en pausa y no se aceleran con la velocidad. Cada
-- bandera tiene su fase (sale de su sitio o de su id), así no ondean todas a
-- la vez. El paño se dibuja en tiras de cuatro vértices (sin triangular cada
-- cuadro) con un poco de luz y sombra según la onda.
--
-- Solo dibuja: no lee ni cambia la simulación.

local Ondear = {}

local DOS_PI = math.pi * 2

--- Reloj de las ondas: el real de la interfaz.
function Ondear.ahora()
    return love.timer.getTime()
end

--- Fase propia de un sitio del mundo (x, y).
function Ondear.fase(x, y)
    return (x * 0.0137 + y * 0.0071) % DOS_PI
end

--- Fase propia de un id (número o texto).
function Ondear.faseDe(id)
    if type(id) == 'number' then
        return (id * 1.618) % DOS_PI
    end
    local suma = 0
    for k = 1, #tostring(id) do
        suma = suma + tostring(id):byte(k) * k
    end
    return (suma * 0.618) % DOS_PI
end

--- Altura de la onda en la parte `u` del paño (0 en el mástil, 1 en la
-- punta): dos senos lentos que viajan hacia la punta, más fuertes al final.
function Ondear.onda(t, u, fase, amplitud)
    local a = math.sin(t * 2.6 - u * 4.2 + fase)
    local b = math.sin(t * 4.1 - u * 6.8 + fase * 1.7)
    return (a * 0.75 + b * 0.25) * amplitud * u
end

--- Paño rectangular que ondea, con la esquina de arriba del mástil en (x, y):
-- `largo` hacia `lado` (1 derecha, -1 izquierda), `alto` hacia abajo.
-- `color` = { r, g, b }; `alfa` opcional. `tramos`: tiras a lo largo.
-- Devuelve el contorno (lista plana de puntos) y la altura de la onda en el
-- centro del paño (para poner encima un escudo).
function Ondear.pano(x, y, largo, alto, color, fase, amplitud, alfa, tramos, lado)
    local g = love.graphics
    local t = Ondear.ahora()
    tramos = tramos or 6
    lado = lado or 1
    alfa = alfa or 1
    local px, py = x, y
    local arriba = { x, y }
    local abajo = { x, y + alto }
    for k = 1, tramos do
        local u = k / tramos
        local nx = x + lado * largo * u
        local ny = y + Ondear.onda(t, u, fase, amplitud)
        -- La tira se aclara u oscurece con la pendiente de la onda.
        local luz = 1 + math.max(-0.16, math.min(0.16, (ny - py) / math.max(1, largo / tramos) * 0.5))
        g.setColor(
            math.min(1, color[1] * luz),
            math.min(1, color[2] * luz),
            math.min(1, color[3] * luz),
            alfa
        )
        g.polygon('fill', px, py, nx, ny, nx, ny + alto, px, py + alto)
        arriba[#arriba + 1] = nx
        arriba[#arriba + 1] = ny
        table.insert(abajo, 1, ny + alto)
        table.insert(abajo, 1, nx)
        px, py = nx, ny
    end
    for k = 1, #abajo do
        arriba[#arriba + 1] = abajo[k]
    end
    return arriba, Ondear.onda(t, 0.5, fase, amplitud)
end

--- Banderín triangular que ondea, con el asta en `x` y el borde de arriba
-- en `y`: punta a `largo` hacia `lado` y `alto` de base. Devuelve la lista
-- de puntos del contorno (para el borde).
function Ondear.banderin(x, y, largo, alto, color, fase, amplitud, lado)
    local g = love.graphics
    local t = Ondear.ahora()
    local tramos = 3
    local arriba, abajo = {}, {}
    for k = 0, tramos do
        local u = k / tramos
        local onda = Ondear.onda(t, u, fase, amplitud)
        local cx = x + lado * largo * u
        local medio = y + alto / 2 + onda
        -- El triángulo se estrecha hacia la punta.
        arriba[k + 1] = { cx, medio - alto / 2 * (1 - u) }
        abajo[k + 1] = { cx, medio + alto / 2 * (1 - u) }
    end
    g.setColor(color[1], color[2], color[3], 1)
    for k = 1, tramos do
        local a1, a2, b1, b2 = arriba[k], arriba[k + 1], abajo[k], abajo[k + 1]
        if k < tramos then
            g.polygon('fill', a1[1], a1[2], a2[1], a2[2], b2[1], b2[2], b1[1], b1[2])
        else
            g.polygon('fill', a1[1], a1[2], a2[1], a2[2], b1[1], b1[2])
        end
    end
    local contorno = {}
    for k = 1, tramos + 1 do
        contorno[#contorno + 1] = arriba[k][1]
        contorno[#contorno + 1] = arriba[k][2]
    end
    for k = tramos, 1, -1 do
        contorno[#contorno + 1] = abajo[k][1]
        contorno[#contorno + 1] = abajo[k][2]
    end
    return contorno
end

--- Humo leve de una chimenea con la boca en (x, y) de la vista: bocanadas
-- que suben, crecen y se desvanecen, empujadas un poco por el viento.
-- `fuerza` de 0 a 1 (más bocanadas y más opacas).
function Ondear.humo(x, y, escala, fase, fuerza)
    local g = love.graphics
    local t = Ondear.ahora()
    local n = 6
    for k = 0, n - 1 do
        local edad = (t * 0.16 + k / n + fase / DOS_PI) % 1
        local sube = edad * 110 * escala
        local deriva = (edad * 34 + math.sin(t * 0.7 + k * 1.3 + fase) * 6 * edad) * escala
        local radio = (5 + edad * 17) * escala
        local alfa = math.sin(edad * math.pi) * (0.14 + 0.18 * fuerza)
        g.setColor(0.86, 0.86, 0.84, alfa)
        g.circle('fill', x + deriva, y - sube, radio, 14)
    end
end

return Ondear
