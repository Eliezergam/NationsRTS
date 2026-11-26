-- Barra superior (diseno/interfaz-militar.md, §5.1): a la izquierda la chapa
-- de la nación (escudo, nombre, poder y nivel), en el centro los cuatro
-- recursos (metal, petróleo, comida y dinero) y a la derecha el día con la
-- pausa y las cuatro velocidades. Sustituye al travesaño del «Estandarte».
--
-- Solo lee la simulación (`almacenDe`, `reservas`, `fuerza`, `nivelCapital`).
-- Un clic en un botón hace lo mismo que su tecla: `pulsar` devuelve la tecla
-- y main.lua la aplica.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Vida = require('interfaz.vida')
local Estandartes = require('mundo.estandartes')
local Simulacion = require('mundo.simulacion')

local BarraSuperior = {}
BarraSuperior.__index = BarraSuperior

local ALTO = 74
-- Cada cuánto se vuelven a pedir a la simulación los números que cuestan
-- (poder y reservas): dos veces por segundo, o al cambiar el día.
local REFRESCO = 0.5

local NOMBRE_RECURSO = { metal = 'Metal', petroleo = 'Petróleo', comida = 'Comida', dinero = 'Dinero' }
local ESTADO_TEXTO = { justo = 'JUSTO', escasez = 'ESCASEZ', crisis = 'CRISIS' }

function BarraSuperior.nuevo()
    local self = setmetatable({}, BarraSuperior)
    self.zonas = {} -- botones de este cuadro: { x, y, w, h, tecla }
    self.ayuda = nil
    self.cache = nil -- { tiempo, nacion, fuerza, reservas }
    return self
end

--- Alto que ocupa, para colgar el resto debajo.
function BarraSuperior.alto()
    return Tema.px(ALTO)
end

--- ¿La pantalla es la pequeña (720p)? Los recursos se estrechan.
local function esCompacta()
    return Tema.compacta()
end

--- Poder y reservas de la nación, refrescados cada `REFRESCO` segundos.
function BarraSuperior:datos(sim, nid)
    local ahora = love.timer.getTime()
    local c = self.cache
    if not c or c.nacion ~= nid or c.sim ~= sim or c.dia ~= sim.estado.dia or ahora - c.tiempo > REFRESCO then
        c = {
            tiempo = ahora,
            dia = sim.estado.dia,
            sim = sim,
            nacion = nid,
            fuerza = sim:fuerza(nid),
            reservas = sim:reservas(nid),
        }
        self.cache = c
    end
    return c
end

--- Cuántas naciones viven, cuántas guerras hay abiertas y cuántos altos el fuego.
local function estadoDelMundo(sim)
    local vivas = #sim:vivas()
    local guerras, calmas = 0, 0
    for _, gid in ipairs(Simulacion.ordenadas(sim.estado.guerras)) do
        if sim.estado.guerras[gid].fase == 'calma' then
            calmas = calmas + 1
        else
            guerras = guerras + 1
        end
    end
    return vivas, guerras, calmas
end

--- Frase de la ayuda de un recurso: «Metal 351 de 500 · entra 12 al día · le
-- dura 29 días».
local function ayudaRecurso(nombre, cantidad, tope, r, afuera)
    local partes = { string.format('%s %s de %s', nombre, Tema.numero(cantidad), Tema.numero(tope)) }
    if r then
        if r.entra and r.entra > 0.05 then
            partes[#partes + 1] = string.format('entra %s al día', (string.format('%.1f', r.entra):gsub('%.', ',')))
        end
        if r.gasta and r.gasta > 0.05 then
            partes[#partes + 1] = string.format('gasta %s al día', (string.format('%.1f', r.gasta):gsub('%.', ',')))
        end
        if r.dias and r.dias < math.huge and r.estado ~= 'holgado' then
            partes[#partes + 1] = string.format('le dura %d %s', math.floor(r.dias), r.dias < 2 and 'día' or 'días')
        end
        if r.estado == 'crisis' then
            partes[#partes + 1] = 'se ha acabado'
        end
    end
    if afuera and afuera >= 0.5 then
        partes[#partes + 1] = string.format('%s afuera, sin almacén', Tema.numero(afuera))
    end
    return table.concat(partes, ' · ')
end

--- Una casilla de recurso: pastilla oliva inclinada con el icono de color,
-- la cifra grande (blanca con contorno; `amarilloDinero` la del dinero), una
-- mini barra y, si no está holgado, el estado escrito. `d` = { tipo, cantidad,
-- tope, estado, afuera, r }. Lo que queda afuera del almacén va en la ayuda.
function BarraSuperior:dibujarRecurso(d, x, y, w, h)
    local g = love.graphics
    Acero.nueve('pastilla_recurso', 'normal', x, y, w, h)
    local lado = Tema.px(50)
    local relleno = Tema.px(16)
    Tema.iconoRecurso(d.tipo, x + relleno, y + (h - lado) / 2 - Tema.px(3), lado)
    local fuente = Acero.fuente('cifra', 36)
    local tx = x + relleno + lado + Tema.px(6)
    local color = d.tipo == 'dinero' and 'amarilloDinero' or 'textoHud'
    if d.estado == 'justo' then
        color = 'amarillo'
    elseif d.estado == 'escasez' or d.estado == 'crisis' then
        color = 'rojoTexto'
    end
    -- La cifra cuenta hacia su valor en vez de saltar (interfaz/vida.lua).
    local cifra = Tema.numero(Vida.numero('recurso:' .. d.tipo, d.estado == 'crisis' and 0 or (d.cifra or d.cantidad)))
    Acero.textoContorno(fuente, cifra, tx, y + Tema.px(-1), color)
    local derecha = x + w - Tema.px(22)
    local etiqueta = Acero.fuente('etiqueta')
    local estado = ESTADO_TEXTO[d.estado]
    if estado then
        Acero.textoContorno(
            etiqueta,
            estado,
            derecha - etiqueta:getWidth(estado),
            y + Tema.px(4),
            d.estado == 'justo' and 'amarillo' or 'rojoTexto'
        )
    end
    -- Mini barra de 4 px bajo la cifra.
    local by = y + h - Tema.px(11)
    local bw = math.min(derecha - tx, Tema.px(90))
    if bw > Tema.px(16) then
        local bh = Tema.px(4)
        if d.estado == 'crisis' then
            Tema.rayado(tx, by, bw, bh, 'rojoOscuro', 'rojo', Tema.px(4))
        else
            Tema.color('olivaNegro')
            g.rectangle('fill', tx, by, bw, bh)
            local parte = math.min(1, (d.cantidad or 0) / math.max(1, d.tope or 1))
            Tema.color(d.tipo == 'dinero' and 'amarilloDinero' or Tema.rellenoEstado[d.estado] or Tema.colores.verde)
            g.rectangle('fill', tx, by, math.floor(bw * parte), bh)
        end
    end
    local mx, my = love.mouse.getPosition()
    if Tema.dentro(mx, my, x, y, w, h) then
        self.ayuda = d.ayuda
    end
end

--- Chapa de la nación: el anillo del kit con el escudo dentro y, al lado,
-- el nombre, el poder y el nivel de la capital sobre un rótulo oliva. Un clic
-- abre el perfil.
function BarraSuperior:dibujarChapa(ctx, x, y, w, h)
    local sim = ctx.sim
    local nacion = sim:nacion(ctx.nacion)
    local anillo = Tema.px(64)
    if not nacion then
        local fuente = Acero.fuente('titulo', 22)
        Acero.rotulo(x, y + Tema.px(6), w, h - Tema.px(12))
        Acero.textoContorno(fuente, 'Sin nación', x + Tema.px(16), y + (h - fuente:getHeight()) / 2, 'textoHudTenue')
        return
    end
    -- Con el texto más grande que los paneles (Tema.TEXTO), la chapa crece
    -- lo justo para que el nombre y la fila de poder no se pisen.
    local nombre = Acero.fuente('boton', 21)
    local cuerpo = Acero.fuente('cuerpo', 17)
    h = math.max(h, nombre:getHeight() + cuerpo:getHeight() + Tema.px(18))
    w = math.max(w, anillo + Tema.px(18) + nombre:getWidth(nacion.nombre))
    -- Rótulo detrás del texto, para leerse sobre cualquier terreno.
    local rx = x + anillo * 0.6
    Acero.rotulo(rx, y + Tema.px(8), w - anillo * 0.6, h - Tema.px(10))
    -- Escudo (el hueco del anillo mide 54 de 80) y encima el anillo.
    local cx, cy = x + anillo / 2, y + h / 2
    local hoja = 4
    Estandartes.dibujarEscudo(Estandartes.escudoDe(ctx.semilla, nacion.id), cx, cy, hoja, Tema.px(34) / (18 * hoja))
    Acero.pieza('chapa_nacion', 'normal', cx - anillo / 2, cy - anillo / 2, anillo, anillo)
    local tx = x + anillo + Tema.px(6)
    local libre = x + w - Tema.px(12) - tx
    Acero.textoContorno(nombre, Tema.cortar(nombre, nacion.nombre, libre), tx, y + Tema.px(9), 'textoHud')
    local datos = self:datos(sim, nacion.id)
    local fila = y + h - cuerpo:getHeight() - Tema.px(8)
    local poder = Tema.numero(datos.fuerza)
    Acero.iconoColor('poder', tx, fila, cuerpo:getHeight())
    local cursor = tx + cuerpo:getHeight() + Tema.px(4)
    Acero.textoContorno(cuerpo, poder, cursor, fila, 'amarillo')
    cursor = cursor + cuerpo:getWidth(poder) + Tema.px(12)
    local nivel = 'Nv. ' .. sim:nivelCapital(nacion.id)
    if cursor + cuerpo:getWidth(nivel) <= x + w - Tema.px(10) then
        Acero.textoContorno(cuerpo, nivel, cursor, fila, 'textoHud')
    end
    self.zonas[#self.zonas + 1] = { x = x, y = y, w = w, h = h, tecla = 'perfil' }
    local mx, my = love.mouse.getPosition()
    if Tema.dentro(mx, my, x, y, w, h) then
        self.ayuda = string.format(
            '%s · poder %s · capital de nivel %d · %d %s (abrir el perfil)',
            nacion.nombre,
            Tema.numero(datos.fuerza),
            sim:nivelCapital(nacion.id),
            #sim:ciudadesDe(nacion.id),
            #sim:ciudadesDe(nacion.id) == 1 and 'ciudad' or 'ciudades'
        )
    end
end

--- Día y velocidades, de derecha a izquierda desde `derecha`. Devuelve el x
-- donde empieza el bloque.
function BarraSuperior:dibujarTiempo(ctx, derecha, y, h)
    local g = love.graphics
    local mx, my = love.mouse.getPosition()
    local estrecha = love.graphics.getWidth() / Tema.escala() < 1400
    local ancho, alto = Tema.px(estrecha and 34 or 40), Tema.px(36)
    local separa = Tema.px(4)
    local by = y + (h - alto) / 2
    local fuente = Acero.fuente('boton', 20)
    local cursor = derecha
    for k = #ctx.velocidades, 0, -1 do
        local activo
        if k == 0 then
            activo = ctx.pausa
        else
            activo = not ctx.pausa and math.abs(ctx.velocidad - ctx.velocidades[k]) < 1e-9
        end
        cursor = cursor - ancho
        local encima = Tema.dentro(mx, my, cursor, by, ancho, alto)
        local boton = { texto = k == 0 and 'II' or (k .. 'x'), tipo = activo and 'dorado' or 'oscuro' }
        Acero.boton(boton, cursor, by, ancho, alto, true)
        if encima then
            if k == 0 then
                self.ayuda = 'Pausa (espacio)'
            else
                local segundos = 1 / ctx.velocidades[k]
                self.ayuda =
                    string.format('Velocidad %d: un día cada %d s (tecla %d)', k, math.floor(segundos + 0.5), k)
            end
        end
        self.zonas[#self.zonas + 1] =
            { x = cursor, y = by, w = ancho, h = alto, tecla = k == 0 and 'space' or tostring(k) }
        cursor = cursor - separa
    end
    cursor = cursor - Tema.px(8)
    local dia = Tema.numero(ctx.sim.estado.dia)
    -- El año del juego (diseno/poblacion.md F1: 10 días).
    local anio = Tema.numero(Simulacion.anioDelJuego(math.max(1, ctx.sim.estado.dia)))
    local etiqueta = Acero.fuente('cuerpo', 18)
    local cifra = Acero.fuente('cifra', 24)
    local derechaDia = cursor
    -- En pantalla estrecha el año va debajo del día, en pequeño, para no
    -- empujar los recursos contra la chapa; en ancha, a la izquierda del día.
    local pequena = Acero.fuente('cuerpo', 15)
    local centro = estrecha and y + (h - cifra:getHeight() - pequena:getHeight()) / 2 or y + (h - cifra:getHeight()) / 2
    local anchoDia = cifra:getWidth(dia)
    cursor = cursor - anchoDia
    Acero.textoContorno(cifra, dia, cursor, centro, 'textoHud')
    cursor = cursor - etiqueta:getWidth('Día') - Tema.px(6)
    local desfase = (cifra:getHeight() - etiqueta:getHeight()) / 2 + Tema.px(1)
    Acero.textoContorno(etiqueta, 'Día', cursor, centro + desfase, 'textoHudTenue')
    if estrecha then
        local texto = 'Año ' .. anio
        local ax = derechaDia - pequena:getWidth(texto)
        Acero.textoContorno(pequena, texto, ax, centro + cifra:getHeight() - Tema.px(2), 'textoHudTenue')
        return math.min(cursor, ax)
    end
    cursor = cursor - Tema.px(14) - cifra:getWidth(anio)
    Acero.textoContorno(cifra, anio, cursor, centro, 'textoHud')
    cursor = cursor - etiqueta:getWidth('Año') - Tema.px(6)
    Acero.textoContorno(etiqueta, 'Año', cursor, centro + desfase, 'textoHudTenue')
    return cursor
end

--- Dibuja la barra. `ctx` = { sim, semilla, pausa, velocidad, velocidades,
-- nacion (id de la nación que se mira o se juega) }.
function BarraSuperior:dibujar(ctx)
    local g = love.graphics
    local w = g.getWidth()
    local alto = Tema.px(ALTO)
    self.zonas = {}
    self.ayuda = nil

    -- Sin franja de fondo: las pastillas flotan sobre el mapa (como en el original).
    local margen = Tema.px(16)
    local compacta = esCompacta()
    local estrecha = w / Tema.escala() < 1400
    local chapaAncho = Tema.px(estrecha and 228 or (compacta and 270 or 300))
    local chapaAlto = Tema.px(70)
    local inicioTiempo = self:dibujarTiempo(ctx, w - margen, 0, alto - Tema.px(2))
    if ctx.nacion then
        self:dibujarChapa(ctx, Tema.px(8), Tema.px(0), chapaAncho, chapaAlto)
        self:dibujarRecursos(ctx, Tema.px(8) + chapaAncho, inicioTiempo)
    else
        self:dibujarObservador(ctx, Tema.px(8), inicioTiempo)
    end
end

--- Los cuatro recursos, centrados en la pantalla y, si chocan, arrimados al
-- hueco libre entre la chapa (termina en `desde`) y el tiempo (empieza en `hasta`).
function BarraSuperior:dibujarRecursos(ctx, desde, hasta)
    local sim = ctx.sim
    local compacta = esCompacta()
    local w = love.graphics.getWidth()
    local ancho, alto = Tema.px(love.graphics.getWidth() / Tema.escala() < 1400 and 172 or 196), Tema.px(60)
    local separa = Tema.px(8)
    local total = ancho * 4 + separa * 3
    local x = math.floor((w - total) / 2)
    x = math.max(x, desde + Tema.px(12))
    x = math.min(x, hasta - Tema.px(12) - total)
    local y = math.floor((Tema.px(ALTO) - Tema.px(2) - alto) / 2)
    local nid = ctx.nacion
    local almacen = sim:almacenDe(nid)
    if not almacen then
        return
    end
    local datos = self:datos(sim, nid)
    local reservas = {}
    for _, r in ipairs(datos.reservas) do
        reservas[r.tipo] = r
    end
    local lista = {
        { tipo = 'metal', cantidad = almacen.metal, tope = almacen.almacen, afuera = almacen.afuera.metal },
        { tipo = 'petroleo', cantidad = almacen.petroleo, tope = almacen.almacen, afuera = almacen.afuera.petroleo },
        { tipo = 'comida' },
        { tipo = 'dinero', cantidad = almacen.dinero, tope = almacen.boveda, afuera = almacen.afuera.dinero },
    }
    for k, d in ipairs(lista) do
        local r = reservas[d.tipo]
        if d.tipo == 'comida' then
            d.cantidad, d.tope = r and r.cantidad or 0, r and r.tope or 0
        end
        d.estado = r and r.estado or 'holgado'
        d.r = r
        d.ayuda = ayudaRecurso(NOMBRE_RECURSO[d.tipo], d.cantidad, d.tope, r, d.afuera)
        if d.tipo == 'dinero' then
            -- Un solo dinero (diseno/economia.md): la cifra es todo el tesoro
            -- que se puede gastar, lo de la bóveda más lo de afuera.
            d.cifra = d.cantidad + (d.afuera or 0)
            d.ayuda = string.format(
                'Tesoro %s: todo lo de la nación sale de aquí · %s en la bóveda (tope %s)',
                Tema.numero(d.cifra),
                Tema.numero(d.cantidad),
                Tema.numero(d.tope)
            ) .. ((d.afuera or 0) >= 0.5 and string.format(
                ' · %s afuera: se gasta primero y lo saquean',
                Tema.numero(d.afuera)
            ) or '')
        end
        self:dibujarRecurso(d, x + (k - 1) * (ancho + separa), y, ancho, alto)
    end
end

--- Sin jugador: la nación que se mira no existe; se cuenta el estado del mundo.
function BarraSuperior:dibujarObservador(ctx, desde, hasta)
    local g = love.graphics
    local vivas, guerras, calmas = estadoDelMundo(ctx.sim)
    local fuente = Acero.fuente('cifra', 20)
    local etiqueta = Acero.fuente('etiqueta')
    local texto = string.format(
        '%d naciones · %s · %s',
        vivas,
        guerras == 1 and '1 guerra' or (guerras .. ' guerras'),
        calmas == 1 and '1 alto el fuego' or (calmas .. ' altos el fuego')
    )
    local altoBarra = Tema.px(ALTO) - Tema.px(2)
    Acero.rotulo(desde, Tema.px(8), hasta - desde - Tema.px(12), altoBarra - Tema.px(16))
    Acero.textoContorno(etiqueta, 'OBSERVADOR', desde + Tema.px(12), (altoBarra - etiqueta:getHeight()) / 2, 'amarillo')
    local libre = hasta - desde - Tema.px(150)
    Acero.textoContorno(
        fuente,
        Tema.cortar(fuente, texto, libre),
        desde + Tema.px(118),
        (altoBarra - fuente:getHeight()) / 2,
        'textoHud'
    )
end

--- La ayuda del botón o recurso bajo el ratón (se dibuja encima de todo).
function BarraSuperior:dibujarAyuda()
    if self.ayuda then
        local mx, my = love.mouse.getPosition()
        Acero.tooltip(self.ayuda, mx, my)
    end
end

--- ¿El punto cae sobre la barra?
function BarraSuperior:encima(_, y)
    return y <= BarraSuperior.alto()
end

--- Clic: devuelve la tecla del botón pulsado (o nil).
function BarraSuperior:pulsar(x, y)
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            return z.tecla
        end
    end
    return nil
end

return BarraSuperior
