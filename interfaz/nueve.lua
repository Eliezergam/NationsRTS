-- Imagen 9-slice: las esquinas no se deforman y los lados y el centro se
-- estiran. Sirve para cualquier imagen con sus márgenes (`nueve` = { izq,
-- der, arr, aba } en píxeles de la imagen), como las piezas del login
-- (assets/ui/login/indice.lua).

local Nueve = {}
Nueve.__index = Nueve

--- Corta `imagen` con los márgenes `nueve`.
function Nueve.nuevo(imagen, nueve)
    local corte = setmetatable({}, Nueve)
    local iw, ih = imagen:getDimensions()
    local izq, der, arr, aba = nueve[1], nueve[2], nueve[3], nueve[4]
    local xs = { 0, izq, iw - der, iw }
    local ys = { 0, arr, ih - aba, ih }
    corte.imagen = imagen
    corte.margenes = { izq, der, arr, aba }
    corte.trozos = {}
    for fila = 1, 3 do
        for columna = 1, 3 do
            local qw = xs[columna + 1] - xs[columna]
            local qh = ys[fila + 1] - ys[fila]
            if qw > 0 and qh > 0 then
                corte.trozos[#corte.trozos + 1] = {
                    quad = love.graphics.newQuad(xs[columna], ys[fila], qw, qh, iw, ih),
                    columna = columna,
                    fila = fila,
                    qw = qw,
                    qh = qh,
                }
            end
        end
    end
    return corte
end

--- Dibuja en el rectángulo (x, y, w, h) de pantalla con las esquinas a la
-- escala `escala` (1: a su tamaño). El color lo pone quien llama.
function Nueve:dibujar(x, y, w, h, escala)
    local m = self.margenes
    local izq = math.floor(m[1] * escala + 0.5)
    local der = math.floor(m[2] * escala + 0.5)
    local arr = math.floor(m[3] * escala + 0.5)
    local aba = math.floor(m[4] * escala + 0.5)
    if izq + der > w then
        izq = math.floor(w / 2)
        der = w - izq
    end
    if arr + aba > h then
        arr = math.floor(h / 2)
        aba = h - arr
    end
    local anchos = { izq, w - izq - der, der }
    local altos = { arr, h - arr - aba, aba }
    local origenX = { x, x + izq, x + w - der }
    local origenY = { y, y + arr, y + h - aba }
    for _, t in ipairs(self.trozos) do
        local dw = anchos[t.columna]
        local dh = altos[t.fila]
        if dw > 0 and dh > 0 then
            love.graphics.draw(self.imagen, t.quad, origenX[t.columna], origenY[t.fila], 0, dw / t.qw, dh / t.qh)
        end
    end
end

return Nueve
