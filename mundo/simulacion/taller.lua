--- Taller y hospital de cada ciudad: heridos que se curan, vehículos averiados que se reparan pagando y remolques.
--
-- Los vehículos nunca se destruyen (diseno/economia.md, 3.8, 3.11, F12): lo
-- que cae queda AVERIADO con un daño de 0 a 1 y viaja con su grupo; al
-- volver entra en el taller de su ciudad. Si el grupo cae entero, sus
-- vehículos vuelven REMOLCADOS a la ciudad de origen en un convoy que no se
-- puede atacar (misión 'regreso', `g.remolque`). Los soldados heridos se
-- curan como antes (gratis, `ritmo` × nivel al día; con hambre, no).
--
-- Cola de una ciudad (solo datos; los recuentos son los de antes, así la
-- vista que los lee no cambia):
--   c.recuperando = { soldados, lanzacohetes,
--                     avance = { soldados, lanzacohetes },
--                     danos = { lanzacohetes = { d, ... } } }
--   `danos[tipo]` tiene un daño por vehículo, de menor a mayor (el taller
--   empieza por el más leve); `avance[tipo]` son los puntos ya reparados del
--   primero. Cada día el taller repara `ritmo[tipo] × nivel` puntos; cuando
--   uno termina se paga `reparacion[tipo] × daño` y vuelve a la ciudad. Si no
--   alcanza, espera reparado hasta poder pagar. Con la ciudad sitiada, nada.
-- En un grupo: `g.heridos = { soldados, lanzacohetes }` y
-- `g.averias = { lanzacohetes = { d, ... } }` (un daño
-- por cada vehículo de `g.heridos`).
-- Modelos (armamento.lua): junto a cada lista de daños, `modelos[tipo]` da el
-- modelo de cada vehículo en el mismo orden. Cada uno se repara a su ritmo y
-- paga su reparación (F8 de diseno/catalogo-armamento.md): lo que sobra del día
-- de un vehículo pasa al siguiente como parte del día, no como puntos.
-- Zonas (averias.lua, versión 28): junto a cada lista de daños, `zonas[tipo]`
-- da el código de averías de cada vehículo en el mismo orden. El daño de la
-- lista es su trabajo de taller (Σ de sus zonas) y lo que se paga al terminar
-- es el coste de sus zonas (`Averias.coste`), no `reparacion × daño`.
-- Tripulación: los tripulantes heridos viajan con las averías de su grupo
-- (`g.averias.tripulantes`) y en la ciudad esperan en `c.recuperando.tripulantes`;
-- se curan al ritmo de los soldados (`ritmo.soldados × nivel`, en su propia
-- cuenta `avance.tripulantes`) y vuelven a sus vehículos: no son soldados de la
-- guarnición ni están en filas (poblacion.lua).
--
-- Módulo de `mundo/simulacion.lua`: `Taller.instalar(Simulacion)` cuelga sus
-- funciones de la clase. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')
local Armamento = require('mundo.simulacion.armamento')
local Averias = require('mundo.simulacion.averias')

local tropasVacias = Ayudas.tropasVacias
local esCiudad = Ayudas.esCiudad
local distancia = Ayudas.distancia
local TROPAS = Ayudas.TROPAS

local Taller = {}

-- Se fija en `instalar`: la clase.
local Simulacion

local VEHICULOS = { 'lanzacohetes' }
Taller.VEHICULOS = VEHICULOS

local function averiasVacias()
    return { lanzacohetes = {} }
end
Taller.averiasVacias = averiasVacias

--- Apunta en `averias` un vehículo de `tipo` y `modelo` con el código de
-- averías `codigo` (averias.lua): su trabajo de taller, su modelo y su código.
function Taller.anotar(averias, tipo, codigo, modelo)
    local zonas = Averias.zonasDe(averias, tipo)
    Armamento.anotarAveria(averias, tipo, Averias.trabajo(codigo), modelo)
    zonas[#averias[tipo]] = codigo
end

--- Un vehículo de `tropa` y `modelo` de `g` queda averiado con el código
-- `codigo` y viaja con él.
function Taller.averiar(g, tropa, codigo, modelo)
    g.heridos = g.heridos or tropasVacias()
    g.averias = g.averias or averiasVacias()
    g.heridos[tropa] = g.heridos[tropa] + 1
    Taller.anotar(g.averias, tropa, codigo, modelo)
end

--- `cantidad` tripulantes heridos viajan con las averías de `g`.
function Taller.herirTripulantes(g, cantidad)
    if cantidad > 0 then
        g.averias = g.averias or averiasVacias()
        g.averias.tripulantes = (g.averias.tripulantes or 0) + cantidad
    end
end

--- Las averías de `heridos` con su daño, su modelo y su código: las de
-- `averias` y, si faltan (una partida vieja), daño 1 (casco 1) y el modelo de
-- referencia. Con los tripulantes heridos de `averias` (los de un grupo) o de
-- `heridos` (los de la cola de una ciudad).
local function averiasDe(heridos, averias)
    local out = averiasVacias()
    out.modelos = averiasVacias()
    out.zonas = averiasVacias()
    for _, tipo in ipairs(VEHICULOS) do
        local lista = averias and averias[tipo] or {}
        for k = 1, heridos and heridos[tipo] or 0 do
            out[tipo][k] = lista[k] or 1
            out.modelos[tipo][k] = Armamento.modeloAveria(averias, tipo, k)
            out.zonas[tipo][k] = Averias.codigo(averias, tipo, k)
        end
    end
    local tripulantes = (averias and averias.tripulantes or 0) + (heridos and heridos.tripulantes or 0)
    out.tripulantes = tripulantes > 0 and tripulantes or nil
    return out
end
Taller.averiasDe = averiasDe

--- Lista de modelos de los daños de `tipo` de `danos`, completa (la crea o
-- la rellena con el de referencia si le faltan).
local function modelosDe(danos, tipo)
    danos.modelos = danos.modelos or averiasVacias()
    local modelos = danos.modelos[tipo]
    for k = #modelos + 1, #danos[tipo] do
        modelos[k] = Armamento.referencia(tipo)
    end
    return modelos
end

--- Completa en su sitio las listas de modelos y de códigos de la cola `r`
-- (una partida vieja puede no tenerlas).
local function completarCola(r)
    r.danos = r.danos or averiasVacias()
    for _, tipo in ipairs(VEHICULOS) do
        local lista = r.danos[tipo]
        for k = #lista + 1, r[tipo] do
            lista[k] = 1
        end
        modelosDe(r.danos, tipo)
        Averias.zonasDe(r.danos, tipo)
    end
end

--- Mete `dano` (de un `modelo`, con el código `codigo`) en la lista de daños
-- de `tipo` de menor a mayor, sin mover al primero si ya se está reparando
-- (`enCurso`).
local function insertarDano(danos, tipo, dano, modelo, codigo, enCurso)
    local lista = danos[tipo]
    local modelos = modelosDe(danos, tipo)
    local zonas = Averias.zonasDe(danos, tipo)
    local k = #lista + 1
    local primero = enCurso and 2 or 1
    while k > primero and lista[k - 1] > dano do
        lista[k] = lista[k - 1]
        modelos[k] = modelos[k - 1]
        zonas[k] = zonas[k - 1]
        k = k - 1
    end
    lista[k] = dano
    modelos[k] = modelo
    zonas[k] = codigo
end

local function colaVacia()
    local r = tropasVacias()
    r.avance = tropasVacias()
    r.danos = averiasVacias()
    return r
end

--- Suma heridos y averiados a la cola de una ciudad: `soldados` y las
-- averías `averias` ({ lanzacohetes = { d, ... },
-- modelos, zonas, tripulantes }).
function Taller:sumarCola(c, soldados, averias)
    local vehiculos = 0
    for _, tipo in ipairs(VEHICULOS) do
        vehiculos = vehiculos + #(averias and averias[tipo] or {})
    end
    local tripulantes = averias and averias.tripulantes or 0
    if soldados + vehiculos + tripulantes <= 0 then
        return
    end
    local r = c.recuperando
    if not r then
        r = colaVacia()
        c.recuperando = r
    end
    completarCola(r)
    r.soldados = r.soldados + soldados
    if tripulantes > 0 then
        r.tripulantes = (r.tripulantes or 0) + tripulantes
    end
    for _, tipo in ipairs(VEHICULOS) do
        for k, dano in ipairs(averias and averias[tipo] or {}) do
            local modelo = Armamento.modeloAveria(averias, tipo, k)
            insertarDano(r.danos, tipo, dano, modelo, Averias.codigo(averias, tipo, k), r.avance[tipo] > 0)
            r[tipo] = r[tipo] + 1
        end
    end
end

--- Un grupo llega a `casa` (ciudad o base propia): sus lanzacohetes sanos
-- vuelven a las plataformas de casa o, si no caben, al parque de su ciudad;
-- sus heridos y averiados entran en el taller de su ciudad. Nada se desguaza.
function Taller:recibirHeridos(g, casa)
    local lanzacohetes = g.lanzacohetes or 0
    local heridos, averias = g.heridos, g.averias
    local por = Armamento.vaciar(g, 'lanzacohetes')
    g.heridos, g.averias = nil, nil
    if lanzacohetes > 0 then
        self:colocarLanzacohetes(casa, lanzacohetes, por)
    end
    if not heridos then
        return
    end
    local ciudad = self:ciudadDeSitio(g.nacion, casa)
    if ciudad then
        self:sumarCola(ciudad, heridos.soldados, averiasDe(heridos, averias))
    end
end

--- Ciudad a cuyo taller va lo de `g`: su ciudad de origen si sigue siendo
-- suya (la de su base, si salió de una), o su capital.
function Taller:ciudadTaller(g)
    local s = self:sitio(g.origen or g.desde)
    if s and s.nacion == g.nacion then
        return self:ciudadDeSitio(g.nacion, s)
    end
    return self:ciudadDeSitio(g.nacion, nil)
end

--- Manda al taller de `ciudad`, remolcados desde (x, y), `heridos` ({
-- soldados, lanzacohetes }) con sus `averias`: un convoy de regreso
-- sin líder que no se puede atacar (`retirada`). Junto a la ciudad, entran
-- al momento. Sin ciudad (la nación ya no tiene), se pierden con ella.
function Taller:remolcar(nid, x, y, ciudad, heridos, averias)
    if not ciudad then
        return nil
    end
    averias = averiasDe(heridos, averias)
    local total = heridos.soldados + #averias.lanzacohetes
    if total <= 0 then
        return nil
    end
    for _, tipo in ipairs(VEHICULOS) do
        self:medir('remolcados|' .. tipo, #averias[tipo], nid)
    end
    if distancia(ciudad, { x = x, y = y }) < 1 then
        self:sumarCola(ciudad, heridos.soldados, averias)
        return nil
    end
    local e = self.estado
    local gid = e.siguienteGrupo
    e.siguienteGrupo = gid + 1
    local ruta = self:trazar(x, y, ciudad.x, ciudad.y) or { x, y, ciudad.x, ciudad.y }
    e.grupos[gid] = {
        id = gid,
        nacion = nid,
        mision = 'regreso',
        desde = ciudad.id,
        destinoX = ciudad.x,
        destinoY = ciudad.y,
        x = x,
        y = y,
        antesX = x,
        antesY = y,
        ruta = ruta,
        largo = Simulacion.largoRuta(ruta),
        recorrido = 0,
        antesRecorrido = 0,
        soldados = 0,
        lanzacohetes = 0,
        heridos = { soldados = heridos.soldados, lanzacohetes = #averias.lanzacohetes },
        averias = averias,
        remolque = true,
        retirada = true,
    }
    return gid
end

-- Plazos y precios --------------------------------------------------------------------------------

--- Días de taller que le quedan a la cola de un tipo de vehículo: los
-- puntos pendientes de cada modelo entre su ritmo (F8).
local function diasPendientes(r, tipo, nivel)
    local lista = r.danos and r.danos[tipo] or {}
    local dias = 0
    for _, modelo in ipairs(Armamento.Catalogo.orden[tipo]) do
        local total, tiene = 0, false
        for k, d in ipairs(lista) do
            if Armamento.modeloAveria(r.danos, tipo, k) == modelo then
                total = total + d
                tiene = true
            end
        end
        if tiene then
            -- El primero (el que se repara) ya lleva su avance.
            if Armamento.modeloAveria(r.danos, tipo, 1) == modelo then
                total = total - r.avance[tipo]
            end
            dias = dias + math.max(0, total) / (Armamento.ritmo(modelo) * nivel)
        end
    end
    return dias
end

--- Días que tarda en vaciarse sola la cola de un tipo de una ciudad (0 si no
-- hay cola de ese tipo). No cuenta asedios, hambre ni falta de dinero para
-- pagar la reparación, que la paran.
function Taller.diasRecuperacion(c, tropa)
    local r = c.recuperando
    if not r or (r[tropa] or 0) <= 0 then
        return 0
    end
    if tropa == 'soldados' or tropa == 'tripulantes' then
        local ritmo = Simulacion.recuperacion.ritmo.soldados * (c.nivel or 1)
        return math.ceil((r[tropa] - (r.avance[tropa] or 0)) / ritmo)
    end
    return math.max(1, math.ceil(diasPendientes(r, tropa, c.nivel or 1) - 1e-9))
end

--- Lo que cuesta reparar el vehículo `k` de `tipo` de unas averías (la cola
-- de un taller): el de sus zonas en su modelo (averias.lua).
local function costeReparacion(averias, tipo, k)
    local reparacion = Armamento.reparacion(Armamento.modeloAveria(averias, tipo, k))
    return Averias.coste(Averias.codigo(averias, tipo, k), reparacion)
end
Taller.costeReparacion = costeReparacion

--- Lo que cuesta sacar ya `cantidad` unidades de un tipo (sin `cantidad`,
-- toda su cola) del taller de una ciudad: dinero y metal. Un vehículo paga
-- además su reparación (F12), la de sus zonas.
function Taller.precioRecuperacion(c, tropa, cantidad)
    local r = c.recuperando
    if not r or not r[tropa] then
        return 0, 0
    end
    local cuantos = math.min(cantidad or r[tropa], r[tropa])
    local dinero = cuantos * Simulacion.recuperacion.precio[tropa]
    local metal = 0
    if tropa ~= 'soldados' then
        local averias = averiasDe(r, r.danos)
        for k = 1, cuantos do
            local coste = costeReparacion(averias, tropa, k)
            dinero = dinero + coste.dinero
            metal = metal + coste.metal
        end
    end
    return dinero, metal
end

--- Vuelve a la ciudad `c` un vehículo reparado de `tipo` y `modelo`.
function Taller:devolverVehiculo(c, tipo, modelo)
    modelo = modelo or Armamento.referencia(tipo)
    if tipo == 'lanzacohetes' then
        self:colocarLanzacohetes(c, 1, { [modelo] = 1 })
    else
        c[tipo] = c[tipo] or 0
        Armamento.meter(c, tipo, modelo, 1)
    end
end

--- Saca del taller el primer vehículo de `tipo` (el más leve) y devuelve su modelo.
local function sacarPrimero(r, tipo)
    local modelo = table.remove(modelosDe(r.danos, tipo), 1)
    table.remove(Averias.zonasDe(r.danos, tipo), 1)
    table.remove(r.danos[tipo], 1)
    r[tipo] = r[tipo] - 1
    r.avance[tipo] = 0
    return modelo
end

--- Si la cola de `c` quedó vacía, se borra.
local function limpiarCola(c)
    local r = c.recuperando
    if r and r.soldados + r.lanzacohetes + (r.tripulantes or 0) == 0 then
        c.recuperando = nil
    end
end

--- Paga para que vuelvan al momento `cantidad` unidades (sin `cantidad`, toda
-- la cola) de un tipo del taller de una ciudad propia no sitiada: `precio`
-- por unidad (médicos y mecánicos) y, un vehículo, también su reparación
-- (F12). Paga el tesoro. Los vehículos salen del más leve al más grave.
-- Devuelve cuántas volvieron, o false y el motivo.
function Taller:acelerarRecuperacion(nid, cid, tropa, cantidad)
    local e = self.estado
    local n, c = e.naciones[nid], e.ciudades[cid]
    local precio = Simulacion.recuperacion.precio[tropa]
    if not (n and c and precio and c.recuperando) or c.nacion ~= nid or self:sitiada(c) then
        return false, 'noPuede'
    end
    local r = c.recuperando
    local quiere = math.min(math.floor(cantidad or r[tropa]), r[tropa])
    local hechos = 0
    if tropa == 'soldados' then
        hechos = math.max(0, math.min(quiere, math.floor(Simulacion.disponible(n, 'dinero') / precio)))
        if hechos > 0 then
            Simulacion.pagar(n, { dinero = hechos * precio })
            r.soldados = r.soldados - hechos
            if r.soldados == 0 then
                r.avance.soldados = 0
            end
            c.soldados = c.soldados + hechos
        end
    else
        completarCola(r)
        for _ = 1, quiere do
            local coste = costeReparacion(r.danos, tropa, 1)
            if not Simulacion.pagar(n, { dinero = precio + coste.dinero, metal = coste.metal }) then
                break
            end
            local modelo = sacarPrimero(r, tropa)
            self:devolverVehiculo(c, tropa, modelo)
            hechos = hechos + 1
        end
    end
    limpiarCola(c)
    if hechos <= 0 then
        return false, 'coste'
    end
    return hechos
end

--- El presidente paga para acelerar la cola de una ciudad si está en guerra o
-- la ciudad está en la frontera: lanzacohetes y soldados, solo lo que
-- tardaría más de `diasMinimos`, con parte del tesoro.
function Taller:acelerarSiHaceFalta(n, c)
    local reglas = Simulacion.recuperacion
    if self:numeroGuerras(n.id) == 0 and not self:enFrontera(c) then
        return
    end
    for _, tropa in ipairs(TROPAS) do
        if c.recuperando and Taller.diasRecuperacion(c, tropa) > reglas.diasMinimos then
            local presupuesto = math.max(0, Simulacion.disponible(n, 'dinero') - reglas.reservaTesoro)
                * (reglas.presupuestoTesoro + reglas.presupuestoAgresividad * n.gobernante.agresividad)
            local unidad = Taller.precioRecuperacion(c, tropa, 1)
            local cantidad = unidad > 0 and math.floor(presupuesto / unidad) or 0
            if cantidad > 0 then
                self:ejecutar({
                    tipo = 'acelerarRecuperacion',
                    nacion = n.id,
                    ciudad = c.id,
                    tropa = tropa,
                    cantidad = cantidad,
                })
            end
        end
    end
end

--- Un día del taller de `c` para un tipo de vehículo (ver la cabecera). Los
-- puntos que sobran de un vehículo pasan al siguiente en la parte del día que
-- quedaba: si es de otro modelo, a su ritmo.
function Taller:repararDia(c, n, tipo)
    local r = c.recuperando
    local lista = r.danos[tipo]
    if #lista == 0 then
        return
    end
    local modelos = modelosDe(r.danos, tipo)
    local nivel = c.nivel or 1
    local modelo = modelos[1]
    local puntos = Armamento.ritmo(modelo) * nivel
    while #lista > 0 do
        if modelos[1] ~= modelo then
            puntos = puntos / (Armamento.ritmo(modelo) * nivel) * (Armamento.ritmo(modelos[1]) * nivel)
            modelo = modelos[1]
        end
        local dano = lista[1]
        local falta = dano - r.avance[tipo]
        if puntos + 1e-9 < falta then
            r.avance[tipo] = r.avance[tipo] + puntos
            return
        end
        puntos = math.max(0, puntos - falta)
        r.avance[tipo] = dano
        local coste = costeReparacion(r.danos, tipo, 1)
        if not Simulacion.pagar(n, coste) then
            return -- reparado, espera a que se pueda pagar
        end
        self:medir('reparados|' .. tipo, 1, c.nacion)
        self:medir('pagoReparacion|dinero', coste.dinero)
        self:medir('pagoReparacion|metal', coste.metal)
        local codigo = Averias.zonasDe(r.danos, tipo)[1]
        for _, zona in ipairs(Averias.ZONAS) do
            if Averias.tiene(codigo, zona) then
                self:medir('reparadaZona|' .. zona, 1)
            end
        end
        sacarPrimero(r, tipo)
        self:devolverVehiculo(c, tipo, modelo)
    end
end

--- Los tripulantes heridos de la cola `r` de `c` se curan al ritmo de los
-- soldados (con hambre, no) y vuelven a sus vehículos: salen de la cola.
local function curarTripulantes(r, c, reglas)
    local heridos = r.tripulantes or 0
    if heridos <= 0 or c.hambre then
        return
    end
    local avance = (r.avance.tripulantes or 0) + reglas.ritmo.soldados * (c.nivel or 1)
    local vuelven = math.min(heridos, math.floor(avance))
    avance = avance - vuelven
    heridos = heridos - vuelven
    r.tripulantes = heridos > 0 and heridos or nil
    r.avance.tripulantes = (heridos > 0 and avance > 0) and avance or nil
end

--- Colas del día, en orden fijo: el presidente NPC decide si paga y después
-- vuelve lo que toca. Una ciudad sitiada no cura ni repara; una con hambre no
-- cura soldados (los vehículos sí se reparan).
function Taller:recuperar()
    local e = self.estado
    local reglas = Simulacion.recuperacion
    for _, c in ipairs(self:todasCiudades()) do
        local n = e.naciones[c.nacion]
        if c.recuperando and not n.jugador then
            self:acelerarSiHaceFalta(n, c)
        end
        local r = c.recuperando
        if r and not self:sitiada(c) then
            completarCola(r)
            if r.soldados > 0 and not c.hambre then
                r.avance.soldados = r.avance.soldados + reglas.ritmo.soldados * (c.nivel or 1)
                local vuelven = math.min(r.soldados, math.floor(r.avance.soldados))
                r.avance.soldados = r.avance.soldados - vuelven
                r.soldados = r.soldados - vuelven
                c.soldados = c.soldados + vuelven
                if r.soldados == 0 then
                    r.avance.soldados = 0
                end
            end
            curarTripulantes(r, c, reglas)
            for _, tipo in ipairs(VEHICULOS) do
                self:repararDia(c, n, tipo)
            end
            limpiarCola(c)
        end
    end
end

--- Cuántos lanzacohetes más le caben a un sitio, contando los que tiene fuera
-- o de camino.
function Taller:huecoLanzacohetes(s)
    return math.max(0, Simulacion.topeLanzacohetes(s) - (s.lanzacohetes or 0) - self:enCamino(s.id, 'lanzacohetes'))
end

--- ¿Tiene la ciudad algo en el taller?
function Taller.enTaller(c)
    return c.recuperando ~= nil and esCiudad(c)
end

local publicas = {
    'sumarCola',
    'recibirHeridos',
    'ciudadTaller',
    'remolcar',
    'devolverVehiculo',
    'acelerarRecuperacion',
    'acelerarSiHaceFalta',
    'repararDia',
    'recuperar',
    'huecoLanzacohetes',
}

--- Cuelga de la clase Simulacion las funciones del taller.
function Taller.instalar(clase)
    Simulacion = clase
    clase.averiar = Taller.averiar
    clase.anotarAveria = Taller.anotar
    clase.herirTripulantes = Taller.herirTripulantes
    clase.costeTaller = costeReparacion
    clase.averiasDe = averiasDe
    clase.averiasVacias = averiasVacias
    clase.diasRecuperacion = Taller.diasRecuperacion
    clase.precioRecuperacion = Taller.precioRecuperacion
    clase.enTaller = Taller.enTaller
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Taller[nombre]
    end
end

return Taller
