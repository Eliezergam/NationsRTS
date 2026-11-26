-- Almacenaje: el trabajo del robot en el almacén. Lo que llega al patio de
-- descarga (pacas de dinero, cajas de comida y de obuses) lo lleva a su rack
-- del anexo, como en los almacenes de verdad (recepción → leer la ubicación →
-- dejarlo): cada rack tiene encima su cartel (DINERO, MUNICIÓN, COMIDA) y el
-- robot lo busca con los ojos; no sabe de antemano dónde está.
--
-- Una vuelta de trabajo:
--   1. Si no conoce ninguna caja suya en el patio, va a los miradores del
--      patio: el lidar le dice dónde hay mesas y los ojos miran cada hueco
--      de cada mesa (se aprenden lo que ven).
--   2. Elige la caja conocida más cercana.
--   3. Busca un rack con cartel de lo suyo y hueco libre: los rellena en
--      orden, el del cartel 1 (el más cercano a la entrada) primero, abajo
--      de un lado al otro y luego arriba. Si aún no ha leído ese cartel (o
--      los que conoce están llenos), va a los miradores del anexo y mira
--      hacia arriba, a la altura de los carteles, hasta encontrarlo.
--   4. Se la encarga al transporte (coger, llevar, dejar) y vuelve a empezar.
-- Antes que nada, si la fábrica de misiles espera dinero, metal o petróleo
-- para un misil, se lo lleva del rack al depósito del misil (setAbastecer).
-- El metal llega en cajas de lingotes y el petróleo en garrafas (los
-- bidones pesan demasiado para él): los guarda en la fila del muro sur
-- (carteles METAL y PETRÓLEO).
--
-- Órdenes que añade al robot:
--   robot:setTrabajar(si)        empieza (true, lo hace solo al cargar) o para
--   robot:getTrabajando()        true mientras trabaja
--   robot:getGuardados()         cuántas cosas ha guardado

---@class Almacenaje : Robot
local Almacenaje = {}
-- Lo que espera para volver a por una caja a la que no pudo llegar (s).
Almacenaje.esperaNoLlego = 120
local Robot = GestorRobots.Robot

-- Qué cartel busca para cada recurso (assets/almacen/objetos_datos.lua).
Almacenaje.cartel = { dinero = 'cartelDinero', comida = 'cartelComida', obuses = 'cartelMunicion', metal = 'cartelMetal', petroleo = 'cartelPetroleo' }
-- Desde dónde mira el patio (x, y, rumbo). En el anexo ya no hay miradores
-- fijos: los carteles se leen desde el rack que cuelga de cada uno (el dueño,
-- 22-nov: que no barra los racks de un extremo a otro).
Almacenaje.miradoresPatio = { { 35.0, 10.5, 0 }, { 49.0, 10.5, 0 } }
-- La placa de un cartel cuelga 0,45 m por delante del centro de su rack, del
-- lado del pasillo (tools/blender/almacen_interior.py).
Almacenaje.saltoCartel = 0.45
Almacenaje.distanciaCartel = 2.8 -- m: a esta distancia se lee el cartel
Almacenaje.pacienciaCartel = 2.5 -- s que se queda mirando un cartel
Almacenaje.maxLecturas = 4 -- carteles que puede leer en una búsqueda
-- Dónde espera cuando no hay nada que hacer.
Almacenaje.espera = { 33.5, 5.0, 0 }
Almacenaje.prisaMirar = 3.0 -- mira tres veces más rápido (el dueño, 21-nov)
Almacenaje.zCartel = 2.45 -- altura de los carteles (los busca ahí)
Almacenaje.repasoPatio = 10 -- s: sin cajas conocidas, vuelve a mirar el patio cada tanto
Almacenaje.prisaFabrica = 2.0 -- llevando recursos a la fábrica corre el doble (el dueño, 2026-11-17)

function Almacenaje:onLoad()
    local d = self.datos.almacenaje
    d.activo = true
    d.guardados = 0
    d.patioMirado = -math.huge
    d.reloj = 0
    d.sinSitio = {}
    d.signos = {} -- [rack] = { tipo = 'cartelDinero', x, y }: los carteles leídos
end

local mirarMesas
local cajasConocidas

local function esperar(condicion, maximo)
    local t = 0
    while not condicion() do
        t = t + coroutine.yield()
        if maximo and t > maximo then
            return false
        end
    end
    return true
end

local function pausa(segundos)
    local t = 0
    while t < segundos do
        t = t + coroutine.yield()
    end
end

local function tarea(self, texto)
    if self.datos.transporte then
        self.datos.transporte.tarea = texto
    end
    print('ROBOT', texto)
end

local function ir(self, sitio, texto, maximo)
    tarea(self, texto)
    self:setBrazosAbajo()
    self:setNavegarA(sitio[1], sitio[2], sitio[3])
    esperar(function()
        return not self:getNavegando()
    end, maximo or 90)
end

-- ¿Está `o` en una mesa del patio de descarga?
local function enPatio(o)
    local mueble = o:getApoyadoEn()
    if not mueble or mueble:getTipo() ~= 'mesaRecepcion' then
        return false
    end
    local x, y = mueble:getPosicion()
    return x > 30 and y > -1.5
end

-- El cartel que cuelga de un rack: la placa está encima, del lado del pasillo
-- (el mismo lado donde están los huecos del rack). Devuelve x, y, z de la
-- placa y la dirección del pasillo (hacia donde se pone el robot para
-- leerla).
local function cartelDeRack(rack)
    local huecos = rack:getHuecos()
    if #huecos == 0 then
        return nil
    end
    local rx, ry = rack:getPosicion()
    local sx, sy = 0, 0
    for _, h in ipairs(huecos) do
        sx, sy = sx + h.x, sy + h.y
    end
    sx, sy = sx / #huecos, sy / #huecos
    local dx, dy = sx - rx, sy - ry
    local largo = math.sqrt(dx * dx + dy * dy)
    if largo < 0.01 then
        return nil
    end
    dx, dy = dx / largo, dy / largo
    return rx, ry + dy * Almacenaje.saltoCartel, Almacenaje.zCartel, dx, dy
end

-- ¿Es este cartel el que cuelga de este rack? (la placa es de 2,6 m de ancho
-- y el punto donde los ojos la tocan puede quedar hasta 1,3 m del centro).
local function esCartelDe(c, sx, sy)
    return math.abs(c.x - sx) <= 2.5 and math.abs(c.y - sy) <= 1.0
end

-- El tipo de cartel que se ha leído en un rack (nil si todavía no lo ha
-- leído). Un cartel que se vio de paso (al trabajar en un rack) también
-- cuenta.
local function tipoDeRack(self, rack)
    local d = self.datos.almacenaje
    local apuntado = d.signos[rack]
    if apuntado then
        return apuntado.tipo
    end
    local sx, sy = cartelDeRack(rack)
    if not sx then
        return nil
    end
    for _, c in ipairs(self:getCarteles()) do
        if esCartelDe(c, sx, sy) then
            d.signos[rack] = { tipo = c.tipo, x = c.x, y = c.y }
            return c.tipo
        end
    end
end

-- Los racks del anexo, por filas (los que están a la misma y). En cada fila
-- va lo que se espera de cada cartel: los carteles de una fila van por
-- bloques del mismo tipo (DINERO 1-5, MUNICIÓN 1-5, METAL 1-3...), así que
-- con uno que ha leído ya se sabe el tipo de los que tiene al lado. Esto es
-- lo que evita el barrido: no hace falta leer los veinte carteles para saber
-- dónde está el del metal (el dueño, 22-nov).
local function filasDeRacks(self)
    local porFila = {}
    for _, o in ipairs(GestorObjetos.getObjetos()) do
        if o:getTipo() == 'rackRobot' then
            local x, y = o:getPosicion()
            local fila = porFila[y]
            if not fila then
                fila = {}
                porFila[y] = fila
            end
            fila[#fila + 1] = o
        end
    end
    local filas = {}
    for y, fila in pairs(porFila) do
        table.sort(fila, function(a, b)
            local ax = (a:getPosicion())
            local bx = (b:getPosicion())
            return ax < bx
        end)
        local vigente -- el tipo que se espera en lo que viene en la fila
        local lista = {}
        for _, rack in ipairs(fila) do
            local rx, ry = rack:getPosicion()
            local tipo = tipoDeRack(self, rack)
            if tipo then
                vigente = tipo
            end
            lista[#lista + 1] = { rack = rack, x = rx, y = ry, tipo = tipo, espera = vigente }
        end
        filas[#filas + 1] = { y = y, racks = lista }
    end
    table.sort(filas, function(a, b)
        return a.y < b.y
    end)
    return filas
end

-- Mira las cajas que hay en el patio para confirmarlas con los ojos: la más
-- cercana primero. Las que ve el lidar (la capa de 1,05 m pasa por encima
-- de las mesas) ya las conoce; con mirarlas basta. Si no conoce ninguna,
-- mira los huecos de las mesas que conoce.
function mirarMesas(self)
    local cajas = cajasConocidas(self)
    for _, c in ipairs(cajas) do
        local o = c.o
        local x, y, z = o:getPosicion()
        local alto = o.datos.tamano and o.datos.tamano[3] or 0.2
        self:setMirarA(x, y, z + alto * 0.6)
        pausa(0.25 / Almacenaje.prisaMirar)
        if self:getHaVisto(o, 0.5) then
            self:setMirarA(nil)
            return
        end
    end
    -- Sin cajas conocidas: mira los huecos de las mesas que ve el lidar.
    local x, y = self:getPosicion()
    local mesas = {}
    for o in pairs(self:getObjetosLidar()) do
        if o:getTipo() == 'mesaRecepcion' then
            local mx, my = o:getPosicion()
            if mx > 30 and my > -1.5 then
                mesas[#mesas + 1] = { o = o, d = (mx - x) ^ 2 + (my - y) ^ 2 }
            end
        end
    end
    table.sort(mesas, function(a, b)
        return a.d < b.d
    end)
    for _, m in ipairs(mesas) do
        for _, h in ipairs(m.o:getHuecos()) do
            self:setMirarA(h.x, h.y, h.z + 0.12)
            pausa(0.25 / Almacenaje.prisaMirar)
            if #cajasConocidas(self) > 0 then
                self:setMirarA(nil)
                return
            end
        end
    end
    self:setMirarA(nil)
end

-- Las cajas suyas que conoce y siguen en el patio, la más cercana primero.
-- Valen las que ha visto con los ojos y las que ha tocado el lidar (la capa
-- de 1,05 m ve las cajas sobre las mesas de una pasada: no hace falta
-- recorrer el patio mirando hueco por hueco para decidir cuál llevar).
cajasConocidas = function(self)
    local lista = {}
    local vistos = {}
    local x, y = self:getPosicion()
    local function mirar(o)
        if vistos[o] then
            return
        end
        vistos[o] = true
        local recurso = o.datos.recurso
        local da = self.datos.almacenaje
        local fallo = da.noLlego and da.noLlego[o]
        local aparte = fallo and da.reloj - fallo < Almacenaje.esperaNoLlego
        if recurso and Almacenaje.cartel[recurso] and not o:getLlevadoPor() and enPatio(o) and not da.sinSitio[o] and not aparte then
            local ox, oy = o:getPosicion()
            lista[#lista + 1] = { o = o, d = (ox - x) ^ 2 + (oy - y) ^ 2 }
        end
    end
    for o in pairs(self:getConocidos()) do
        mirar(o)
    end
    for o in pairs(self:getObjetosLidar()) do
        mirar(o)
    end
    table.sort(lista, function(a, b)
        return a.d < b.d
    end)
    return lista
end

-- Primer hueco libre de un rack: abajo de un lado al otro (de oeste a este,
-- desde la entrada), luego arriba.
local function huecoLibre(rack)
    local huecos = rack:getHuecos()
    table.sort(huecos, function(a, b)
        if math.abs(a.z - b.z) > 0.01 then
            return a.z < b.z
        end
        return a.x < b.x
    end)
    for _, h in ipairs(huecos) do
        if not h.ocupado then
            return h.numero
        end
    end
end

-- Un rack con hueco bajo un cartel del tipo pedido que ya ha leído: los
-- rellena en orden, el de la entrada primero.
local function destino(self, tipo)
    local candidatos = {}
    for _, fila in ipairs(filasDeRacks(self)) do
        for _, r in ipairs(fila.racks) do
            if r.tipo == tipo then
                local numero = huecoLibre(r.rack)
                if numero then
                    candidatos[#candidatos + 1] = { rack = r.rack, numero = numero, x = r.x }
                end
            end
        end
    end
    table.sort(candidatos, function(a, b)
        return a.x < b.x
    end)
    if candidatos[1] then
        return candidatos[1].rack, candidatos[1].numero
    end
end

-- El cartel que conviene leer ahora: el que promete el tipo que se busca (el
-- bloque de la fila que ya se conoce); si no hay ninguno, el más cercano de
-- los que todavía no se sabe (para descubrir un tipo nuevo); y si ya los
-- conoce todos, el final de la fila más cercana por comprobar (en una fila
-- el tipo puede cambiar a mitad: METAL 1-3 y PETRÓLEO 4-5).
local function mejorCandidato(self, tipo, descartados)
    local x, y = self:getPosicion()
    local mejor, mejorP, mejorClave
    for _, fila in ipairs(filasDeRacks(self)) do
        for _, r in ipairs(fila.racks) do
            if not r.tipo and not (descartados and descartados[r.rack]) then
                local p, clave
                if r.espera == tipo then
                    p, clave = 0, r.x -- el bloque que ya conoce
                elseif not r.espera then
                    p, clave = 1, (r.x - x) ^ 2 + (r.y - y) ^ 2 -- uno nuevo por descubrir
                end
                if p and (not mejor or p < mejorP or (p == mejorP and clave < mejorClave)) then
                    mejor, mejorP, mejorClave = r, p, clave
                end
            end
        end
    end
    if mejor then
        return mejor.rack
    end
    local fin, mejorD
    for _, fila in ipairs(filasDeRacks(self)) do
        local ultimo = fila.racks[#fila.racks]
        if ultimo and not ultimo.tipo and not (descartados and descartados[ultimo.rack]) then
            local d = (ultimo.x - x) ^ 2 + (ultimo.y - y) ^ 2
            if not mejorD or d < mejorD then
                fin, mejorD = ultimo.rack, d
            end
        end
    end
    return fin
end

-- Va a mirarle el cartel a un rack: se pone a un par de metros, en el pasillo,
-- y mira la placa que cuelga encima. Un cartel cada vez (nada de barrer la
-- fila entera con la cabeza).
local function leerCartel(self, rack)
    local sx, sy, sz, dx, dy = cartelDeRack(rack)
    if not sx then
        return false
    end
    ir(self, { sx + dx * Almacenaje.distanciaCartel, sy + dy * Almacenaje.distanciaCartel,
        math.atan2(-dy, -dx) }, 'miro el cartel del rack', 30)
    self:setMirarA(sx, sy, sz)
    -- Espera a que los ojos lean *ese* cartel (no vale el otro que se ve de
    -- paso por el pasillo).
    local leido = esperar(function()
        for _, c in ipairs(self:getCarteles()) do
            if esCartelDe(c, sx, sy) then
                return true
            end
        end
        return false
    end, Almacenaje.pacienciaCartel)
    self:setMirarA(nil)
    if not leido then
        return false
    end
    -- Qué cartel ha leído.
    local c
    for _, nuevo in ipairs(self:getCarteles()) do
        if esCartelDe(nuevo, sx, sy) then
            c = nuevo
            break
        end
    end
    if not c then
        return false
    end
    self.datos.almacenaje.signos[rack] = { tipo = c.tipo, x = c.x, y = c.y }
    print(string.format('ROBOT leo el cartel %s del rack de %.1f, %.1f', c.tipo, sx, sy))
    return true
end

-- Busca un cartel del tipo pedido: va al que más promete y lo lee. Con uno
-- leído ya sabe dónde está su rack y no vuelve a buscarlo.
local function buscarCartel(self, tipo, nombre)
    local descartados = {}
    for _ = 1, Almacenaje.maxLecturas do
        local rack, numero = destino(self, tipo)
        if rack then
            return rack, numero
        end
        local candidato = mejorCandidato(self, tipo, descartados)
        if not candidato then
            return nil
        end
        descartados[candidato] = true
        if leerCartel(self, candidato) then
            local r, n = destino(self, tipo)
            if r then
                return r, n
            end
        end
    end
    return destino(self, tipo)
end

local NOMBRE = { cartelDinero = 'DINERO', cartelComida = 'COMIDA', cartelMunicion = 'MUNICIÓN', cartelMetal = 'METAL', cartelPetroleo = 'PETRÓLEO' }

-- Abastecer la fábrica ----------------------------------------------------------

local RECURSOS_DEPOSITO = { 'dinero', 'metal', 'petroleo' }

-- Lo de `recurso` guardado en los racks del anexo que conviene llevar: el
-- que más lleva (las pacas a medias, al final).
local function guardadoEnRack(recurso)
    local mejor
    for _, o in ipairs(GestorObjetos.getObjetos()) do
        local mueble = o:getApoyadoEn()
        if o.datos.recurso == recurso and not o:getLlevadoPor() and mueble and mueble:getTipo() == 'rackRobot' and (o.cantidad or 0) > 0 then
            if not mejor or o.cantidad > mejor.cantidad then
                mejor = o
            end
        end
    end
    return mejor
end

-- Si a la fábrica le falta algo en el depósito del misil, lleva una cosa
-- del rack al hueco libre de su zona. Devuelve true si ha llevado algo.
local function abastecer(self)
    local ab = self.datos.almacenaje.abastecer
    if not ab then
        return false
    end
    local falta = ab.faltan()
    for _, recurso in ipairs(RECURSOS_DEPOSITO) do
        if falta[recurso] then
            local dep = ab.deposito
            local numero
            for _, k in ipairs(dep.datos.zonas[recurso] or {}) do
                if not dep.huecosOcupados[k] then
                    numero = k
                    break
                end
            end
            local objeto = numero and guardadoEnRack(recurso)
            if objeto then
                print(string.format('ROBOT llevo la %s (%s) al depósito del misil, hueco %d', objeto:getNombre(), tostring(objeto.cantidad), numero))
                local nombres = { dinero = 'dinero', metal = 'metal', petroleo = 'petróleo' }
                tarea(self, 'la fábrica necesita ' .. nombres[recurso] .. ': llevo la ' .. objeto:getNombre() .. ' al depósito')
                self:setPrisa(Almacenaje.prisaFabrica)
                self:setLlevar(objeto, dep, numero)
                self.datos.conduccion.maximaConPrisa = 0
                esperar(function()
                    return #self:getEncargos() == 0 and not self:getOcupado()
                end)
                self:setPrisa(nil)
                print(string.format('ROBOT dejada en el depósito (iba hasta a %.1f m/s)', self.datos.conduccion.maximaConPrisa or 0))
                return true
            end
        end
    end
    return false
end

-- Dónde mira el patio: al lado de la mesa más cercana que conoce (las cajas
-- se ven desde el lado corto, donde están los huecos); si no conoce
-- ninguna, al portón del patio, desde donde el lidar ve las mesas.
local function sitioDelPatio(self)
    local x, y = self:getPosicion()
    local mejor, mejorD
    for o in pairs(self:getObjetosLidar()) do
        if o:getTipo() == 'mesaRecepcion' then
            local mx, my = o:getPosicion()
            if mx > 30 and my > -1.5 then
                local d = (mx - x) ^ 2 + (my - y) ^ 2
                if not mejorD or d < mejorD then
                    mejor, mejorD = o, d
                end
            end
        end
    end
    if mejor then
        local mx, my = mejor:getPosicion()
        local rx, ry = mejor:getRumbo()
        local cx, cy = math.cos(rx), math.sin(rx)
        return { mx - cx * 1.8, my - cy * 1.8, math.atan2(cy, cx) }
    end
    return Almacenaje.miradoresPatio[1]
end

-- Una vuelta de trabajo (ver arriba).
local function vuelta(self)
    local d = self.datos.almacenaje
    -- Primero la fábrica: si espera algo para un misil, se lo lleva.
    if abastecer(self) then
        return
    end
    local cajas = cajasConocidas(self)
    if #cajas == 0 then
        if d.reloj - d.patioMirado > Almacenaje.repasoPatio then
            ir(self, sitioDelPatio(self), 'voy a ver qué ha llegado al patio', 40)
            tarea(self, 'miro las mesas de descarga')
            mirarMesas(self)
            d.patioMirado = d.reloj
            return
        end
        ir(self, Almacenaje.espera, 'no hay nada mío en el patio: espero')
        pausa(3)
        return
    end
    local caja = cajas[1].o
    local tipo = Almacenaje.cartel[caja.datos.recurso]
    local rack, numero = destino(self, tipo)
    if not rack then
        rack, numero = buscarCartel(self, tipo, NOMBRE[tipo])
    end
    if not rack then
        tarea(self, 'no encuentro sitio para la ' .. caja:getNombre() .. ': la dejo en el patio')
        d.sinSitio[caja] = true
        pausa(2)
        return
    end
    print(string.format('ROBOT llevo la %s (%s) al rack de %s, hueco %d', caja:getNombre(), tostring(caja.cantidad), NOMBRE[tipo], numero))
    self:setLlevar(caja, rack, numero)
    esperar(function()
        return #self:getEncargos() == 0 and not self:getOcupado()
    end)
    if caja:getApoyadoEn() == rack then
        d.guardados = d.guardados + 1
    end
    -- No llegó hasta ella (algo tapa el sitio desde donde se coge): la deja
    -- un rato y sigue con otra, en vez de volver a la misma sin parar.
    local t = self.datos.transporte
    if t.noLlego == caja then
        t.noLlego = nil
        d.noLlego = d.noLlego or setmetatable({}, { __mode = 'k' })
        d.noLlego[caja] = d.reloj
        print(string.format('ROBOT dejo la %s para dentro de %d s', caja:getNombre(), Almacenaje.esperaNoLlego))
    end
end

function Almacenaje:onUpdate(dt)
    local d = self.datos.almacenaje
    d.reloj = d.reloj + dt
    if not d.activo then
        return
    end
    if not d.hilo then
        -- Si alguien le ha dado otros encargos, primero esos.
        if self:getOcupado() or #self:getEncargos() > 0 then
            return
        end
        d.hilo = coroutine.create(function()
            vuelta(self)
        end)
    end
    local ok, error = coroutine.resume(d.hilo, dt)
    if not ok then
        print('ROBOT error en el almacenaje: ' .. tostring(error))
        d.hilo = nil
    elseif coroutine.status(d.hilo) == 'dead' then
        d.hilo = nil
    end
end

--- Lo que necesita la fábrica de misiles: { deposito = el depósito del
-- misil, faltan = function() → { recurso = cantidad } }. Antes de guardar lo
-- del patio, le lleva del rack lo que falte.
function Robot:setAbastecer(abastecer)
    self.datos.almacenaje.abastecer = abastecer
end

function Robot:setTrabajar(si)
    self.datos.almacenaje.activo = si ~= false
end

function Robot:getTrabajando()
    return self.datos.almacenaje.activo == true
end

function Robot:getGuardados()
    return self.datos.almacenaje.guardados
end

GestorRobots.registrarEspecializacion('almacenaje', Almacenaje)
return Almacenaje
