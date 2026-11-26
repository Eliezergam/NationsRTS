-- Galería de componentes de la interfaz «Acero» (diseno/interfaz-militar.md,
-- fase 1): una pantalla con todos los componentes de `interfaz/acero.lua` en
-- todos sus estados, para mirarlos de un vistazo y compararlos con el diseño.
--
--   love NationsRTS 12345 --tam 1920x1080 --galeria --captura 2 galeria.png
--
-- No toca la simulación ni el mundo: solo dibuja.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')

local Galeria = {}

local TIPOS = { 'dorado', 'gris', 'oscuro', 'rojo' }
local ESTADOS = { 'normal', 'resaltado', 'pulsado', 'desactivado' }
local ICONOS = { 'metal', 'petroleo', 'comida', 'dinero', 'soldado', 'tanque', 'lanzacohetes', 'atacar', 'defender' }

--- Título de una zona de la galería.
local function rotulo(texto, x, y)
    local fuente = Acero.fuente('subtitulo', 18)
    love.graphics.setFont(fuente)
    Tema.color('amarillo')
    love.graphics.print(texto, x, y)
    return y + fuente:getHeight() + Tema.px(6)
end

--- Dibuja la galería en toda la pantalla.
function Galeria.dibujar()
    local g = love.graphics
    local w, h = g.getDimensions()
    Tema.actualizar()
    Tema.color('olivaClaro')
    g.rectangle('fill', 0, 0, w, h)
    local x0, y0 = Tema.px(24), Tema.px(20)
    local texto = Acero.fuente('etiqueta')

    -- Botones: cuatro tipos por cuatro estados.
    local y = rotulo('Botones (normal, resaltado, pulsado, desactivado)', x0, y0)
    local bw, bh = Tema.px(150), Tema.px(44)
    for fila, tipo in ipairs(TIPOS) do
        for columna, estado in ipairs(ESTADOS) do
            Acero.boton(
                { texto = fila == 1 and 'Reparar' or 'Botón ' .. tipo, tipo = tipo, estado = estado },
                x0 + (columna - 1) * (bw + Tema.px(8)),
                y + (fila - 1) * (bh + Tema.px(8)),
                bw,
                bh
            )
        end
    end
    -- Con precio y con icono.
    local yp = y + 4 * (bh + Tema.px(8))
    Acero.boton({ texto = 'Reparar +20', tipo = 'dorado', precio = 300 }, x0, yp, Tema.px(200), bh)
    Acero.boton(
        { texto = 'Recolectar', tipo = 'dorado', icono = 'recolectar' },
        x0 + Tema.px(208),
        yp,
        Tema.px(200),
        bh
    )
    Acero.boton({ texto = 'Ir', tipo = 'gris', icono = 'mover' }, x0 + Tema.px(416), yp, Tema.px(120), bh)
    Acero.boton({ texto = '−', tipo = 'oscuro' }, x0 + Tema.px(544), yp, Tema.px(44), bh)
    Acero.boton({ texto = '+', tipo = 'oscuro' }, x0 + Tema.px(596), yp, Tema.px(44), bh)

    -- Botones de icono con insignia y en cada estado.
    local yi = rotulo('Botones de icono', x0, yp + bh + Tema.px(16))
    local nombres = { 'Normal', 'Encendido', 'Con aviso', 'Con 120' }
    for k, nombre in ipairs(nombres) do
        Acero.botonIcono(x0 + (k - 1) * Tema.px(88), yi, Tema.px(72), Tema.px(64), {
            icono = ICONOS[k + 4],
            etiqueta = nombre,
            activo = k == 2,
            cuenta = k == 3 and 3 or (k == 4 and 120 or 0),
        })
    end

    -- Iconos teñidos.
    local yn = rotulo('Iconos del kit teñidos', x0, yi + Tema.px(64) + Tema.px(16))
    local colores = { 'textoHud', 'amarillo', 'rojoTexto', 'verde', 'amarillo', 'caquiPestana' }
    for k, nombre in ipairs(ICONOS) do
        Acero.icono(nombre, x0 + (k - 1) * Tema.px(48), yn, Tema.px(32), colores[(k - 1) % #colores + 1])
    end

    -- Segunda columna.
    local x1 = w / 2 + Tema.px(8)
    local y1 = rotulo('Panel con cabecera', x1, y0)
    local pw, ph = Tema.px(440), Tema.px(220)
    local cx, cy, cw = Acero.panel(x1, y1, pw, ph, { titulo = 'Casa', cerrar = true })
    g.setFont(Acero.fuente('cuerpo'))
    Tema.color('textoHudTenue')
    g.print('Contenido del panel', cx + Tema.px(8), cy + Tema.px(8))
    Acero.barra(cx + Tema.px(8), cy + Tema.px(44), cw - Tema.px(16), Tema.px(14), 0.7, 'energia', 0.1)
    Acero.chip(cx + Tema.px(8), cy + Tema.px(70), Tema.px(176), Tema.px(44))
    Acero.icono('metal', cx + Tema.px(16), cy + Tema.px(76), Tema.px(32), 'textoHud')
    g.setFont(Acero.fuente('cifra'))
    Tema.color('textoHud')
    g.print('1 234', cx + Tema.px(58), cy + Tema.px(80))

    -- Barras.
    local yb = rotulo('Barras', x1 + Tema.px(460), y1 - Tema.px(28))
    local tipos = { 'energia', 'recurso', 'peligro', 'estadistica', 'experiencia' }
    for k, tipo in ipairs(tipos) do
        Acero.barra(x1 + Tema.px(460), yb + (k - 1) * Tema.px(22), Tema.px(300), Tema.px(14), 0.25 + k * 0.15, tipo)
        g.setFont(texto)
        Tema.color('textoHudTenue')
        g.print(tipo, x1 + Tema.px(770), yb + (k - 1) * Tema.px(22) - 1)
    end
    Tema.rayado(x1 + Tema.px(460), yb + 5 * Tema.px(22), Tema.px(300), Tema.px(14), 'rojoOscuro', 'rojo', Tema.px(6))

    -- Pestañas.
    local yt = rotulo('Pestañas', x1, y1 + ph + Tema.px(20))
    local pestanas = { 'Resumen', 'Ejército', 'Nación', 'Relaciones' }
    for k, nombre in ipairs(pestanas) do
        Acero.pestana(x1 + (k - 1) * Tema.px(110), yt, Tema.px(108), Tema.px(40), nombre, k == 1, k == 3)
    end

    -- Filas de lista.
    local yf = rotulo('Filas de lista (normal, resaltada, seleccionada)', x1, yt + Tema.px(56))
    local estados = { 'normal', 'hover', 'seleccionada' }
    for k, estado in ipairs(estados) do
        Acero.fila(x1, yf + (k - 1) * Tema.px(44), Tema.px(440), Tema.px(40), estado)
        g.setFont(Acero.fuente('cuerpo'))
        Tema.color('textoHud')
        g.print('Fila ' .. estado, x1 + Tema.px(16), yf + (k - 1) * Tema.px(44) + Tema.px(8))
    end

    -- Insignias y ayuda.
    local yg = rotulo('Insignias y ayuda', x1, yf + 3 * Tema.px(44) + Tema.px(16))
    Acero.insignia(x1 + Tema.px(14), yg + Tema.px(12), 3)
    Acero.insignia(x1 + Tema.px(60), yg + Tema.px(12), 12)
    Acero.insignia(x1 + Tema.px(110), yg + Tema.px(12), 120)
    Acero.tooltip(
        'Metal 351 de 500 · entra 12 al día · le dura 29 días',
        x1 + Tema.px(130) - Tema.px(14),
        yg - Tema.px(18)
    )
end

return Galeria
