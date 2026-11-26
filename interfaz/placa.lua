-- Placa de lugar: una etiqueta pequeña arriba al centro, bajo la barra
-- superior (diseno/interfaz-militar.md, §10). Franja del país, estrella si es
-- capital, el nombre y «19 039 habitantes» si se está dentro de la ciudad o «a
-- 312 m» si no. Un clic abre el panel de esa ciudad.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')

local Placa = {}
Placa.__index = Placa

function Placa.nuevo()
    local self = setmetatable({}, Placa)
    self.rect = nil
    self.ciudad = nil
    return self
end

--- Dibuja la placa de `ciudad` (dibujable del mundo) a `distancia` unidades,
-- con su borde de arriba en `arriba` (píxeles de pantalla).
function Placa:dibujar(sim, ciudad, distancia, arriba)
    local g = love.graphics
    local w = g.getWidth()
    local c = sim:ciudad(ciudad.region)
    local nacion = c and sim:nacion(c.nacion)
    local nombre = Acero.fuente('boton', 22)
    local detalle = Acero.fuente('cuerpo', 17)
    local dentro = distancia < ciudad.radio
    local texto
    if dentro then
        texto = Tema.numero(c and c.poblacion or 0) .. ' habitantes'
    else
        texto = 'a ' .. Tema.numero(math.floor(distancia / 10)) .. ' m'
    end
    local capital = nacion and nacion.capital == ciudad.region
    local relleno = Tema.px(12)
    local franja = Tema.px(5)
    local estrella = capital and nombre:getHeight() * 0.5 + Tema.px(6) or 0
    local ancho = relleno
        + franja
        + Tema.px(10)
        + estrella
        + nombre:getWidth(ciudad.nombre)
        + Tema.px(12)
        + detalle:getWidth(texto)
        + relleno
    local alto = Tema.px(40)
    local x = math.floor((w - ancho) / 2)
    local y = arriba + Tema.px(8)
    self.rect = { x = x, y = y, w = ancho, h = alto }
    self.ciudad = ciudad

    Acero.chip(x, y, ancho, alto)
    local cursor = x + relleno
    Tema.color(nacion and nacion.color or Tema.colores.lineaOliva)
    g.rectangle('fill', cursor, y + Tema.px(8), franja, alto - Tema.px(16))
    cursor = cursor + franja + Tema.px(10)
    if capital then
        local r = nombre:getHeight() * 0.25
        local cx, cy = cursor + r, y + alto / 2
        local puntos = {}
        for k = 0, 9 do
            local a = -math.pi / 2 + k * math.pi / 5
            local radio = k % 2 == 0 and r or r * 0.45
            puntos[#puntos + 1] = cx + math.cos(a) * radio
            puntos[#puntos + 1] = cy + math.sin(a) * radio
        end
        Tema.color('amarillo')
        for _, t in ipairs(love.math.triangulate(puntos)) do
            g.polygon('fill', t)
        end
        cursor = cursor + estrella
    end
    g.setFont(nombre)
    Tema.color('textoHud')
    g.print(ciudad.nombre, cursor, math.floor(y + (alto - nombre:getHeight()) / 2))
    cursor = cursor + nombre:getWidth(ciudad.nombre) + Tema.px(12)
    g.setFont(detalle)
    Tema.color('textoHudTenue')
    g.print(texto, cursor, math.floor(y + (alto - detalle:getHeight()) / 2))
end

function Placa:ocultar()
    self.rect = nil
    self.ciudad = nil
end

--- Clic en la placa: devuelve su ciudad (para abrir su pendón) o nil.
function Placa:pulsar(x, y)
    local r = self.rect
    if r and Tema.dentro(x, y, r.x, r.y, r.w, r.h) then
        return self.ciudad
    end
    return nil
end

return Placa
