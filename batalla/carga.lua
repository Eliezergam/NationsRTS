-- Pantalla mostrada mientras se construye el campo de batalla. El generador
-- informa por etapas para que una malla detallada no parezca un bloqueo.

local Carga = {}

Carga.ultimoDibujo = 0
Carga.intervalo = 1 / 24

local function puedeDibujar()
    return love.graphics and love.graphics.isActive and love.graphics.isActive()
end

function Carga.iniciar()
    Carga.ultimoDibujo = 0
    Carga.mostrar('Preparando el campo de batalla', 0, true)
end

function Carga.mostrar(etapa, progreso, forzar)
    if not puedeDibujar() then
        return
    end

    local ahora = love.timer.getTime()
    if not forzar and ahora - Carga.ultimoDibujo < Carga.intervalo then
        return
    end

    Carga.ultimoDibujo = ahora
    progreso = math.max(0, math.min(1, progreso or 0))

    local g = love.graphics
    local ancho = g.getWidth()
    local alto = g.getHeight()
    local barraAncho = math.min(620, ancho * 0.62)
    local barraAlto = math.max(10, alto * 0.014)
    local barraX = (ancho - barraAncho) * 0.5
    local barraY = alto * 0.68
    local horizonte = alto * 0.48

    g.push('all')
    g.origin()
    g.clear(0.035, 0.045, 0.055, 1)
    g.setColor(0.12, 0.16, 0.18, 1)
    g.polygon(
        'fill',
        0,
        horizonte,
        ancho * 0.18,
        alto * 0.3,
        ancho * 0.38,
        horizonte,
        ancho * 0.58,
        alto * 0.25,
        ancho * 0.82,
        horizonte,
        ancho,
        alto * 0.34,
        ancho,
        alto,
        0,
        alto
    )
    g.setColor(0.19, 0.24, 0.18, 1)
    g.polygon(
        'fill',
        0,
        alto * 0.58,
        ancho * 0.22,
        alto * 0.44,
        ancho * 0.46,
        alto * 0.61,
        ancho * 0.72,
        alto * 0.42,
        ancho,
        alto * 0.56,
        ancho,
        alto,
        0,
        alto
    )
    g.setColor(0.92, 0.94, 0.9, 1)
    g.printf('GENERANDO CAMPO DE BATALLA', 0, alto * 0.55, ancho, 'center')
    g.setColor(0.68, 0.74, 0.68, 1)
    g.printf(etapa or '', 0, alto * 0.6, ancho, 'center')
    g.setColor(0.08, 0.1, 0.09, 0.92)
    g.rectangle('fill', barraX, barraY, barraAncho, barraAlto, barraAlto * 0.5)
    g.setColor(0.46, 0.66, 0.34, 1)
    g.rectangle('fill', barraX, barraY, barraAncho * progreso, barraAlto, barraAlto * 0.5)
    g.setColor(0.78, 0.84, 0.76, 1)
    g.printf(string.format('%d %%', math.floor(progreso * 100 + 0.5)), 0, barraY + barraAlto + 12, ancho, 'center')
    g.pop()
    g.present()
    love.event.pump()
end

return Carga
