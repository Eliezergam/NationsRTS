-- Plantar bandera (modo jugador; diseno/territorio-y-capitales.md, 3.7): el
-- modo de colocación con el ratón. En el mapa, el bloque de 6 x 6 celdas que
-- dará la bandera (verde si se puede, granate si no), con las celdas que ya
-- son de otra nación rayadas (esas no se pisan), y el mástil fantasma; al
-- lado del ratón, el coste y, si no se puede, el motivo en claro. El clic
-- izquierdo planta (un comando a `sim:ejecutar`, como un presidente NPC) y el
-- derecho o Esc cancela.
--
-- Solo lee la simulación (`puedePlantarBandera`, `duenoCelda`); planta con un
-- comando.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Iso = require('mundo.iso')
local Simulacion = require('mundo.simulacion')
local Senales = require('mundo.senales')
local Estandartes = require('mundo.estandartes')

local Plantar = {}
Plantar.__index = Plantar

local PASOS_CELDA = 8 -- tramos por lado de celda al seguir el relieve
-- Verde vivo del bloque válido: el oliva del tema se pierde sobre la hierba.
local VERDE = { 0.42, 0.86, 0.3 }

--- Motivos de `puedePlantarBandera`, en claro.
local MOTIVOS = {
    nacion = 'Tu nación ya no existe',
    coste = 'No alcanza el dinero o el metal',
    ajena = 'Es tierra de otra nación',
    terreno = 'Aquí no se puede plantar',
    lejos = 'Tiene que tocar tu territorio',
    separacion = 'Ya hay una bandera tuya aquí al lado',
    propia = 'Ya es tu territorio: plántala en el borde',
    enObra = 'Ya tienes una bandera en obra en este bloque',
}

--- Modo de colocación para la nación `nid`.
function Plantar.nuevo(nid)
    local self = setmetatable({}, Plantar)
    self.nacion = nid
    self.x, self.y = nil, nil -- punto del suelo bajo el ratón
    self.fijo = false -- las capturas fijan el punto (sin ratón)
    self.valido, self.motivo = false, nil
    return self
end

--- Punto del suelo bajo el punto de la vista (vx, vy): Iso.mundo da el de
-- altura 0; unas vueltas con la altura del terreno lo asientan en la ladera.
function Plantar.sueloBajo(terreno, vx, vy)
    local x, y = Iso.mundo(vx, vy)
    for _ = 1, 4 do
        local z = math.max(0, terreno:altura(x, y))
        x, y = Iso.mundo(vx, vy + z * Iso.escalaAltura)
    end
    return x, y
end

--- Coloca el punto (en coordenadas del mundo) y mira si se puede plantar.
function Plantar:poner(sim, x, y)
    self.x, self.y = x, y
    local ok, motivo = sim:puedePlantarBandera(self.nacion, x, y)
    self.valido = ok and true or false
    self.motivo = not ok and (MOTIVOS[motivo] or 'No se puede plantar aquí') or nil
    if motivo == 'separacion' then
        self.motivo = string.format('%s (mín. %s)', self.motivo, Tema.numero(Simulacion.bandera.separacion))
    end
end

--- Planta la bandera: el mismo comando que usa un presidente NPC. Devuelve el
-- id o false (y deja el motivo).
function Plantar:confirmar(sim)
    if not self.x then
        return false
    end
    self:poner(sim, self.x, self.y)
    if not self.valido then
        return false
    end
    local id = sim:ejecutar({ tipo = 'bandera', nacion = self.nacion, x = self.x, y = self.y })
    if not id then
        self.valido, self.motivo = false, 'La simulación no acepta la bandera'
    end
    return id
end

--- Celdas del bloque que daría la bandera: { cx, cy, dueno } (dueno: id de
-- nación o nil) y su caja cx0, cy0, cx1, cy1.
function Plantar:celdas(sim)
    local cx0, cy0, cx1, cy1 = Simulacion.bloqueBandera(self.x, self.y)
    local lista = {}
    for cy = cy0, cy1 do
        for cx = cx0, cx1 do
            lista[#lista + 1] = { cx, cy, sim:duenoCelda(cx, cy) }
        end
    end
    return lista, cx0, cy0, cx1, cy1
end

--- Punto del suelo (x, y) en la vista, a la altura del terreno (el agua, a su nivel).
local function sobreSuelo(terreno, x, y)
    return Iso.vista(x, y, math.max(0, terreno:altura(x, y)))
end

--- Malla del bloque: cada celda partida en tramos que siguen el relieve,
-- del color que toca (libre, tuya o de otra nación). Se rehace solo cuando
-- el bloque cambia de sitio, de validez o el territorio cambia.
function Plantar:mallaBloque(mundo, sim)
    local lista, cx0, cy0, cx1, cy1 = self:celdas(sim)
    local clave = table.concat({ cx0, cy0, tostring(self.valido), sim.estado.versionTerritorio or 0 }, ':')
    if self.clave == clave then
        return self.malla, self.contorno, self.ajenas
    end
    local c = Simulacion.celda
    local tinte = self.valido and VERDE or Tema.colores.rojo
    local ajena = Tema.colores.rojoOscuro
    local vertices = {}
    local ajenas = {}
    local otras = 0
    local paso = c / PASOS_CELDA
    for _, celda in ipairs(lista) do
        local cx, cy, dueno = celda[1], celda[2], celda[3]
        -- Las libres (las que ganarías) resaltan; las tuyas apenas.
        local color, alfa = tinte, 0.42
        if dueno and dueno ~= self.nacion then
            color, alfa = ajena, 0.55
        elseif dueno == self.nacion then
            alfa = 0.1
        end
        for j = 0, PASOS_CELDA - 1 do
            for i = 0, PASOS_CELDA - 1 do
                local xa, ya = cx * c + i * paso, cy * c + j * paso
                local ax, ay = sobreSuelo(mundo.terreno, xa, ya)
                local bx, by = sobreSuelo(mundo.terreno, xa + paso, ya)
                local dx, dy = sobreSuelo(mundo.terreno, xa + paso, ya + paso)
                local ex, ey = sobreSuelo(mundo.terreno, xa, ya + paso)
                for _, p in ipairs({ { ax, ay }, { bx, by }, { dx, dy }, { ax, ay }, { dx, dy }, { ex, ey } }) do
                    vertices[#vertices + 1] = { p[1], p[2], 0, 0, color[1], color[2], color[3], alfa }
                end
            end
        end
        if dueno and dueno ~= self.nacion then
            otras = otras + 1
            -- Rayada (líneas paralelas a un lado, que en la vista salen
            -- inclinadas y siguen de una celda a la otra): esta no se pisaría.
            for r = 0, 3 do
                local linea = {}
                local y = cy * c + (r + 0.5) * c / 4
                for k = 0, PASOS_CELDA do
                    local vx, vy = sobreSuelo(mundo.terreno, cx * c + k * paso, y)
                    linea[#linea + 1] = vx
                    linea[#linea + 1] = vy
                end
                ajenas[#ajenas + 1] = linea
            end
        end
    end
    -- Contorno del bloque entero, por los bordes de celda.
    local contorno = {}
    local x0, y0, x1, y1 = cx0 * c, cy0 * c, (cx1 + 1) * c, (cy1 + 1) * c
    local lados = { { x0, y0, x1, y0 }, { x1, y0, x1, y1 }, { x1, y1, x0, y1 }, { x0, y1, x0, y0 } }
    local tramos = PASOS_CELDA * (cx1 - cx0 + 1)
    for _, l in ipairs(lados) do
        for k = 0, tramos - 1 do
            local t = k / tramos
            local vx, vy = sobreSuelo(mundo.terreno, l[1] + (l[3] - l[1]) * t, l[2] + (l[4] - l[2]) * t)
            contorno[#contorno + 1] = vx
            contorno[#contorno + 1] = vy
        end
    end
    self.clave = clave
    self.malla = love.graphics.newMesh(vertices, 'triangles', 'static')
    self.contorno, self.ajenas, self.otras = contorno, ajenas, otras
    return self.malla, self.contorno, self.ajenas
end

--- En el mapa (dentro de la transformación de la cámara): el bloque de
-- celdas que dará, siguiendo el relieve, y el mástil fantasma.
function Plantar:dibujarMundo(mundo, zoom, semilla, color)
    if not self.x then
        return
    end
    local g = love.graphics
    local tinte = self.valido and VERDE or Tema.colores.rojo
    local malla, contorno, ajenas = self:mallaBloque(mundo, mundo.sim)
    local k = 1 / math.max(0.05, zoom)
    g.setColor(1, 1, 1, 1)
    g.draw(malla)
    g.setLineWidth(math.max(1, 1.5 * k))
    g.setColor(0.08, 0.06, 0.04, 0.6)
    for _, linea in ipairs(ajenas) do
        g.line(linea)
    end
    -- Contorno con una sombra oscura debajo: se lee sobre la hierba y sobre
    -- el territorio pintado.
    g.setColor(0.08, 0.06, 0.04, 0.6)
    g.setLineWidth(math.max(1, 5 * k))
    g.polygon('line', contorno)
    g.setColor(tinte[1], tinte[2], tinte[3], 1)
    g.setLineWidth(math.max(1, 2.5 * k))
    g.polygon('line', contorno)
    g.setLineWidth(1)
    local z = math.max(0, mundo.terreno:altura(self.x, self.y))
    local vx, vy = Iso.vista(self.x, self.y, z)
    g.push()
    g.translate(vx, vy)
    g.scale(k)
    local fantasma = { x = self.x, y = self.y, enObra = not self.valido, progreso = 1, vida = 100 }
    Senales.bandera(
        fantasma,
        0,
        0,
        self.valido and color or Tema.colores.textoHudTenue,
        Estandartes.escudoDe(semilla, self.nacion)
    )
    g.pop()
end

--- Junto al punto de pantalla (sx, sy): título, coste y el motivo o cómo se
-- confirma. `nacion` para el coste en rojo si no alcanza.
function Plantar:dibujarPantalla(sx, sy, nacion)
    local g = love.graphics
    local titulo = Acero.fuente('boton', 20)
    local texto = Acero.fuente('cuerpo', 16)
    local reglas = Simulacion.bandera
    local coste = string.format(
        'Cuesta %s dinero y %s metal · %s al día',
        Tema.numero(reglas.dinero),
        Tema.numero(reglas.metal),
        Tema.decimal(-reglas.mantenimiento)
    )
    local alcanza = nacion
        and Simulacion.disponible(nacion, 'dinero') >= reglas.dinero
        and Simulacion.disponible(nacion, 'metal') >= reglas.metal
    local lineas = {
        { 'Plantar bandera', titulo, 'textoHud' },
        { coste, texto, alcanza and 'amarillo' or 'rojoTexto' },
    }
    if (self.otras or 0) > 0 then
        local celdas = self.otras == 1 and '1 celda es' or (self.otras .. ' celdas son')
        lineas[#lineas + 1] = { celdas .. ' de otra nación: no se pisan', texto, 'textoHudTenue' }
    end
    if self.valido then
        lineas[#lineas + 1] = { 'Clic: plantar · clic derecho o Esc: cancelar', texto, 'verde' }
    else
        lineas[#lineas + 1] = { self.motivo or 'Mueve el ratón sobre el mapa', texto, 'rojoTexto' }
        lineas[#lineas + 1] = { 'Clic derecho o Esc: cancelar', texto, 'textoHudTenue' }
    end
    local relleno = Tema.px(8)
    local ancho, alto = 0, relleno * 2
    for _, l in ipairs(lineas) do
        ancho = math.max(ancho, l[2]:getWidth(l[1]))
        alto = alto + l[2]:getHeight()
    end
    ancho = ancho + relleno * 2
    local w, h = g.getDimensions()
    local x = math.min(sx + Tema.px(22), w - ancho - Tema.px(8))
    local y = math.min(sy + Tema.px(18), h - alto - Tema.px(8))
    Acero.placa(x, y, ancho, alto, Tema.px(4), 'olivaNegro', self.valido and 'amarillo' or 'rojoTexto', 0.96)
    local cy = y + relleno
    for _, l in ipairs(lineas) do
        g.setFont(l[2])
        Tema.color(l[3])
        g.print(l[1], x + relleno, cy)
        cy = cy + l[2]:getHeight()
    end
end

return Plantar
