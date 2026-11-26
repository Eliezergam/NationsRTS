-- Lo que ven los sensores del robot, dibujado encima de la escena (tecla R
-- en el almacén): los rayos del lidar en 3D (rojos; un punto donde chocan),
-- los puntos de agarre de los objetos (amarillos) y los huecos de los
-- muebles (azules), y en una esquina el mapa que va aprendiendo, con su
-- ruta, más la lista de lo que reconoce alrededor.

local dream = require('lib.3DreamEngine')

local VistaSensores = {}
VistaSensores.__index = VistaSensores

-- Cómo se llama cada tipo para leer.
local NOMBRES = {
    rack = 'rack', rackPolvorin = 'rack del polvorín', muro = 'muro', pared = 'pared', chapaFachada = 'pared',
    pilar = 'pilar', porton = 'portón', puertaBlindada = 'puerta blindada', vidrio = 'vidrio de la sala',
    salaControl = 'sala de control', banco = 'banco de trabajo', caja = 'cajas', estanteria = 'estantería',
    contenedorMisil = 'contenedor de misil', ledsServidores = 'servidores', pantallasPuestos = 'monitores',
    cablesSala = 'cables', mesaRecepcion = 'mesa de recepción', estanteriaRobot = 'estantería del robot',
    cajaRobot = 'caja de plástico', cajaMunicion = 'caja de munición',
    cartelDinero = 'cartel «DINERO»', cartelMunicion = 'cartel «MUNICIÓN»', cartelComida = 'cartel «COMIDA»',
    valla = 'valla', exterior = 'suelo de fuera', rackRobot = 'rack del robot',
}

-- Color de cada tipo en el mapa.
local COLORES = {
    rack = { 0.25, 0.5, 1 }, mesaRecepcion = { 0.9, 0.6, 0.3 }, estanteriaRobot = { 1, 0.55, 0.1 },
    cajaRobot = { 1, 0.85, 0.1 }, cajaMunicion = { 1, 0.85, 0.1 }, vidrio = { 0.5, 0.9, 1 },
    salaControl = { 0.5, 0.9, 1 }, muro = { 0.75, 0.75, 0.75 }, pared = { 0.75, 0.75, 0.75 },
}

function VistaSensores.nombre(tipo)
    return NOMBRES[tipo] or tipo or '?'
end

function VistaSensores.nueva()
    local self = setmetatable({}, VistaSensores)
    self.visible = true
    self.letra = love.graphics.newFont('assets/fuentes/BarlowCondensed-SemiBold.ttf', 18)
    self.letraPequena = love.graphics.newFont('assets/fuentes/BarlowCondensed-SemiBold.ttf', 14)
    return self
end

-- Del almacén a la pantalla (nil si queda detrás de la cámara).
local function aPantalla(x, y, z)
    local c = dream.camera
    if not c.transformProj then
        return nil
    end
    local p = c.transformProj * dream.vec4(x, z, -y, 1)
    if p[4] <= 0.05 then
        return nil
    end
    local w, h = love.graphics.getDimensions()
    return (p[1] / p[4] + 1) * w / 2, (p[2] / p[4] + 1) * h / 2
end
VistaSensores.aPantalla = aPantalla

-- Un segmento del almacén en pantalla, recortado contra el plano de la
-- cámara (si un extremo queda detrás, se corta ahí; si no, saldría
-- disparado a cualquier sitio). Devuelve x0, y0, x1, y1 o nil.
local function segmento(ax, ay, az, bx, by, bz)
    local c = dream.camera
    if not c.transformProj then
        return nil
    end
    local p = c.transformProj * dream.vec4(ax, az, -ay, 1)
    local q = c.transformProj * dream.vec4(bx, bz, -by, 1)
    local cerca = 0.06
    if p[4] < cerca and q[4] < cerca then
        return nil
    end
    if p[4] < cerca or q[4] < cerca then
        local t = (cerca - p[4]) / (q[4] - p[4])
        local r = { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, p[3] + (q[3] - p[3]) * t, cerca }
        if p[4] < cerca then
            p = r
        else
            q = r
        end
    end
    local w, h = love.graphics.getDimensions()
    return (p[1] / p[4] + 1) * w / 2, (p[2] / p[4] + 1) * h / 2, (q[1] / q[4] + 1) * w / 2, (q[2] / q[4] + 1) * h / 2
end

function VistaSensores:prepararMapa(mapa)
    if self.mapa == mapa then
        return
    end
    self.mapa = mapa
    self.datos = love.image.newImageData(mapa.ancho, mapa.alto)
    self.datos:mapPixel(function()
        return 0.05, 0.06, 0.07, 0.8
    end)
    self.imagen = love.graphics.newImage(self.datos)
    self.imagen:setFilter('nearest', 'nearest')
end

-- Pinta en la imagen las casillas que cambiaron.
function VistaSensores:actualizarMapa(mapa)
    self:prepararMapa(mapa)
    local cambios = mapa.ultimosCambios
    if #cambios == 0 then
        return
    end
    local umbral = mapa.umbral or 0.6
    for _, i in ipairs(cambios) do
        local cx, cy = i % mapa.ancho, math.floor(i / mapa.ancho)
        local v = mapa.celdas[i]
        local r, g, b, a
        if v > umbral then
            local c = COLORES[mapa.tipos[i]] or { 0.85, 0.85, 0.85 }
            r, g, b, a = c[1], c[2], c[3], 1
        elseif v < -0.2 then
            r, g, b, a = 0.22, 0.26, 0.3, 0.85
        else
            r, g, b, a = 0.12, 0.13, 0.15, 0.85
        end
        self.datos:setPixel(cx, mapa.alto - 1 - cy, r, g, b, a)
    end
    mapa.ultimosCambios = {}
    self.imagen:replacePixels(self.datos)
end

--- Solo los rayos de los ojos de `robot` (para los que no se siguen).
function VistaSensores:dibujarOjosDe(robot)
    if not self.visible then
        return
    end
    local g = love.graphics
    g.push('all')
    g.origin()
    self:dibujarOjos(robot)
    g.pop()
end

function VistaSensores:dibujar(robot)
    if not self.visible or not robot then
        return
    end
    local g = love.graphics
    g.push('all')
    g.origin()
    self:dibujarRayos(robot)
    self:dibujarPuntos(robot)
    self:dibujarMapa(robot)
    self:dibujarTexto(robot)
    g.pop()
end

-- El lidar gira: se dibuja solo el abanico que «está barriendo» ahora (con
-- una estela que se apaga), no los 360 rayos a la vez. Los datos son los del
-- último barrido (el robot los usa todos igual).
VistaSensores.vueltasPorSegundo = 1.2
VistaSensores.estela = math.rad(50)

-- Los rayos rojos del lidar no se dibujan (decisión del dueño, 17-nov):
-- en pantalla solo se ven los de los ojos. Poner a true para depurar.
VistaSensores.verLidar = false

function VistaSensores:dibujarRayos(robot)
    if not VistaSensores.verLidar then
        self:dibujarOjos(robot)
        return
    end
    local g = love.graphics
    g.setLineWidth(1)
    local barrido = (love.timer.getTime() * VistaSensores.vueltasPorSegundo * 2 * math.pi) % (2 * math.pi)
    for _, r in ipairs(robot:getRayos()) do
        -- Cuánto hace que el barrido pasó por este rayo (0 = ahora mismo).
        local relativo = (r.angulo - robot:getRumbo()) % (2 * math.pi)
        local atras = (barrido - relativo) % (2 * math.pi)
        if atras < VistaSensores.estela then
            local f = 1 - atras / VistaSensores.estela
            local hx, hy = r.x + math.cos(r.angulo) * r.distancia, r.y + math.sin(r.angulo) * r.distancia
            local x0, y0, x1, y1 = segmento(r.x, r.y, r.z, hx, hy, r.z)
            if x0 then
                g.setColor(1, 0.12, 0.08, (r.choca and 0.55 or 0.2) * f)
                g.line(x0, y0, x1, y1)
                if r.choca and aPantalla(hx, hy, r.z) then
                    g.setColor(1, 0.2, 0.1, 0.95 * f)
                    g.circle('fill', x1, y1, 3)
                end
            end
        end
    end
    self:dibujarOjos(robot)
end

-- Dos rayos fijos desde los ojos hacia donde mira la cabeza, hasta lo
-- primero que tocan (siempre encendidos).
-- Los rayos de los ojos tampoco se dibujan si no se piden (el dueño, 17-nov):
-- el robot sigue viendo igual; la tecla O del almacén los enseña o los quita.
-- 18-nov: encendidos al entrar para ver los del soldado que entrena.
VistaSensores.verOjos = not os.getenv('VIDEO_CARA') -- (VIDEO_CARA: sin rayos, para ver la cara)

--- Disparos del robot (robots/especializaciones/combate.lua): trazadoras
-- naranjas de la boca al impacto, fogonazo en la boca, chispas donde dan
-- (rojas si dan al enemigo) y un recuadro rojo con la vida del enemigo al
-- que apunta.
function VistaSensores:dibujarDisparos(robot)
    if not robot or not robot.getDisparos then
        return
    end
    local disparos, chispas, vida = robot:getDisparos()
    if not disparos then
        return
    end
    local g = love.graphics
    g.push('all')
    g.origin()
    g.setBlendMode('add')
    for _, b in ipairs(disparos) do
        -- La bala vuela: se dibuja un trozo que avanza de la boca al impacto.
        local f = b.t / vida
        local f0, f1 = math.max(0, f - 0.35), math.min(1, f + 0.35)
        local ax, ay, az = b[1] + (b[4] - b[1]) * f0, b[2] + (b[5] - b[2]) * f0, b[3] + (b[6] - b[3]) * f0
        local cx, cy, cz = b[1] + (b[4] - b[1]) * f1, b[2] + (b[5] - b[2]) * f1, b[3] + (b[6] - b[3]) * f1
        local x0, y0, x1, y1 = segmento(ax, ay, az, cx, cy, cz)
        if x0 then
            g.setLineWidth(4)
            g.setColor(1, 0.45, 0.1, 0.35)
            g.line(x0, y0, x1, y1)
            g.setLineWidth(1.6)
            g.setColor(1, 0.85, 0.5, 0.9)
            g.line(x0, y0, x1, y1)
        end
    end
    for _, c in ipairs(chispas) do
        local px, py = aPantalla(c[1], c[2], c[3])
        if px then
            local f = 1 - c.t / 0.25
            if c.enemigo then
                g.setColor(1, 0.35, 0.15, f)
            else
                g.setColor(1, 0.8, 0.4, f)
            end
            g.circle('fill', px, py, 2 + 5 * f)
            for k = 0, 4 do
                local a = k * 1.256 + c.t * 3 + c[1] * 7
                local l = 4 + 14 * (1 - f)
                g.line(px + math.cos(a) * l * 0.4, py + math.sin(a) * l * 0.4, px + math.cos(a) * l, py + math.sin(a) * l)
            end
        end
    end
    local fx, fy, fz, fuerza = robot:getFogonazo()
    if fx then
        local px, py = aPantalla(fx, fy, fz)
        if px then
            g.setColor(1, 0.75, 0.35, 0.8 * fuerza)
            g.circle('fill', px, py, 10 + 8 * love.math.random())
            g.setColor(1, 0.95, 0.8, fuerza)
            g.circle('fill', px, py, 5)
        end
    end
    g.setBlendMode('alpha')
    -- El enemigo al que apunta: recuadro rojo y su vida.
    local e = robot.getObjetivo and robot:getObjetivo()
    if e then
        local ex, ey = e:getPosicion()
        local m = e:getMatriz()
        local px0, py0 = aPantalla(ex, ey, m[12] + 1.55)
        local px1, py1 = aPantalla(ex, ey, m[12])
        if px0 and px1 then
            local alto = math.abs(py1 - py0)
            local ancho = alto * 0.55
            g.setColor(1, 0.25, 0.2, 0.9)
            g.setLineWidth(2)
            g.rectangle('line', px0 - ancho / 2, py0, ancho, alto)
            g.setLineWidth(1)
            local texto = e.vida > 0 and string.format('ENEMIGO · vida %d/%d', e.vida, e.vidaMax or e.vida) or 'DESTRUIDO'
            g.setFont(self.letraPequena)
            local w = self.letraPequena:getWidth(texto)
            g.setColor(0, 0, 0, 0.65)
            g.rectangle('fill', px0 - w / 2 - 5, py0 - 24, w + 10, 20, 4, 4)
            g.setColor(1, 0.4, 0.35, 1)
            g.print(texto, px0 - w / 2, py0 - 22)
        end
    end
    g.pop()
end

function VistaSensores:dibujarOjos(robot)
    if not VistaSensores.verOjos then
        return
    end
    local g = love.graphics
    local ojos = robot.getOjos and robot:getOjos() or {}
    local etiqueta
    for _, o in ipairs(ojos) do
        local x0, y0, x1, y1 = segmento(o[1], o[2], o[3], o[4], o[5], o[6])
        if x0 then
            g.setLineWidth(2)
            g.setColor(0.3, 0.85, 1, 0.75)
            g.line(x0, y0, x1, y1)
            local px, py = aPantalla(o[4], o[5], o[6])
            if px and o.tipo then
                g.setColor(0.6, 0.95, 1, 1)
                g.circle('fill', px, py, 3.5)
                etiqueta = etiqueta or { px, py, o }
            end
        end
    end
    g.setLineWidth(1)
    -- Lo que tocan los ojos, con su nombre (y lo que sabe de ello).
    if etiqueta then
        local px, py, o = etiqueta[1], etiqueta[2], etiqueta[3]
        local texto = string.format('%s · %.1f m', o.nombre, o.distancia)
        if o.objeto and o.objeto.cantidad then
            texto = texto .. ' · ' .. math.floor(o.objeto.cantidad)
        end
        if o.objeto and o.objeto:getMovible() then
            texto = texto .. string.format(' · %d kg', o.objeto:getPeso())
        end
        -- Lo que dice la zona de información que cruza el rayo (puerta,
        -- portón, marco, esquina).
        if o.info then
            local i = o.info
            texto = texto .. ' · ' .. i.nombre
            if i.ancho then
                texto = texto .. string.format(' %.1f × %.1f m%s', i.ancho, i.alto, i.abierto and '' or ' (cerrada)')
            end
        end
        g.setFont(self.letraPequena)
        local w = self.letraPequena:getWidth(texto)
        g.setColor(0, 0, 0, 0.65)
        g.rectangle('fill', px + 8, py - 22, w + 10, 20, 4, 4)
        g.setColor(0.6, 0.95, 1, 1)
        g.print(texto, px + 13, py - 20)
    end
end

function VistaSensores:dibujarPuntos(robot)
    local g = love.graphics
    local rx, ry = robot:getPosicion()
    g.setFont(self.letraPequena)
    for _, o in ipairs(GestorObjetos.getObjetos()) do
        local ox, oy = o:getPosicion()
        if (ox - rx) ^ 2 + (oy - ry) ^ 2 < 8 ^ 2 then
            for _, p in ipairs(o:getPuntosAgarre()) do
                local x, y = aPantalla(p.x, p.y, p.z)
                if x then
                    g.setColor(1, 0.85, 0.05, 1)
                    g.polygon('line', x, y - 7, x + 7, y, x, y + 7, x - 7, y)
                    g.circle('fill', x, y, 2)
                end
            end
            for _, h in ipairs(o:getHuecos()) do
                local x, y = aPantalla(h.x, h.y, h.z + 0.005)
                if x then
                    g.setColor(0.3, 0.75, 1, h.ocupado and 0.35 or 0.9)
                    g.rectangle('line', x - 5, y - 3, 10, 6)
                end
            end
        end
    end
end

function VistaSensores:dibujarMapa(robot)
    local g = love.graphics
    local mapa = robot:getMapa()
    self:actualizarMapa(mapa)
    local w = g.getWidth()
    local escala = math.min(0.75, (w * 0.34) / mapa.ancho)
    local ancho, alto = mapa.ancho * escala, mapa.alto * escala
    local x0, y0 = w - ancho - 16, 16
    g.setColor(0, 0, 0, 0.55)
    g.rectangle('fill', x0 - 8, y0 - 8, ancho + 16, alto + 40, 6, 6)
    g.setColor(1, 1, 1, 1)
    g.draw(self.imagen, x0, y0, 0, escala, escala)
    local function punto(x, y)
        return x0 + (x - mapa.x0) / mapa.resolucion * escala, y0 + alto - (y - mapa.y0) / mapa.resolucion * escala
    end
    -- Ruta.
    local ruta = robot:getRuta()
    if #ruta > 0 then
        local px, py = punto(robot:getPosicion())
        g.setColor(0.2, 1, 0.4, 0.9)
        g.setLineWidth(2)
        for _, p in ipairs(ruta) do
            local qx, qy = punto(p[1], p[2])
            g.line(px, py, qx, qy)
            px, py = qx, qy
        end
    end
    -- Robot.
    local x, y = robot:getPosicion()
    local px, py = punto(x, y)
    local a = robot:getRumbo()
    g.setColor(1, 1, 1, 1)
    g.circle('fill', px, py, 4)
    g.setLineWidth(2)
    g.line(px, py, px + math.cos(a) * 10, py - math.sin(a) * 10)
    g.setFont(self.letraPequena)
    g.setColor(1, 1, 1, 0.85)
    g.print(string.format('MAPA QUE APRENDE · %d m² vistos · rutas: %d', math.floor(mapa:getVistas() * mapa.resolucion ^ 2), robot:getReplanes()), x0, y0 + alto + 8)
end

function VistaSensores:dibujarTexto(robot)
    local g = love.graphics
    local x, y = 16, 92
    local lista = {}
    for tipo, v in pairs(robot:getVisto()) do
        lista[#lista + 1] = { tipo = tipo, distancia = v.distancia, veces = v.veces }
    end
    table.sort(lista, function(a, b)
        return a.distancia < b.distancia
    end)
    local lineas = math.min(#lista, 7)
    local reconocido = robot.getReconocido and robot:getReconocido()
    g.setColor(0, 0, 0, 0.55)
    g.rectangle('fill', x - 4, y - 4, 360, 76 + lineas * 20, 6, 6)
    g.setFont(self.letra)
    g.setColor(1, 0.85, 0.2, 1)
    g.print('ROBOT: ' .. (robot.getTarea and robot:getTarea() or ''), x + 6, y)
    g.setColor(1, 1, 1, 0.9)
    local llevando = robot:getLlevando()
    g.print(string.format('LIDAR %d capas · %d rayos', #robot:getAjustes('lidar').capas, robot:getAjustes('lidar').rayos) .. (llevando and ('  ·  lleva: ' .. llevando:getNombre()) or ''), x + 6, y + 22)
    g.setFont(self.letraPequena)
    for k = 1, lineas do
        local v = lista[k]
        g.setColor(1, 0.45, 0.35, 1)
        g.print(string.format('el lidar nota %s a %.1f m (%d rayos)', VistaSensores.nombre(v.tipo), v.distancia, v.veces), x + 6, y + 46 + (k - 1) * 20)
    end
    g.setColor(0.6, 0.95, 1, 1)
    g.print('OJOS: ' .. (reconocido and string.format('es %s, a %.1f m', reconocido.nombre, reconocido.distancia) or '—'), x + 6, y + 46 + lineas * 20)
end

return VistaSensores
