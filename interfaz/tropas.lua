-- Panel de tropas (referencia del dueño: diseno/referencias-warpath/tropas_*.jpg,
-- como en Warpath): barra fija abajo a la derecha, encima de la barra de
-- navegación, con una tarjeta por cada grupo tuyo que está fuera de la ciudad.
--
--   Tarjeta   la imagen de su unidad principal (el render del Arsenal de su
--             modelo o, si no lo hay, el de su tropa), su era en números
--             romanos, la cantidad de esa unidad y un icono de estado (en
--             marcha, recolectando, guarnición, en batalla, regresando...).
--             Dorada si el grupo está elegido en el mapa.
--   Botones   encima de las tarjetas: «Regresar» (flecha curva: los elegidos
--             o, sin elegir nada, todos los del filtro que no pelean),
--             «Seleccionar todos» (✓, dorado si están todos elegidos) y los
--             filtros por tipo: tierra (tanque), agua (ancla, sin barcos
--             todavía) y guarniciones de bandera (bandera).
--   Tocar     una tarjeta elige ese grupo en el mapa, centra la cámara en él
--             y abre encima un radial pequeño con «Regresar» («Retirarse» si
--             está en batalla: pierde la carga).
--   Muchos    las tarjetas se desplazan en horizontal (rueda o ‹ ›).
--   Nada      sin grupos fuera, la barra no se dibuja.
--
-- Regresar es caminar: el grupo vuelve por su ruta (sin teletransporte). La
-- vista no cambia la simulación: `pulsar` devuelve lo que hay que hacer y
-- main.lua lo manda con `Simulacion:ejecutar` (`regresarGrupo`, o `retirar`
-- si la simulación aún no lo tiene).

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Indice = require('assets.ui.indice')
local Simulacion = require('mundo.simulacion')

local PanelTropas = {}
PanelTropas.__index = PanelTropas

PanelTropas.ancho = 100 -- px de diseño de una tarjeta
PanelTropas.alto = 80
PanelTropas.hueco = 6
PanelTropas.boton = 44 -- lado de los botones de arriba
PanelTropas.anchoMaximo = 560 -- px de diseño que ocupan las tarjetas como mucho

-- Filtros por tipo (en orden, a la derecha de los botones).
local FILTROS = {
    { id = 'tierra', icono = 'tanque', ayuda = 'Tropas de tierra que están fuera' },
    { id = 'agua', icono = 'cat_marina', ayuda = 'Tropas de mar: todavía no hay barcos' },
    { id = 'bandera', icono = 'bandera', ayuda = 'Guarniciones de tus banderas' },
}

local ROMANOS = { 'I', 'II', 'III', 'IV' }
local ARTE_TROPA = { soldados = 'soldado' }

function PanelTropas.nuevo()
    local self = setmetatable({}, PanelTropas)
    self.filtro = 'tierra'
    self.inicio = 1 -- primera tarjeta visible (desplazamiento)
    self.radial = nil -- grupo con el radial pequeño abierto
    self.zonas = {}
    self.rect = nil
    self.ayuda = nil
    self.imagenes = {}
    self.recortes = {}
    self.aviso = nil -- { texto, hasta }: lo que pasó con la última orden
    return self
end

--- Aviso corto encima de la barra (unos segundos, reloj de la interfaz).
function PanelTropas:avisar(texto)
    self.aviso = { texto = texto, hasta = love.timer.getTime() + 4 }
end

--- Qué hace el grupo `g`: icono del kit y texto.
function PanelTropas.estado(g)
    if g.batalla then
        return 'batallas', 'En batalla'
    elseif g.mision == 'regreso' then
        return 'retirar', 'Regresando'
    elseif g.mision == 'guarnicion' then
        return 'bandera', g.bandera and 'Guarnición' or 'Va a su guarnición'
    elseif g.mision == 'recolectar' or g.mision == 'apoyo' then
        return 'recolectar', 'Recolectando'
    elseif g.mision == 'construir' then
        return 'construir', 'En obra'
    elseif g.mision == 'abasto' or g.mision == 'entrega' then
        return 'suministros', 'Convoy'
    elseif g.ruta and (g.largo or 0) - (g.recorrido or 0) > 1 then
        return 'mover', 'En marcha'
    end
    return 'defender', 'En posición'
end

--- ¿Acepta el grupo `g` regresar? Lo mismo que mira la simulación
-- (`puedeRegresar`): no los que ya vuelven, las obras, las entregas, los
-- convoyes ni los remolques. Devuelve true, o false y el motivo en texto.
function PanelTropas.puedeRegresar(g)
    if g.remolque then
        return false, 'va remolcado'
    elseif g.mision == 'regreso' then
        return false, 'ya vuelve'
    elseif g.mision == 'construir' then
        return false, 'lleva una obra'
    elseif g.mision == 'entrega' or g.mision == 'abasto' then
        return false, 'es un convoy'
    end
    return true
end

--- Unidad principal del grupo: el modelo de vehículo que más poder aporta
-- (con su era) o, sin vehículos, los soldados. { tropa, modelo, era, cantidad }.
function PanelTropas.principal(g)
    local mejor, valor, tropa
    for _, tipo in ipairs(Simulacion.Armamento.TIPOS) do
        for _, d in ipairs(Simulacion.desglose(g, tipo)) do
            local v = d.cantidad * Simulacion.fichaModelo(d.modelo).juego.poder
            if not valor or v > valor then
                mejor, valor, tropa = d, v, tipo
            end
        end
    end
    if mejor then
        local ficha = Simulacion.fichaModelo(mejor.modelo)
        return { tropa = tropa, modelo = mejor.modelo, era = ficha.era, cantidad = mejor.cantidad }
    end
    return { tropa = 'soldados', cantidad = g.soldados or 0 }
end

--- ¿Entra el grupo `g` en el filtro `filtro`?
local function enFiltro(g, filtro)
    if filtro == 'bandera' then
        return g.mision == 'guarnicion'
    elseif filtro == 'agua' then
        return false -- todavía no hay barcos
    end
    return g.mision ~= 'guarnicion'
end

--- Grupos de la nación `nid` que están fuera, en orden de id (todos, sin filtro).
function PanelTropas.grupos(sim, nid)
    local out = {}
    for _, gid in ipairs(Simulacion.ordenadas(sim.estado.grupos)) do
        local g = sim.estado.grupos[gid]
        if g.nacion == nid then
            out[#out + 1] = g
        end
    end
    return out
end

--- Los del filtro de ahora.
function PanelTropas:filtrados(sim, nid)
    local out = {}
    for _, g in ipairs(PanelTropas.grupos(sim, nid)) do
        if enFiltro(g, self.filtro) then
            out[#out + 1] = g
        end
    end
    return out
end

--- Imagen (una vez) de la miniatura del Arsenal de `clave`.
function PanelTropas:imagen(clave)
    local datos = Indice.arsenal[clave]
    local ruta = datos and datos.miniatura
    -- Sin el render (la copia pública del código va sin los de pago), sin imagen.
    if not ruta or not love.filesystem.getInfo(Indice.carpeta .. ruta, 'file') then
        return nil
    end
    local img = self.imagenes[ruta]
    if not img then
        img = love.graphics.newImage(Indice.carpeta .. ruta)
        img:setFilter('linear', 'linear')
        self.imagenes[ruta] = img
    end
    return img
end

--- Zona pulsable.
function PanelTropas:zona(x, y, w, h, accion, ayuda)
    self.zonas[#self.zonas + 1] = { x = x, y = y, w = w, h = h, accion = accion, ayuda = ayuda }
end

--- Botón cuadrado del HUD con un icono (o `dibujar(x, y, lado, color)`).
local function botonIcono(x, y, lado, icono, dorado, activo, dibujar)
    local mx, my = love.mouse.getPosition()
    local encima = Tema.dentro(mx, my, x, y, lado, lado)
    local estado = 'normal'
    if activo == false then
        estado = 'desactivado'
    elseif encima and love.mouse.isDown(1) then
        estado = 'pulsado'
    elseif encima then
        estado = 'resaltado'
    end
    Acero.nueve(dorado and 'boton_dorado' or 'boton_oscuro', estado, x, y, lado, lado)
    local color = dorado and 'amarilloTinta' or (activo == false and 'textoDesact' or 'textoHud')
    local chico = math.floor(lado * 0.56)
    local ix, iy = x + math.floor((lado - chico) / 2), y + math.floor((lado - chico) / 2)
    if dibujar then
        dibujar(ix, iy, chico, color)
    else
        Acero.icono(icono, ix, iy, chico, color)
    end
end

--- ✓ dibujado con dos trazos.
local function marca(x, y, lado, color)
    local g = love.graphics
    Tema.color(color)
    g.setLineWidth(math.max(2, lado * 0.14))
    g.setLineJoin('miter')
    g.line(x + lado * 0.12, y + lado * 0.55, x + lado * 0.4, y + lado * 0.82, x + lado * 0.9, y + lado * 0.2)
    g.setLineWidth(1)
end

--- Una tarjeta: imagen, era, cantidad y estado; dorada si está elegida.
function PanelTropas:dibujarTarjeta(g, x, y, w, h, elegida)
    local gr = love.graphics
    local px = Tema.px
    local mx, my = love.mouse.getPosition()
    local encima = Tema.dentro(mx, my, x, y, w, h)
    Acero.nueve('tarjeta_unidad', elegida and 'activa' or (encima and 'resaltada' or 'normal'), x, y, w, h)
    local p = PanelTropas.principal(g)
    local margen = px(3)
    local iw, ih = w - margen * 2, h - margen * 2
    local img = p.modelo and self:imagen(p.modelo) or self:imagen(ARTE_TROPA[p.tropa])
    if img and p.cantidad > 0 then
        -- La miniatura llena la tarjeta (recortada por los lados, sin deformar).
        local escala = math.max(iw / img:getWidth(), ih / img:getHeight())
        local vw, vh = math.floor(iw / escala), math.floor(ih / escala)
        local clave = tostring(img) .. ':' .. vw .. 'x' .. vh
        local quad = self.recortes[clave]
        if not quad then
            quad = gr.newQuad(
                math.floor((img:getWidth() - vw) / 2),
                math.floor((img:getHeight() - vh) / 2),
                vw,
                vh,
                img:getWidth(),
                img:getHeight()
            )
            self.recortes[clave] = quad
        end
        gr.setColor(1, 1, 1, 1)
        gr.draw(img, quad, x + margen, y + margen, 0, escala, escala)
    else
        -- Sin tropa a la vista (un convoy): el icono de lo que hace.
        local icono = PanelTropas.estado(g)
        local lado = math.floor(ih * 0.55)
        Acero.icono(icono, x + (w - lado) / 2, y + (h - lado) / 2, lado, 'textoHudTenue')
    end
    -- Sombra abajo para que se lean la cantidad y el estado.
    gr.setColor(0, 0, 0, 0.5)
    gr.rectangle('fill', x + margen, y + h - px(24), iw, px(24) - margen)
    local fuente = Acero.fuente('cifra', 18)
    local chica = Acero.fuente('boton', 15)
    -- Era, arriba a la izquierda.
    if p.era then
        Acero.textoContorno(chica, ROMANOS[p.era] or tostring(p.era), x + px(6), y + px(3), 'amarillo')
    end
    -- Estado, abajo a la izquierda.
    local icono = PanelTropas.estado(g)
    local lado = px(18)
    Acero.icono(icono, x + px(5), y + h - lado - px(5), lado, 'textoHud')
    -- Cantidad de la unidad principal, abajo a la derecha.
    local cifra = Tema.numero(p.cantidad)
    Acero.textoContorno(
        fuente,
        cifra,
        x + w - px(6) - fuente:getWidth(cifra),
        y + h - fuente:getHeight() - px(2),
        'textoHud'
    )
    return encima
end

--- Texto de la ayuda de una tarjeta: «Gral. X · 3 BM-21, 120 soldados · En marcha».
local function ayudaGrupo(sim, g)
    local ficha = sim:fichaGrupo(g.id, g.nacion)
    local quien = ficha and ficha.lider and ficha.lider.etiqueta or 'Grupo ' .. g.id
    local partes = {}
    for _, tipo in ipairs(Simulacion.Armamento.TIPOS) do
        for _, d in ipairs(Simulacion.desglose(g, tipo)) do
            partes[#partes + 1] = Tema.numero(d.cantidad) .. ' ' .. Simulacion.nombreModelo(d.modelo)
        end
    end
    if (g.soldados or 0) > 0 then
        partes[#partes + 1] = Tema.numero(g.soldados) .. ' soldados'
    end
    local _, que = PanelTropas.estado(g)
    return string.format('%s · %s · %s', quien, #partes > 0 and table.concat(partes, ', ') or 'sin tropa', que)
end

--- Dibuja la barra. `ctx` = { sim, nacion, elegidos (tabla gid -> true),
-- derecha (x donde acaba, px de pantalla), abajo (y donde acaba) }. Sin
-- grupos fuera no dibuja nada (`rect` = nil).
function PanelTropas:dibujar(ctx)
    self.zonas = {}
    self.ayuda = nil
    self.rect = nil
    local sim, nid = ctx.sim, ctx.nacion
    if not (sim and nid) then
        return
    end
    local todos = PanelTropas.grupos(sim, nid)
    if #todos == 0 then
        self.radial = nil
        return
    end
    local g = love.graphics
    local px = Tema.px
    local lista = self:filtrados(sim, nid)
    local w, h = px(PanelTropas.ancho), px(PanelTropas.alto)
    local hueco = px(PanelTropas.hueco)
    local lado = px(PanelTropas.boton)
    local derecha = ctx.derecha
    local abajo = ctx.abajo
    local caben = math.max(1, math.floor((px(PanelTropas.anchoMaximo) + hueco) / (w + hueco)))
    -- Si no caben todas, se deja sitio a las flechas ‹ › dentro de la barra.
    local flecha = px(20)
    local conFlechas = #lista > caben
    if conFlechas then
        caben = math.max(1, math.floor((px(PanelTropas.anchoMaximo) - (flecha + px(4)) * 2 + hueco) / (w + hueco)))
    end
    local visibles = math.min(#lista, caben)
    self.inicio = math.max(1, math.min(self.inicio, #lista - visibles + 1))
    local anchoTarjetas = math.max(1, visibles) * (w + hueco) - hueco
    local margenFlechas = conFlechas and (flecha + px(4)) or 0
    local anchoBotones = (#FILTROS + 2) * (lado + hueco) + hueco
    local ancho = math.max(anchoTarjetas + margenFlechas * 2, anchoBotones)
    local altoTarjetas = #lista > 0 and h or px(30)
    local x = derecha - ancho
    local yTarjetas = abajo - altoTarjetas
    local yBotones = yTarjetas - hueco - lado
    self.rect = { x = x, y = yBotones, w = ancho, h = abajo - yBotones }
    -- Elegidos: los del mapa que son de esta nación.
    local elegidos = ctx.elegidos or {}
    local todosElegidos = #lista > 0
    for _, gr in ipairs(lista) do
        if not elegidos[gr.id] then
            todosElegidos = false
        end
    end
    -- Botones: filtros a la derecha; ✓ y regresar a su izquierda.
    local bx = derecha - lado
    for k = #FILTROS, 1, -1 do
        local f = FILTROS[k]
        local activo = f.id ~= 'agua'
        botonIcono(bx, yBotones, lado, f.icono, self.filtro == f.id, activo)
        self:zona(bx, yBotones, lado, lado, { tipo = 'filtro', filtro = f.id, activo = activo }, f.ayuda)
        bx = bx - lado - hueco
    end
    bx = bx - hueco
    botonIcono(bx, yBotones, lado, nil, todosElegidos, #lista > 0, marca)
    self:zona(
        bx,
        yBotones,
        lado,
        lado,
        { tipo = 'todos', activo = #lista > 0 },
        todosElegidos and 'Soltar todos' or 'Seleccionar todos los de este filtro'
    )
    bx = bx - lado - hueco
    local algunoElegido = false
    for _, gr in ipairs(todos) do
        if elegidos[gr.id] then
            algunoElegido = true
        end
    end
    botonIcono(bx, yBotones, lado, 'retirar', false, #lista > 0 or algunoElegido)
    self:zona(
        bx,
        yBotones,
        lado,
        lado,
        { tipo = 'regresar', activo = #lista > 0 or algunoElegido },
        algunoElegido and 'Regresar los elegidos: vuelven andando a su ciudad'
            or 'Regresar todos los de este filtro que no están en batalla'
    )
    -- Tarjetas (o, sin ninguna en el filtro, una franja discreta).
    if #lista == 0 then
        local fuente = Acero.fuente('etiqueta', 14)
        g.setColor(0.05, 0.06, 0.04, 0.55)
        g.rectangle('fill', x, yTarjetas, ancho, altoTarjetas, px(3), px(3))
        g.setFont(fuente)
        Tema.color('textoHudTenue')
        local texto = self.filtro == 'agua' and 'Todavía no hay barcos' or 'Nada fuera en este filtro'
        g.print(texto, x + (ancho - fuente:getWidth(texto)) / 2, yTarjetas + (altoTarjetas - fuente:getHeight()) / 2)
    end
    local tx = derecha - margenFlechas - anchoTarjetas
    local mx, my = love.mouse.getPosition()
    local radialDe
    for k = self.inicio, self.inicio + visibles - 1 do
        local gr = lista[k]
        local cx = tx + (k - self.inicio) * (w + hueco)
        if self:dibujarTarjeta(gr, cx, yTarjetas, w, h, elegidos[gr.id]) then
            self.ayuda = ayudaGrupo(sim, gr)
        end
        self:zona(cx, yTarjetas, w, h, { tipo = 'elegir', gid = gr.id })
        if self.radial == gr.id then
            radialDe = { gr = gr, x = cx + w / 2 }
        end
    end
    -- Desplazamiento: ‹ › a los lados si no caben todas.
    if conFlechas then
        local fy = yTarjetas + (h - px(40)) / 2
        local puedeAtras, puedeAdelante = self.inicio > 1, self.inicio + visibles - 1 < #lista
        local ix, dx = tx - flecha - px(4), derecha - flecha
        Acero.pieza('boton_franja_izquierda', puedeAtras and 'normal' or 'desactivado', ix, fy, flecha, px(40))
        Acero.pieza('boton_franja_derecha', puedeAdelante and 'normal' or 'desactivado', dx, fy, flecha, px(40))
        self:zona(ix, fy, flecha, px(40), { tipo = 'desplazar', paso = -1, activo = puedeAtras })
        self:zona(dx, fy, flecha, px(40), { tipo = 'desplazar', paso = 1, activo = puedeAdelante })
    end
    -- Radial pequeño sobre la tarjeta tocada, con «Regresar».
    if self.radial and not radialDe then
        -- Su grupo ya no está a la vista (volvió, cambió de filtro o se desplazó).
        local sigue = sim.estado.grupos[self.radial]
        if not sigue then
            self.radial = nil
        end
    end
    if radialDe then
        self:dibujarRadial(radialDe.gr, radialDe.x, yBotones)
    end
    self:dibujarAviso(derecha, yBotones)
    if not self.ayuda then
        for _, z in ipairs(self.zonas) do
            if z.ayuda and Tema.dentro(mx, my, z.x, z.y, z.w, z.h) then
                self.ayuda = z.ayuda
            end
        end
    end
end

--- El radial pequeño del grupo `gr`: medio disco oscuro encima de la barra,
-- centrado en `cx`, con el botón «Regresar» (o «Retirarse» en batalla).
function PanelTropas:dibujarRadial(gr, cx, yBase)
    local g = love.graphics
    local px = Tema.px
    local radio = px(74)
    local w = g.getDimensions()
    cx = math.max(radio + px(8), math.min(w - radio - px(8), cx))
    local cy = yBase - px(4)
    g.setColor(0.05, 0.06, 0.04, 0.72)
    g.arc('fill', cx, cy, radio, math.pi, math.pi * 2)
    g.setColor(0.93, 0.94, 0.92, 0.35)
    g.setLineWidth(math.max(1, px(1.5)))
    g.arc('line', 'open', cx, cy, radio, math.pi, math.pi * 2)
    g.setLineWidth(1)
    local puede, motivo = PanelTropas.puedeRegresar(gr)
    local ancho = px(64)
    local alto = px(84)
    local bx, by = cx - ancho / 2, cy - radio + px(4)
    local etiqueta = gr.batalla and 'Retirarse' or 'Regresar'
    Acero.botonIcono(bx, by, ancho, alto, { icono = 'retirar', etiqueta = etiqueta, desactivado = not puede })
    self:zona(
        bx,
        by,
        ancho,
        alto,
        { tipo = 'regresarUno', gid = gr.id, activo = puede },
        puede
                and (gr.batalla and 'Es una retirada: sale de la batalla y pierde la carga' or 'Vuelve andando a su ciudad')
            or ('No puede regresar: ' .. motivo)
    )
    -- El medio disco también es del panel: los clics en él no pasan al mapa.
    self:zona(cx - radio, cy - radio, radio * 2, radio, { tipo = 'nada' })
end

--- El aviso de la última orden, a la izquierda de los botones.
function PanelTropas:dibujarAviso(derecha, y)
    local a = self.aviso
    if not a then
        return
    end
    if love.timer.getTime() > a.hasta then
        self.aviso = nil
        return
    end
    local g = love.graphics
    local px = Tema.px
    local fuente = Acero.fuente('boton', 16)
    local ancho = fuente:getWidth(a.texto) + px(24)
    local alto = px(PanelTropas.boton)
    local x = derecha - (#FILTROS + 2) * (px(PanelTropas.boton) + px(PanelTropas.hueco)) - px(8) - ancho
    x = math.max(px(8), x)
    Tema.color('olivaNegro', 0.92)
    g.rectangle('fill', x, y, ancho, alto, px(3), px(3))
    Tema.borde(x, y, ancho, alto, 'amarillo')
    g.setFont(fuente)
    Tema.color('amarillo')
    g.print(a.texto, x + px(12), y + (alto - fuente:getHeight()) / 2)
end

function PanelTropas:dibujarAyuda()
    if self.ayuda then
        local mx, my = love.mouse.getPosition()
        Tema.ayuda(self.ayuda, mx, my, Tema.px(340))
    end
end

--- ¿Cae (x, y) en la barra o en su radial?
function PanelTropas:encima(x, y)
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            return true
        end
    end
    local r = self.rect
    return r ~= nil and Tema.dentro(x, y, r.x, r.y, r.w, r.h)
end

--- Rueda sobre la barra: desplaza las tarjetas. true si la usó.
function PanelTropas:rueda(x, y, dy)
    if not self:encima(x, y) then
        return false
    end
    self.inicio = self.inicio - (dy > 0 and 1 or -1)
    return true
end

--- Clic. nil si cayó fuera (y cierra el radial pequeño); si no, 'nada' o
-- una acción para main.lua: { tipo = 'elegir', gid } (elegirlo, centrar la
-- cámara; el radial ya queda abierto), { tipo = 'todos' } (elegir o soltar
-- todos los del filtro), { tipo = 'regresar' } (los elegidos o, sin
-- ninguno, los del filtro que no pelean) o { tipo = 'regresarUno', gid }.
function PanelTropas:pulsar(x, y)
    for k = #self.zonas, 1, -1 do
        local z = self.zonas[k]
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            local a = z.accion
            if a.activo == false or a.tipo == 'nada' then
                return 'nada'
            elseif a.tipo == 'filtro' then
                self.filtro = a.filtro
                self.inicio = 1
                self.radial = nil
                return 'nada'
            elseif a.tipo == 'desplazar' then
                self.inicio = self.inicio + a.paso
                return 'nada'
            elseif a.tipo == 'elegir' then
                self.radial = self.radial ~= a.gid and a.gid or nil
                return { tipo = 'elegir', gid = a.gid, radial = self.radial ~= nil }
            elseif a.tipo == 'regresarUno' then
                self.radial = nil
            end
            return a
        end
    end
    local r = self.rect
    if r and Tema.dentro(x, y, r.x, r.y, r.w, r.h) then
        return 'nada'
    end
    self.radial = nil
    return nil
end

--- Ids de los grupos del filtro de ahora (para «Seleccionar todos»).
function PanelTropas:idsFiltro(sim, nid)
    local out = {}
    for _, g in ipairs(self:filtrados(sim, nid)) do
        out[#out + 1] = g.id
    end
    return out
end

--- Ids que regresa la flecha: los elegidos de la nación o, sin ninguno, los
-- del filtro que no están en batalla (una retirada se pide aparte).
function PanelTropas:idsRegresar(sim, nid, elegidos)
    local out = {}
    for _, g in ipairs(PanelTropas.grupos(sim, nid)) do
        if elegidos[g.id] then
            out[#out + 1] = g.id
        end
    end
    if #out > 0 then
        return out, true
    end
    for _, g in ipairs(self:filtrados(sim, nid)) do
        if not g.batalla then
            out[#out + 1] = g.id
        end
    end
    return out, false
end

return PanelTropas
