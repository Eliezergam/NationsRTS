-- Lo que se mueve y brilla del avión de carga (tools/blender/avion_carga*.py):
--   avion:setCompuertas(puertas, rampa)  0 cerradas, 1 abiertas; van hacia
--       ese valor a su ritmo (primero los pétalos, la rampa cuando ya no
--       choca con ellos; al cerrar, al revés).
--   avion:setRodar(velocidad)  m/s: las 20 ruedas giran a esa velocidad.
-- Los 8 ventiladores de las bocas de los motores giran siempre (ralentí).
-- En la cara, un lienzo vivo (lo que se ve tras el vidrio ahumado): la
-- consola verde con sus dos radares barriendo, ecos que se encienden al
-- pasar el barrido y columnas de código que corren. Las luces de colores
-- de dentro parpadean por grupos; las de posición fijas; el destello, a
-- golpes.
--
-- Lo de ahora, en avion.datos.avionCarga: puertas, rampa (0-1), quiere*,
-- giroRueda (rad).

local dream = require('lib.3DreamEngine')
local Nucleo = require('robots.nucleo')
local Robot = Nucleo.Robot

local AvionCarga = {}

AvionCarga.puertaAbierta = math.rad(90)
AvionCarga.rampaAbierta = math.rad(-26.55) -- apoyada en la pista (medido en Blender)
AvionCarga.tiempoPuertas = 4 -- s de cerradas a abiertas
AvionCarga.tiempoRampa = 3.5
AvionCarga.rampaDesde = 0.55 -- abertura de los pétalos con la que la rampa ya no los toca
AvionCarga.radioRueda = 0.8 -- m
AvionCarga.ralenti = 7 -- rad/s de los ventiladores de los motores
AvionCarga.hud = 'assets/batalla/robots/avionCarga_hud.png'
AvionCarga.placa = 'assets/batalla/robots/avionCarga_placa.png'
AvionCarga.brilloPantalla = 3.5
AvionCarga.ritmoBarrido = 1.3 -- rad/s
-- Materiales de la casa que en el avión van más mates: rugosidad, metal.
AvionCarga.mate = {
    robotNegro = { 0.72, 0.2 }, robotNegroMate = { 0.85, 0.1 }, robotArticulacion = { 0.7, 0.3 },
    robotPlata = { 0.45, 0.8 }, robotAcero = { 0.5, 0.8 }, robotBlanco = { 0.6, 0.0 },
    pesadoNegro = { 0.72, 0.2 }, pesadoAcero = { 0.5, 0.8 }, pesadoPlata = { 0.45, 0.8 }, pesadoBlanco = { 0.6, 0.0 },
}

-- Lienzo de la cara (las coordenadas de avionCarga_hud.png a la mitad):
-- radares, columnas de código (zonas que el lienzo pinta él mismo y tapa
-- de la imagen quieta) y el ritmo al que corre el código.
local ANCHO, ALTO = 1024, 256
local RADARES = { { 410, 120.5, 0.0 }, { 614, 120.5, 2.1 } }
local RADIO = 75
local CODIGO = { { 0, 340 }, { 700, 1024 } }

local VERDE = { 0.25, 1.0, 0.35 }
local CLARO = { 0.7, 1.0, 0.7 }

local imagenHud, imagenPlaca

local function cargarImagenes()
    if not imagenHud then
        imagenHud = love.graphics.newImage(AvionCarga.hud)
        imagenHud:setFilter('linear', 'linear')
        imagenPlaca = love.graphics.newImage(AvionCarga.placa, { mipmaps = true })
    end
end

function AvionCarga.prerequisitos(self)
    return self:getTienePieza('rampa') and self:getTienePieza('pantallaCodigo')
end

-- El modelo de cerca y sus copias de lejos.
local function copias(self)
    local lista = { self.objeto }
    for _, c in pairs(self.lods or {}) do
        lista[#lista + 1] = c
    end
    return lista
end

local function materialesDe(self, nombrePieza, material)
    for _, modelo in ipairs(copias(self)) do
        local o = modelo.objects[nombrePieza]
        for _, malla in pairs(o and o.meshes or {}) do
            malla:setMaterial(material)
        end
    end
end

local function emisivo(nombre, r, g, b, fuerza)
    local m = dream:newMaterial(nombre)
    m:setColor(r * 0.2, g * 0.2, b * 0.2, 1)
    m:setEmission(r, g, b)
    m:setEmissionFactor(fuerza, fuerza, fuerza)
    m:setRoughness(0.3)
    m:setMetallic(0)
    m:setCullMode('none')
    return m
end

function AvionCarga.onLoad(self)
    cargarImagenes()
    local d = self.datos.avionCarga
    d.puertas, d.rampa, d.quierePuertas, d.quiereRampa = 0, 0, 0, 0
    d.velocidad, d.giroRueda, d.reloj = 0, 0, 0
    d.puertaI, d.puertaD, d.piezaRampa = self:getPieza('puertaI'), self:getPieza('puertaD'), self:getPieza('rampa')
    d.ruedas, d.ventiladores, d.giroVentilador = {}, {}, 0
    for _, nombre in ipairs(self:getNombresPiezas()) do
        if nombre:match('^rueda') then
            d.ruedas[#d.ruedas + 1] = self:getPieza(nombre)
        elseif nombre:match('^ventilador') then
            d.ventiladores[#d.ventiladores + 1] = self:getPieza(nombre)
        end
    end
    -- Chapa mate: el negro semibrillante de los robots, en superficies tan
    -- grandes, refleja el cielo entero y se ve cromado (foto del 20-nov).
    -- Copias propias del avión, sin tocar las de los robots.
    local mates = {}
    for _, modelo in ipairs(copias(self)) do
    for _, o in pairs(modelo.objects) do
        for _, malla in pairs(o.meshes or {}) do
            local m = malla.material
            local nombre = m and m.name or ''
            if AvionCarga.mate[nombre] then
                if not mates[nombre] then
                    -- Nueva, con el color, la textura de color y la de
                    -- relieve de la casa; rugosidad y metal sin el mapa
                    -- (ese mapa solo deja bajarlos).
                    local copia = dream:newMaterial(nombre .. 'Avion')
                    local c = m.color or { 1, 1, 1, 1 }
                    copia:setColor(c[1], c[2], c[3], c[4] or 1)
                    if m.albedoTexture then
                        copia:setAlbedoTexture(m.albedoTexture)
                    end
                    if m.normalTexture then
                        copia:setNormalTexture(m.normalTexture)
                    end
                    copia:setRoughness(AvionCarga.mate[nombre][1])
                    copia:setMetallic(AvionCarga.mate[nombre][2])
                    mates[nombre] = copia
                end
                malla:setMaterial(mates[nombre])
            end
        end
    end
    end
    -- La cara: lienzo vivo como albedo (su alfa) y como brillo.
    d.lienzo = love.graphics.newCanvas(ANCHO, ALTO)
    d.lienzo:setFilter('linear', 'linear')
    local pantalla = dream:newMaterial('avionPantallaViva')
    pantalla:setColor(1, 1, 1, 1)
    pantalla:setAlbedoTexture(d.lienzo)
    pantalla:setEmissionTexture(d.lienzo)
    pantalla:setEmissionFactor(AvionCarga.brilloPantalla, AvionCarga.brilloPantalla, AvionCarga.brilloPantalla)
    pantalla:setRoughness(0.4)
    pantalla:setMetallic(0)
    -- Recorte (pasada sólida), no alfa: dos transparentes juntas (ella y el
    -- vidrio) el motor las ordenaba mal y la pantalla no salía.
    pantalla:setCutout()
    pantalla:setAlphaCutoff(0.08)
    -- A doble cara: sus caras miran hacia dentro (en Blender se veían igual).
    pantalla:setCullMode('none')
    pantalla:throwsShadow(false)
    materialesDe(self, 'pantallaCodigo', pantalla)
    -- El fondo: la placa de circuitos.
    local placa = dream:newMaterial('avionPlaca')
    placa:setColor(1, 1, 1, 1)
    placa:setAlbedoTexture(imagenPlaca)
    placa:setRoughness(0.45)
    placa:setMetallic(0.3)
    placa:setCullMode('none')
    materialesDe(self, 'placaCircuitos', placa)
    -- El vidrio ahumado: deja ver la consola.
    local vidrio = dream:newMaterial('avionVidrio')
    vidrio:setColor(0.05, 0.06, 0.07, 0.3)
    vidrio:setRoughness(0.04)
    vidrio:setMetallic(0)
    vidrio:setIOR(1.0)
    vidrio:setAlpha()
    vidrio:throwsShadow(false)
    materialesDe(self, 'vidrioCabina', vidrio)
    -- Luces: un material por grupo, para parpadear.
    d.luces = {}
    local azar = love.math.newRandomGenerator(77)
    for _, l in ipairs({
        { 'lucesVerde', 0.2, 1, 0.3 }, { 'lucesAmbar', 1, 0.6, 0.1 }, { 'lucesRoja', 1, 0.12, 0.1 },
        { 'lucesAzul', 0.2, 0.45, 1 }, { 'lucesCian', 0.1, 0.9, 1 }, { 'lucesMagenta', 1, 0.2, 0.9 },
    }) do
        local m = emisivo('avion_' .. l[1], l[2], l[3], l[4], 8)
        materialesDe(self, l[1], m)
        d.luces[#d.luces + 1] = { material = m, ritmo = 0.8 + azar:random() * 3, fase = azar:random() * 6 }
    end
    materialesDe(self, 'luzPosicionRoja', emisivo('avionPosRoja', 1, 0.1, 0.08, 12))
    materialesDe(self, 'luzPosicionVerde', emisivo('avionPosVerde', 0.1, 1, 0.3, 12))
    d.destello = emisivo('avionDestello', 1, 1, 1, 0)
    materialesDe(self, 'luzDestello', d.destello)
    -- Ecos de cada radar (ángulo, radio) y columnas de código.
    d.ecos = {}
    for k = 1, #RADARES do
        d.ecos[k] = {}
        for e = 1, 7 do
            d.ecos[k][e] = { azar:random() * 2 * math.pi, (0.2 + azar:random() * 0.7) * RADIO }
        end
    end
    d.columnas = {}
    for _, zona in ipairs(CODIGO) do
        for x = zona[1] + 20, zona[2] - 60, 75 do
            local filas = {}
            for f = 1, 18 do
                filas[f] = { azar:random(3, 12), azar:random() }
            end
            d.columnas[#d.columnas + 1] = { x = x, filas = filas, ritmo = 14 + azar:random() * 30, desplazamiento = azar:random() * 8 }
        end
    end
end

--- 0 cerradas, 1 abiertas.
function Robot:setCompuertas(puertas, rampa)
    local d = self.datos.avionCarga
    d.quierePuertas = math.max(0, math.min(1, puertas or 0))
    d.quiereRampa = math.max(0, math.min(1, rampa or puertas or 0))
end

--- m/s sobre la pista.
function Robot:setRodar(velocidad)
    self.datos.avionCarga.velocidad = velocidad or 0
end

local function acercar(a, b, paso)
    if a < b then
        return math.min(b, a + paso)
    end
    return math.max(b, a - paso)
end

local function dibujarCara(d)
    local g = love.graphics
    g.push('all')
    g.setCanvas({ d.lienzo, stencil = true })
    g.clear(0, 0, 0, 0)
    g.origin()
    -- La imagen quieta (rejilla, trazas, barras) sin lo que se pinta vivo.
    g.stencil(function()
        for _, r in ipairs(RADARES) do
            g.circle('fill', r[1], r[2], RADIO + 14)
        end
        for _, z in ipairs(CODIGO) do
            g.rectangle('fill', z[1], 0, z[2] - z[1], ALTO)
        end
    end, 'replace', 1)
    g.setStencilTest('equal', 0)
    g.setColor(1, 1, 1, 1)
    g.draw(imagenHud, 0, 0, 0, ANCHO / imagenHud:getWidth(), ALTO / imagenHud:getHeight())
    g.setStencilTest()
    -- Radares.
    g.setLineWidth(1)
    for k, r in ipairs(RADARES) do
        local cx, cy = r[1], r[2]
        local barrido = r[3] + d.reloj * AvionCarga.ritmoBarrido
        -- Estela: cuña de 70° detrás de la línea que se apaga.
        for paso = 0, 13 do
            local a0 = barrido - paso * math.rad(5)
            g.setColor(VERDE[1], VERDE[2], VERDE[3], 0.5 * (1 - paso / 14) ^ 1.6)
            g.arc('fill', cx, cy, RADIO, a0 - math.rad(5), a0)
        end
        for anillo = 1, 3 do
            g.setColor(VERDE[1], VERDE[2], VERDE[3], anillo == 3 and 1 or 0.6)
            g.setLineWidth(anillo == 3 and 1.5 or 1)
            g.circle('line', cx, cy, RADIO * anillo / 3, 64)
        end
        g.setLineWidth(1)
        for marca = 0, 35 do
            local a = marca / 36 * 2 * math.pi
            local l = marca % 3 == 0 and 11 or 6
            g.line(cx + math.cos(a) * RADIO, cy + math.sin(a) * RADIO, cx + math.cos(a) * (RADIO + l), cy + math.sin(a) * (RADIO + l))
        end
        g.setColor(VERDE[1], VERDE[2], VERDE[3], 0.45)
        g.line(cx - RADIO, cy, cx + RADIO, cy)
        g.line(cx, cy - RADIO, cx, cy + RADIO)
        -- Ecos: se encienden al pasar el barrido y se apagan despacio.
        for _, e in ipairs(d.ecos[k]) do
            local desde = (barrido - e[1]) % (2 * math.pi)
            local vivo = math.max(0, 1 - desde / 3.5)
            local px, py = cx + math.cos(e[1]) * e[2], cy + math.sin(e[1]) * e[2]
            g.setColor(CLARO[1], CLARO[2], CLARO[3], 0.3 + 0.7 * vivo)
            g.circle('fill', px, py, 1.5 + 1.5 * vivo)
            if vivo > 0.6 then
                g.setColor(VERDE[1], VERDE[2], VERDE[3], vivo)
                g.circle('line', px, py, 5)
            end
        end
        g.setColor(CLARO)
        g.setLineWidth(1.5)
        g.line(cx, cy, cx + math.cos(barrido) * RADIO, cy + math.sin(barrido) * RADIO)
        g.circle('fill', cx, cy, 2)
    end
    -- Código que corre hacia arriba.
    g.setLineWidth(1)
    for _, c in ipairs(d.columnas) do
        local corrido = d.reloj * c.ritmo + c.desplazamiento * 8
        local primera = math.floor(corrido / 8)
        local fino = corrido % 8
        for f = 0, 30 do
            local fila = c.filas[(primera + f) % #c.filas + 1]
            local y = ALTO - 8 - f * 8 + fino
            if y > 4 then
                local x = c.x
                local azar = fila[2]
                for t = 1, fila[1] do
                    local largo = 2 + math.floor((azar * 97 + t * 13.7) % 4)
                    local brillo = ((azar * 31 + t) % 7 < 1) and CLARO or VERDE
                    g.setColor(brillo[1], brillo[2], brillo[3], 1)
                    g.rectangle('fill', x, y, largo, 1.5)
                    x = x + largo + 2
                end
            end
        end
    end
    g.pop()
end

function AvionCarga.onUpdate(self, dt)
    local d = self.datos.avionCarga
    d.reloj = d.reloj + dt
    -- Pétalos y rampa, sin chocar: la rampa espera a los pétalos al abrir,
    -- y los pétalos a la rampa al cerrar.
    local pasoP, pasoR = dt / AvionCarga.tiempoPuertas, dt / AvionCarga.tiempoRampa
    if d.quiereRampa > 0 and d.puertas < AvionCarga.rampaDesde then
        d.puertas = acercar(d.puertas, d.quierePuertas, pasoP)
    elseif d.quierePuertas < AvionCarga.rampaDesde and d.rampa > 0 then
        d.rampa = acercar(d.rampa, 0, pasoR)
    else
        d.puertas = acercar(d.puertas, d.quierePuertas, pasoP)
        d.rampa = acercar(d.rampa, d.quiereRampa, pasoR)
    end
    local suave = function(t)
        return t * t * (3 - 2 * t)
    end
    d.puertaI:setGiro('z', -AvionCarga.puertaAbierta * suave(d.puertas))
    d.puertaD:setGiro('z', AvionCarga.puertaAbierta * suave(d.puertas))
    d.piezaRampa:setGiro('y', AvionCarga.rampaAbierta * suave(d.rampa))
    -- Ruedas.
    d.giroRueda = d.giroRueda + d.velocidad / AvionCarga.radioRueda * dt
    for _, rueda in ipairs(d.ruedas) do
        rueda:setGiro('y', d.giroRueda)
    end
    -- Ventiladores de los motores: al ralentí, siempre girando.
    d.giroVentilador = (d.giroVentilador + AvionCarga.ralenti * dt) % (2 * math.pi)
    for _, v in ipairs(d.ventiladores) do
        v:setGiro('x', d.giroVentilador)
    end
    -- Luces de dentro (parpadeo suave por grupos) y destello (dos golpes cada 1,5 s).
    for _, l in ipairs(d.luces) do
        local f = 4 + 6 * (0.5 + 0.5 * math.sin(d.reloj * l.ritmo * 2 + l.fase)) ^ 3
        l.material:setEmissionFactor(f, f, f)
    end
    local t = d.reloj % 1.5
    local destello = (t < 0.06 or (t > 0.2 and t < 0.26)) and 30 or 0
    d.destello:setEmissionFactor(destello, destello, destello)
    -- La cara, a 30 cuadros por segundo.
    d.cara = (d.cara or 0) + dt
    if d.cara >= 1 / 30 then
        d.cara = 0
        dibujarCara(d)
    end
end

return AvionCarga
