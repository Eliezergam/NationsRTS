-- Colisiones del mundo de la batalla: cada objeto que ocupa sitio declara aquí
-- su forma y sus etiquetas, y nadie pregunta qué es (el dueño, 19-nov: «una
-- especie de tag que se le pueda poner a un objeto y ya con eso ellos hacen su
-- función, no decir piedra, árbol, casa»).
--
-- Una colisión es { forma, etiquetas, dueño }:
--   forma      { tipo = 'cilindro', x, y, r, z0, z1 }
--              { tipo = 'caja', x, y, hx, hy, rumbo, z0, z1 }
--              en metros y ejes de los robots (x este, y norte, z arriba).
--   etiquetas  lo que significa para quien la encuentra, p. ej.
--              solido     no se puede atravesar (sensores, cuerpo, balas)
--              cobertura  sirve para cubrirse detrás
--              derribable un vehículo o un misil la puede tumbar
--              copa       { z0, r }: copa de árbol (la cámara no entra)
--   dueño      el objeto del juego que la puso (para avisarle si la tocan).
--
-- El mundo físico (batalla/robots/fisica.lua, Jolt) crea un cuerpo por cada
-- colisión y lo quita cuando se quita aquí; los sensores y los ojos de los
-- robots lanzan rayos contra él. Las consultas por zona (¿qué cobertura hay
-- cerca?) van contra este registro.

local Colisiones = {}
Colisiones.__index = Colisiones

Colisiones.celda = 16 -- m de la rejilla de búsqueda

function Colisiones.nueva()
    local self = setmetatable({}, Colisiones)
    self.celdas = {}
    self.lista = {}
    self.oyentes = {}
    return self
end

--- Radio (m) del círculo que envuelve la forma en planta.
local function envolvente(f)
    if f.tipo == 'cilindro' then
        return f.r
    end
    return math.sqrt(f.hx * f.hx + f.hy * f.hy)
end
Colisiones.envolvente = envolvente

local function clave(i, j)
    return i * 131072 + j
end

--- Pone una colisión y la devuelve.
function Colisiones:poner(dueno, forma, etiquetas)
    local c = { forma = forma, etiquetas = etiquetas or {}, dueno = dueno, radio = envolvente(forma) }
    local t = Colisiones.celda
    c.i0, c.j0 = math.floor((forma.x - c.radio) / t), math.floor((forma.y - c.radio) / t)
    c.i1, c.j1 = math.floor((forma.x + c.radio) / t), math.floor((forma.y + c.radio) / t)
    for j = c.j0, c.j1 do
        for i = c.i0, c.i1 do
            local k = clave(i, j)
            local l = self.celdas[k]
            if not l then
                l = {}
                self.celdas[k] = l
            end
            l[#l + 1] = c
        end
    end
    self.lista[#self.lista + 1] = c
    for _, fn in ipairs(self.oyentes) do
        fn('puesta', c)
    end
    return c
end

--- Quita una colisión (un árbol que cae, un edificio que se derrumba...).
function Colisiones:quitar(c)
    if not c or c.quitada then
        return
    end
    c.quitada = true
    for j = c.j0, c.j1 do
        for i = c.i0, c.i1 do
            local l = self.celdas[clave(i, j)]
            if l then
                for k = #l, 1, -1 do
                    if l[k] == c then
                        table.remove(l, k)
                    end
                end
            end
        end
    end
    for _, fn in ipairs(self.oyentes) do
        fn('quitada', c)
    end
end

--- `fn(suceso, colision)` con suceso 'puesta' o 'quitada'.
function Colisiones:escuchar(fn)
    self.oyentes[#self.oyentes + 1] = fn
end

--- Distancia en planta de (x, y) al contorno de la colisión (negativa
-- dentro) y la dirección (nx, ny) que va del contorno hacia el punto.
function Colisiones.distancia(c, x, y)
    local f = c.forma
    if f.tipo == 'cilindro' then
        local dx, dy = x - f.x, y - f.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < 1e-6 then
            return -f.r, 1, 0
        end
        return d - f.r, dx / d, dy / d
    end
    local co, si = math.cos(f.rumbo), math.sin(f.rumbo)
    local dx, dy = x - f.x, y - f.y
    local u, v = dx * co + dy * si, -dx * si + dy * co
    local eu, ev = math.abs(u) - f.hx, math.abs(v) - f.hy
    local nu, nv, d
    if eu > 0 or ev > 0 then
        local au, av = math.max(eu, 0), math.max(ev, 0)
        d = math.sqrt(au * au + av * av)
        nu, nv = (u >= 0 and au or -au) / d, (v >= 0 and av or -av) / d
    elseif eu > ev then
        d, nu, nv = eu, u >= 0 and 1 or -1, 0
    else
        d, nu, nv = ev, 0, v >= 0 and 1 or -1
    end
    return d, nu * co - nv * si, nu * si + nv * co
end

--- Lo que mide la forma desde su centro en la dirección (ux, uy) (unitaria).
function Colisiones.alcance(c, ux, uy)
    local f = c.forma
    if f.tipo == 'cilindro' then
        return f.r
    end
    local co, si = math.cos(f.rumbo), math.sin(f.rumbo)
    local u, v = ux * co + uy * si, -ux * si + uy * co
    return math.abs(u) * f.hx + math.abs(v) * f.hy
end

--- Colisiones con la `etiqueta` (todas si es nil) a menos de `radio` m de
-- (x, y), medido al contorno. `salida` se vacía y se llena.
function Colisiones:cerca(x, y, radio, etiqueta, salida)
    salida = salida or {}
    for k = #salida, 1, -1 do
        salida[k] = nil
    end
    local t = Colisiones.celda
    local vistas = {}
    for j = math.floor((y - radio) / t), math.floor((y + radio) / t) do
        for i = math.floor((x - radio) / t), math.floor((x + radio) / t) do
            local l = self.celdas[clave(i, j)]
            if l then
                for _, c in ipairs(l) do
                    if not vistas[c] and (not etiqueta or c.etiquetas[etiqueta]) then
                        vistas[c] = true
                        if Colisiones.distancia(c, x, y) < radio then
                            salida[#salida + 1] = c
                        end
                    end
                end
            end
        end
    end
    return salida
end

return Colisiones
