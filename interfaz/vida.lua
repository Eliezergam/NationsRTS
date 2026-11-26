-- Vida de la interfaz (el dueño: «que las cosas tengan movimiento para que no
-- se sientan rígidas», todo sutil): botones que crecen un poco al pasar el
-- ratón y se hunden al pulsar, insignias que laten cuando cambian, un brillo
-- que pasa de vez en cuando por los iconos importantes, paneles que entran
-- deslizándose con fundido y cifras que cuentan en vez de saltar.
--
-- La interfaz se dibuja en modo inmediato, así que cada cosa animada se
-- reconoce por una clave (su sitio, su id...) y aquí se guarda su estado. Todo
-- va con el reloj real (`love.timer.getTime`), no con el del juego: la pausa
-- y la velocidad no lo tocan. Lo que deja de dibujarse se olvida solo.
--
-- Solo dibuja: no lee ni cambia la simulación.

local Vida = {}

--- Con `quieta` (las capturas, salvo con `--vida`) nada se anima: los
-- paneles salen ya dentro, las cifras en su valor y sin brillos ni latidos,
-- para que las fotos no dependan de cuántos cuadros pasan.
Vida.quieta = false

local estados = {} -- clave -> { v, t, inicio, visto, ultimo }
local limpieza = 0

--- Estado de una clave (se crea con `valor` la primera vez).
local function estado(clave, valor)
    local ahora = love.timer.getTime()
    local e = estados[clave]
    if not e then
        e = { v = valor, t = ahora, visto = ahora }
        estados[clave] = e
    end
    -- De vez en cuando se olvida lo que lleva un rato sin dibujarse.
    if ahora - limpieza > 2 then
        limpieza = ahora
        for k, otro in pairs(estados) do
            if ahora - otro.visto > 3 then
                estados[k] = nil
            end
        end
    end
    return e, ahora
end

--- Valor que se acerca a `objetivo` con suavidad (`rapidez` por segundo;
-- 12 llega en unos 0,25 s). La primera vez ya está en el objetivo.
function Vida.suave(clave, objetivo, rapidez)
    if Vida.quieta then
        return objetivo
    end
    local e, ahora = estado(clave, objetivo)
    local dt = math.min(0.1, ahora - e.t)
    e.t = ahora
    e.visto = ahora
    e.v = e.v + (objetivo - e.v) * (1 - math.exp(-(rapidez or 12) * dt))
    if math.abs(objetivo - e.v) < 0.001 then
        e.v = objetivo
    end
    return e.v
end

--- Clave de un rectángulo de pantalla (botones sin id propio).
function Vida.claveRect(prefijo, x, y, w, h)
    return string.format('%s:%d:%d:%d:%d', prefijo, x, y, w, h)
end

--- Cuánto crece un botón (0 a 1) y si está hundido: crece al pasar el ratón
-- y se hunde al pulsar. Devuelve `crece` (0 a 1) y `hunde` (0 a 1).
function Vida.boton(clave, encima, pulsado)
    local crece = Vida.suave(clave .. ':c', (encima and not pulsado) and 1 or 0, 16)
    local hunde = Vida.suave(clave .. ':h', pulsado and 1 or 0, 28)
    return crece, hunde
end

--- Cifra que cuenta hacia `valor` en vez de saltar (en medio segundo, más o
-- menos). Devuelve el número que se enseña, entero.
function Vida.numero(clave, valor)
    if Vida.quieta then
        return math.floor(valor + 0.5)
    end
    local e, ahora = estado(clave, valor)
    local dt = math.min(0.1, ahora - e.t)
    e.t = ahora
    e.visto = ahora
    local falta = valor - e.v
    e.v = e.v + falta * (1 - math.exp(-7 * dt))
    if math.abs(valor - e.v) < 0.5 then
        e.v = valor
    end
    return math.floor(e.v + 0.5)
end

--- Latido de una insignia: cuando `valor` cambia, dos latidos cortos en
-- 0,7 s. Devuelve la escala (1 en reposo).
function Vida.latido(clave, valor)
    if Vida.quieta then
        return 1
    end
    local e, ahora = estado(clave, valor)
    e.visto = ahora
    if e.ultimo == nil then
        e.ultimo = valor
    elseif e.ultimo ~= valor then
        e.ultimo = valor
        e.inicio = ahora
    end
    if not e.inicio then
        return 1
    end
    local edad = ahora - e.inicio
    if edad > 0.7 then
        e.inicio = nil
        return 1
    end
    return 1 + 0.22 * math.abs(math.sin(edad * math.pi / 0.35)) * (1 - edad / 0.7)
end

-- Entrada de paneles ------------------------------------------------------------------------------

local DURACION_ENTRADA = 0.22
local shaderAlfa
local pila = {} -- entradas abiertas: { empujado, alfa, shader }

local CODIGO_ALFA = [[
extern number alfa;
vec4 effect(vec4 color, Image textura, vec2 tc, vec2 sc)
{
    vec4 pixel = Texel(textura, tc) * color;
    pixel.a *= alfa;
    return pixel;
}
]]

--- Progreso de la entrada de `clave` (0 recién aparecido, 1 ya dentro).
-- Si lleva un rato sin dibujarse, la próxima vez entra de nuevo.
function Vida.progreso(clave)
    if Vida.quieta then
        return 1
    end
    local ahora = love.timer.getTime()
    local e = estados[clave]
    if not e or ahora - e.visto > 0.15 then
        e = { v = 0, t = ahora, visto = ahora, inicio = ahora }
        estados[clave] = e
    end
    e.visto = ahora
    local p = math.min(1, (ahora - e.inicio) / DURACION_ENTRADA)
    -- Frenado al final (ease-out cúbico).
    return 1 - (1 - p) ^ 3
end

--- Empieza a dibujar un panel que entra: desplazado (`dx`, `dy` px al
-- principio, 0 al final) y con fundido. Cerrar siempre con `Vida.fin()`.
function Vida.entrar(clave, dx, dy)
    local p = Vida.progreso(clave)
    local g = love.graphics
    local entrada = { empujado = false }
    if p < 1 then
        g.push()
        g.translate(math.floor((dx or 0) * (1 - p) + 0.5), math.floor((dy or 0) * (1 - p) + 0.5))
        entrada.empujado = true
        if not shaderAlfa then
            shaderAlfa = love.graphics.newShader(CODIGO_ALFA)
        end
        -- Con entradas una dentro de otra, el fundido se multiplica.
        local alfa = p
        for _, otra in ipairs(pila) do
            alfa = alfa * (otra.alfa or 1)
        end
        entrada.alfa = p
        entrada.shader = g.getShader()
        shaderAlfa:send('alfa', alfa)
        g.setShader(shaderAlfa)
    end
    pila[#pila + 1] = entrada
    return p
end

--- Termina el panel que empezó con `Vida.entrar`.
function Vida.fin()
    local entrada = table.remove(pila)
    if entrada and entrada.empujado then
        love.graphics.setShader(entrada.shader)
        love.graphics.pop()
        -- Vuelve el fundido de la entrada de fuera, si la hay.
        local alfa = 1
        for _, otra in ipairs(pila) do
            alfa = alfa * (otra.alfa or 1)
        end
        if alfa < 1 and shaderAlfa then
            shaderAlfa:send('alfa', alfa)
            love.graphics.setShader(shaderAlfa)
        end
    end
end

-- Brillo de los iconos ------------------------------------------------------------------------------

local shaderBrillo

local CODIGO_BRILLO = [[
extern vec2 origen;
extern number centro;
extern number ancho;
vec4 effect(vec4 color, Image textura, vec2 tc, vec2 sc)
{
    float a = Texel(textura, tc).a;
    float d = (sc.x - origen.x) + (sc.y - origen.y) - centro;
    float k = exp(-d * d / (ancho * ancho));
    return vec4(1.0, 1.0, 1.0, a * k * color.a);
}
]]

--- Brillo que cruza en diagonal la imagen `img` dibujada en (x, y) con
-- escala (sx, sy): pasa una vez cada `periodo` segundos (con su `fase`) y
-- tarda 0,9 s. Sigue la forma de la imagen (su alfa). `fuerza` de 0 a 1.
function Vida.brillo(img, x, y, sx, sy, fase, fuerza, periodo)
    if Vida.quieta then
        return
    end
    periodo = periodo or 8
    local t = (love.timer.getTime() + (fase or 0)) % periodo
    local k = t / 0.9
    if k > 1 then
        return
    end
    local g = love.graphics
    if not shaderBrillo then
        shaderBrillo = love.graphics.newShader(CODIGO_BRILLO)
    end
    local w, h = img:getWidth() * sx, img:getHeight() * sy
    local ox, oy = g.transformPoint(x, y)
    local tamano = w + h
    shaderBrillo:send('origen', { ox, oy })
    shaderBrillo:send('centro', -0.15 * tamano + k * 1.3 * tamano)
    shaderBrillo:send('ancho', tamano * 0.09)
    local anterior = g.getShader()
    local modo, alfaModo = g.getBlendMode()
    g.setShader(shaderBrillo)
    g.setBlendMode('add')
    g.setColor(1, 1, 1, (fuerza or 0.5) * math.sin(k * math.pi))
    g.draw(img, x, y, 0, sx, sy)
    g.setBlendMode(modo, alfaModo)
    g.setShader(anterior)
end

return Vida
