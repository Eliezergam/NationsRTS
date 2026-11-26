--- Ejército: selección y movimiento de ejércitos sobre el mapa, como en
-- Warpath. Las fichas son los grupos de la simulación.
--
--   Selección   un clic elige una ficha; un doble clic elige todas las fichas
--               propias dentro de su círculo de acción; Mayús + clic suma o
--               quita; arrastrar sobre el suelo dibuja un cuadro y elige las
--               fichas propias de dentro; Esc o «Soltar» deseleccionan.
--   Movimiento  con una selección, un clic en el mapa (o el derecho sin
--               arrastrar) la manda allí: a un punto, o a un sitio, una mina o
--               una bandera. Se dibuja el camino real (`Simulacion` traza la
--               ruta del grupo) con su marcador, su distancia y su toque.
--   Panel       abajo, las tarjetas de lo seleccionado y los botones de orden.
--
-- No cambia la simulación por su cuenta: todo son comandos de `sim:ejecutar`.
-- El resplandor, el círculo, los caminos y los toques se dibujan en píxeles de
-- pantalla (tras el mundo), así que se ven igual a cualquier zoom.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Iso = require('mundo.iso')
local Simulacion = require('mundo.simulacion')
local Plantar = require('interfaz.plantar')

local Ejercito = {}
Ejercito.__index = Ejercito

Ejercito.radioAccion = 1000 -- px del mundo (100 m) del círculo de acción
Ejercito.radioMinimo = 64 -- px de pantalla: el círculo no baja de aquí al alejar
Ejercito.tiempoDoble = 0.35 -- segundos entre los dos clics de un doble clic
Ejercito.umbralArrastre = 6 -- px que separan un clic de un arrastre
Ejercito.duracionToque = 0.7 -- segundos que dura un toque en pantalla
Ejercito.duracionAviso = 4

local VERDE = { 0.35, 1.0, 0.45 }
local ROJO = { 0.96, 0.42, 0.32 }

function Ejercito.nuevo()
    local self = setmetatable({}, Ejercito)
    self:reiniciar()
    return self
end

--- Deja todo como al empezar (mundo nuevo).
function Ejercito:reiniciar()
    self.ids = {}
    self.reloj = 0
    self.modo = 'mover' -- 'mover' o 'atacar': lo que hace el próximo clic en el mapa
    self.pendiente = nil -- clic izquierdo sin soltar: { x0, y0 }
    self.caja = nil -- cuadro de selección mientras se arrastra: { x0, y0, x, y }
    self.ultimo = nil -- último clic sobre una ficha (para el doble clic)
    self.toques = {}
    self.aviso = nil
    self.zonas = {}
    self.rect = nil
    self.congelado = false -- solo las pruebas: los toques no envejecen
end

-- Selección ------------------------------------------------------------------------------------

function Ejercito:cuantos()
    return #self.ids
end

function Ejercito:primero()
    return self.ids[1]
end

function Ejercito:tiene(gid)
    for _, id in ipairs(self.ids) do
        if id == gid then
            return true
        end
    end
    return false
end

function Ejercito:limpiar()
    self.ids = {}
    self.pendiente, self.caja, self.ultimo = nil, nil, nil
    self.modo = 'mover'
end

function Ejercito:poner(ids)
    self.ids = {}
    for _, id in ipairs(ids) do
        if not self:tiene(id) then
            self.ids[#self.ids + 1] = id
        end
    end
    table.sort(self.ids)
end

function Ejercito:sumar(ids)
    for _, id in ipairs(ids) do
        if not self:tiene(id) then
            self.ids[#self.ids + 1] = id
        end
    end
    table.sort(self.ids)
end

function Ejercito:alternar(gid)
    for i, id in ipairs(self.ids) do
        if id == gid then
            table.remove(self.ids, i)
            return
        end
    end
    self.ids[#self.ids + 1] = gid
    table.sort(self.ids)
end

--- ¿Se puede mover el grupo? Los convoyes de munición y los remolques no
-- aceptan órdenes (solo se retira un convoy, desde su ficha).
local function movible(gr)
    return gr.mision ~= 'abasto' and not gr.remolque
end

--- ¿Es un grupo del jugador que se puede elegir?
local function esPropio(mundo, jugador, gid)
    local gr = mundo.sim.estado.grupos[gid]
    return gr ~= nil and jugador ~= nil and gr.nacion == jugador.jugador and movible(gr)
end

--- Grupos propios, en orden fijo.
local function gruposPropios(mundo, jugador)
    local lista = {}
    if not jugador then
        return lista
    end
    for _, gid in ipairs(Simulacion.ordenadas(mundo.sim.estado.grupos)) do
        local gr = mundo.sim.estado.grupos[gid]
        if gr.nacion == jugador.jugador and movible(gr) then
            lista[#lista + 1] = gid
        end
    end
    return lista
end

-- Geometría de pantalla ------------------------------------------------------------------------

local function aPantalla(camara, w, h, vx, vy)
    return (vx - camara.x) * camara.zoom + w / 2, (vy - camara.y) * camara.zoom + h / 2
end

local function aVista(camara, w, h, sx, sy)
    return camara.x + (sx - w / 2) / camara.zoom, camara.y + (sy - h / 2) / camara.zoom
end

--- Dónde está (en el mundo) la ficha de un grupo.
local function posicionMundo(mundo, gr)
    local x, y = mundo:posicionFicha(gr, mundo.sim:fraccionPaso())
    return x or gr.x, y or gr.y
end

--- Punto de la vista donde se apoya la ficha de un grupo.
local function anclaVista(mundo, gr)
    local x, y = posicionMundo(mundo, gr)
    return Iso.vista(x, y, mundo.terreno:altura(x, y))
end

--- Semieje horizontal (px de pantalla) del círculo de acción: el círculo del
-- mundo es una elipse 2:1 de semieje r·√2 en la vista isométrica.
local function semieje(camara, radio)
    return math.max(Tema.px(Ejercito.radioMinimo), radio * math.sqrt(2) * camara.zoom)
end

--- ¿Cae (px, py) dentro de la elipse centrada en (cx, cy) de semieje a (y a/2)?
local function dentroDeElipse(px, py, cx, cy, a)
    local dx, dy = (px - cx) / a, (py - cy) / (a / 2)
    return dx * dx + dy * dy <= 1
end

--- Cajas de las fichas dibujadas este cuadro: grupo -> { x, y, w, h } (vista).
local function cajasPorGrupo(mundo)
    local cajas = {}
    for _, c in ipairs(mundo.cajasFichas or {}) do
        cajas[c.grupo] = c.caja
    end
    return cajas
end

-- Gestos ---------------------------------------------------------------------------------------

--- Todas las fichas propias dentro del círculo de acción de la ficha `gid`
-- (lo que se ve dentro de su círculo, aunque sean vehículos o soldados).
function Ejercito:grupoDe(mundo, camara, jugador, gid)
    local w, h = love.graphics.getDimensions()
    local centro = mundo.sim.estado.grupos[gid]
    local vx, vy = anclaVista(mundo, centro)
    local cx, cy = aPantalla(camara, w, h, vx, vy)
    local a = semieje(camara, Ejercito.radioAccion)
    local dentro = {}
    for _, otro in ipairs(gruposPropios(mundo, jugador)) do
        local ox, oy = aPantalla(camara, w, h, anclaVista(mundo, mundo.sim.estado.grupos[otro]))
        if dentroDeElipse(ox, oy, cx, cy, a) then
            dentro[#dentro + 1] = otro
        end
    end
    return dentro
end

--- Clic izquierdo en el mapa. Devuelve 'ficha' si eligió (o quitó) una ficha
-- propia, 'orden' si hay selección (el clic se resuelve al soltar: mandar
-- allí o cuadro de selección) y nil si el clic no es de este módulo.
function Ejercito:pulsar(mundo, camara, jugador, x, y, suma)
    if not jugador then
        return nil
    end
    local w, h = love.graphics.getDimensions()
    local vx, vy = aVista(camara, w, h, x, y)
    local gid = mundo:fichaEn(vx, vy)
    -- Segundo clic sobre una ficha ya elegida: si se arrastra, la selección va
    -- adonde se suelte (el dueño, 2026-09-30); si no, es un clic normal al soltar.
    if gid and not suma and self:tiene(gid) and esPropio(mundo, jugador, gid) then
        self.pendiente = nil
        self.arrastreOrden = { gid = gid, x0 = x, y0 = y, x = x, y = y }
        return 'ficha'
    end
    if gid and esPropio(mundo, jugador, gid) then
        return self:elegirFicha(mundo, camara, jugador, gid, x, y, vx, vy, suma)
    end
    if gid then
        return nil -- ficha ajena: la ficha se ve en su panel (lo decide main)
    end
    self.pendiente = { x0 = x, y0 = y, suma = suma }
    self:tocar(vx, vy, 'toque')
    if self:cuantos() > 0 then
        return 'orden'
    end
    return nil
end

--- Elige una ficha propia (clic, doble clic para su grupo, Mayús para sumar).
function Ejercito:elegirFicha(mundo, camara, jugador, gid, x, y, vx, vy, suma)
    do
        local doble = not suma
            and self.ultimo
            and self.ultimo.gid == gid
            and self.reloj - self.ultimo.t <= Ejercito.tiempoDoble
            and math.abs(self.ultimo.x - x) < Ejercito.umbralArrastre * 2
            and math.abs(self.ultimo.y - y) < Ejercito.umbralArrastre * 2
        if doble then
            local todos = self:grupoDe(mundo, camara, jugador, gid)
            if suma then
                self:sumar(todos)
            else
                self:poner(todos)
            end
            self.ultimo = nil
        else
            if suma then
                self:alternar(gid)
            else
                self:poner({ gid })
            end
            self.ultimo = { gid = gid, t = self.reloj, x = x, y = y }
        end
        self.pendiente = nil
        self:tocar(vx, vy, 'toque')
        return 'ficha'
    end
end

--- El ratón se mueve con el botón izquierdo apretado: pasado el umbral, es un cuadro.
function Ejercito:mover(x, y)
    local o = self.arrastreOrden
    if o then
        o.x, o.y = x, y
        if math.abs(x - o.x0) > Ejercito.umbralArrastre or math.abs(y - o.y0) > Ejercito.umbralArrastre then
            o.arrastrado = true
        end
        return
    end
    local p = self.pendiente
    if not p then
        return
    end
    if self.caja then
        self.caja.x, self.caja.y = x, y
    elseif math.abs(x - p.x0) > Ejercito.umbralArrastre or math.abs(y - p.y0) > Ejercito.umbralArrastre then
        self.caja = { x0 = p.x0, y0 = p.y0, x = x, y = y }
    end
end

--- Suelta el botón izquierdo. Con cuadro, elige las fichas propias de dentro;
-- sin él (un clic) y con selección, la manda a ese punto. Devuelve 'caja',
-- 'orden' (cuántas órdenes salieron, segundo valor) o nil.
function Ejercito:soltar(mundo, camara, jugador, x, y)
    local o = self.arrastreOrden
    self.arrastreOrden = nil
    if o and jugador then
        if o.arrastrado then
            return 'orden', self:ordenar(mundo, camara, jugador, x, y)
        end
        local w, h = love.graphics.getDimensions()
        local vx, vy = aVista(camara, w, h, x, y)
        self:elegirFicha(mundo, camara, jugador, o.gid, x, y, vx, vy, false)
        return 'caja'
    end
    local p = self.pendiente
    self.pendiente = nil
    if not (p and jugador) then
        self.caja = nil
        return nil
    end
    if self.caja then
        local c = self.caja
        self.caja = nil
        self:elegirCaja(
            mundo,
            camara,
            jugador,
            math.min(c.x0, x),
            math.min(c.y0, y),
            math.max(c.x0, x),
            math.max(c.y0, y),
            p.suma
        )
        return 'caja'
    end
    if self:cuantos() > 0 then
        return 'orden', self:ordenar(mundo, camara, jugador, x, y)
    end
    return nil
end

--- Elige las fichas propias cuyo pie o cuyo estandarte caen en el cuadro.
function Ejercito:elegirCaja(mundo, camara, jugador, x0, y0, x1, y1, suma)
    local w, h = love.graphics.getDimensions()
    local cajas = cajasPorGrupo(mundo)
    local dentro = {}
    for _, gid in ipairs(gruposPropios(mundo, jugador)) do
        local gr = mundo.sim.estado.grupos[gid]
        local px, py = aPantalla(camara, w, h, anclaVista(mundo, gr))
        local ok = px >= x0 and px <= x1 and py >= y0 and py <= y1
        local c = cajas[gid]
        if c and not ok then
            local cx, cy = aPantalla(camara, w, h, c.x + c.w / 2, c.y + c.h / 2)
            ok = cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1
        end
        if ok then
            dentro[#dentro + 1] = gid
        end
    end
    if suma then
        self:sumar(dentro)
    else
        self:poner(dentro)
    end
end

--- Ctrl+A: todas las fichas propias.
function Ejercito:todas(mundo, jugador)
    self:poner(gruposPropios(mundo, jugador))
end

--- Un toque en pantalla en el punto (vx, vy) de la vista.
function Ejercito:tocar(vx, vy, tipo)
    self.toques[#self.toques + 1] = { vx = vx, vy = vy, edad = 0, tipo = tipo }
    if #self.toques > 12 then
        table.remove(self.toques, 1)
    end
end

function Ejercito:avisar(texto)
    self.aviso = { texto = texto, edad = 0 }
end

-- Órdenes --------------------------------------------------------------------------------------

--- Lo que hay bajo el punto (vx, vy) de la vista: una mina, una instalación,
-- una ciudad o el suelo. { tipo, x, y, sitio, nombre } (x, y del mundo).
function Ejercito.destinoEn(mundo, vx, vy)
    local sim = mundo.sim
    local mina = mundo:minaEn(vx, vy)
    local deposito = mina and sim:mina(mina)
    if deposito then
        return { tipo = 'mina', x = deposito.x, y = deposito.y, id = mina, nombre = 'la mina' }
    end
    local mejor, mejorD
    for _, id in ipairs(Simulacion.ordenadas(sim.estado.instalaciones)) do
        local i = sim.estado.instalaciones[id]
        local ix, iy = Iso.vista(i.x, i.y, mundo.terreno:altura(i.x, i.y))
        local d = (vx - ix) ^ 2 + ((vy - iy) * 2) ^ 2
        if d < 170 * 170 and (not mejorD or d < mejorD) then
            mejor, mejorD = { tipo = 'sitio', x = i.x, y = i.y, sitio = i, nombre = i.nombre or i.tipo }, d
        end
    end
    if mejor then
        return mejor
    end
    for _, ciudad in pairs(mundo.ciudadesVistas) do
        local cx, cy = Iso.vista(ciudad.x, ciudad.y, ciudad.altura)
        local d = (vx - cx) ^ 2 + ((vy - cy) * 2) ^ 2
        local datos = sim:ciudad(ciudad.region)
        if datos and d < (ciudad.radio * 1.3) ^ 2 and (not mejorD or d < mejorD) then
            mejor, mejorD = { tipo = 'sitio', x = datos.x, y = datos.y, sitio = datos, nombre = datos.nombre }, d
        end
    end
    if mejor then
        return mejor
    end
    local x, y = Plantar.sueloBajo(mundo.terreno, vx, vy)
    return { tipo = 'punto', x = x, y = y, nombre = 'ese punto' }
end

--- Manda la selección al punto (x, y) de la pantalla. Usa las acciones de la
-- simulación: `redirigir` a un sitio propio, `irAPunto` en cualquier otro caso
-- (contra un sitio enemigo, ataca al llegar). Devuelve cuántas fichas salieron.
function Ejercito:ordenar(mundo, camara, jugador, x, y)
    if not jugador or self:cuantos() == 0 then
        return 0
    end
    local sim = mundo.sim
    local nid = jugador.jugador
    local w, h = love.graphics.getDimensions()
    local vx, vy = aVista(camara, w, h, x, y)
    local destino = Ejercito.destinoEn(mundo, vx, vy)
    local blanco = destino.sitio or (destino.tipo == 'punto' and sim:blancoEn(destino.x, destino.y)) or nil
    local ajeno = blanco ~= nil and blanco.nacion ~= nil and blanco.nacion ~= nid
    if ajeno then
        local nacion = sim:nacion(blanco.nacion)
        local nombre = nacion and nacion.nombre or 'esa nación'
        if not sim:guerraEntre(nid, blanco.nacion) then
            self:avisar('Estás en paz con ' .. nombre .. ': para declararle la guerra, «Atacar» en su menú')
            return 0
        end
        local puede, motivo = sim:puedeAtacar(nid, blanco.id)
        if not puede then
            self:avisar(motivo == 'sinFrontera' and 'No tienes frontera con ellos' or 'No se puede atacar ahí')
            return 0
        end
        destino.x, destino.y = blanco.x, blanco.y
    elseif self.modo == 'atacar' then
        self:avisar('Atacar: elige un sitio enemigo')
        return 0
    end
    local propio = blanco ~= nil and blanco.nacion == nid
    local salieron, sinPoder = 0, 0
    for _, gid in ipairs({ table.unpack(self.ids) }) do
        local gr = sim.estado.grupos[gid]
        local hecho = false
        if gr and gr.nacion == nid then
            if propio then
                hecho = sim:ejecutar({ tipo = 'redirigir', nacion = nid, grupo = gid, destino = blanco.id })
            end
            if not hecho then
                hecho = sim:ejecutar({ tipo = 'irAPunto', nacion = nid, grupo = gid, x = destino.x, y = destino.y })
            end
        end
        if hecho then
            salieron = salieron + 1
        else
            sinPoder = sinPoder + 1
        end
    end
    local dx, dy = Iso.vista(destino.x, destino.y, mundo.terreno:altura(destino.x, destino.y))
    self:tocar(dx, dy, ajeno and 'ataque' or 'orden')
    if salieron > 0 then
        self.modo = 'mover'
        local texto = salieron == 1 and 'La ficha marcha' or (salieron .. ' fichas marchan')
        if sinPoder > 0 then
            texto = texto .. ' (' .. sinPoder .. ' no pueden: obras o entregas)'
        end
        self:avisar(texto .. (ajeno and ' al ataque' or ''))
    else
        self:avisar('Esa orden no se puede dar ahora')
    end
    return salieron
end

--- Retira a casa las fichas seleccionadas.
function Ejercito:retirar(mundo, jugador)
    local n = 0
    for _, gid in ipairs({ table.unpack(self.ids) }) do
        if mundo.sim:ejecutar({ tipo = 'retirar', nacion = jugador.jugador, grupo = gid }) then
            n = n + 1
        end
    end
    self:avisar(
        n > 0 and (n == 1 and 'La ficha vuelve a casa' or (n .. ' fichas vuelven a casa')) or 'No pueden retirarse'
    )
end

--- Cada cuadro: envejece los toques y avisos, y olvida los grupos que ya no existen.
function Ejercito:actualizar(dt, mundo, jugador)
    if not self.congelado then
        self.reloj = self.reloj + dt
        for i = #self.toques, 1, -1 do
            local t = self.toques[i]
            t.edad = t.edad + dt
            if t.edad > Ejercito.duracionToque then
                table.remove(self.toques, i)
            end
        end
        if self.aviso then
            self.aviso.edad = self.aviso.edad + dt
            if self.aviso.edad > Ejercito.duracionAviso then
                self.aviso = nil
            end
        end
    end
    for i = #self.ids, 1, -1 do
        if not esPropio(mundo, jugador, self.ids[i]) then
            table.remove(self.ids, i)
        end
    end
end

-- Caminos --------------------------------------------------------------------------------------

--- Texto de una distancia (1 px = 10 cm): «12,4 km» o «350 m».
local function textoDistancia(px)
    local metros = px / 10
    if metros >= 1000 then
        return (string.format('%.1f km', metros / 1000):gsub('%.', ','))
    end
    return string.format('%d m', math.floor(metros / 10 + 0.5) * 10)
end

--- Lo que le queda por recorrer a un grupo: los puntos del mundo y el largo
-- que falta; nil si no va a ninguna parte. Empieza en (x, y), donde se dibuja
-- su ficha ahora (`Mundo:posicionFicha`), sigue por donde está en la
-- simulación (un paso de marcha por delante como mucho) y luego por los
-- vértices de su ruta que aún no pasó.
local function camino(gr, x, y)
    if not (gr.ruta and gr.largo and x) then
        return nil
    end
    local recorrido = gr.recorrido
    local falta = gr.largo - recorrido + math.sqrt((gr.x - x) ^ 2 + (gr.y - y) ^ 2)
    if falta < 30 then
        return nil
    end
    local puntos = { x, y }
    if gr.x ~= x or gr.y ~= y then
        puntos[3], puntos[4] = gr.x, gr.y
    end
    local acumulado = 0
    local ruta = gr.ruta
    for k = 3, #ruta, 2 do
        local tramo = math.sqrt((ruta[k] - ruta[k - 2]) ^ 2 + (ruta[k + 1] - ruta[k - 1]) ^ 2)
        if acumulado + tramo > recorrido then
            puntos[#puntos + 1] = ruta[k]
            puntos[#puntos + 1] = ruta[k + 1]
        end
        acumulado = acumulado + tramo
    end
    return puntos, falta
end

--- El camino de un grupo desde su ficha (ver `camino`), para la vista y las pruebas.
function Ejercito.caminoDesdeFicha(mundo, gr)
    local x, y = mundo:posicionFicha(gr, mundo.sim:fraccionPaso())
    return camino(gr, x, y)
end

--- Línea punteada por una lista plana de puntos de pantalla.
local function punteada(g, pts, trazo, hueco, fase)
    local ciclo = trazo + hueco
    local p = (fase or 0) % ciclo
    for k = 3, #pts, 2 do
        local x0, y0, x1, y1 = pts[k - 2], pts[k - 1], pts[k], pts[k + 1]
        local largo = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        if largo > 0 then
            local dx, dy = (x1 - x0) / largo, (y1 - y0) / largo
            local t = 0
            while t < largo do
                local enTrazo = p < trazo
                local paso = math.min((enTrazo and trazo or ciclo) - p, largo - t)
                if enTrazo then
                    g.line(x0 + dx * t, y0 + dy * t, x0 + dx * (t + paso), y0 + dy * (t + paso))
                end
                t = t + paso
                p = p + paso
                if p >= ciclo - 1e-6 then
                    p = 0
                end
            end
        end
    end
end

--- Dibuja el camino de un grupo y devuelve su marcador final y lo que falta.
local function dibujarCamino(self, g, mundo, camara, w, h, gr, color)
    local puntos, falta = Ejercito.caminoDesdeFicha(mundo, gr)
    if not puntos then
        return nil
    end
    -- Se parte en trozos de 150 m para que siga el relieve.
    local pantalla = {}
    for k = 1, #puntos - 2, 2 do
        local x0, y0, x1, y1 = puntos[k], puntos[k + 1], puntos[k + 2], puntos[k + 3]
        local n = math.max(1, math.ceil(math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) / 1500))
        for i = (k == 1 and 0 or 1), n do
            local x, y = x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n
            local sx, sy = aPantalla(camara, w, h, Iso.vista(x, y, mundo.terreno:altura(x, y)))
            pantalla[#pantalla + 1] = sx
            pantalla[#pantalla + 1] = sy
        end
    end
    if #pantalla < 4 then
        return nil
    end
    -- Sale del pie del estandarte, también si se apartó para no tapar a otro.
    local apartado = mundo.apartados and mundo.apartados[gr.id]
    if apartado then
        pantalla[1] = pantalla[1] + apartado * camara.zoom
    end
    g.setColor(0, 0, 0, 0.45)
    g.setLineWidth(5)
    punteada(g, pantalla, 8, 8, -self.reloj * 12)
    g.setColor(1, 1, 1, 0.95)
    g.setLineWidth(2.5)
    punteada(g, pantalla, 8, 8, -self.reloj * 12)
    g.setLineWidth(1)
    return { x = pantalla[#pantalla - 1], y = pantalla[#pantalla], falta = falta, color = color }
end

--- Marcador de destino: anillo, punto y la distancia (y los días que faltan).
local function dibujarMarcador(g, m, texto)
    g.setColor(0, 0, 0, 0.5)
    g.circle('fill', m.x, m.y, Tema.px(11))
    g.setColor(m.color[1], m.color[2], m.color[3], 1)
    g.setLineWidth(3)
    g.circle('line', m.x, m.y, Tema.px(11))
    g.setLineWidth(1)
    g.circle('fill', m.x, m.y, Tema.px(4))
    local fuente = Tema.fuente('sansNegrita', 14)
    g.setFont(fuente)
    local ancho = fuente:getWidth(texto)
    local x, y = m.x - ancho / 2, m.y - Tema.px(11) - fuente:getHeight() - Tema.px(6)
    g.setColor(0.08, 0.06, 0.04, 0.85)
    g.rectangle('fill', x - Tema.px(6), y - Tema.px(1), ancho + Tema.px(12), fuente:getHeight() + Tema.px(2), 3, 3)
    g.setColor(1, 1, 1, 1)
    g.print(texto, x, y)
end

-- Marcas en el mapa ----------------------------------------------------------------------------

--- Círculo punteado de acción con sus flechas, centrado en (cx, cy).
local function dibujarCirculo(self, g, cx, cy, a)
    local b = a / 2
    local perimetro = math.pi * (3 * (a + b) - math.sqrt((3 * a + b) * (a + 3 * b)))
    local n = math.min(260, math.max(24, math.floor(perimetro / Tema.px(11))))
    local fase = self.reloj * 0.06
    g.setColor(0, 0, 0, 0.35)
    for k = 0, n - 1 do
        local t = (k / n + fase) * 2 * math.pi
        g.circle('fill', cx + math.cos(t) * a + 1, cy + math.sin(t) * b + 1, Tema.px(2.6))
    end
    g.setColor(1, 1, 1, 0.95)
    for k = 0, n - 1 do
        local t = (k / n + fase) * 2 * math.pi
        g.circle('fill', cx + math.cos(t) * a, cy + math.sin(t) * b, Tema.px(2))
    end
    -- Cuatro flechas que giran despacio con el círculo, en el sentido de las agujas del reloj.
    local lado = Tema.px(7)
    for k = 0, 3 do
        local t = (k / 4 + fase) * 2 * math.pi
        local px, py = cx + math.cos(t) * a, cy + math.sin(t) * b
        local tx, ty = -math.sin(t) * a, math.cos(t) * b
        local largo = math.sqrt(tx * tx + ty * ty)
        tx, ty = tx / largo, ty / largo
        local nx, ny = -ty, tx
        g.setColor(1, 1, 1, 1)
        g.polygon(
            'fill',
            px + tx * lado,
            py + ty * lado,
            px - tx * lado * 0.6 + nx * lado * 0.7,
            py - ty * lado * 0.6 + ny * lado * 0.7,
            px - tx * lado * 0.6 - nx * lado * 0.7,
            py - ty * lado * 0.6 - ny * lado * 0.7
        )
    end
end

--- Resplandor verde alrededor de una ficha (su caja en pantalla) y de sus pies.
local function dibujarResplandor(g, x0, y0, x1, y1, pieX, pieY)
    local ancho = x1 - x0
    -- Bajo los pies: una elipse verde que late suave.
    local pulso = 1 + 0.06 * math.sin(love.timer.getTime() * 4)
    local rx = math.max(Tema.px(26), ancho * 0.5) * pulso
    for i = 4, 1, -1 do
        g.setColor(VERDE[1], VERDE[2], VERDE[3], 0.09 * (5 - i))
        g.ellipse('fill', pieX, pieY, rx * (0.7 + i * 0.16), rx * (0.7 + i * 0.16) / 2)
    end
    g.setColor(VERDE[1], VERDE[2], VERDE[3], 0.95)
    g.setLineWidth(2)
    g.ellipse('line', pieX, pieY, rx * 0.9, rx * 0.45)
    -- Sin halo cuadrado alrededor del estandarte (el dueño, 2026-09-30): solo
    -- la elipse bajo los pies y el anillo de puntos que gira.
    g.setLineWidth(1)
end

local function dibujarToque(g, t, camara, w, h)
    local sx, sy = aPantalla(camara, w, h, t.vx, t.vy)
    local u = math.min(1, t.edad / Ejercito.duracionToque)
    local color = t.tipo == 'ataque' and ROJO or VERDE
    if t.tipo == 'toque' then
        color = { 1, 1, 1 }
    end
    local grande = t.tipo ~= 'toque'
    local radio = Tema.px(grande and (10 + 34 * u) or (6 + 20 * u))
    g.setColor(color[1], color[2], color[3], (1 - u) * 0.95)
    g.setLineWidth(grande and 4 or 3)
    g.circle('line', sx, sy, radio)
    if grande then
        g.setColor(color[1], color[2], color[3], (1 - u) * 0.35)
        g.circle('fill', sx, sy, radio * 0.75)
        g.setColor(color[1], color[2], color[3], (1 - u) * 0.8)
        g.setLineWidth(2)
        g.circle('line', sx, sy, radio * 0.5)
    end
    g.setLineWidth(1)
end

--- Cuadro de selección que se arrastra.
local function dibujarCaja(g, c)
    local x0, y0 = math.min(c.x0, c.x), math.min(c.y0, c.y)
    local ancho, alto = math.abs(c.x - c.x0), math.abs(c.y - c.y0)
    g.setColor(VERDE[1], VERDE[2], VERDE[3], 0.18)
    g.rectangle('fill', x0, y0, ancho, alto)
    g.setColor(VERDE[1], VERDE[2], VERDE[3], 0.95)
    g.setLineWidth(2)
    g.rectangle('line', x0, y0, ancho, alto)
    g.setLineWidth(1)
end

--- Lo que va bajo las fichas (el dueño, 2026-09-30: el círculo, debajo de la
-- bandera): el círculo de acción que gira y la elipse bajo los pies de cada
-- ficha elegida. Se llama desde el mundo antes de dibujar las fichas.
function Ejercito:dibujarDebajo(mundo, camara)
    if #self.ids == 0 then
        return
    end
    local g = love.graphics
    local w, h = g.getDimensions()
    local grupos = mundo.sim.estado.grupos
    do
        -- Un círculo de acción alrededor de todo lo elegido.
        local sx, sy, n, lejos = 0, 0, 0, 0
        local pies = {}
        for _, gid in ipairs(self.ids) do
            local gr = grupos[gid]
            if gr then
                local px, py = aPantalla(camara, w, h, anclaVista(mundo, gr))
                pies[gid] = { px, py }
                sx, sy, n = sx + px, sy + py, n + 1
            end
        end
        if n > 0 then
            local cx, cy = sx / n, sy / n
            for _, p in pairs(pies) do
                lejos = math.max(lejos, math.sqrt((p[1] - cx) ^ 2 + (2 * (p[2] - cy)) ^ 2))
            end
            local a = math.max(semieje(camara, Ejercito.radioAccion), lejos * 1.25 + Tema.px(30))
            dibujarCirculo(self, g, cx, cy, a)
        end
        local cajas = cajasPorGrupo(mundo)
        for _, gid in ipairs(self.ids) do
            local p = pies[gid]
            local c = cajas[gid]
            if p and c then
                local x0, y0 = aPantalla(camara, w, h, c.x, c.y)
                local x1, y1 = aPantalla(camara, w, h, c.x + c.w, c.y + c.h)
                dibujarResplandor(g, x0, y0, x1, y1, p[1], p[2])
            elseif p then
                dibujarResplandor(g, p[1] - Tema.px(20), p[2] - Tema.px(40), p[1] + Tema.px(20), p[2], p[1], p[2])
            end
        end
    end
    g.setLineWidth(1)
end

--- Todo lo que va sobre el mapa (se llama tras el mundo, en pantalla): caminos,
-- círculo de acción, resplandor de cada ficha, toques y cuadro de selección.
function Ejercito:dibujarMapa(mundo, camara)
    local g = love.graphics
    local w, h = g.getDimensions()
    local grupos = mundo.sim.estado.grupos
    -- Arrastrando desde la ficha: línea hasta el ratón.
    local o = self.arrastreOrden
    if o and o.arrastrado then
        g.setColor(VERDE[1], VERDE[2], VERDE[3], 0.9)
        g.setLineWidth(3)
        g.line(o.x0, o.y0, o.x, o.y)
        g.circle('line', o.x, o.y, 10)
        g.setLineWidth(1)
    end
    if #self.ids > 0 then
        -- Caminos, sin repetir marcador cuando varias fichas van al mismo sitio.
        local marcadores = {}
        for _, gid in ipairs(self.ids) do
            local gr = grupos[gid]
            if gr then
                local m = dibujarCamino(self, g, mundo, camara, w, h, gr, gr.mision == 'atacar' and ROJO or VERDE)
                if m then
                    local clave = math.floor(m.x / 24) .. ':' .. math.floor(m.y / 24)
                    local previo = marcadores[clave]
                    if not previo or m.falta > previo.falta then
                        marcadores[clave] = m
                    end
                end
            end
        end
        local claves = {}
        for clave in pairs(marcadores) do
            claves[#claves + 1] = clave
        end
        table.sort(claves)
        for _, clave in ipairs(claves) do
            local m = marcadores[clave]
            local dias = math.max(1, math.ceil(m.falta / Simulacion.velocidadEjercito))
            dibujarMarcador(g, m, string.format('%s · %d d', textoDistancia(m.falta), dias))
        end
    end
    for _, t in ipairs(self.toques) do
        dibujarToque(g, t, camara, w, h)
    end
    if self.caja then
        dibujarCaja(g, self.caja)
    end
    g.setLineWidth(1)
end

-- Panel inferior -------------------------------------------------------------------------------

--- Suma de lo seleccionado: soldados, lanzacohetes, heridos, poder
-- y los modelos de sus vehículos (`modelos`: modelo -> cantidad).
function Ejercito:resumen(mundo)
    local r = { grupos = 0, soldados = 0, lanzacohetes = 0, heridos = 0, poder = 0, modelos = {} }
    for _, gid in ipairs(self.ids) do
        local gr = mundo.sim.estado.grupos[gid]
        if gr then
            local c = Simulacion.composicion(gr)
            r.grupos = r.grupos + 1
            r.soldados = r.soldados + c.soldados
            r.lanzacohetes = r.lanzacohetes + c.lanzacohetes
            r.heridos = r.heridos + c.heridos.soldados + c.heridos.lanzacohetes
            r.poder = r.poder + Simulacion.poder(gr)
            for _, tipo in ipairs(Simulacion.Armamento.TIPOS) do
                for _, d in ipairs(Simulacion.desglose(gr, tipo)) do
                    r.modelos[d.modelo] = (r.modelos[d.modelo] or 0) + d.cantidad
                end
            end
        end
    end
    return r
end

--- Qué hace lo seleccionado: «En marcha · 4,2 km · 3 d», «En posición»…
function Ejercito:estado(mundo)
    local sim = mundo.sim
    local falta, mision, batalla = 0, nil, false
    for _, gid in ipairs(self.ids) do
        local gr = sim.estado.grupos[gid]
        if gr then
            local _, f = Ejercito.caminoDesdeFicha(mundo, gr)
            if f and f > falta then
                falta, mision = f, gr.mision
            end
            batalla = batalla or gr.batalla ~= nil
        end
    end
    if batalla then
        return 'En batalla'
    elseif falta > 0 then
        local dias = math.max(1, math.ceil(falta / Simulacion.velocidadEjercito))
        local que = mision == 'atacar' and 'Ataca' or (mision == 'regreso' and 'Vuelve a casa' or 'En marcha')
        return string.format('%s · %s · %d d', que, textoDistancia(falta), dias)
    end
    return 'En posición'
end

--- Icono de una tropa (dibujado con formas) en el cuadrado (x, y, lado).
local ICONO_TARJETA = { soldados = 'soldado', lanzacohetes = 'lanzacohetes' }

--- Icono de una tarjeta del panel: los del kit (el de poder, a color).
local function dibujarIcono(_, tipo, x, y, lado)
    if tipo == 'poder' then
        Acero.iconoColor('poder', x, y, lado)
    else
        Acero.icono(ICONO_TARJETA[tipo], x, y, lado, 'textoHud')
    end
end

-- Órdenes del panel, en dos columnas.
local BOTONES = {
    { accion = 'modo:mover', texto = 'Mover', tipo = 'secundario', modo = 'mover' },
    { accion = 'modo:atacar', texto = 'Atacar', tipo = 'peligro', modo = 'atacar' },
    { accion = 'recolectar', texto = 'Recolectar', tipo = 'secundario', activo = false },
    { accion = 'retirar', texto = 'Retirar', tipo = 'secundario' },
    { accion = 'soltar', texto = 'Soltar', tipo = 'secundario' },
}

--- Panel de abajo: cabecera, una tarjeta por tipo de tropa y los botones de
-- orden. Se coloca entre las noticias (izquierda) y el pendón (derecha), sobre
-- la barra de navegación (`reserva` px libres al pie).
function Ejercito:dibujarPanel(mundo, jugador, noticias, pendon, reserva)
    -- Gris caqui claro con texto negro, como los demás paneles del mapa.
    Tema.modoClaro = true
    local ok, fallo = pcall(self.dibujarPanelClaro, self, mundo, jugador, noticias, pendon, reserva)
    Tema.modoClaro = false
    if not ok then
        error(fallo, 0)
    end
end

function Ejercito:dibujarPanelClaro(mundo, jugador, noticias, pendon, reserva)
    self.zonas, self.rect = {}, nil
    self.tarjetas = {}
    if not jugador or self:cuantos() == 0 then
        return
    end
    local g = love.graphics
    local w, h = g.getDimensions()
    local r = self:resumen(mundo)
    if r.grupos == 0 then
        return
    end
    local tarjetas = {}
    if r.soldados > 0 then
        tarjetas[#tarjetas + 1] = { tipo = 'soldados', nombre = 'Soldados', cifra = r.soldados }
    end
    if r.lanzacohetes > 0 then
        tarjetas[#tarjetas + 1] = { tipo = 'lanzacohetes', nombre = 'Cohetes', cifra = r.lanzacohetes }
    end
    tarjetas[#tarjetas + 1] = { tipo = 'poder', nombre = 'Poder', cifra = math.floor(r.poder + 0.5) }
    local pad, hueco = Tema.px(10), Tema.px(6)
    local libreIzq = (noticias.rect and noticias.rect.x + noticias.rect.w or 0) + Tema.px(12)
    local libreDer = (pendon.rect and pendon.rect.x or w) - Tema.px(12)
    libreIzq = math.max(libreIzq, Tema.px(12))
    local fuenteBoton = Tema.fuente('sc', 14)
    local bw = 0
    for _, b in ipairs(BOTONES) do
        bw = math.max(bw, Tema.anchoBoton(b, true), fuenteBoton:getWidth(b.texto) + Tema.px(16))
    end
    local bh = Tema.px(28)
    local altoCabecera = Tema.px(26)
    local ch = bh * 3 + hueco * 2
    local anchoBotones = bw * 2 + hueco
    local disponible = libreDer - libreIzq - pad * 2 - anchoBotones - Tema.px(12)
    local cw = math.max(Tema.px(52), math.min(Tema.px(88), (disponible - hueco * (#tarjetas - 1)) / #tarjetas))
    local ancho = pad * 2 + #tarjetas * cw + (#tarjetas - 1) * hueco + Tema.px(12) + anchoBotones
    local alto = pad * 2 + altoCabecera + ch
    local x = math.max(libreIzq, math.floor((libreIzq + libreDer - ancho) / 2))
    local y = h - alto - (reserva or Tema.px(14)) - Tema.px(8)
    self.rect = { x = x, y = y, w = ancho, h = alto }
    Acero.sombra(x, y, ancho, alto)
    Acero.fondoPanel(x, y, ancho, alto)
    g.setColor(VERDE[1], VERDE[2], VERDE[3], 1)
    g.rectangle('fill', x + Tema.px(14), y + Tema.px(3), ancho - Tema.px(28), Tema.px(2))
    -- Cabecera: quién y qué hace.
    local titulo = Tema.fuente('sc', 17)
    local texto = Tema.fuente('sans', 14)
    local cx, cy = x + pad, y + pad
    local nombre
    if r.grupos == 1 then
        local ficha = mundo.sim:fichaGrupo(self.ids[1], mundo.mira)
        nombre = ficha and ficha.lider and ficha.lider.etiqueta or 'Ejército'
    else
        nombre = r.grupos .. ' fichas elegidas'
    end
    g.setFont(titulo)
    Tema.color('textoHud')
    g.print(nombre, cx, cy - Tema.px(1))
    local estado = self:estado(mundo)
    g.setFont(texto)
    Tema.color('textoHudTenue')
    g.print(
        Tema.cortar(texto, estado, ancho - pad * 2 - titulo:getWidth(nombre) - Tema.px(14)),
        x + ancho - pad - math.min(texto:getWidth(estado), ancho - pad * 2 - titulo:getWidth(nombre) - Tema.px(14)),
        cy + Tema.px(2)
    )
    cy = cy + altoCabecera
    -- Tarjetas.
    local numero = Tema.fuente('scNegra', 22)
    local etiqueta = Tema.fuente('sc', 11, 10)
    for i, t in ipairs(tarjetas) do
        local tx = cx + (i - 1) * (cw + hueco)
        Tema.color('olivaClaro')
        g.rectangle('fill', tx, cy, cw, ch, 2, 2)
        Tema.borde(tx, cy, cw, ch, t.tipo == 'poder' and 'caquiPestana' or 'lineaOliva')
        local lado = math.min(cw - Tema.px(20), Tema.px(34))
        dibujarIcono(g, t.tipo, tx + (cw - lado) / 2, cy + Tema.px(6), lado)
        g.setFont(numero)
        Tema.color('textoHud')
        local cifra = Tema.numero(t.cifra)
        g.print(cifra, tx + (cw - numero:getWidth(cifra)) / 2, cy + Tema.px(6) + lado + Tema.px(1))
        g.setFont(etiqueta)
        Tema.color('textoHudTenue')
        local nom = Tema.cortar(etiqueta, t.nombre:upper(), cw - Tema.px(4))
        g.print(nom, tx + (cw - etiqueta:getWidth(nom)) / 2, cy + ch - etiqueta:getHeight() - Tema.px(4))
        if t.tipo == 'lanzacohetes' then
            -- Sus modelos, en la ayuda (dibujarAyuda).
            local partes = {}
            for _, m in ipairs(Simulacion.Armamento.modelos(t.tipo)) do
                if r.modelos[m] then
                    partes[#partes + 1] = Tema.numero(r.modelos[m]) .. ' ' .. Simulacion.nombreModelo(m)
                end
            end
            self.tarjetas[#self.tarjetas + 1] =
                { x = tx, y = cy, w = cw, h = ch, texto = t.nombre .. ': ' .. table.concat(partes, ', ') }
        end
    end
    if r.heridos > 0 then
        -- Los heridos no salen a combatir: una nota sobre las tarjetas.
        g.setFont(etiqueta)
        Tema.color('amarillo')
        local nota = Tema.numero(r.heridos) .. ' heridos'
        g.print(nota, x + pad + Tema.px(2) + titulo:getWidth(nombre) + Tema.px(10), cy - altoCabecera + Tema.px(6))
    end
    -- Botones de orden en dos columnas.
    local bx = cx + #tarjetas * (cw + hueco) - hueco + Tema.px(12)
    for i, b in ipairs(BOTONES) do
        local col, fila = (i - 1) % 2, math.floor((i - 1) / 2)
        local px, py = bx + col * (bw + hueco), cy + fila * (bh + hueco)
        local activo = b.activo ~= false
        local ficha = { texto = b.texto, tipo = b.tipo, activo = activo }
        if b.modo and self.modo == b.modo then
            ficha.tipo = 'principal'
        end
        Tema.boton(ficha, px, py, bw, bh, true)
        self.zonas[#self.zonas + 1] = { x = px, y = py, w = bw, h = bh, accion = b.accion, activo = activo }
    end
end

--- Aviso y ayudas del panel (encima de todo lo demás).
function Ejercito:dibujarAyuda()
    local g = love.graphics
    local w = g.getDimensions()
    if self.rect and self.aviso then
        local fuente = Tema.fuente('sansNegrita', 15)
        local ancho = math.min(w - Tema.px(40), fuente:getWidth(self.aviso.texto) + Tema.px(24))
        local alto = fuente:getHeight() + Tema.px(10)
        local x = math.max(Tema.px(8), math.min(w - ancho - Tema.px(8), self.rect.x + (self.rect.w - ancho) / 2))
        local y = self.rect.y - alto - Tema.px(8)
        Tema.color('olivaNegro', 0.95)
        g.rectangle('fill', x, y, ancho, alto, 3, 3)
        Tema.borde(x, y, ancho, alto, 'amarillo')
        g.setFont(fuente)
        Tema.color('amarillo')
        g.print(Tema.cortar(fuente, self.aviso.texto, ancho - Tema.px(16)), x + Tema.px(12), y + Tema.px(5))
    end
    local mx, my = love.mouse.getPosition()
    for _, t in ipairs(self.tarjetas or {}) do
        if Tema.dentro(mx, my, t.x, t.y, t.w, t.h) then
            Tema.ayuda(t.texto, mx, my, Tema.px(300))
        end
    end
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(mx, my, z.x, z.y, z.w, z.h) then
            if z.accion == 'recolectar' then
                Tema.ayuda(
                    'Las fichas en el campo aún no pueden ir a una mina a recolectar: la simulación solo lo permite desde una ciudad (desde el pendón de la mina).',
                    mx,
                    my,
                    Tema.px(320)
                )
            elseif z.accion == 'modo:atacar' then
                Tema.ayuda(
                    'El próximo clic debe caer sobre un sitio enemigo (hace falta estar en guerra).',
                    mx,
                    my,
                    Tema.px(300)
                )
            elseif z.accion == 'retirar' then
                Tema.ayuda('Las fichas elegidas vuelven a su ciudad.', mx, my, Tema.px(260))
            elseif z.accion == 'soltar' then
                Tema.ayuda('Deja de elegir estas fichas (Esc).', mx, my, Tema.px(260))
            end
        end
    end
end

--- Clic en el panel: true si lo usó (aunque no fuera en un botón).
function Ejercito:pulsarPanel(mundo, jugador, x, y)
    local r = self.rect
    if not (r and Tema.dentro(x, y, r.x, r.y, r.w, r.h)) then
        return false
    end
    for _, z in ipairs(self.zonas) do
        if z.activo and Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            local modo = z.accion:match('^modo:(.+)$')
            if modo then
                self.modo = modo
            elseif z.accion == 'retirar' then
                self:retirar(mundo, jugador)
            elseif z.accion == 'soltar' then
                self:limpiar()
            end
            return true
        end
    end
    return true
end

return Ejercito
