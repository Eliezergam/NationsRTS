-- Control táctico de la escena de batalla (estilo RTS, como el mapa 2D de
-- interfaz/ejercito.lua): selección y órdenes a las unidades del jugador.
--
--   Selección  clic izquierdo elige solo esa unidad; Mayús + clic la suma o
--              la quita; arrastrar con el izquierdo dibuja un cuadro y elige
--              las propias de dentro (con Mayús, las suma); doble clic elige
--              todas las propias de ese tipo que se ven; T y L eligen todos
--              los tanques o lanzacohetes (con Mayús, los suman).
--   Órdenes    clic derecho corto (sin arrastrar: arrastrar el derecho es
--              mirar) sobre el terreno = MOVER allí, en formación y por
--              terreno transitable (ruta y marcador visibles); sobre un
--              enemigo = ATACARLO; H = MANTENER POSICIÓN. Lo que no tiene
--              orden sigue su IA de siempre.
--
-- No toca la simulación ni decide bajas: guarda la selección y da órdenes a
-- las unidades de `Tropas` (`Tropas:darOrden`). Se dibuja en 2D encima de la
-- escena, proyectado sobre el suelo: el anillo de datos de cada elegida y la
-- cinta holográfica de su ruta (batalla/marcas_holo.lua).

local Ordenes = require('batalla.ordenes')
local Camara = require('batalla.camara')
local MarcasHolo = require('batalla.marcas_holo')

local Control = {}
Control.__index = Control

Control.radioClick = 28
Control.tiempoDoble = 0.35 -- s entre los dos clics de un doble clic
Control.duracionMarca = 1.6 -- s que dura el aviso de una orden en el terreno
Control.radioAnillo = { tanque = 95, lanzacohetes = 130 } -- px del mundo
Control.radioMarcador = 170 -- px del mundo del marcador de destino
Control.verde = MarcasHolo.menta -- el de la selección y las órdenes (#6DFFC4)
Control.rojo = { 0.96, 0.42, 0.32 }

--- Control para las tropas y la cámara de una escena.
function Control.nuevo(tropas, camara)
    local self = setmetatable({}, Control)
    self.tropas = tropas
    self.camara = camara
    self.seleccion = {}
    self.elegidaDesde = {} -- unidad -> love.timer.getTime() al elegirla (entrada del anillo)
    self.cuenta = 0
    self.proyectados = {}
    self.ordenes = Ordenes.nuevas(tropas)
    tropas.rutas = self.ordenes -- las órdenes de atacar se acercan por ellas
    self.propio = 1 -- bando del jugador (1 atacante, 2 defensor)
    self.marcas = {} -- órdenes recién dadas: { tipo, x, y, ruta, blanco, t }
    self.ultimo = nil -- último clic sobre una unidad (doble clic)
    self.holo = MarcasHolo.nuevas(self)
    return self
end

--- El bando que manda el jugador.
function Control:usarBando(indice)
    self.propio = indice or 1
end

--- ¿Es `u` una unidad del jugador que se puede elegir?
function Control:propia(u)
    return u ~= nil and not u.muerto and not u.retirado and u.bando == self.propio
end

--- Proyecta un punto del mundo a pantalla. Devuelve x, y, profundidad, si se
-- ve dentro de la pantalla (`visible`) y si queda delante de la cámara.
function Control:proyectar(x, y, z, salida)
    local m = self.camara.vistaProyeccion
    local ancho, alto = love.graphics.getDimensions()
    local cx = m[1] * x + m[2] * y + m[3] * z + m[4]
    local cy = m[5] * x + m[6] * y + m[7] * z + m[8]
    local cz = m[9] * x + m[10] * y + m[11] * z + m[12]
    local cw = m[13] * x + m[14] * y + m[15] * z + m[16]

    if math.abs(cw) < 0.00001 then
        return nil
    end

    local nx = cx / cw
    local ny = cy / cw
    local nz = cz / cw
    local visible = cw > 0 and nx >= -1 and nx <= 1 and ny >= -1 and ny <= 1 and nz >= -1 and nz <= 1

    salida = salida or {}
    salida.x = (nx * 0.5 + 0.5) * ancho
    salida.y = (1 - (ny * 0.5 + 0.5)) * alto
    salida.z = nz
    salida.visible = visible
    salida.delante = cw > 0 and nz <= 1
    salida.w = cw -- profundidad en la vista (px del mundo), para tapar con la escena
    return salida
end

--- Unidad bajo el punto de pantalla: la que toca el rayo del `selector`
-- (su volumen en 3D, batalla/dream/rayos.lua) o, si no toca ninguna, la
-- más cercana a la cámara de las que tienen su centro a menos de
-- `radioClick` px en pantalla (un clic al lado de una unidad la elige).
function Control:unidadEn(x, y)
    if self.selector then
        local tocada = self.selector(x, y)
        if tocada then
            return tocada
        end
    end
    local mejor, mejorD, mejorZ
    local salida = self.proyectados
    for _, unidad in ipairs(self.tropas.unidades) do
        if not unidad.muerto then
            local p = self:proyectar(unidad.x, unidad.y, unidad.z + 18, salida)
            if p and p.visible then
                local dx = p.x - x
                local dy = p.y - y
                local d = dx * dx + dy * dy
                if d <= Control.radioClick * Control.radioClick and (not mejor or p.z < mejorZ or d < mejorD * 0.5) then
                    mejor = unidad
                    mejorD = d
                    mejorZ = p.z
                end
            end
        end
    end
    return mejor
end

function Control:usarSelector(selector)
    self.selector = selector
end

-- Selección -------------------------------------------------------------------------------------

function Control:vaciar()
    for unidad in pairs(self.seleccion) do
        self.seleccion[unidad] = nil
        self.elegidaDesde[unidad] = nil
    end
    self.cuenta = 0
end

function Control:seleccionada(unidad)
    return self.seleccion[unidad] == true
end

--- Selecciona una unidad. Con `sumar`, alterna esa unidad sin borrar las demás.
function Control:seleccionar(unidad, sumar)
    if not sumar then
        self:vaciar()
    end

    if not unidad then
        return
    end

    if sumar and self.seleccion[unidad] then
        self.seleccion[unidad] = nil
        self.cuenta = self.cuenta - 1
        return
    end

    if not self.seleccion[unidad] then
        self.seleccion[unidad] = true
        self.elegidaDesde[unidad] = love.timer.getTime()
        self.cuenta = self.cuenta + 1
    end
end

--- Suma `unidad` a la selección (sin alternar).
function Control:anadir(unidad)
    if not self.seleccion[unidad] then
        self.seleccion[unidad] = true
        self.elegidaDesde[unidad] = love.timer.getTime()
        self.cuenta = self.cuenta + 1
    end
end

--- Las unidades elegidas, en orden de entrada (estable).
function Control:lista()
    local out = {}
    for unidad in pairs(self.seleccion) do
        out[#out + 1] = unidad
    end
    table.sort(out, function(a, b)
        return a.numero < b.numero
    end)
    return out
end

--- Clic izquierdo en (x, y): elige solo esa unidad propia (con `sumar`, la
-- suma o la quita); doble clic, todas las propias de su tipo a la vista. Un
-- clic en el vacío o en un enemigo, sin `sumar`, deja la selección vacía.
function Control:click(x, y, sumar, ahora)
    ahora = ahora or love.timer.getTime()
    local u = self:unidadEn(x, y)
    if not self:propia(u) then
        if not sumar then
            self:vaciar()
        end
        self.ultimo = nil
        return
    end
    local ultimo = self.ultimo
    -- Como en el mapa 2D: con Mayús no hay doble clic (el segundo, quita).
    local doble = not sumar and ultimo and ultimo.u == u and ahora - ultimo.t <= Control.tiempoDoble
    if doble then
        if not sumar then
            self:vaciar()
        end
        self:tipoAVista(u.tipo)
        self.ultimo = nil
        return
    end
    self:seleccionar(u, sumar)
    self.ultimo = { u = u, t = ahora }
end

--- Suma a la selección las unidades propias de `tipo` que se ven en pantalla.
function Control:tipoAVista(tipo)
    local salida = self.proyectados
    for _, u in ipairs(self.tropas.unidades) do
        if u.tipo == tipo and self:propia(u) then
            local p = self:proyectar(u.x, u.y, u.z + 18, salida)
            if p and p.visible then
                self:anadir(u)
            end
        end
    end
end

--- Todas las unidades propias de `tipo` en el campo (con `sumar`, se suman).
function Control:todasDeTipo(tipo, sumar)
    if not sumar then
        self:vaciar()
    end
    for _, u in ipairs(self.tropas.unidades) do
        if u.tipo == tipo and self:propia(u) then
            self:anadir(u)
        end
    end
end

--- Cuadro de selección mientras se arrastra (nil: ninguno).
function Control:cuadro(x0, y0, x1, y1)
    if not x0 then
        self.caja = nil
        return
    end
    self.caja = { x0 = math.min(x0, x1), y0 = math.min(y0, y1), x1 = math.max(x0, x1), y1 = math.max(y0, y1) }
end

--- Elige las unidades propias que caen en el cuadro (con `sumar`, las suma).
function Control:elegirCaja(x0, y0, x1, y1, sumar)
    if not sumar then
        self:vaciar()
    end
    local ax, ay, bx, by = math.min(x0, x1), math.min(y0, y1), math.max(x0, x1), math.max(y0, y1)
    local salida = self.proyectados
    for _, u in ipairs(self.tropas.unidades) do
        if self:propia(u) then
            local p = self:proyectar(u.x, u.y, u.z + 12, salida)
            if p and p.visible and p.x >= ax and p.x <= bx and p.y >= ay and p.y <= by then
                self:anadir(u)
            end
        end
    end
    self.caja = nil
end

-- Órdenes ---------------------------------------------------------------------------------------

--- Deja constancia de una orden para dibujarla un rato.
function Control:marcar(marca)
    marca.t = love.timer.getTime()
    self.marcas[#self.marcas + 1] = marca
    if #self.marcas > 8 then
        table.remove(self.marcas, 1)
    end
end

--- Clic derecho corto en (sx, sy): sobre un enemigo, la selección lo ataca;
-- sobre el terreno, va allí en formación. Devuelve 'atacar', 'mover',
-- 'sinRuta' o nil (sin selección o sin suelo bajo el ratón).
function Control:ordenar(sx, sy)
    if self.cuenta == 0 then
        return nil
    end
    local elegidas = self:lista()
    local objetivo = self:unidadEn(sx, sy)
    if objetivo and not objetivo.muerto and objetivo.bando ~= self.propio then
        for _, u in ipairs(elegidas) do
            self.tropas:darOrden(u, { tipo = 'atacar', blanco = objetivo })
        end
        self:marcar({ tipo = 'atacar', blanco = objetivo })
        return 'atacar'
    end
    local w, h = love.graphics.getDimensions()
    local x, y = Ordenes.puntoEnPantalla(self.camara, self.tropas.suelo, sx, sy, w, h, Camara.campo)
    if not x then
        return nil
    end
    return self:moverA(elegidas, x, y)
end

--- Manda `unidades` a (x, y) del mundo en formación por terreno transitable.
function Control:moverA(unidades, x, y)
    local cx, cy = 0, 0
    for _, u in ipairs(unidades) do
        cx, cy = cx + u.x, cy + u.y
    end
    cx, cy = cx / #unidades, cy / #unidades
    local ordenes = self.ordenes
    local ruta = ordenes:ruta(cx, cy, x, y)
    if not ruta then
        self:marcar({ tipo = 'sinRuta', x = x, y = y })
        return 'sinRuta'
    end
    local destino = ruta[#ruta]
    local previo = ruta[#ruta - 1] or { x = cx, y = cy }
    local rumbo = math.atan2(destino.y - previo.y, destino.x - previo.x)
    if (destino.x - previo.x) ^ 2 + (destino.y - previo.y) ^ 2 < 1 then
        rumbo = math.atan2(destino.y - cy, destino.x - cx)
    end
    local huecos = ordenes:formacion(unidades, destino.x, destino.y, rumbo)
    for _, u in ipairs(unidades) do
        -- Los puntos intermedios de la ruta del grupo, desde el más cercano a
        -- la unidad; si hasta él no hay recta, su propio camino.
        local intermedios = {}
        local desde, mejorD = 2, math.huge
        for k = 2, #ruta - 1 do
            local d = (ruta[k].x - u.x) ^ 2 + (ruta[k].y - u.y) ^ 2
            if d < mejorD then
                desde, mejorD = k, d
            end
        end
        for k = desde, #ruta - 1 do
            intermedios[#intermedios + 1] = { x = ruta[k].x, y = ruta[k].y }
        end
        local hueco = huecos[u]
        local primero = intermedios[1] or hueco
        local puntos = {}
        if not ordenes:recta(u.x, u.y, primero.x, primero.y) then
            local propia = ordenes:ruta(u.x, u.y, primero.x, primero.y)
            for k = 2, propia and #propia - 1 or 0 do
                puntos[#puntos + 1] = propia[k]
            end
        end
        for _, p in ipairs(intermedios) do
            puntos[#puntos + 1] = p
        end
        puntos[#puntos + 1] = { x = hueco.x, y = hueco.y }
        -- Suave (tensada y en curva): el vehículo la sigue tal cual se dibuja.
        table.insert(puntos, 1, { x = u.x, y = u.y })
        puntos = ordenes:suavizar(puntos)
        table.remove(puntos, 1)
        self.tropas:darOrden(u, { tipo = 'mover', ruta = puntos, destino = hueco, grupo = ruta, suave = true })
    end
    self:marcar({ tipo = 'mover', x = destino.x, y = destino.y, ruta = ruta })
    return 'mover'
end

--- MANTENER POSICIÓN a la selección (H).
function Control:mantener()
    for _, u in ipairs(self:lista()) do
        self.tropas:darOrden(u, { tipo = 'mantener' })
    end
end

--- Quita de la selección las unidades que cayeron o se retiraron.
function Control:actualizar()
    for unidad in pairs(self.seleccion) do
        if unidad.muerto or unidad.retirado then
            self.seleccion[unidad] = nil
            self.cuenta = self.cuenta - 1
        end
    end
end

-- Dibujo ----------------------------------------------------------------------------------------

--- Altura del suelo (o del agua) en (x, y) para dibujar encima.
function Control:suelo(x, y)
    local s = self.tropas.suelo
    return math.max(s:altura(x, y), s.nivelMar or -math.huge) + 4
end

--- Círculo de radio `r` px del mundo sobre el suelo en (x, y), proyectado.
function Control:anillo(x, y, r, lados)
    local g = love.graphics
    local puntos = {}
    local p = {}
    for k = 0, lados do
        local a = k / lados * math.pi * 2
        local px, py = x + math.cos(a) * r, y + math.sin(a) * r
        if not self:proyectar(px, py, self:suelo(px, py), p) or not p.delante then
            return
        end
        puntos[#puntos + 1] = p.x
        puntos[#puntos + 1] = p.y
    end
    g.line(puntos)
end

--- Marcador de destino: dos anillos y un punto, que laten.
function Control:marcador(x, y, color, alfa)
    local g = love.graphics
    local pulso = 0.5 + 0.5 * math.sin(love.timer.getTime() * 5)
    g.setColor(color[1], color[2], color[3], alfa)
    g.setLineWidth(2.5)
    self:anillo(x, y, Control.radioMarcador * (0.9 + 0.1 * pulso), 28)
    g.setLineWidth(1.5)
    self:anillo(x, y, Control.radioMarcador * 0.45, 18)
    local p = self:proyectar(x, y, self:suelo(x, y), {})
    if p and p.delante then
        g.circle('fill', p.x, p.y, 4)
    end
end

--- Lo que le queda por recorrer a `unidad` de su orden de mover: desde
-- donde está ahora hasta su hueco, por los puntos que aún no ha pasado
-- (como en los RTS: la línea nace en la unidad y se acorta al avanzar).
-- nil si no va a ningún sitio.
function Control:rutaPendiente(unidad)
    local o = unidad.orden
    if not (o and o.tipo == 'mover' and type(o.ruta) == 'table') then
        return nil
    end
    local pendiente = { { x = unidad.x, y = unidad.y } }
    for k = o.paso or 1, #o.ruta do
        pendiente[#pendiente + 1] = o.ruta[k]
    end
    if #pendiente < 2 then
        return nil
    end
    return pendiente
end

--- Dibuja la selección (el anillo de datos de cada elegida), la cinta
-- holográfica de lo que le queda de ruta a cada una (nace en la unidad, se
-- acorta y desaparece al llegar), los enemigos que atacan (rojo), las
-- órdenes recién dadas y el cuadro de selección.
function Control:dibujar()
    local g = love.graphics
    g.push('all')
    local ahora = love.timer.getTime()
    local verde, rojo = Control.verde, Control.rojo
    local holo = self.holo
    holo:empezar()
    -- Blancos de las órdenes de atacar de lo elegido (cada uno una vez).
    local blancos = {}
    for unidad in pairs(self.seleccion) do
        local o = unidad.orden
        local pendiente = self:rutaPendiente(unidad)
        if pendiente then
            holo:cinta(unidad, pendiente, holo:radioAnillo(unidad))
        elseif o and o.tipo == 'atacar' and o.blanco and not o.blanco.muerto then
            blancos[o.blanco] = true
        end
    end
    for unidad in pairs(self.seleccion) do
        holo:anillo(unidad, holo:radioAnillo(unidad), ahora - (self.elegidaDesde[unidad] or ahora))
    end
    holo:terminar()
    for blanco in pairs(blancos) do
        g.setColor(rojo[1], rojo[2], rojo[3], 0.95)
        g.setLineWidth(2.5)
        self:anillo(blanco.x, blanco.y, (Control.radioAnillo[blanco.tipo] or 90) * 1.2, 22)
    end
    -- Órdenes recién dadas: el destino se ve un rato aunque se deseleccione.
    for k = #self.marcas, 1, -1 do
        local m = self.marcas[k]
        local edad = ahora - m.t
        if edad > Control.duracionMarca then
            table.remove(self.marcas, k)
        else
            local alfa = 1 - edad / Control.duracionMarca
            if m.tipo == 'mover' then
                -- Solo el destino: la línea sale de cada unidad mientras va.
                self:marcador(m.x, m.y, verde, alfa)
            elseif m.tipo == 'sinRuta' then
                self:marcador(m.x, m.y, rojo, alfa)
            elseif m.tipo == 'atacar' and m.blanco then
                g.setColor(rojo[1], rojo[2], rojo[3], alfa)
                g.setLineWidth(3)
                self:anillo(m.blanco.x, m.blanco.y, (Control.radioAnillo[m.blanco.tipo] or 90) * (1.2 + edad), 22)
            end
        end
    end
    -- Cuadro de selección.
    local c = self.caja
    if c then
        g.setColor(verde[1], verde[2], verde[3], 0.12)
        g.rectangle('fill', c.x0, c.y0, c.x1 - c.x0, c.y1 - c.y0)
        g.setColor(verde[1], verde[2], verde[3], 0.9)
        g.setLineWidth(1.5)
        g.rectangle('line', c.x0, c.y0, c.x1 - c.x0, c.y1 - c.y0)
    end
    g.pop()
end

return Control
