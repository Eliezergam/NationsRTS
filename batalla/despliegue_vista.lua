-- Dibujo de la fase de preparación (batalla/despliegue.lua): las zonas de
-- despliegue sobre el terreno (borde del color de cada bando con una franja
-- por dentro que se desvanece, como en Bannerlord, y su nombre) y el panel
-- de abajo con el contador y el botón «Listo», con la interfaz militar
-- (interfaz/acero.lua). El interior de la zona no se tiñe: el terreno se ve
-- con su color.
--
-- Se dibuja en 2D encima de la escena, como los anillos de selección
-- (batalla/anillo_holo.lua): cada punto de la zona se pone a la altura del
-- suelo y se proyecta con la cámara de la batalla, y lo que la escena tapa
-- (una loma, un edificio, un muro) no se ve: cada píxel compara su
-- profundidad con la de la escena 3D (el dueño, 19-nov: las líneas cruzaban
-- naves y montañas). Solo dibuja: no cambia nada.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Vida = require('interfaz.vida')
local MarcasHolo = require('batalla.marcas_holo')

local DespliegueVista = {}
DespliegueVista.__index = DespliegueVista

DespliegueVista.pasoBorde = 150 -- px del mundo entre los puntos del borde
DespliegueVista.maxPasos = 200 -- tramos por lado del borde, como mucho
DespliegueVista.anchoFranja = 300 -- px del mundo de la franja de color por dentro del borde
DespliegueVista.alfaFranja = 0.32 -- opacidad de la franja junto al borde (se desvanece hacia dentro)
DespliegueVista.fundido = 0.6 -- s que tardan las zonas en irse al empezar el combate
DespliegueVista.ancho = 440 -- ancho de diseño del panel (1080p)

DespliegueVista.alzado = 6 -- px del mundo sobre el suelo (que no se hunda entre dos puntos)

local VERTICES_POR_TRAMO = 6 -- dos triángulos de la franja por tramo
local FORMATO = {
    { 'VertexPosition', 'float', 2 },
    { 'VertexColor', 'float', 4 },
    { 'Profundidad', 'float', 1 }, -- distancia al ojo en la vista (px del mundo)
}

-- Lo que tapa la escena no se dibuja (la misma prueba que `tapado` en
-- batalla/anillo_holo.lua, con el lienzo de profundidad de 3Dream).
local CODIGO_SOMBREADOR = [[
varying float vProfundidad;

#ifdef VERTEX
attribute float Profundidad;

vec4 position(mat4 transformProjection, vec4 vertexPosition)
{
    vProfundidad = Profundidad;
    return transformProjection * vertexPosition;
}
#endif

#ifdef PIXEL
uniform Image profundidadEscena;
uniform float escalaProfundidad;
uniform vec2 rangoProfundidad;
uniform float conProfundidad;

vec4 effect(vec4 color, Image textura, vec2 uv, vec2 pantalla)
{
    if (conProfundidad > 0.5) {
        float escena = Texel(profundidadEscena, pantalla / love_ScreenSize.xy).r;
        float d = vProfundidad * escalaProfundidad;
        float mia = rangoProfundidad.x * d + rangoProfundidad.y;
        if (escena < mia - 0.05 - 0.01 * d) {
            discard;
        }
    }
    return color;
}
#endif
]]

--- Vista de la preparación `despliegue` con el `control` de la escena (su
-- cámara y su proyección) y los colores del `combate`.
function DespliegueVista.nueva(despliegue, control, combate)
    local self = setmetatable({}, DespliegueVista)
    self.despliegue = despliegue
    self.control = control
    self.colores = { combate.atacante.color, combate.defensor.color }
    self.nombres = { combate.atacante.nombre, combate.defensor.nombre }
    local capacidad = 4 * DespliegueVista.maxPasos * VERTICES_POR_TRAMO
    self.malla = love.graphics.newMesh(FORMATO, capacidad, 'triangles', 'stream')
    self.vertices = {}
    -- El borde: un cinto de cuadriláteros en pantalla (dos pasadas: filo
    -- oscuro y color), también con profundidad.
    self.mallaBorde = love.graphics.newMesh(FORMATO, capacidad * 2, 'triangles', 'stream')
    self.verticesBorde = {}
    self.sombreador = love.graphics.newShader(CODIGO_SOMBREADOR)
    local vacia = love.graphics.newImage(love.image.newImageData(1, 1))
    self.sinProfundidad = vacia
    self.botonListo = nil
    return self
end

--- Opacidad de las zonas: 1 durante la preparación; al terminar, se funden
-- en `fundido` s (en las capturas, que no animan, desaparecen ya).
function DespliegueVista:opacidad()
    local d = self.despliegue
    if not d.terminada then
        return 1
    end
    if Vida.quieta then
        return 0
    end
    local ahora = love.timer.getTime()
    self.finVisto = self.finVisto or ahora
    return math.max(0, 1 - (ahora - self.finVisto) / DespliegueVista.fundido)
end

--- Punto (d, l) del eje del combate proyectado sobre el suelo. Devuelve la
-- tabla de `Control:proyectar` (con `delante`) o nil.
function DespliegueVista:proyectarEje(d, l, salida)
    local x, y = self.despliegue:aMundo(d, l)
    return self.control:proyectar(x, y, self.control:suelo(x, y), salida)
end

--- Punto del suelo en (d, l) del eje del combate: { x, y, z } del mundo (a
-- la altura del suelo o del agua) y su proyección del cuadro en `proy`.
function DespliegueVista:puntoSuelo(d, l)
    local x, y = self.despliegue:aMundo(d, l)
    return { x = x, y = y, z = self.control:suelo(x, y) + DespliegueVista.alzado, proy = {} }
end

--- Contorno de una zona, calculado una vez (el terreno no cambia): dos
-- vueltas cerradas con el mismo número de puntos, `borde` (el borde de la
-- zona, un punto cada `pasoBorde` px) y `dentro` (la orilla de la franja,
-- `anchoFranja` px hacia dentro).
function DespliegueVista:contorno(zona)
    local franja = math.min(DespliegueVista.anchoFranja, (zona.dMax - zona.dMin) / 2, (zona.lMax - zona.lMin) / 2)
    -- Esquinas y, para cada una, la esquina de la franja (hacia dentro).
    local esquinas = {
        { zona.dMin, zona.lMin, zona.dMin + franja, zona.lMin + franja },
        { zona.dMax, zona.lMin, zona.dMax - franja, zona.lMin + franja },
        { zona.dMax, zona.lMax, zona.dMax - franja, zona.lMax - franja },
        { zona.dMin, zona.lMax, zona.dMin + franja, zona.lMax - franja },
    }
    local borde = {}
    local dentro = {}
    for k = 1, 4 do
        local p = esquinas[k]
        local q = esquinas[k % 4 + 1]
        local largo = math.abs(q[1] - p[1]) + math.abs(q[2] - p[2])
        local pasos = math.max(1, math.min(DespliegueVista.maxPasos, math.ceil(largo / DespliegueVista.pasoBorde)))
        for paso = 0, pasos - 1 do
            local t = paso / pasos
            borde[#borde + 1] = self:puntoSuelo(p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t)
            dentro[#dentro + 1] = self:puntoSuelo(p[3] + (q[3] - p[3]) * t, p[4] + (q[4] - p[4]) * t)
        end
    end
    return { borde = borde, dentro = dentro }
end

--- Proyecta con la cámara del cuadro los puntos de `lista`: cada uno queda
-- con `proy` (x, y de pantalla) y `ve` (delante de la cámara).
function DespliegueVista:proyectar(lista)
    local control = self.control
    for _, p in ipairs(lista) do
        local r = control:proyectar(p.x, p.y, p.z, p.proy)
        p.ve = r ~= nil and r.delante
    end
end

--- Franja de color por dentro del borde, que se desvanece hacia el interior,
-- en una sola malla. Los tramos con algún punto detrás de la cámara no se
-- dibujan.
function DespliegueVista:franja(contorno, color, alfa)
    local vertices = self.vertices
    local n = 0
    local r = color[1]
    local gr = color[2]
    local b = color[3]
    local opaco = DespliegueVista.alfaFranja * alfa
    local function anadir(p, a)
        n = n + 1
        local v = vertices[n] or {}
        vertices[n] = v
        v[1] = p.proy.x
        v[2] = p.proy.y
        v[3] = r
        v[4] = gr
        v[5] = b
        v[6] = a
        v[7] = p.proy.w or 0
    end
    local borde = contorno.borde
    local dentro = contorno.dentro
    local cuantos = #borde
    for i = 1, cuantos do
        local j = i % cuantos + 1
        local a = borde[i]
        local c = borde[j]
        local e = dentro[i]
        local f = dentro[j]
        if a.ve and c.ve and e.ve and f.ve then
            anadir(a, opaco)
            anadir(c, opaco)
            anadir(f, 0)
            anadir(a, opaco)
            anadir(f, 0)
            anadir(e, 0)
        end
    end
    if n == 0 then
        return
    end
    for k = n + 1, #vertices do
        vertices[k] = nil
    end
    self.malla:setVertices(vertices)
    self.malla:setDrawRange(1, n)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.malla)
end

--- Borde de una zona sobre el suelo: un filo oscuro debajo y la línea del
-- color del bando encima, que late muy poco. Cada tramo seguido de puntos a
-- la vista va en una sola línea (las esquinas quedan unidas).
function DespliegueVista:bordear(contorno, color, alfa)
    local borde = contorno.borde
    local cuantos = #borde
    local pulso = Vida.quieta and 1 or (0.85 + 0.15 * math.sin(love.timer.getTime() * 2.4))
    local vertices = self.verticesBorde
    local n = 0
    local function anadir(x, y, r, g, b, a, w)
        n = n + 1
        local v = vertices[n] or {}
        vertices[n] = v
        v[1], v[2], v[3], v[4], v[5], v[6], v[7] = x, y, r, g, b, a, w
    end
    -- Cada tramo entre dos puntos a la vista, un cuadrilátero de `ancho` px
    -- de pantalla alrededor del segmento.
    local function pasada(ancho, r, g, b, a)
        local medio = ancho / 2
        for k = 1, cuantos do
            local p = borde[k]
            local q = borde[k % cuantos + 1]
            if p.ve and q.ve then
                local dx, dy = q.proy.x - p.proy.x, q.proy.y - p.proy.y
                local largo = math.sqrt(dx * dx + dy * dy)
                if largo > 0.01 then
                    -- Un poco más largo por cada punta: las esquinas quedan unidas.
                    local ux, uy = dx / largo * medio, dy / largo * medio
                    local nx, ny = -uy, ux
                    local ax, ay = p.proy.x - ux, p.proy.y - uy
                    local bx, by = q.proy.x + ux, q.proy.y + uy
                    local wp, wq = p.proy.w or 0, q.proy.w or 0
                    anadir(ax + nx, ay + ny, r, g, b, a, wp)
                    anadir(bx + nx, by + ny, r, g, b, a, wq)
                    anadir(bx - nx, by - ny, r, g, b, a, wq)
                    anadir(ax + nx, ay + ny, r, g, b, a, wp)
                    anadir(bx - nx, by - ny, r, g, b, a, wq)
                    anadir(ax - nx, ay - ny, r, g, b, a, wp)
                end
            end
        end
    end
    pasada(math.max(3, Tema.px(7)), 0, 0, 0, 0.5 * alfa)
    pasada(math.max(2, Tema.px(3.5)), color[1], color[2], color[3], 0.95 * alfa * pulso)
    if n == 0 then
        return
    end
    for k = n + 1, #vertices do
        vertices[k] = nil
    end
    self.mallaBorde:setVertices(vertices)
    self.mallaBorde:setDrawRange(1, n)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.mallaBorde)
end

--- Nombre de la zona en su centro, si se ve.
function DespliegueVista:rotular(zona, texto, color, alfa)
    local p = self:proyectarEje((zona.dMin + zona.dMax) / 2, 0, {})
    if not (p and p.visible) then
        return
    end
    local fuente = Acero.fuente('subtitulo')
    local ancho = fuente:getWidth(texto)
    local x = math.floor(p.x - ancho / 2)
    local y = math.floor(p.y - fuente:getHeight() / 2)
    -- Sin pisar el panel (su sitio del cuadro anterior).
    local panel = self.panel
    if
        panel
        and x < panel.x + panel.w
        and panel.x < x + ancho
        and y < panel.y + panel.h
        and panel.y < y + fuente:getHeight()
    then
        return
    end
    Acero.textoContorno(fuente, texto, x, y, color, 'olivaNegro', alfa)
end

--- Las dos zonas sobre el terreno (mientras dura la preparación y el
-- fundido de después).
function DespliegueVista:dibujarZonas()
    local alfa = self:opacidad()
    if alfa <= 0 then
        return
    end
    local g = love.graphics
    g.push('all')
    -- La profundidad de la escena para tapar (sin 3Dream, nada se tapa).
    local sombreador = self.sombreador
    local lienzo, a, b = MarcasHolo.profundidadEscena()
    sombreador:send('profundidadEscena', lienzo or self.sinProfundidad)
    sombreador:send('conProfundidad', lienzo and 1 or 0)
    sombreador:send('rangoProfundidad', { a or 1, b or 0 })
    -- px del mundo a unidades de 3Dream (batalla/dream/conversor.lua).
    sombreador:send('escalaProfundidad', 0.01)
    g.setShader(sombreador)
    local d = self.despliegue
    for indice = 1, 2 do
        -- Las zonas no cambian: su contorno se calcula una vez.
        self.contornos = self.contornos or {}
        local contorno = self.contornos[indice] or self:contorno(d.zonas[indice])
        self.contornos[indice] = contorno
        self:proyectar(contorno.borde)
        self:proyectar(contorno.dentro)
        local color = self.colores[indice]
        self:franja(contorno, color, alfa)
        self:bordear(contorno, color, alfa)
    end
    g.setShader()
    for indice = 1, 2 do
        local zona = d.zonas[indice]
        local texto = indice == d.propio and 'Tu zona de despliegue' or 'Zona enemiga'
        self:rotular(zona, Tema.mayusculas(texto), self.colores[indice], alfa)
    end
    g.pop()
end

--- Estado de un bando en el panel: { texto, color }.
local function estadoBando(listo)
    if listo then
        return 'listo', 'verde'
    end
    return 'organizando', 'textoHudTenue'
end

--- Panel de la preparación, abajo en el centro: título y contador, aviso
-- del combate en pausa, estado de cada bando y el botón «Listo». El alto
-- sale de lo que lleva. Guarda el rectángulo del botón en `botonListo` (nil
-- si no se puede pulsar).
function DespliegueVista:dibujarPanel()
    self.botonListo = nil
    local d = self.despliegue
    if d.terminada then
        return
    end
    local g = love.graphics
    local w, h = g.getDimensions()
    local titulo = Acero.fuente('subtitulo')
    local grande = Acero.fuente('cifraGrande')
    local etiqueta = Acero.fuente('etiqueta')
    local cuerpo = Acero.fuente('cuerpo')
    local margen = Tema.px(16)
    local hueco = Tema.px(8)
    local altoBoton = Tema.px(46)
    local altoCabecera = math.max(titulo:getHeight() + etiqueta:getHeight(), grande:getHeight())
    local altoContenido = altoCabecera + hueco * 2 + Tema.px(2) + cuerpo:getHeight() + hueco * 2 + altoBoton
    -- Ancho: el de diseño o lo que pidan los textos (sin pisarse con el contador).
    local aviso = 'Combate en pausa: nadie dispara ni avanza'
    local cabecera = math.max(titulo:getWidth('PREPARACIÓN'), etiqueta:getWidth(aviso))
        + Tema.px(24)
        + grande:getWidth('0:00')
    local anchoColumna = math.floor(cuerpo:getHeight() * 0.42) + Tema.px(8) + cuerpo:getWidth('Rival: organizando')
    local pide = math.max(cabecera, anchoColumna * 2 + Tema.px(24)) + margen * 2
    local _, _, anchoLibre = Acero.contenido('panel_acero', 0, 0, 1000, 10)
    local ancho = math.max(Tema.px(DespliegueVista.ancho), pide + (1000 - anchoLibre))
    ancho = math.min(ancho, w - Tema.px(32))
    local _, _, _, altoLibre = Acero.contenido('panel_acero', 0, 0, ancho, 1000)
    local alto = altoContenido + margen * 2 + (1000 - altoLibre)
    local x = math.floor((w - ancho) / 2)
    local y = math.floor(h - alto - Tema.px(28))
    self.panel = { x = x, y = y, w = ancho, h = alto }
    g.push('all')
    Vida.entrar('despliegue', 0, Tema.px(24))
    local cx, cy, cw = Acero.panel(x, y, ancho, alto)
    cx = cx + margen
    cw = cw - margen * 2
    cy = cy + margen
    -- Título, aviso y contador.
    g.setFont(titulo)
    Tema.color('textoHud')
    g.print('PREPARACIÓN', cx, cy)
    g.setFont(etiqueta)
    Tema.color('textoHudTenue')
    g.print(aviso, cx, cy + titulo:getHeight())
    local segundos = d:segundosRestantes()
    local reloj = string.format('%d:%02d', math.floor(segundos / 60), segundos % 60)
    g.setFont(grande)
    Tema.color(segundos <= 10 and 'rojoTexto' or 'amarillo')
    g.print(reloj, cx + cw - grande:getWidth(reloj), cy + math.floor((altoCabecera - grande:getHeight()) / 2))
    local filaY = cy + altoCabecera + hueco
    Acero.separador(cx, filaY, cw)
    filaY = filaY + Tema.px(2) + hueco
    -- Estado de cada bando: su color, quién es y si está listo.
    g.setFont(cuerpo)
    local rival = d.propio == 1 and 2 or 1
    local columnas = { { d.propio, 'Tú' }, { rival, 'Rival' } }
    for k, columna in ipairs(columnas) do
        local indice = columna[1]
        local px = cx + (k - 1) * cw / 2
        local color = self.colores[indice]
        local lado = math.floor(cuerpo:getHeight() * 0.42)
        g.setColor(color[1], color[2], color[3], 1)
        g.rectangle('fill', px, filaY + math.floor((cuerpo:getHeight() - lado) / 2), lado, lado)
        local texto, nombreColor = estadoBando(d.listos[indice])
        local nombre = columna[2] .. ': '
        local tx = px + lado + Tema.px(8)
        Tema.color('textoHud')
        g.print(nombre, tx, filaY)
        Tema.color(nombreColor)
        g.print(texto, tx + cuerpo:getWidth(nombre), filaY)
    end
    -- Botón «Listo».
    local anchoBoton = math.min(cw, Tema.px(260))
    local by = filaY + cuerpo:getHeight() + hueco * 2
    local bx = math.floor(x + (ancho - anchoBoton) / 2)
    local yaListo = d.listos[d.propio]
    local boton = {
        texto = yaListo and 'Esperando al rival' or 'Listo',
        tipo = 'dorado',
        activo = not yaListo,
    }
    Acero.boton(boton, bx, by, anchoBoton, altoBoton)
    if not yaListo then
        self.botonListo = { x = bx, y = by, w = anchoBoton, h = altoBoton }
    end
    Vida.fin()
    g.pop()
end

--- ¿Cae (x, y) de la pantalla sobre el botón «Listo»?
function DespliegueVista:sobreListo(x, y)
    local b = self.botonListo
    return b ~= nil and Tema.dentro(x, y, b.x, b.y, b.w, b.h)
end

return DespliegueVista
