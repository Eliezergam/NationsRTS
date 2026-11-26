-- Primera persona de la batalla 3D (decisión del dueño: «cámara que camina»).
-- No encarna a ninguna unidad ni le disparan: es el ojo de un observador a
-- pie, a la altura de los ojos, para recorrer el campo y verlo de cerca.
--
--   ratón       mira (modo relativo de LÖVE, sin botón)
--   W/S A/D     caminar adelante/atrás y a los lados (1,4 m/s)
--   Shift       correr (4,5 m/s)
--   Espacio     saltar
--
-- Sigue el relieve con suavizado y choca con los troncos y las rocas grandes
-- (las plantas de `Suelo.plantasFisicas`), los vehículos (sus volúmenes de
-- batalla/dream/rayos.lua, girados con la unidad), el edificio del sitio, el
-- agua honda, el límite del campo y, en la preparación, el recinto de la
-- cámara (`Camara:usarRecinto`). Solo lee la escena: no cambia la pelea.
--
-- Escala del juego: 10 px por metro.

local Controlador = require('batalla.controlador_camara')

local Caminante = {}
Caminante.__index = Caminante

Caminante.alturaOjo = 17 -- px (1,7 m) del ojo sobre los pies
Caminante.velocidadPaso = 14 -- px/s (1,4 m/s)
Caminante.velocidadCarrera = 45 -- px/s (4,5 m/s)
Caminante.aceleracion = 10 -- 1/s: rapidez con la que se alcanza la velocidad pedida
Caminante.radioCuerpo = 3 -- px (0,3 m)
Caminante.profundidadMaxima = 8 -- px (0,8 m) de agua que aún se vadea
Caminante.sensibilidad = 0.003 -- rad por px del ratón
Caminante.limiteMirada = math.rad(85)
Caminante.seguirLoma = 14 -- 1/s: suavizado de los pies sobre el relieve
Caminante.gravedad = 98 -- px/s² (9,8 m/s²)
Caminante.alturaSalto = 5 -- px (0,5 m)
Caminante.pasoColision = 4 -- px máximos por subpaso (no atravesar troncos finos)

--- Caminante con los pies en (x, y) mirando con `rumbo` (el de la cámara:
-- se mira hacia -cos, -sin). Busca el sitio libre más cercano.
function Caminante.nuevo(suelo, tropas, camara, x, y, rumbo)
    local self = setmetatable({}, Caminante)
    self.suelo = suelo
    self.tropas = tropas
    self.camara = camara
    self.rumbo = rumbo or 0
    self.inclinacion = 0
    self.vx = 0
    self.vy = 0
    self.vz = 0
    self.enAire = false
    self.x, self.y = self:sitioLibre(x, y)
    self.zPies = self:alturaSuelo(self.x, self.y)
    return self
end

--- Altura del suelo que se pisa en (x, y) (el fondo, aunque haya agua).
function Caminante:alturaSuelo(x, y)
    return self.suelo:altura(x, y)
end

--- Nivel del agua en (x, y), o nil si no hay.
function Caminante:nivelAgua(x, y)
    local agua = self.suelo.agua
    if agua then
        return agua:nivelEn(x, y)
    end
    return self.suelo.nivelMar
end

--- ¿Hay agua demasiado honda para vadear en (x, y)?
function Caminante:aguaHonda(x, y)
    local nivel = self:nivelAgua(x, y)
    if not nivel then
        return false
    end
    return nivel - self.suelo:altura(x, y) > Caminante.profundidadMaxima
end

--- Ojo del caminante (x, y, z en px).
function Caminante:ojo()
    local z = self.zPies + Caminante.alturaOjo
    -- Vadeando, el ojo nunca queda bajo el agua.
    local nivel = self:nivelAgua(self.x, self.y)
    if nivel then
        z = math.max(z, nivel + 4)
    end
    return self.x, self.y, z
end

--- Ratón relativo: `dx`, `dy` px (derecha y abajo giran a la derecha y abajo).
function Caminante:mirar(dx, dy)
    self.rumbo = self.rumbo + dx * Caminante.sensibilidad
    local inclinacion = self.inclinacion + dy * Caminante.sensibilidad
    self.inclinacion = math.max(-Caminante.limiteMirada, math.min(Caminante.limiteMirada, inclinacion))
end

--- Espacio: salta si está en el suelo.
function Caminante:saltar()
    if self.enAire then
        return
    end
    self.enAire = true
    self.vz = math.sqrt(2 * Caminante.gravedad * Caminante.alturaSalto)
end

--- Velocidad horizontal que piden las teclas (px/s, ejes del juego).
function Caminante:velocidadPedida()
    local isDown = love.keyboard.isDown
    local adelante = 0
    local lado = 0
    if isDown('w', 'up') then
        adelante = adelante + 1
    end
    if isDown('s', 'down') then
        adelante = adelante - 1
    end
    if isDown('d', 'right') then
        lado = lado + 1
    end
    if isDown('a', 'left') then
        lado = lado - 1
    end
    if adelante == 0 and lado == 0 then
        return 0, 0
    end
    local c = math.cos(self.rumbo)
    local s = math.sin(self.rumbo)
    -- Adelante (-c, -s) y derecha (s, -c), los ejes de `Camara:ejes`.
    local dx = -c * adelante + s * lado
    local dy = -s * adelante - c * lado
    local largo = math.sqrt(dx * dx + dy * dy)
    local rapidez = Caminante.velocidadPaso
    if isDown('lshift', 'rshift') then
        rapidez = Caminante.velocidadCarrera
    end
    return dx / largo * rapidez, dy / largo * rapidez
end

-- Colisiones ------------------------------------------------------------------------------------

--- Volumen de un vehículo (batalla/dream/rayos.lua). Se pide al usarlo: el
-- motor 3Dream debe estar ya cargado antes de su extensión de rayos.
local function volumen(tipo)
    return require('batalla.dream.rayos').volumen[tipo]
end

--- Saca (x, y) del círculo de centro (cx, cy) y radio `r`.
local function fueraDeCirculo(x, y, cx, cy, r)
    local dx = x - cx
    local dy = y - cy
    local d2 = dx * dx + dy * dy
    if d2 >= r * r then
        return x, y
    end
    local d = math.sqrt(d2)
    if d < 0.0001 then
        return cx + r, cy
    end
    return cx + dx / d * r, cy + dy / d * r
end

--- Saca (x, y) del rectángulo de centro (cx, cy), medio largo `a` en el
-- `rumbo` y medio ancho `b`, por el lado más cercano.
local function fueraDeCaja(x, y, cx, cy, rumbo, a, b)
    local c = math.cos(rumbo)
    local s = math.sin(rumbo)
    local dx = x - cx
    local dy = y - cy
    local u = dx * c + dy * s
    local v = -dx * s + dy * c
    if math.abs(u) >= a or math.abs(v) >= b then
        return x, y
    end
    if a - math.abs(u) < b - math.abs(v) then
        u = u >= 0 and a or -a
    else
        v = v >= 0 and b or -b
    end
    return cx + u * c - v * s, cy + u * s + v * c
end

--- Empuja (x, y) fuera de troncos, rocas, vehículos y edificio.
function Caminante:apartar(x, y)
    local radio = Caminante.radioCuerpo
    local suelo = self.suelo
    -- Troncos y rocas grandes (las plantas con `arbol`, las de la física).
    local celda = suelo.celdaPlantas or 128
    local celdas = suelo.celdasPlantas
    if celdas then
        local alcance = radio + 120
        local i0 = math.floor((x - alcance) / celda)
        local i1 = math.floor((x + alcance) / celda)
        local j0 = math.floor((y - alcance) / celda)
        local j1 = math.floor((y + alcance) / celda)
        for j = j0, j1 do
            for i = i0, i1 do
                for _, p in ipairs(celdas[i * 131072 + j] or {}) do
                    if p.arbol and not p.caido and p.radio then
                        x, y = fueraDeCirculo(x, y, p.x, p.y, p.radio + radio)
                    end
                end
            end
        end
    end
    -- Vehículos, vivos o destrozados (el casco sigue ahí).
    for _, u in ipairs(self.tropas.unidades) do
        if not u.retirado then
            local v = volumen(u.tipo)
            if v then
                local a = v.largo * 10 + radio
                local b = v.ancho * 10 + radio
                if math.abs(x - u.x) < a + b and math.abs(y - u.y) < a + b then
                    x, y = fueraDeCaja(x, y, u.x, u.y, u.rumbo or 0, a, b)
                end
            end
        end
    end
    -- Edificios y muro de una ciudad o mina (batalla/sitios/plano.lua).
    if suelo.plano then
        self.solidos = suelo.plano:solidosCerca(x, y, radio, self.solidos)
        for _, h in ipairs(self.solidos) do
            x, y = fueraDeCaja(x, y, h.cx, h.cy, h.ang, h.hx + radio, h.hy + radio)
        end
    end
    -- Edificio del sitio (un cuadrado alineado con los ejes).
    local sitio = suelo.sitio
    if sitio and not suelo.plano and suelo:ocupado(x, y, radio) then
        local r = suelo:radioEdificio() + radio
        x, y = fueraDeCaja(x, y, sitio.x, sitio.y, 0, r, r)
    end
    return x, y
end

--- Límite del campo y, en la preparación, recinto de la cámara.
function Caminante:limitar(x, y)
    local recinto = self.camara and self.camara.recinto
    if recinto then
        x, y = recinto.ajustar(x, y)
    end
    local limite = self.suelo.limite
    if limite then
        x, y = limite:ajustar(x, y, Caminante.radioCuerpo)
    end
    return x, y
end

--- Paso de (x, y) hacia (nx, ny) con todas las colisiones: si el agua honda
-- corta el paso, se desliza por el eje que aún se puede.
function Caminante:paso(x, y, nx, ny)
    nx, ny = self:apartar(nx, ny)
    nx, ny = self:limitar(nx, ny)
    if not self:aguaHonda(nx, ny) then
        return nx, ny
    end
    if not self:aguaHonda(nx, y) then
        return nx, y
    end
    if not self:aguaHonda(x, ny) then
        return x, ny
    end
    return x, y
end

--- El sitio libre más cercano a (x, y) en espiral (para empezar a caminar).
function Caminante:sitioLibre(x, y)
    x, y = self:limitar(x, y)
    for anillo = 0, 40 do
        local muestras = anillo == 0 and 1 or anillo * 8
        for k = 0, muestras - 1 do
            local a = k / muestras * math.pi * 2
            local px = x + math.cos(a) * anillo * 20
            local py = y + math.sin(a) * anillo * 20
            px, py = self:limitar(px, py)
            local ax, ay = self:apartar(px, py)
            if ax == px and ay == py and not self:aguaHonda(px, py) then
                return px, py
            end
        end
    end
    return x, y
end

--- Un cuadro: caminar, chocar y seguir el relieve. Devuelve si hubo entrada.
function Caminante:actualizar(dt)
    dt = math.min(dt, 0.1)
    local qx, qy = self:velocidadPedida()
    local f = Controlador.fraccion(Caminante.aceleracion, dt)
    if self.enAire then
        f = f * 0.15 -- en el aire apenas se cambia de rumbo
    end
    self.vx = self.vx + (qx - self.vx) * f
    self.vy = self.vy + (qy - self.vy) * f
    local dx = self.vx * dt
    local dy = self.vy * dt
    local largo = math.sqrt(dx * dx + dy * dy)
    local pasos = math.max(1, math.ceil(largo / Caminante.pasoColision))
    local x = self.x
    local y = self.y
    for _ = 1, pasos do
        x, y = self:paso(x, y, x + dx / pasos, y + dy / pasos)
    end
    if dt > 0 then
        -- Lo que el choque quitó deja de empujar (se desliza por el borde).
        self.vx = (x - self.x) / dt
        self.vy = (y - self.y) / dt
        local rapidez = math.sqrt(self.vx * self.vx + self.vy * self.vy)
        local maximo = Caminante.velocidadCarrera
        if rapidez > maximo then
            self.vx = self.vx / rapidez * maximo
            self.vy = self.vy / rapidez * maximo
        end
    end
    self.x = x
    self.y = y
    -- Pies: siguen la loma con suavizado; nunca bajo el suelo.
    local h = self:alturaSuelo(x, y)
    if self.enAire then
        self.vz = self.vz - Caminante.gravedad * dt
        self.zPies = self.zPies + self.vz * dt
        if self.zPies <= h then
            self.zPies = h
            self.vz = 0
            self.enAire = false
        end
    else
        self.zPies = self.zPies + (h - self.zPies) * Controlador.fraccion(Caminante.seguirLoma, dt)
        self.zPies = math.max(h - 2, math.min(h + 6, self.zPies))
    end
    return qx ~= 0 or qy ~= 0 or self.enAire
end

return Caminante
