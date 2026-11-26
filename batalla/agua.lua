-- Agua de la batalla (Valeria): dónde no se puede pisar y sus bordes para la
-- física. El agua del mapa (el mar y sus ensenadas, que en la batalla se ven
-- como lagos) y el río de batalla/cauces.lua: el cauce hondo no se pisa; el
-- vado (menos de `vadoPisable` px de agua, donde cruza un pasillo) sí. Los
-- lagos de la hidrología, las ondas y los puentes de ESTILO-TERRENO §6 y §6.5
-- están PENDIENTES.
--
-- Los bordes se sacan de una rejilla de `celda` px sobre el límite del campo:
-- cada lado entre una celda de agua y una de tierra es un tramo, y los tramos
-- seguidos de una misma fila o columna se juntan en uno. La física pone ahí
-- una pared estática (batalla/fisica.lua, `crearAgua`): ningún vehículo entra.

local Agua = {}
Agua.__index = Agua

Agua.celda = 50 -- px (5 m) de la rejilla de los bordes
Agua.margen = 6 -- px sobre el nivel del mar que aún cuentan como agua (orilla)
Agua.vadoPisable = 5 -- px de agua del río que aún se pisan (el vado tiene 3)
Agua.orillaRio = 3 -- m de la orilla del río hasta los que se mira su agua
Agua.celdaRio = 100 -- px de la rejilla que dice dónde puede haber río hondo (para no interpolar lejos)

function Agua.nuevo(suelo)
    local self = setmetatable({}, Agua)
    self.suelo = suelo
    self.nivel = suelo.nivelMar
    self.hayRio = suelo.cauces and suelo.cauces.rio or false
    if self.hayRio then
        self:marcarRio()
    end
    self:rellenarCharcos()
    self:sacarBordes()
    return self
end

--- ¿Es agua (x, y)? El mar y la orilla encharcada. Con `radio` (px), también
-- si lo es alguno de los cuatro puntos a esa distancia.
function Agua:enAgua(x, y, radio)
    if not radio then
        return self:aguaEn(x, y)
    end
    return self:aguaEn(x + radio, y)
        or self:aguaEn(x - radio, y)
        or self:aguaEn(x, y + radio)
        or self:aguaEn(x, y - radio)
end

--- ¿Es agua el punto (x, y)? El mar y su orilla, o el río hondo. Con la
-- rejilla de tránsito del suelo hecha, casi siempre sale de ella.
function Agua:aguaEn(x, y)
    local s = self.suelo
    if s.transito then
        local r = s:consultarTransito(x, y, 2)
        if r ~= nil then
            return r
        end
    end
    return self:aguaExacta(x, y)
end

--- `aguaEn` con las cuentas exactas.
function Agua:aguaExacta(x, y)
    local s = self.suelo
    local h = s:altura(x, y)
    if h < self.nivel + Agua.margen then
        return true
    end
    if self.hayRio then
        return self:rioHondo(x, y, h)
    end
    return false
end

--- Celdas de `celdaRio` px del área que tienen algún vértice junto al agua
-- del río (`dAgua` bajo `orillaRio`): solo en ellas se interpola. La física
-- pregunta muchas veces por cuadro y casi siempre lejos del río.
function Agua:marcarRio()
    local s = self.suelo
    local rej = s.relieve
    local celda = Agua.celdaRio
    local n = math.ceil(s.lado / celda)
    local x0, y0 = s.cx - s.lado / 2, s.cy - s.lado / 2
    local cerca = {}
    for k = 0, rej.total - 1 do
        if rej.dAgua[k] <= Agua.orillaRio then
            local i = math.floor((rej.x[k] - x0) / celda)
            local j = math.floor((rej.y[k] - y0) / celda)
            -- La celda del vértice y sus vecinas (los triángulos lo comparten).
            for dj = -1, 1 do
                for di = -1, 1 do
                    local a, b = i + di, j + dj
                    if a >= 0 and b >= 0 and a < n and b < n then
                        cerca[b * n + a] = true
                    end
                end
            end
        end
    end
    self.rioCerca, self.rioN, self.rioX0, self.rioY0 = cerca, n, x0, y0
end

--- ¿Hay más de `vadoPisable` px de agua del río sobre el suelo `h` en (x, y)?
function Agua:rioHondo(x, y, h)
    local s = self.suelo
    local i = math.floor((x - self.rioX0) / Agua.celdaRio)
    local j = math.floor((y - self.rioY0) / Agua.celdaRio)
    local n = self.rioN
    if i < 0 or j < 0 or i >= n or j >= n or not self.rioCerca[j * n + i] then
        return false
    end
    local rej = s.relieve
    if rej:interpolar(rej.dAgua, x, y) > Agua.orillaRio then
        return false
    end
    return h < rej:interpolar(rej.nivelAgua, x, y) - Agua.vadoPisable
end

--- Lagos de la hidrología: PENDIENTE (el mar ya lo evita el A* por su altura).
function Agua:lagoEn(_, _)
    return false
end

--- ¿Cae (x, y) en el cauce del río (o del cañón) con `margen` px más?
function Agua:rioEn(x, y, margen)
    local cauces = self.suelo.cauces
    return cauces and cauces:enCauce(x, y, margen) or false
end

--- Nivel del agua en (x, y) (px): el del río sobre su cauce; si no, el del mar.
function Agua:nivelEn(x, y)
    local cauces = self.suelo.cauces
    local nivel = self.hayRio and cauces:nivelEn(x, y)
    return nivel or self.nivel
end

--- Peso (0 a 1) con el que los pasillos pueden rellenar el vértice `k`: sin
-- ríos todavía, siempre 1.
function Agua:pesoFueraDelCauce(_)
    return 1
end

--- Puentes: PENDIENTE.
function Agua:puenteEn(_, _)
    return false
end

--- Charcos de uno o dos vértices bajo el nivel del agua, sueltos en tierra
-- firme (restos del suavizado, más pequeños que la rejilla de los bordes):
-- se rellenan hasta la orilla. Devuelve cuántos vértices subió.
function Agua:rellenarCharcos()
    local rej = self.suelo.relieve
    local lado, h = rej.lado, rej.h
    local nivelAgua = rej.nivelAgua
    local tope = self.nivel + Agua.margen
    local subidos = 0
    for _ = 1, 2 do
        for j = 1, lado - 2 do
            for i = 1, lado - 2 do
                local k = j * lado + i
                -- El lecho del río no es un charco aunque baje del tope.
                if h[k] < tope and nivelAgua[k] <= self.nivel + 0.5 then
                    local mojados = 0
                    for dj = -1, 1 do
                        for di = -1, 1 do
                            if (di ~= 0 or dj ~= 0) and h[k + dj * lado + di] < tope then
                                mojados = mojados + 1
                            end
                        end
                    end
                    if mojados <= 2 then
                        h[k] = tope + 1
                        subidos = subidos + 1
                    end
                end
            end
        end
    end
    self.charcos = subidos
    return subidos
end

--- Tramos de borde entre agua y tierra dentro del límite (con 20 m de
-- margen), en `self.bordes` como { x1, y1, x2, y2 } en px.
function Agua:sacarBordes()
    local s = self.suelo
    local limite = s.limite
    local celda = Agua.celda
    local r = limite.radio + 200
    local n = math.floor(2 * r / celda) + 1
    local x0, y0 = limite.cx - r, limite.cy - r
    local rej = s.relieve
    local agua = {}
    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local x, y = x0 + (i + 0.5) * celda, y0 + (j + 0.5) * celda
            local h = rej:interpolar(rej.h, x, y)
            agua[j * n + i] = h < self.nivel + Agua.margen or (self.hayRio and self:rioHondo(x, y, h))
        end
    end
    local dentro = (r + celda) ^ 2
    local function cerca(x, y)
        return (x - limite.cx) ^ 2 + (y - limite.cy) ^ 2 < dentro
    end
    local bordes = {}
    -- Lados verticales (entre (i, j) e (i + 1, j)), juntados por columnas.
    for i = 0, n - 2 do
        local desde
        for j = 0, n do
            local hay = j < n and agua[j * n + i] ~= agua[j * n + i + 1] and cerca(x0 + (i + 1) * celda, y0 + j * celda)
            if hay and not desde then
                desde = j
            elseif not hay and desde then
                local x = x0 + (i + 1) * celda
                bordes[#bordes + 1] = { x, y0 + desde * celda, x, y0 + j * celda }
                desde = nil
            end
        end
    end
    -- Lados horizontales (entre (i, j) e (i, j + 1)), juntados por filas.
    for j = 0, n - 2 do
        local desde
        for i = 0, n do
            local hay = i < n
                and agua[j * n + i] ~= agua[(j + 1) * n + i]
                and cerca(x0 + i * celda, y0 + (j + 1) * celda)
            if hay and not desde then
                desde = i
            elseif not hay and desde then
                local y = y0 + (j + 1) * celda
                bordes[#bordes + 1] = { x0 + desde * celda, y, x0 + i * celda, y }
                desde = nil
            end
        end
    end
    self.bordes = bordes
end

return Agua
