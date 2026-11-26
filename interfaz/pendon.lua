--- Panel de sitio: el de una ciudad, una instalación, una mina o una bandera
-- (diseno/interfaz-militar.md, §5.2 a §5.5). Va a la derecha, bajo la barra
-- superior: cabecera con el nombre y el cierre, identidad, cifras, vida,
-- avisos y pestañas son fijos; lo demás va en una zona que se desplaza con la
-- rueda. (El módulo conserva el nombre de «Pendón» de cuando era el
-- «Estandarte colgante».)
--
-- Solo lee la simulación. Los botones mandan comandos a `sim:ejecutar` (como
-- el presidente NPC) o devuelven una acción para main.lua (cerrar, ir a una
-- nación).

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Inteligencia = require('interfaz.inteligencia')
local VentanaPoblacion = require('interfaz.poblacion')
local Simulacion = require('mundo.simulacion')

local Pendon = {}
Pendon.__index = Pendon

local PESTANAS = {
    { clave = 'resumen', texto = 'Resumen' },
    { clave = 'ejercito', texto = 'Ejército' },
    { clave = 'nacion', texto = 'Nación' },
    { clave = 'relaciones', texto = 'Relaciones' },
}
local NOMBRE_RECURSO = { metal = 'Metal', petroleo = 'Petróleo', comida = 'Comida', oro = 'Oro' }
local NOMBRE_TROPA = { lanzacohetes = 'lanzacohetes', soldados = 'soldados' }
local ORDEN_TROPAS = { 'lanzacohetes', 'soldados' }
local FILAS_POR_PASO = 3 -- filas que baja un paso de rueda (C9)

function Pendon.nuevo()
    local self = setmetatable({}, Pendon)
    self.clave = nil -- lo que muestra; al cambiar, vuelve arriba
    self.pestana = 'resumen'
    self.desplazamiento = 0
    self.maximo = 0
    self.rect = nil -- { x, y, w, h } de todo el pendón (con la punta)
    self.lista = nil -- { x, y, w, h } de la zona desplazable
    self.zonas = {} -- zonas pulsables de este cuadro: { x, y, w, h, accion }
    self.ayuda = nil
    -- Cuántas tropas quiere sacar el jugador al armar un grupo nuevo desde
    -- esta ciudad (dueño 2026-09-29). Se resetean al cambiar de ciudad o al
    -- armar el grupo.
    self.sacar = { soldados = 0, lanzacohetes = 0 }
    return self
end

--- Contenido desplazable: una lista de piezas con su alto y su dibujo.
local function nuevoContenido()
    local contenido = { piezas = {}, alto = 0 }
    function contenido.poner(alto, dibujar)
        contenido.piezas[#contenido.piezas + 1] = { alto = alto, dibujar = dibujar }
        contenido.alto = contenido.alto + alto
    end
    function contenido.hueco(alto)
        contenido.poner(alto, nil)
    end
    return contenido
end

--- Fila dato-valor (C3): etiqueta a la izquierda, valor en negrita a la
-- derecha y una línea punteada debajo.
local function fila(contenido, etiqueta, valor, colorValor)
    contenido.poner(Tema.px(22), function(x, y, w)
        local g = love.graphics
        local texto = Tema.fuente('sans', 15)
        local negrita = Tema.fuente('sansNegrita', 15)
        local alto = Tema.px(22)
        local anchoValor = negrita:getWidth(valor)
        g.setFont(texto)
        Tema.color('textoHudTenue')
        g.print(
            Tema.cortar(texto, etiqueta, w - anchoValor - Tema.px(8)),
            x,
            math.floor(y + (alto - texto:getHeight()) / 2)
        )
        g.setFont(negrita)
        Tema.color(colorValor or 'textoHud')
        g.print(valor, x + w - anchoValor, math.floor(y + (alto - negrita:getHeight()) / 2))
        Tema.color('caquiPestana', 0.28)
        for px = x, x + w, 4 do
            g.rectangle('fill', px, y + alto - 1, 2, 1)
        end
    end)
end

local function titulo(contenido, texto, primero)
    if not primero then
        contenido.hueco(Tema.px(12))
    end
    local alto = Tema.fuente('sc', 13, 10):getHeight() + Tema.px(6)
    contenido.poner(alto, function(x, y, w)
        Tema.tituloSeccion(texto, x, y, w)
    end)
end

--- Línea de texto suelta (notas bajo una sección).
local function nota(contenido, texto, color)
    local fuente = Tema.fuente('sans', 14)
    contenido.poner(fuente:getHeight() + Tema.px(2), function(x, y, w)
        love.graphics.setFont(fuente)
        Tema.color(color or 'textoHudTenue')
        love.graphics.print(Tema.cortar(fuente, texto, w), x, y)
    end)
end

--- Lanzacohetes de una ciudad fuera de ella (F8): en grupos o de camino.
local function lanzacohetesFuera(sim, c)
    local recuperando = c.recuperando and c.recuperando.lanzacohetes or 0
    return math.max(0, sim:enCamino(c.id, 'lanzacohetes') - recuperando)
end

--- Fila de recuperación de una tropa con su botón Acelerar (C7). El botón paga
-- por la nación dueña de la ciudad (aún no hay nación del jugador), con el
-- mismo comando que usa un presidente NPC.
function Pendon:filaRecuperacion(contenido, sim, c, nacion, tropa)
    local cuantos = c.recuperando and c.recuperando[tropa] or 0
    if cuantos <= 0 then
        return
    end
    local sitiada = sim:sitiada(c)
    local plazo
    if sitiada then
        plazo = 'parada: sitiada'
    elseif tropa == 'soldados' and c.hambre then
        plazo = 'parados: hambre'
    else
        local dias = Simulacion.diasRecuperacion(c, tropa)
        plazo = dias == 1 and '1 día' or string.format('%d días', dias)
    end
    -- Lo que puede gastar: lo de la bóveda más lo de afuera.
    local dinero = Simulacion.disponible(nacion, 'dinero')
    local boton = {
        texto = 'Acelerar',
        tipo = 'principal',
        precio = Simulacion.precioRecuperacion(c, tropa),
        activo = not sitiada and dinero >= Simulacion.recuperacion.precio[tropa],
    }
    local alto = Tema.px(28)
    contenido.poner(alto, function(x, y, w, visible)
        local g = love.graphics
        local fuente = Tema.fuente('sans', 14)
        local anchoBoton = Tema.anchoBoton(boton, true)
        local radio = Tema.px(6)
        Tema.reloj(x + radio, y + alto / 2, radio, sitiada and 'rojoTexto' or 'amarillo')
        g.setFont(fuente)
        Tema.color('textoHud')
        local texto = string.format('%d %s · %s', cuantos, NOMBRE_TROPA[tropa], plazo)
        g.print(
            Tema.cortar(fuente, texto, w - anchoBoton - radio * 2 - Tema.px(14)),
            x + radio * 2 + Tema.px(6),
            math.floor(y + (alto - fuente:getHeight()) / 2)
        )
        local bh = Tema.px(26)
        local bx, by = x + w - anchoBoton, y + math.floor((alto - bh) / 2)
        Tema.boton(boton, bx, by, anchoBoton, bh, true)
        if boton.activo and visible(by, bh) then
            self.zonas[#self.zonas + 1] = {
                x = bx,
                y = by,
                w = anchoBoton,
                h = bh,
                accion = function()
                    sim:ejecutar({
                        tipo = 'acelerarRecuperacion',
                        nacion = c.nacion,
                        ciudad = c.id,
                        tropa = tropa,
                        pagaTesoro = true,
                    })
                end,
            }
        end
    end)
end

--- Medidor de reserva con su ayuda al pasar el ratón.
function Pendon:medidor(contenido, r, nombre, ayuda)
    contenido.poner(Tema.alturaMedidor(r) + Tema.px(6), function(x, y, w, visible)
        local encima = Tema.medidor(r, nombre, x, y, w)
        if encima and visible(y, Tema.alturaMedidor(r)) then
            self.ayuda = ayuda
        end
    end)
end

--- Defensas de un sitio (C7): «Lanzacohetes · 1 / 10» y sus casillas.
local function defensa(contenido, nombre, partes, plazas, ancho)
    local fuente = Tema.fuente('sans', 15)
    local porFila = math.min(plazas, 15)
    local hueco = Tema.px(3)
    local lado = math.min(Tema.px(18), math.floor((ancho - hueco * (porFila - 1)) / porFila))
    local filas = math.ceil(plazas / porFila)
    local alto = fuente:getHeight() + Tema.px(4) + filas * lado + (filas - 1) * hueco + Tema.px(6)
    contenido.poner(alto, function(x, y, w)
        local g = love.graphics
        g.setFont(fuente)
        Tema.color('textoHud')
        g.print(nombre, x, y)
        local negrita = Tema.fuente('sansNegrita', 15)
        local cuenta = string.format('%d / %d', partes.listas, plazas)
        g.setFont(negrita)
        g.print(cuenta, x + w - negrita:getWidth(cuenta), y)
        Tema.casillas(partes, plazas, x, y + fuente:getHeight() + Tema.px(4), w)
    end)
end

--- Barra sencilla de proporción con etiqueta y valor (salud, fortificación, obra).
local function barra(contenido, etiqueta, valor, parte, color)
    local fuente = Tema.fuente('sans', 15)
    local alto = fuente:getHeight() + Tema.px(14)
    contenido.poner(alto, function(x, y, w)
        local g = love.graphics
        local negrita = Tema.fuente('sansNegrita', 15)
        g.setFont(fuente)
        Tema.color('textoHudTenue')
        g.print(etiqueta, x, y)
        g.setFont(negrita)
        Tema.color('textoHud')
        g.print(valor, x + w - negrita:getWidth(valor), y)
        local by = y + fuente:getHeight() + Tema.px(2)
        local bh = Tema.px(8)
        Tema.color('olivaNegro')
        g.rectangle('fill', x, by, w, bh)
        Tema.color(color)
        g.rectangle('fill', x + 1, by + 1, math.floor((w - 2) * math.max(0, math.min(1, parte))), bh - 2)
        Tema.borde(x, by, w, bh, 'lineaOliva')
    end)
end

--- Sección POBLACIÓN del resumen (diseno/poblacion.md): el mismo desglose
-- que la ventana de Población (interfaz/poblacion.lua), en breve.
function Pendon:poblacion(contenido, sim, c)
    local r = VentanaPoblacion.desglose(sim, c)
    if not r then
        return
    end
    local reglas = Simulacion.poblacion
    titulo(contenido, 'POBLACIÓN')
    fila(contenido, string.format('Niños (0 a %d)', reglas.trabajaMin - 1), Tema.numero(r.ninos))
    fila(
        contenido,
        string.format('Edad de trabajar (%d a %d)', reglas.trabajaMin, reglas.trabajaMax),
        Tema.numero(r.enEdadDeTrabajar)
    )
    fila(
        contenido,
        string.format('Reclutables (%d a %d)', reglas.edadMin, reglas.edadMax),
        string.format('%s de %s aptos', Tema.numero(r.reclutables), Tema.numero(r.aptos)),
        r.reclutables > 0 and 'textoHud' or 'rojoTexto'
    )
    fila(contenido, string.format('Mayores (%d o más)', reglas.trabajaMax + 1), Tema.numero(r.mayores))
    fila(contenido, 'Total en filas (de esta ciudad)', Tema.numero(r.enFilas), 'amarillo')
    barra(
        contenido,
        'Vivienda',
        string.format('%s / %s', Tema.numero(r.total), Tema.numero(r.tope)),
        r.ocupacion,
        r.ocupacion >= reglas.viviendaLlena and 'amarillo' or 'verde'
    )
    if r.textoFrena then
        nota(contenido, r.textoFrena, 'amarillo')
    end
end

--- Tres cajas de cifra pequeñas en una fila (FUERZAS).
local function cajasPequenas(contenido, cajas)
    local etiqueta = Tema.fuente('sc', 12, 10)
    local cifra = Tema.fuente('sansNegrita', 18)
    local alto = Tema.px(6) + etiqueta:getHeight() + cifra:getHeight() + Tema.px(6)
    contenido.poner(alto, function(x, y, w)
        local g = love.graphics
        local hueco = Tema.px(6)
        local ancho = math.floor((w - hueco * (#cajas - 1)) / #cajas)
        for k, caja in ipairs(cajas) do
            local cx = x + (k - 1) * (ancho + hueco)
            Tema.color('oliva', 0.7)
            g.rectangle('fill', cx, y, ancho, alto)
            Tema.borde(cx, y, ancho, alto, 'lineaOliva')
            Tema.color('textoHudTenue')
            Tema.espaciado(caja[1], cx + Tema.px(8), y + Tema.px(5), etiqueta, etiqueta:getHeight() * 0.1)
            g.setFont(cifra)
            Tema.color('textoHud')
            g.print(caja[2], cx + Tema.px(8), y + Tema.px(5) + etiqueta:getHeight())
        end
    end)
end

--- Relación con otra nación (C10): punto del país, nombre, eje de −100 a +100
-- y valor. Un clic lleva a su capital.
function Pendon:relacion(contenido, otra, valor)
    local alto = Tema.px(26)
    contenido.poner(alto, function(x, y, w, visible)
        local g = love.graphics
        local fuente = Tema.fuente('sans', 14)
        local negrita = Tema.fuente('sansNegrita', 14)
        local mx, my = love.mouse.getPosition()
        local encima = visible(y, alto) and Tema.dentro(mx, my, x, y, w, alto)
        if encima then
            Tema.color('caquiPestana', 0.14)
            g.rectangle('fill', x - Tema.px(4), y, w + Tema.px(8), alto)
        end
        local punto = Tema.px(4)
        Tema.color(otra.color)
        g.circle('fill', x + punto, y + alto / 2, punto)
        local anchoValor = negrita:getWidth('−100')
        local eje = Tema.px(70)
        local nombreW = w - punto * 2 - Tema.px(8) - eje - Tema.px(10) - anchoValor - Tema.px(6)
        g.setFont(fuente)
        Tema.color('textoHud')
        g.print(
            Tema.cortar(fuente, otra.nombre, nombreW),
            x + punto * 2 + Tema.px(8),
            math.floor(y + (alto - fuente:getHeight()) / 2)
        )
        local ejeX = x + w - anchoValor - Tema.px(10) - eje
        local ejeY = math.floor(y + alto / 2)
        local barraH = Tema.px(6)
        Tema.color('olivaNegro')
        g.rectangle('fill', ejeX, ejeY - barraH / 2, eje, barraH)
        local mitad = eje / 2
        local largo = math.floor(mitad * math.min(1, math.abs(valor) / 100))
        if valor > 0 then
            Tema.color('verde')
            g.rectangle('fill', ejeX + mitad, ejeY - barraH / 2, largo, barraH)
        elseif valor < 0 then
            Tema.color('rojo')
            g.rectangle('fill', ejeX + mitad - largo, ejeY - barraH / 2, largo, barraH)
        end
        Tema.color('caquiPestana')
        g.rectangle('fill', ejeX + mitad, ejeY - barraH / 2 - 2, 1, barraH + 4)
        local texto = valor > 0 and '+' .. valor or (valor < 0 and '−' .. -valor or '0')
        local color = valor >= 25 and 'verde' or (valor <= -25 and 'rojoTexto' or 'textoHudTenue')
        g.setFont(negrita)
        Tema.color(color)
        g.print(texto, x + w - negrita:getWidth(texto), math.floor(y + (alto - negrita:getHeight()) / 2))
        if visible(y, alto) then
            self.zonas[#self.zonas + 1] = {
                x = x,
                y = y,
                w = w,
                h = alto,
                accion = { tipo = 'nacion', id = otra.id },
            }
        end
    end)
end

--- Grupos en marcha de una nación: atacando, en retirada y volviendo.
local function gruposEnMarcha(sim, nid)
    local cuenta = { atacando = 0, retirada = 0, volviendo = 0, otros = 0 }
    for _, gid in ipairs(Simulacion.ordenadas(sim.estado.grupos)) do
        local grupo = sim.estado.grupos[gid]
        if grupo.nacion == nid then
            if grupo.mision == 'atacar' then
                cuenta.atacando = cuenta.atacando + 1
            elseif grupo.mision == 'regreso' and grupo.retirada then
                cuenta.retirada = cuenta.retirada + 1
            elseif grupo.mision == 'regreso' then
                cuenta.volviendo = cuenta.volviendo + 1
            else
                cuenta.otros = cuenta.otros + 1
            end
        end
    end
    return cuenta
end

local function hayRecuperacion(c)
    local r = c.recuperando
    if not r then
        return false
    end
    for _, tropa in ipairs(ORDEN_TROPAS) do
        if (r[tropa] or 0) > 0 then
            return true
        end
    end
    return false
end

--- Pestaña Resumen: reservas, defensas y fuerzas.
function Pendon:resumen(contenido, sim, c, nacion, ancho)
    titulo(contenido, 'RESERVAS', true)
    local pais = sim:reservas(nacion.id)
    local granero = sim:reservaComida(c)
    local almacen = sim:almacenDe(nacion.id)
    for _, r in ipairs({ pais[1], pais[2], granero }) do
        local de = r.tipo == 'comida' and 'del granero' or 'del país'
        local ayuda = string.format(
            '%s %s: %s de %s · %s %s al día',
            NOMBRE_RECURSO[r.tipo],
            de,
            Tema.numero(r.cantidad),
            Tema.numero(r.tope),
            Tema.decimal(r.entra),
            Tema.decimal(-r.gasta)
        )
        -- Lo que no cabe en el almacén queda afuera (3.4): se pierde un 3 % al
        -- día y se lo llevan si saquean la capital.
        local afuera = almacen.afuera[r.tipo]
        if afuera and afuera >= 0.5 then
            ayuda = ayuda .. string.format(' · %s afuera', Tema.numero(afuera))
        end
        self:medidor(contenido, r, NOMBRE_RECURSO[r.tipo], ayuda)
    end
    titulo(contenido, 'DEFENSAS')
    local plazas = Simulacion.defensasCiudad.tope[c.nivel or 1]
    local recuperando = c.recuperando and c.recuperando.lanzacohetes or 0
    defensa(contenido, 'Lanzacohetes', {
        listas = c.lanzacohetes or 0,
        recuperando = recuperando,
        fuera = lanzacohetesFuera(sim, c),
    }, plazas, ancho)
    self:filaRecuperacion(contenido, sim, c, nacion, 'lanzacohetes')
    defensa(contenido, 'Baterías', { listas = c.baterias or 0 }, plazas, ancho)
    titulo(contenido, 'FUERZAS')
    cajasPequenas(contenido, {
        { 'AVIONES', Tema.numero(c.aviones) },
        { 'INTERCEP.', Tema.numero(c.interceptores or 0) },
    })
    self:poblacion(contenido, sim, c)
end

--- ¿`c` es una ciudad del jugador, viva, con tropa disponible? (Definida
-- antes de Pendon:ejercito, que la usa, porque las local function en Lua
-- solo se ven desde funciones definidas después en el archivo.)
local function jugadorEsPropio(sim, c, nacion)
    if not nacion or not nacion.jugador then
        return false
    end
    if not c or c.nacion ~= nacion.id then
        return false
    end
    return c.soldados > 0 or (c.lanzacohetes or 0) > 0
end

--- Pestaña Ejército: tropas, recuperación por tropa y grupos en marcha.
function Pendon:ejercito(contenido, sim, c, nacion)
    titulo(contenido, 'TROPAS', true)
    fila(contenido, 'Soldados', Tema.numero(c.soldados))
    fila(contenido, 'Lanzacohetes', Tema.numero(c.lanzacohetes or 0))
    fila(contenido, 'Aviones', Tema.numero(c.aviones))
    fila(contenido, 'Interceptores', Tema.numero(c.interceptores or 0))
    -- Economía cerrada: el tope de cada tropa por nivel (contando lo que está
    -- fuera, herido o en fábrica) y el polvorín de la ciudad.
    titulo(contenido, 'TOPE DE LA CIUDAD')
    local inv = sim:inventarioCiudad(c.id)
    for _, par in ipairs({ { 'soldados', 'Soldados' }, { 'lanzacohetes', 'Lanzacohetes' } }) do
        local tope = sim:topeCiudad(c, par[1])
        fila(
            contenido,
            par[2],
            string.format('%s / %s', Tema.numero(inv[par[1]]), Tema.numero(tope)),
            inv[par[1]] >= tope and 'rojoTexto' or nil
        )
    end
    titulo(contenido, 'POLVORÍN')
    local p = sim:polvorin(c.id) or {}
    fila(contenido, 'Balas', Tema.numero(p.balas or 0))
    fila(contenido, 'Misiles', Tema.numero(p.misiles or 0))
    if hayRecuperacion(c) then
        titulo(contenido, 'RECUPERÁNDOSE')
        if sim:sitiada(c) then
            nota(contenido, 'Parada: la ciudad está sitiada', 'rojoTexto')
        elseif c.hambre and (c.recuperando.soldados or 0) > 0 then
            nota(contenido, 'Los soldados no se curan: hay hambre', 'amarillo')
        end
        for _, tropa in ipairs(ORDEN_TROPAS) do
            self:filaRecuperacion(contenido, sim, c, nacion, tropa)
        end
    end
    local grupos = gruposEnMarcha(sim, nacion.id)
    titulo(contenido, 'GRUPOS EN MARCHA')
    local total = grupos.atacando + grupos.retirada + grupos.volviendo + grupos.otros
    if total == 0 then
        nota(contenido, 'Ninguno: todo el ejército está en casa')
    else
        fila(contenido, 'Atacando', tostring(grupos.atacando), grupos.atacando > 0 and 'rojoTexto' or nil)
        fila(contenido, 'En retirada', tostring(grupos.retirada), grupos.retirada > 0 and 'amarillo' or nil)
        fila(contenido, 'Volviendo', tostring(grupos.volviendo))
        if grupos.otros > 0 then
            fila(contenido, 'Otras misiones', tostring(grupos.otros))
        end
    end
    -- Bloque "Sacar tropas" (dueño 2026-09-29): solo en ciudades propias.
    -- Permite armar un grupo nuevo a partir de soldados y lanzacohetes de la
    -- ciudad, listo para mover con click derecho.
    if nacion and jugadorEsPropio(sim, c, nacion) then
        self:sacarTropas(contenido, sim, c)
    end
end

--- Bloque "Sacar tropas" del pendón (dueño 2026-09-29): dos filas con
-- botones −/+ para elegir cuántos soldados y lanzacohetes sacar,
-- y un botón "Armar grupo" que descuenta esos efectivos de la ciudad y
-- crea un grupo parado en ella, listo para que el jugador lo mueva con
-- click derecho en el mapa.
function Pendon:sacarTropas(contenido, sim, c)
    titulo(contenido, 'SACAR TROPAS', false)
    local filas = {
        { clave = 'soldados', etiqueta = 'Soldados', max = c.soldados },
        { clave = 'lanzacohetes', etiqueta = 'Lanzacohetes', max = c.lanzacohetes or 0 },
    }
    for _, filaInfo in ipairs(filas) do
        contenido.poner(Tema.px(44), function(x, y, w)
            local g = love.graphics
            local alto = Tema.px(44)
            local fuente = Acero.fuente('cuerpo')
            local negrita = Acero.fuente('cifra')
            g.setFont(fuente)
            Tema.color('textoHudTenue')
            local yy = math.floor(y + (alto - fuente:getHeight()) / 2)
            g.print(filaInfo.etiqueta, x, yy)
            -- Selector de cantidad: − valor + y lo que hay.
            local disponibles = string.format(' / %d', filaInfo.max)
            local xMax = x + w - fuente:getWidth(disponibles)
            g.print(disponibles, xMax, yy)
            local lado = Tema.px(36)
            local anchoValor = Tema.px(52)
            local xMas = xMax - Tema.px(4) - lado
            local xValor = xMas - Tema.px(4) - anchoValor
            local xMenos = xValor - Tema.px(4) - lado
            local yBtn = math.floor(y + (alto - lado) / 2)
            local num = tostring(self.sacar[filaInfo.clave] or 0)
            g.setFont(negrita)
            Tema.color('textoHud')
            g.print(
                num,
                xValor + (anchoValor - negrita:getWidth(num)) / 2,
                math.floor(y + (alto - negrita:getHeight()) / 2)
            )
            self:dibujarBotonMasMenos(xMenos, yBtn, lado, 'menos', filaInfo.clave, self.sacar[filaInfo.clave] or 0)
            self:dibujarBotonMasMenos(
                xMas,
                yBtn,
                lado,
                'mas',
                filaInfo.clave,
                self.sacar[filaInfo.clave] or 0,
                filaInfo.max
            )
            Tema.color('lineaOliva')
            g.rectangle('fill', x, y + alto - 1, w, 1)
        end)
    end
    -- Botón "Armar grupo".
    local vacio = (self.sacar.soldados or 0) + (self.sacar.lanzacohetes or 0) <= 0
    contenido.poner(Tema.px(52), function(x, y, w)
        local botonArmar = {
            texto = 'Armar grupo',
            tipo = 'principal',
            activo = not vacio,
            accion = function()
                local gid = self:armarGrupoDesde(sim, c)
                if gid then
                    self.grupoArmadoReciente = gid
                end
            end,
        }
        local bx, by, bw, bh = x, y + Tema.px(6), w, Tema.px(40)
        Tema.boton(botonArmar, bx, by, bw, bh, true)
        self.zonas[#self.zonas + 1] = { x = bx, y = by, w = bw, h = bh, accion = botonArmar.accion }
    end)
end

--- Dibuja un botón cuadrado +/− para ajustar la tropa a sacar (dueño
-- 2026-09-29) y registra su zona pulsable. El ajuste se hace de a saltos
-- (10 soldados, 1 lanzacohetes), manteniendo el valor entre 0 y
-- el máximo disponible.
function Pendon:dibujarBotonMasMenos(x, y, lado, signo, clave, actual, maximo)
    local activo = signo == 'mas' and (maximo == nil or actual < maximo) or (signo == 'menos' and actual > 0)
    Acero.boton({ texto = signo == 'mas' and '+' or '−', tipo = 'oscuro', activo = activo }, x, y, lado, lado, true)
    self.zonas[#self.zonas + 1] = {
        x = x,
        y = y,
        w = lado,
        h = lado,
        accion = function()
            self:ajustarSacar(clave, signo == 'mas' and 1 or -1)
        end,
    }
end

--- Ajusta la cantidad a sacar para una tropa (dueño 2026-09-29). Saltos:
-- soldados de a 10 (con un mínimo de 1 si la fila tiene algo) y
-- lanzacohetes de a 1. Se acota a [0, maxDisponible], pero `maxDisponible`
-- se chequea en el armado final (`armarGrupoDesde`).
function Pendon:ajustarSacar(clave, dir)
    local paso = (clave == 'soldados') and 10 or 1
    local v = (self.sacar[clave] or 0) + dir * paso
    if v < 0 then
        v = 0
    end
    if dir > 0 and v < paso then
        -- Si el jugador quiere sumar y estaba en 0, le damos al menos un paso
        -- para que sea visible (aunque después el armado verificará el tope).
        v = paso
    end
    self.sacar[clave] = v
end

--- Crea un grupo en la capital con la cantidad marcada en `self.sacar` y
-- descuenta esos efectivos de la ciudad (dueño 2026-09-29). Lo deja
-- parado en la ciudad (misión 'mover' con destino en la propia capital)
-- para que el jugador lo mueva con click derecho. Devuelve el id del
-- grupo nuevo o nil si no se pudo armar.
function Pendon:armarGrupoDesde(sim, c)
    local s = self.sacar
    local soldados = math.min(s.soldados or 0, c.soldados or 0)
    local lco = math.min(s.lanzacohetes or 0, c.lanzacohetes or 0)
    if soldados + lco <= 0 then
        return nil
    end
    -- enviarGrupo devuelve el id del grupo o false, motivo. La firma es
    -- (nid, desdeId, mision, objetivoId, construye, soldados,
    -- lanzacohetes). Para "parado en la propia capital" usamos 'mover'
    -- con destino = la capital: el grupo aparece con su ruta = {} (un
    -- solo punto) y se queda ahí hasta que el jugador le dé una orden.
    local nid = c.nacion
    local gid = sim:enviarGrupo(nid, c.id, 'mover', c.id, nil, soldados, lco)
    if not gid then
        sim:noticia('No se pudo armar el grupo (sin líder libre)', { 1, 0.6, 0.4 })
        return nil
    end
    -- Resetea los sliders para que el próximo armado empiece limpio.
    self.sacar.soldados = 0
    self.sacar.lanzacohetes = 0
    sim:noticia(
        string.format('Grupo armado en %s: %d soldados, %d lanzacohetes', c.nombre, soldados, lco),
        { 0.7, 0.9, 0.5 }
    )
    return gid
end

--- Pestaña Nación: gobierno, economía de la ciudad y tecnología.
function Pendon:nacion(contenido, sim, c, nacion, oculta)
    titulo(contenido, 'GOBIERNO', true)
    fila(contenido, 'Gobernante', nacion.gobernante.nombre)
    fila(contenido, 'Agresividad', string.format('%d %%', nacion.gobernante.agresividad * 100))
    fila(contenido, 'Prudencia', string.format('%d %%', nacion.gobernante.prudencia * 100))
    if oculta then
        fila(contenido, 'Fuerza de la nación', 'Desconocida', 'textoHudTenue')
    else
        fila(contenido, 'Fuerza de la nación', Tema.numero(sim:fuerza(nacion.id)))
    end
    titulo(contenido, 'ECONOMÍA')
    if c.comprado then
        fila(contenido, 'Comida comprada hoy', Tema.numero(c.comprado))
    end
    local campamentos, bases = 0, 0
    for _, i in ipairs(sim:instalacionesDe(nacion.id)) do
        if i.tipo == 'base' then
            bases = bases + 1
        elseif i.tipo == 'campamento' then
            campamentos = campamentos + 1
        end
    end
    fila(contenido, 'Campamentos', Tema.numero(campamentos))
    fila(contenido, 'Bases militares', Tema.numero(bases))
    local recolectores = sim:recolectores(nacion.id)
    fila(contenido, 'Grupos recolectando', Tema.numero(#recolectores))
    if c.huerto then
        if sim.estado.dia < c.huerto.hasta then
            fila(contenido, 'Huerto', string.format('en %d días', c.huerto.hasta - sim.estado.dia), 'amarillo')
        else
            fila(contenido, 'Huerto', string.format('%s al día', Tema.decimal(sim:comidaHuerto(c))), 'verde')
        end
    end
    titulo(contenido, 'TECNOLOGÍA')
    local total = #Simulacion.tecnologias
    fila(contenido, 'Sabidas', string.format('%d de %d', nacion.tecnologia, total))
    if nacion.tecnologia > 0 then
        fila(contenido, 'La última', Simulacion.tecnologias[nacion.tecnologia].nombre)
    end
    local siguiente = Simulacion.tecnologias[nacion.tecnologia + 1]
    if siguiente then
        local parte = math.min(0.99, nacion.investigacion / siguiente.coste)
        fila(contenido, 'Investiga ' .. siguiente.nombre, string.format('%d %%', parte * 100), 'amarillo')
    end
end

--- Pestaña Relaciones: todas las naciones vivas, de la más fuerte a la más
-- débil en valor absoluto y, a igualdad, por id (el orden de siempre).
function Pendon:relaciones(contenido, sim, nacion)
    local lista = {}
    for _, otra in ipairs(sim:vivas()) do
        if otra ~= nacion then
            lista[#lista + 1] = { nacion = otra, valor = math.floor(sim:relacion(nacion.id, otra.id)) }
        end
    end
    table.sort(lista, function(a, b)
        if math.abs(a.valor) ~= math.abs(b.valor) then
            return math.abs(a.valor) > math.abs(b.valor)
        end
        return a.nacion.id < b.nacion.id
    end)
    titulo(contenido, string.format('RELACIONES · %d NACIONES', #lista), true)
    if #lista == 0 then
        nota(contenido, 'No queda ninguna otra nación')
    end
    for _, rel in ipairs(lista) do
        self:relacion(contenido, rel.nacion, rel.valor)
    end
end

--- Avisos de una ciudad (C6), de lo más grave a lo menos: guerras, sitio,
-- hambre y altos el fuego. Como mucho dos líneas.
local function avisosDe(sim, c, nacion)
    local avisos = {}
    local guerras, calmas = {}, {}
    for _, guerra in ipairs(sim:guerrasDe(nacion.id)) do
        if guerra.fase == 'calma' then
            calmas[#calmas + 1] = guerra
        else
            guerras[#guerras + 1] = guerra
        end
    end
    table.sort(guerras, function(a, b)
        if a.dias ~= b.dias then
            return a.dias > b.dias
        end
        return (a.atacante + a.defensor) < (b.atacante + b.defensor)
    end)
    local function enemiga(guerra)
        return sim:nacion(guerra.atacante == nacion.id and guerra.defensor or guerra.atacante)
    end
    for _, guerra in ipairs(guerras) do
        avisos[#avisos + 1] = {
            tipo = 'guerra',
            texto = 'En guerra con ' .. enemiga(guerra).nombre,
            plazo = string.format('día %d', guerra.dias),
        }
    end
    if sim:sitiada(c) then
        avisos[#avisos + 1] = { tipo = 'guerra', texto = 'Ciudad sitiada', plazo = 'sin curas' }
    end
    if c.hambre then
        avisos[#avisos + 1] = { tipo = 'escasez', texto = 'Hambre en la ciudad', plazo = '' }
    end
    for _, guerra in ipairs(calmas) do
        avisos[#avisos + 1] = {
            tipo = 'tregua',
            texto = 'Alto el fuego con ' .. enemiga(guerra).nombre,
            plazo = string.format('hasta el día %d', guerra.faseHasta),
        }
    end
    if c.mejora and #avisos < 2 then
        avisos[#avisos + 1] = {
            tipo = 'info',
            texto = string.format('Mejorando a nivel %d', c.mejora.nivel),
            plazo = string.format('%d días', c.mejora.hasta - sim.estado.dia),
        }
    end
    if #avisos > 2 then
        local resto = #avisos - 1
        local segundo = avisos[2]
        if #guerras > 1 then
            segundo = {
                tipo = 'guerra',
                texto = string.format('+%d guerras más', #guerras - 1),
                plazo = resto > #guerras - 1 and string.format('+%d avisos', resto - (#guerras - 1)) or '',
            }
        else
            segundo.plazo = string.format('+%d más', resto - 1)
        end
        avisos = { avisos[1], segundo }
    end
    return avisos
end

-- Aviso: franja de un tipo de aviso. `tipo` -> fondo, marca y color del texto.
local FONDO_AVISO = {
    guerra = { 'rojoOscuro', 'rojo', 'textoHud' },
    tregua = { 'olivaClaro', 'lineaOliva', 'textoHudTenue' },
    escasez = { 'olivaClaro', 'amarillo', 'amarillo' },
    info = { 'olivaClaro', 'caquiPestana', 'textoHud' },
}

local function dibujarAviso(aviso, x, y, w, h)
    local g = love.graphics
    local estilo = FONDO_AVISO[aviso.tipo]
    Acero.placa(x, y, w, h, Tema.px(4), estilo[1], estilo[2])
    Tema.color(estilo[2])
    g.rectangle('fill', x + 1, y + Tema.px(4), Tema.px(3), h - Tema.px(8))
    local negrita = Acero.fuente('cifra', 17)
    local fuente = Acero.fuente('cuerpo', 16)
    local anchoPlazo = fuente:getWidth(aviso.plazo)
    local lado = Tema.px(20)
    Acero.icono('alerta', x + Tema.px(10), y + (h - lado) / 2, lado, aviso.tipo == 'guerra' and 'textoHud' or estilo[2])
    g.setFont(negrita)
    Tema.color(estilo[3])
    local textoX = x + Tema.px(36)
    g.print(
        Tema.cortar(negrita, aviso.texto, w - (textoX - x) - anchoPlazo - Tema.px(18)),
        textoX,
        math.floor(y + (h - negrita:getHeight()) / 2)
    )
    g.setFont(fuente)
    Tema.color(aviso.tipo == 'guerra' and 'textoHud' or 'textoHudTenue')
    g.print(aviso.plazo, x + w - anchoPlazo - Tema.px(10), math.floor(y + (h - fuente:getHeight()) / 2))
end

--- Cifras fijas (2×2): etiqueta y cifra; `cifras[k]` = { etiqueta, valor,
-- extra, progreso }.
local function altoCifras()
    local etiqueta = Acero.fuente('etiqueta')
    local cifra = Acero.fuente('cifra')
    local caja = Tema.px(8) + etiqueta:getHeight() + cifra:getHeight() + Tema.px(6)
    return caja * 2 + Tema.px(8), caja
end

local function dibujarCifras(cifras, x, y, w)
    local g = love.graphics
    local etiqueta = Acero.fuente('etiqueta')
    local cifra = Acero.fuente('cifra')
    local pequena = Acero.fuente('etiqueta', 15)
    local _, caja = altoCifras()
    local hueco = Tema.px(8)
    local ancho = math.floor((w - hueco) / 2)
    for k, c in ipairs(cifras) do
        local cx = x + ((k - 1) % 2) * (ancho + hueco)
        local cy = y + math.floor((k - 1) / 2) * (caja + hueco)
        Acero.chip(cx, cy, ancho, caja)
        g.setFont(etiqueta)
        Tema.color('textoHudTenue')
        g.print(c[1], cx + Tema.px(12), cy + Tema.px(6))
        g.setFont(cifra)
        Tema.color(c.color or 'textoHud')
        local valorY = cy + Tema.px(6) + etiqueta:getHeight()
        g.print(c[2], cx + Tema.px(12), valorY)
        if c[3] then
            g.setFont(pequena)
            Tema.color(c.colorExtra or 'textoHudTenue')
            local libre = ancho - Tema.px(24) - cifra:getWidth(c[2]) - Tema.px(6)
            local extra = Tema.cortar(pequena, c[3], libre)
            g.print(
                extra,
                cx + ancho - Tema.px(12) - pequena:getWidth(extra),
                valorY + cifra:getHeight() - pequena:getHeight() - Tema.px(2)
            )
        end
        if c[4] then
            Tema.color('olivaNegro')
            g.rectangle('fill', cx + Tema.px(10), cy + caja - Tema.px(6), ancho - Tema.px(20), Tema.px(3))
            Tema.color('amarillo')
            g.rectangle(
                'fill',
                cx + Tema.px(10),
                cy + caja - Tema.px(6),
                math.floor((ancho - Tema.px(20)) * c[4]),
                Tema.px(3)
            )
        end
    end
end

--- Bloque de identidad bajo la cabecera: el lema y el sello (orden y ciudades).
local function altoIdentidad()
    return Acero.fuente('cuerpo', 17):getHeight() + Acero.fuente('etiqueta'):getHeight() + Tema.px(6)
end

function Pendon:dibujarIdentidad(cabecera, x, y, w)
    local g = love.graphics
    local lema = Acero.fuente('cuerpo', 17)
    local sello = Acero.fuente('etiqueta')
    g.setFont(lema)
    Tema.color('amarillo')
    g.print(Tema.cortar(lema, cabecera.lema, w), x, y)
    local sy = y + lema:getHeight() + Tema.px(4)
    local punto = Tema.px(4)
    Tema.color(cabecera.colorSello or 'lineaOliva')
    g.circle('fill', x + punto, sy + sello:getHeight() / 2, punto)
    g.setFont(sello)
    Tema.color('textoHudTenue')
    g.print(Tema.cortar(sello, cabecera.sello, w - punto * 3), x + punto * 2 + Tema.px(6), sy)
end

--- Pestañas (C8) a todo el ancho; un punto rojo avisa de algo pendiente.
function Pendon:dibujarPestanas(x, y, w, pendientes)
    local alto = Tema.px(40)
    local ancho = w / #PESTANAS
    for k, p in ipairs(PESTANAS) do
        local px = math.floor(x + (k - 1) * ancho)
        local pw = math.floor(x + k * ancho) - px
        local activa = self.pestana == p.clave
        Acero.pestana(px, y, pw, alto, p.texto, activa, pendientes[p.clave])
        self.zonas[#self.zonas + 1] = {
            x = px,
            y = y,
            w = pw,
            h = alto,
            accion = { tipo = 'pestana', clave = p.clave },
        }
    end
    return alto
end

--- Dibuja la zona desplazable con su contenido y su barra de desplazamiento (C9).
function Pendon:dibujarLista(contenido, x, y, w, alto)
    local g = love.graphics
    self.maximo = math.max(0, contenido.alto - alto)
    self.desplazamiento = math.max(0, math.min(self.maximo, self.desplazamiento))
    self.lista = { x = x, y = y, w = w, h = alto }
    local function visible(py, ph)
        return py + ph > y and py < y + alto
    end
    local sx, sy, sw, sh = g.getScissor()
    g.intersectScissor(x - Tema.px(4), y, w + Tema.px(8), alto)
    local cursor = y - self.desplazamiento
    for _, pieza in ipairs(contenido.piezas) do
        if pieza.dibujar and visible(cursor, pieza.alto) then
            pieza.dibujar(x, cursor, w, visible)
        end
        cursor = cursor + pieza.alto
    end
    if sx then
        g.setScissor(sx, sy, sw, sh)
    else
        g.setScissor()
    end
    if self.maximo > 0 then
        Acero.desplazamiento(x + w + Tema.px(4), y, alto, alto, contenido.alto, self.desplazamiento / self.maximo)
    end
end

--- Tipo de barra de una vida de 0 a 100 (F5): verde, dorada o roja.
local function barraVida(parte)
    if parte > 0.5 then
        return 'energia'
    end
    if parte > 0.25 then
        return 'recurso'
    end
    return 'peligro'
end

--- Alto del bloque de vida (etiqueta, barra y, si la lleva, la fila de
-- reparación). `vida` = { valor (0 a 100), estado, colorEstado, reparar }.
local function altoVida(vida)
    local etiqueta = Acero.fuente('etiqueta')
    local alto = etiqueta:getHeight() + Tema.px(4) + Tema.px(14) + Tema.px(6)
    if vida.reparar then
        alto = alto + Tema.px(44) + Tema.px(6)
    end
    return alto
end

--- Bloque fijo de vida (diseno/territorio-y-capitales.md, 3.1 y 3.5): «VIDA»,
-- el estado, el valor, la barra de 0 a 100 y, en una ciudad tuya, la fila de
-- reparación (coste y días a la izquierda, botón a la derecha).
function Pendon:dibujarVida(vida, x, y, w)
    local g = love.graphics
    local etiqueta = Acero.fuente('subtitulo', 18)
    local negrita = Acero.fuente('cifra', 18)
    local pequena = Acero.fuente('etiqueta', 15)
    local valor = string.format('%d / 100', math.floor(vida.valor + 0.5))
    local anchoValor = negrita:getWidth(valor)
    g.setFont(etiqueta)
    Tema.color('amarillo')
    g.print('VIDA', x, y - Tema.px(2))
    local anchoEtiqueta = etiqueta:getWidth('VIDA')
    if vida.estado then
        g.setFont(pequena)
        Tema.color(vida.colorEstado or 'textoHudTenue')
        local libre = w - anchoEtiqueta - anchoValor - Tema.px(24)
        g.print(Tema.cortar(pequena, vida.estado, libre), x + anchoEtiqueta + Tema.px(12), y + Tema.px(2))
    end
    g.setFont(negrita)
    Tema.color('textoHud')
    g.print(valor, x + w - anchoValor, y - Tema.px(1))
    local by = y + etiqueta:getHeight() + Tema.px(2)
    local bh = Tema.px(14)
    local parte = math.max(0, math.min(1, vida.valor / 100))
    Acero.barra(x, by, w, bh, parte, barraVida(parte), (vida.pendiente or 0) / 100)
    local r = vida.reparar
    if not r then
        return
    end
    local fy = by + bh + Tema.px(8)
    local bh2 = Tema.px(40)
    local anchoBoton = math.max(Tema.px(150), Tema.anchoBoton(r.boton, true))
    Tema.boton(r.boton, x + w - anchoBoton, fy, anchoBoton, bh2, true)
    if r.boton.activo ~= false then
        self.zonas[#self.zonas + 1] =
            { x = x + w - anchoBoton, y = fy, w = anchoBoton, h = bh2, accion = r.boton.accion }
    end
    g.setFont(pequena)
    Tema.color(r.colorDetalle or 'textoHudTenue')
    local libre = w - anchoBoton - Tema.px(10)
    local lineas = r.detalle
    local altoLinea = pequena:getHeight()
    local ty = math.floor(fy + (bh2 - altoLinea * #lineas) / 2)
    for k, linea in ipairs(lineas) do
        g.print(Tema.cortar(pequena, linea, libre), x, ty + (k - 1) * altoLinea)
    end
end

--- Coloca y dibuja un panel completo: cabecera, identidad, cifras, vida,
-- avisos, botones, pestañas (si las lleva) y la lista. `datos` = { clave,
-- colorPais, cabecera, cifras, vida, avisos, botones, pestanas, pendientes,
-- contenido(ancho) }.
function Pendon:dibujarPendon(datos, arriba)
    -- Gris caqui claro con texto negro (como el tooltip del original).
    Tema.modoClaro = true
    local ok, fallo = pcall(self.dibujarPendonClaro, self, datos, arriba)
    Tema.modoClaro = false
    if not ok then
        error(fallo, 0)
    end
end

function Pendon:dibujarPendonClaro(datos, arriba)
    local g = love.graphics
    local w, h = g.getDimensions()
    if self.clave ~= datos.clave then
        self.clave = datos.clave
        self.desplazamiento = 0
        -- Cambió el panel: vaciar los sliders de sacar tropas (dueño 2026-09-29).
        self.sacar.soldados = 0
        self.sacar.lanzacohetes = 0
    end
    self.zonas = {}
    self.ayuda = nil
    local compacta = Tema.compacta()
    local ancho = Tema.px(compacta and 420 or 480)
    local x = w - Tema.px(16) - ancho
    local y = arriba or Tema.px(80)
    local relleno = Tema.px(12)
    -- El contenido va dentro del marco de la pieza (su relleno interior).
    local _, _, cw0 = Acero.contenido('panel_acero_cabecera', x, y, ancho, Tema.px(400))
    local cw = cw0 - relleno * 2
    local contenido = datos.contenido(cw - Tema.px(12))
    -- Parte fija del interior.
    local altoAviso = Tema.px(34)
    local hueco = Tema.px(8)
    local fijo = relleno + altoIdentidad() + hueco
    if datos.cifras then
        fijo = fijo + altoCifras() + hueco
    end
    if datos.vida then
        fijo = fijo + altoVida(datos.vida) + Tema.px(6)
    end
    fijo = fijo + #datos.avisos * (altoAviso + Tema.px(6))
    local altoBoton = Tema.px(44)
    if datos.botones and #datos.botones > 0 then
        fijo = fijo + #datos.botones * (altoBoton + Tema.px(8))
    end
    if datos.pestanas then
        fijo = fijo + Tema.px(40) + hueco
    end
    fijo = fijo + relleno
    local cabecera = Tema.px(50)
    local marcoBajo = Tema.px(8)
    -- Como mucho hasta la fila de hexágonos de abajo.
    local altoMax = h - y - Tema.px(96 + 16 + 8)
    local altoLista = math.max(Tema.px(60), math.min(contenido.alto, altoMax - cabecera - marcoBajo - fijo))
    local alto = cabecera + fijo + altoLista + marcoBajo
    local _, _, _, _, cierre = Acero.panel(x, y, ancho, alto, { titulo = datos.cabecera.nombre, cerrar = true })
    self.rect = { x = x, y = y, w = ancho, h = alto }
    if cierre then
        self.zonas[#self.zonas + 1] =
            { x = cierre.x, y = cierre.y, w = cierre.w, h = cierre.h, accion = { tipo = 'cerrar' } }
    end
    local cx = x + math.floor((ancho - cw) / 2)
    local cursor = y + cabecera + relleno
    -- Franja del color del país bajo la cabecera.
    Tema.color(datos.colorPais)
    g.rectangle('fill', cx, y + cabecera + Tema.px(3), cw, Tema.px(3))
    cursor = cursor + Tema.px(4)
    self:dibujarIdentidad(datos.cabecera, cx, cursor, cw)
    cursor = cursor + altoIdentidad() + hueco
    if datos.cifras then
        dibujarCifras(datos.cifras, cx, cursor, cw)
        cursor = cursor + altoCifras() + hueco
    end
    if datos.vida then
        self:dibujarVida(datos.vida, cx, cursor, cw)
        cursor = cursor + altoVida(datos.vida) + Tema.px(6)
    end
    for _, aviso in ipairs(datos.avisos) do
        dibujarAviso(aviso, cx, cursor, cw, altoAviso)
        cursor = cursor + altoAviso + Tema.px(6)
    end
    -- Botones de órdenes (modo jugador: «Atacar a ...»), a todo lo ancho.
    if datos.botones and #datos.botones > 0 then
        for _, b in ipairs(datos.botones) do
            Tema.boton(b, cx, cursor, cw, altoBoton)
            if b.activo ~= false then
                self.zonas[#self.zonas + 1] = { x = cx, y = cursor, w = cw, h = altoBoton, accion = b.accion }
            end
            cursor = cursor + altoBoton + Tema.px(8)
        end
    end
    if datos.pestanas then
        cursor = cursor + self:dibujarPestanas(cx, cursor, cw, datos.pendientes or {}) + hueco
    end
    self:dibujarLista(contenido, cx, cursor, cw - Tema.px(12), altoLista)
end

--- «2 de metal, 1 de petróleo y 15» con el coste de reparar `puntos`.
local function textoCoste(coste)
    return string.format(
        '%s metal · %s petróleo · %s dinero',
        Tema.numero(coste.metal),
        Tema.numero(coste.petroleo),
        Tema.numero(coste.dinero)
    )
end

--- Puntos de vida que la nación puede pagar ahora (guardado y afuera, F4).
local function puntosPagables(nacion)
    local porPunto = Simulacion.costeReparacion(1)
    local puntos = math.huge
    for _, recurso in ipairs({ 'metal', 'petroleo', 'dinero' }) do
        if porPunto[recurso] > 0 then
            puntos = math.min(puntos, math.floor(Simulacion.disponible(nacion, recurso) / porPunto[recurso]))
        end
    end
    return math.max(0, puntos)
end

--- Datos del bloque de vida de una ciudad. Con `propia` (la gobierna el
-- jugador), la fila «Reparar» con su coste y sus días (3.5): encarga lo que
-- falta hasta 100, o lo que alcance a pagar.
local function vidaDeCiudad(sim, c, nacion, propia)
    local valor = Simulacion.vidaSitio(c)
    local pendiente = c.reparacion or 0
    local vida = { valor = valor, pendiente = pendiente }
    local sitiada = sim:sitiada(c)
    if pendiente > 0 and sitiada then
        vida.estado, vida.colorEstado = 'reparación parada: sitiada', 'rojoTexto'
    elseif pendiente > 0 then
        local dias = Simulacion.diasReparacion(c)
        vida.estado = string.format(
            'reparando +%d al día · %d %s',
            Simulacion.ritmoReparacion(c),
            dias,
            dias == 1 and 'día' or 'días'
        )
        vida.colorEstado = 'amarillo'
    elseif sitiada then
        vida.estado, vida.colorEstado = 'sitiada', 'rojoTexto'
    end
    if not propia then
        return vida
    end
    local falta = math.floor(Simulacion.vidaCiudad.maxima - valor - pendiente)
    if falta < 1 then
        return vida
    end
    local puntos = math.min(falta, puntosPagables(nacion))
    local boton = { texto = 'Reparar', tipo = 'principal', activo = puntos >= 1 }
    local detalle
    local colorDetalle
    if puntos >= 1 then
        local coste = Simulacion.costeReparacion(puntos)
        boton.texto = string.format('Reparar +%d', puntos)
        boton.precio = coste.dinero
        local dias = math.ceil((pendiente + puntos) / Simulacion.ritmoReparacion(c))
        detalle = {
            string.format('%s metal · %s petróleo', Tema.numero(coste.metal), Tema.numero(coste.petroleo)),
            string.format('%d %s%s', dias, dias == 1 and 'día' or 'días', sitiada and ' (parada: sitiada)' or ''),
        }
        colorDetalle = sitiada and 'rojoTexto' or nil
        boton.accion = function()
            sim:ejecutar({ tipo = 'reparar', nacion = nacion.id, ciudad = c.id, puntos = puntos })
        end
    else
        detalle = { 'No alcanza: cada punto cuesta', textoCoste(Simulacion.costeReparacion(1)) }
        colorDetalle = 'rojoTexto'
    end
    vida.reparar = { boton = boton, detalle = detalle, colorDetalle = colorDetalle }
    return vida
end

--- Pendón de una ciudad. `ciudad` es la ciudad dibujable del mundo (con
-- `region`); los datos vivos salen de la simulación. `botones` (opcional):
-- órdenes { texto, tipo, activo, accion = función } bajo los avisos. Con
-- `propia` (la gobierna el jugador), el bloque de vida lleva «Reparar».
function Pendon:dibujarCiudad(sim, ciudad, arriba, botones, propia, mira)
    local c = sim:ciudad(ciudad.region)
    local nacion = c and sim:nacion(c.nacion)
    if not nacion then
        self.rect = nil
        return
    end
    local orden = Simulacion.ordenes[nacion.orden]
    local capital = nacion.capital == ciudad.region
    local ciudades = #sim:ciudadesDe(nacion.id)
    local nivel = { 'NIVEL', tostring(c.nivel or 1) }
    if c.mejora then
        local dias = c.mejora.hasta - sim.estado.dia
        local total = (Simulacion.niveles[c.mejora.nivel] or {}).dias or dias
        nivel[3] = string.format('a nivel %d en %d días', c.mejora.nivel, dias)
        nivel[4] = math.max(0, math.min(1, 1 - dias / math.max(1, total)))
    elseif nacion.plan and nacion.plan.ciudad == c.id then
        nivel[3] = 'ahorra para subir'
    end
    -- El tesoro es lo de la bóveda; lo que no cabe queda afuera (3.4) y se
    -- ve al lado, en ámbar: es lo que se llevan si saquean la capital.
    local almacen = sim:almacenDe(nacion.id)
    -- Ajena: su poder y su arsenal, solo con informe (interfaz/inteligencia.lua).
    local oculta = Inteligencia.oculto(mira, c.nacion)
    local informe = oculta and Inteligencia.informe(sim, mira, c.id)
    local tesoro = { 'TESORO', Tema.numero(almacen.dinero), color = 'amarillo' }
    if almacen.afuera.dinero >= 0.5 then
        tesoro[3] = '+' .. Tema.numero(almacen.afuera.dinero) .. ' afuera'
        tesoro.colorExtra = 'amarillo'
    end
    self:dibujarPendon({
        clave = ciudad,
        ancho = 380,
        colorPais = nacion.color,
        cabecera = {
            nombre = ciudad.nombre,
            capital = capital,
            lema = (capital and 'Capital de ' or 'Ciudad de ') .. nacion.nombre,
            sello = string.format(
                '%s · %d %s',
                orden.nombre:upper(),
                ciudades,
                ciudades == 1 and 'CIUDAD' or 'CIUDADES'
            ),
            colorSello = orden.color,
        },
        cifras = {
            nivel,
            { 'POBLACIÓN', Tema.numero(c.poblacion) },
            oculta and { 'SOLDADOS', informe and Tema.numero((informe.tropas or {}).soldados or 0) or '?' }
                or { 'SOLDADOS', Tema.numero(c.soldados) },
            tesoro,
        },
        vida = not oculta and vidaDeCiudad(sim, c, nacion, propia) or nil,
        avisos = avisosDe(sim, c, nacion),
        botones = botones,
        pestanas = true,
        pendientes = { ejercito = hayRecuperacion(c) },
        contenido = function(ancho)
            local contenido = nuevoContenido()
            if oculta and (self.pestana == 'resumen' or self.pestana == 'ejercito') then
                self:guarnicionInformada(contenido, sim, mira, c)
            elseif self.pestana == 'resumen' then
                self:resumen(contenido, sim, c, nacion, ancho)
            elseif self.pestana == 'ejercito' then
                self:ejercito(contenido, sim, c, nacion)
            elseif self.pestana == 'nacion' then
                self:nacion(contenido, sim, c, nacion, oculta)
            else
                self:relaciones(contenido, sim, nacion)
            end
            return contenido
        end,
    }, arriba)
end

--- Pendón estrecho de una instalación o base (P3), sin pestañas. `botones`
-- (opcional): órdenes como las del pendón de una ciudad.
function Pendon:dibujarInstalacion(sim, id, arriba, botones, mira)
    local i = sim:instalacion(id)
    local nacion = i and sim:nacion(i.nacion)
    if not nacion then
        self.rect = nil
        return
    end
    local sello
    if i.tipo == 'base' then
        sello = 'BASE MILITAR'
    elseif i.tipo == 'campamento' then
        sello = 'CAMPAMENTO · PUESTO DE ACOPIO'
    elseif i.tipo == 'bandera' then
        sello = 'BANDERA · SOLO TERRITORIO'
    else
        sello = i.tipo:upper()
    end
    local nombre = (Simulacion.nombreInstalacion(sim, i):gsub('^una? ', ''))
    nombre = nombre:sub(1, 1):upper() .. nombre:sub(2)
    local avisos = {}
    if (i.atacadaDia or -99) >= sim.estado.dia - 2 then
        local quien = i.atacadaPor and sim:nacion(i.atacadaPor)
        avisos[1] = {
            tipo = 'guerra',
            texto = quien and ('Atacada por ' .. quien.nombre) or 'Bajo ataque',
            plazo = string.format('día %d', i.atacadaDia),
        }
    end
    -- Ajena: la vida también es secreta (va en la guarnición, del informe).
    local vida = not Inteligencia.oculto(mira, i.nacion) and { valor = Simulacion.vidaSitio(i) } or nil
    self:dibujarPendon({
        clave = 'instalacion' .. id,
        ancho = 320,
        colorPais = nacion.color,
        cabecera = { nombre = nombre, lema = nacion.nombre, sello = sello, colorSello = nacion.color, tamano = 22 },
        vida = vida,
        avisos = avisos,
        botones = botones,
        contenido = function(ancho)
            local contenido = nuevoContenido()
            if i.progreso < 1 then
                barra(contenido, 'En obras', string.format('%d %%', i.progreso * 100), i.progreso, 'caquiPestana')
            end
            if i.tipo == 'bandera' then
                self:contenidoBandera(contenido, i)
                return contenido
            end
            if Inteligencia.oculto(mira, i.nacion) then
                -- Ajena: solo lo que dijo el último informe (interfaz/inteligencia.lua).
                self:guarnicionInformada(contenido, sim, mira, i)
                return contenido
            end
            barra(contenido, 'Fortificación', string.format('%d %%', i.fortificacion * 100), i.fortificacion, 'verde')
            titulo(contenido, 'GUARNICIÓN')
            fila(contenido, 'Soldados', Tema.numero(i.soldados))
            fila(contenido, 'Interceptores', Tema.numero(i.interceptores or 0))
            fila(contenido, 'Aviones', Tema.numero(i.aviones or 0))
            -- Dispara del polvorín de la ciudad que la abastece.
            local p = sim:polvorin(i.id)
            if p then
                fila(
                    contenido,
                    'Polvorín (ciudad)',
                    string.format('%s · %s', Tema.numero(p.balas), Tema.numero(p.misiles))
                )
            end
            if i.tipo == 'base' then
                contenido.hueco(Tema.px(8))
                defensa(contenido, 'Lanzacohetes', {
                    listas = i.lanzacohetes or 0,
                    fuera = lanzacohetesFuera(sim, i),
                }, Simulacion.topeLanzacohetes(i), ancho)
            end
            if i.tipo == 'campamento' then
                nota(contenido, 'Da territorio; sus grupos salen y entregan aquí')
            end
            if i.progreso >= 1 then
                nota(contenido, string.format('Operativa desde el día %d', i.inicio or 0))
            end
            return contenido
        end,
    }, arriba)
end

--- Guarnición de un sitio ajeno según el último informe de `mira`: poder,
-- tropas y defensas con su antigüedad, o «Desconocido · Explorar».
function Pendon:guarnicionInformada(contenido, sim, mira, s)
    local inf = Inteligencia.informe(sim, mira, s.id)
    titulo(contenido, 'GUARNICIÓN')
    if not inf then
        fila(contenido, 'Poder', Inteligencia.textoDesconocido, 'textoHudTenue')
        fila(contenido, 'Vida', Inteligencia.textoDesconocido, 'textoHudTenue')
        nota(contenido, 'Manda exploradores para saber su poder y sus tropas')
        return
    end
    fila(contenido, 'Informe', Inteligencia.hace(sim, inf.dia))
    fila(contenido, 'Poder', Tema.numero(Simulacion.poderRedondeado(inf.poder or 0)))
    fila(contenido, 'Vida', string.format('%d / 100', math.floor(Inteligencia.vidaInforme(inf) + 0.5)))
    local t = inf.tropas or {}
    fila(contenido, 'Soldados', Tema.numero(t.soldados or 0))
    fila(contenido, 'Lanzacohetes', Tema.numero(t.lanzacohetes or 0))
    local d = inf.defensas or {}
    for _, par in ipairs({
        { 'misiles', 'Misiles' },
        { 'interceptores', 'Interceptores' },
        { 'aviones', 'Aviones' },
        { 'baterias', 'Baterías' },
    }) do
        if (d[par[1]] or 0) > 0 then
            fila(contenido, par[2], Tema.numero(d[par[1]]))
        end
    end
    if (d.fortificacion or 0) > 0 then
        fila(contenido, 'Fortificación', string.format('%d %%', d.fortificacion * 100))
    end
end

--- Pendón estrecho de un yacimiento (diseno/recoleccion-y-batallas.md,
-- 3.2 y 3.5): lo que queda de su reserva, si está cerrada, de quién es la
-- tierra (y el +25 % de su dueño) y quién recolecta ahora. `botones`
-- (opcional): «Recolectar» y, si hay recolectores ajenos, «Atacar».
-- `mira`: la nación del jugador (nil si solo se mira).
function Pendon:dibujarYacimiento(sim, id, arriba, botones, mira)
    local y = sim:mina(id)
    if not y then
        self.rect = nil
        return
    end
    local recurso = Simulacion.recursos[y.tipo]
    local nombreRecurso = NOMBRE_RECURSO[y.tipo] or y.tipo
    local duena = y.dueno and sim:nacion(y.dueno)
    local colorPais = duena and duena.color or { 0.55, 0.52, 0.48 }
    local dia = sim.estado.dia
    local avisos = {}
    if y.batalla then
        local b = sim:estadoBatalla(y.batalla)
        avisos[#avisos + 1] = {
            tipo = 'guerra',
            texto = 'Batalla en la mina',
            plazo = b and string.format('día %d', b.dias + 1) or '',
        }
    end
    if y.cerrada then
        avisos[#avisos + 1] = {
            tipo = 'escasez',
            texto = 'Agotada: cerrada',
            plazo = string.format('%d días', y.diasCerrada),
        }
    end
    self:dibujarPendon({
        clave = 'yacimiento' .. id,
        ancho = 320,
        colorPais = colorPais,
        cabecera = {
            nombre = recurso and (recurso.nombre:sub(1, 1):upper() .. recurso.nombre:sub(2)) or nombreRecurso,
            lema = duena and ('Tierra de ' .. duena.nombre) or 'Tierra de nadie',
            sello = 'YACIMIENTO · ' .. nombreRecurso:upper(),
            colorSello = colorPais,
            tamano = 22,
        },
        avisos = avisos,
        botones = botones,
        contenido = function()
            local contenido = nuevoContenido()
            if y.cerrada then
                barra(contenido, 'Queda', '0', 0, 'rojo')
                nota(contenido, string.format('Vuelve llena el día %d', y.agotadaHasta))
            else
                local parte = y.queda / math.max(1, y.reserva)
                barra(
                    contenido,
                    'Queda',
                    Tema.numero(y.queda) .. ' de ' .. Tema.numero(y.reserva),
                    parte,
                    parte > 0.5 and 'amarillo' or (parte > 0.2 and 'amarillo' or 'rojo')
                )
            end
            titulo(contenido, 'MINA')
            fila(contenido, 'Riqueza', Tema.numero(y.riqueza), 'amarillo')
            if y.tipo == 'oro' then
                fila(contenido, 'Cada unidad', Tema.numero(Simulacion.yacimientos.precioOro) .. ' de dinero')
            end
            if duena then
                local bonus =
                    string.format('+%d %% para %s', (Simulacion.recoleccion.ventajaTerritorio - 1) * 100, duena.nombre)
                fila(contenido, 'Bonus', Tema.cortar(Tema.fuente('sansNegrita', 15), bonus, Tema.px(190)), 'verde')
            else
                nota(contenido, 'Sin dueño: nadie tiene bonus aquí')
            end
            titulo(contenido, 'RECOLECTAN')
            if #y.recolectores == 0 then
                nota(contenido, 'Nadie: está libre')
            end
            for _, r in ipairs(y.recolectores) do
                local n = sim:nacion(r.nacion)
                local etiqueta = n and n.nombre or '?'
                if r.nacion == mira then
                    etiqueta = etiqueta .. ' (tú)'
                end
                local grupos = #r.grupos == 1 and '1 grupo' or (#r.grupos .. ' grupos')
                fila(
                    contenido,
                    etiqueta,
                    grupos .. ' · trabajo ' .. Tema.numero(r.trabajo),
                    r.nacion == y.bonus and 'verde' or nil
                )
            end
            if not y.cerrada and y.queda < y.reserva and #y.recolectores == 0 then
                nota(contenido, 'Sin nadie, recupera el 1 % al día')
            end
            if dia < (y.agotadaHasta or 0) then
                nota(contenido, 'Cerrada: no admite órdenes de recolectar')
            end
            return contenido
        end,
    }, arriba)
end

--- Lo que dice el pendón de una bandera (3.7): solo da territorio, se paga
-- cada día y se repara sola si no la atacan.
function Pendon:contenidoBandera(contenido, i)
    local reglas = Simulacion.bandera
    titulo(contenido, 'BANDERA', i.progreso >= 1)
    local lado = Simulacion.bloques.bandera
    fila(contenido, 'Territorio', string.format('%d x %d celdas', lado, lado))
    fila(contenido, 'Mantenimiento', Tema.decimal(-reglas.mantenimiento) .. ' al día', 'amarillo')
    nota(contenido, 'Solo da territorio: ni produce ni recluta')
    nota(contenido, 'Sin pagar, pierde 5 de vida al día')
    if i.progreso >= 1 then
        nota(contenido, string.format('Plantada el día %d', i.inicio or 0))
    end
end

--- La ayuda del medidor bajo el ratón (se dibuja encima de todo).
function Pendon:dibujarAyuda()
    if self.ayuda and self.rect then
        local mx, my = love.mouse.getPosition()
        Tema.ayuda(self.ayuda, mx, my)
    end
end

--- Primer botón con comando visible (para el modo captura `acelerar`, que
-- hace clic en él como lo haría el ratón).
function Pendon:primerBoton()
    for _, z in ipairs(self.zonas) do
        if type(z.accion) == 'function' then
            return z
        end
    end
    return nil
end

--- Olvida el pendón (no hay nada que mostrar este cuadro).
function Pendon:ocultar()
    self.rect = nil
    self.lista = nil
    self.zonas = {}
    self.ayuda = nil
end

function Pendon:encima(x, y)
    local r = self.rect
    return r and Tema.dentro(x, y, r.x, r.y, r.w, r.h) or false
end

--- Rueda sobre el pendón: desplaza la lista. Devuelve true si la usó.
function Pendon:rueda(x, y, dy)
    if not self:encima(x, y) or self.maximo <= 0 then
        return false
    end
    local paso = Tema.px(22) * FILAS_POR_PASO
    self.desplazamiento = math.max(0, math.min(self.maximo, self.desplazamiento - dy * paso))
    return true
end

--- Clic en el pendón. Devuelve nil si cayó fuera; si cayó dentro, la acción
-- para main.lua ({ tipo = 'cerrar' }, { tipo = 'nacion', id }) o
-- { tipo = 'nada' } (el clic no pasa al mapa).
function Pendon:pulsar(x, y)
    if not self:encima(x, y) then
        return nil
    end
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            if type(z.accion) == 'function' then
                z.accion()
                return { tipo = 'nada' }
            end
            if z.accion.tipo == 'pestana' then
                if self.pestana ~= z.accion.clave then
                    self.pestana = z.accion.clave
                    self.desplazamiento = 0
                end
                return { tipo = 'nada' }
            end
            return z.accion
        end
    end
    return { tipo = 'nada' }
end

return Pendon
