--- El mundo: comarcas de terreno (8 x 8 trozos) que se generan en hilos por
-- delante de la cámara (`mundo/comarcas.lua`) y se olvidan, pasado un tope de
-- memoria, lo más antiguo y lejano.
--
-- El mundo FÍSICO sale de la semilla y no se guarda. El mundo VIVO (naciones,
-- instalaciones, grupos, guerras) está en `self.sim` (mundo/simulacion.lua):
-- aquí solo se dibuja. Cuando se descubre una ciudad, su nación entra en la
-- simulación entera (todas sus ciudades y depósitos) junto con las naciones
-- vecinas, para que tenga con quién comerciar y pelear.

local Terreno = require('mundo.terreno')
local Plantas = require('mundo.plantas')
local Ciudades = require('mundo.ciudades')
local Simulacion = require('mundo.simulacion')
local Recursos = require('mundo.recursos')
local Territorio = require('mundo.territorio')
local Instalaciones = require('mundo.instalaciones')
local Ruido = require('mundo.ruido')
local Iso = require('mundo.iso')
local Ondear = require('mundo.ondear')
local Modelos = require('mundo.modelos')
local Estandartes = require('mundo.estandartes')
local Inteligencia = require('interfaz.inteligencia')
local Choques = require('mundo.choques')
local Senales = require('mundo.senales')
local Indice = require('assets.ui.indice')
local Sombreado = require('mundo.sombreado')
local Comarcas = require('mundo.comarcas')
local Tema = require('interfaz.tema')
local Generador = require('mundo.generador')
local Capas = require('mundo.capas')

local Mundo = {}
Mundo.__index = Mundo

Mundo.margen = 900 -- px de mundo más allá de lo visible (yacimientos y territorio)
Mundo.zoomMinimo = 0.04 -- el zoom más lejano: lo que se ve con él ya está generado
Mundo.zona = Ciudades.porNacion -- regiones por lado de una nación

local LADO = Terreno.celda * Terreno.celdasPorTrozo
-- Cada mundo recibe las mallas de territorio de los hilos por su propio canal.
local siguienteMundo = 0
-- s que se espera la respuesta de un hilo antes de volver a pedirla.
local ESPERA_TERRITORIO = 2

function Mundo.nuevo(semilla)
    local self = setmetatable({}, Mundo)
    self.semilla = semilla
    self.terreno = Terreno.nuevo(semilla)
    self.ciudades = Ciudades.nuevo(self.terreno)
    self.terreno.ciudades = self.ciudades
    self.recursos = Recursos.nuevo(self.terreno, self.ciudades)
    self.trozos = {} -- 'tx,ty' -> trozo de una comarca lista (para el territorio)
    siguienteMundo = siguienteMundo + 1
    self.canalTerritorio = 'territorio.hechos.' .. siguienteMundo
    -- Sube al cambiar de simulación: lo que se pidió con la de antes se tira.
    self.generacionTerritorio = 0
    self.cuantos = 0
    self.ciudadesVistas = {} -- nombre -> ciudad
    self.ciudadesPorId = {} -- id de región -> ciudad dibujable
    self.depositosVistos = {} -- id -> depósito dibujable
    self.zonasRegistradas = {}
    self.zonasHechas = {} -- 'zx,zy' -> datos de la zona que han hecho los hilos
    self.activas = {}
    self.plantas = 0
    self.velocidad = 1 / 60 -- días de juego por segundo: un día dura un minuto
    self.mostrarTerritorio = true
    self.capas = Capas.nuevas() -- casillas del mapa estratégico (ejércitos, yacimientos, batallas)
    -- Reloj visual de la guerra en el mapa (las fichas que se acercan en un
    -- choque): va con el tiempo, se para en pausa y no se acelera.
    self.relojCombate = 0
    self.dibujos = {
        avion = function(...)
            Ciudades.dibujarAvion(...)
        end,
    }
    self.obrasVistas = {} -- instalaciones ya apartadas de las plantas
    self.huertosVistos = {} -- [ciudad] = su huerto ya apartado de las plantas
    self.sim = Simulacion.nueva(semilla, self:opcionesSimulacion())
    self.comarcas = Comarcas.nuevo(self)
    self.msGenerar = 0
    return self
end

--- Lo que la simulación necesita saber del mundo físico: dónde se puede construir.
function Mundo:opcionesSimulacion()
    return {
        sitioValido = self:sitioValido(),
        -- Al cargar, la simulación rehace los yacimientos de sus zonas (no se guardan).
        datosZona = function(zx, zy)
            return self:datosZona(zx, zy)
        end,
    }
end

--- Dónde se puede construir: tierra firme, no muy alta, fuera de las ciudades.
function Mundo:sitioValido()
    return function(x, y)
        local h = self.terreno:base(x, y)
        return h > 18 and h < 200 and not self.ciudades:dentro(x, y)
    end
end

--- Caja de mundo que cubre un rectángulo de la vista (más el margen).
local function cajaMundo(vista)
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, esquina in ipairs({
        { vista.x, vista.y },
        { vista.x + vista.w, vista.y },
        { vista.x, vista.y + vista.h },
        { vista.x + vista.w, vista.y + vista.h },
    }) do
        local x, y = Iso.mundo(esquina[1], esquina[2])
        minX, minY = math.min(minX, x), math.min(minY, y)
        maxX, maxY = math.max(maxX, x), math.max(maxY, y)
    end
    local m = Mundo.margen
    return minX - m, minY - m, maxX + m, maxY + m
end

--- Primera ciudad cerca del origen, para empezar allí.
function Mundo:ciudadInicial()
    for radio = 0, 6 do
        for ry = -radio, radio do
            for rx = -radio, radio do
                local ciudad = self.ciudades:deRegion(rx, ry)
                if ciudad then
                    return ciudad
                end
            end
        end
    end
end

-- Naciones por zonas ------------------------------------------------------------------------

--- Datos de la zona (zx, zy): sus ciudades (la más grande primero: la capital)
-- y sus depósitos. Todo sale de la semilla; normalmente ya los han hecho los
-- hilos (`Comarcas`), y si no, se calculan aquí.
function Mundo:datosZona(zx, zy)
    local hecha = self.zonasHechas[zx .. ',' .. zy]
    if hecha then
        return hecha
    end
    return Generador.datosZona({ ciudades = self.ciudades, recursos = self.recursos }, zx, zy)
end

--- Lo que un hilo ya calculó de la zona (zx, zy) queda en las cachés de aquí:
-- los yacimientos de sus regiones (`datos.depositos`, los de
-- `Generador.datosZona`) y sus candidatas a ciudad y capitales (`ciudades`,
-- de `mundo/obrero.lua`). 27-nov: al mover la cámara, inventar aquí los
-- yacimientos o la ciudad de una región nueva eran 25-30 ms de golpe. Sale lo
-- mismo que si se calculara aquí (la misma semilla y el mismo código); lo que
-- ya estaba no se toca.
function Mundo:sembrarZona(zx, zy, datos, ciudades)
    local lado = Recursos.region
    local ancho = Ciudades.porNacion * Ciudades.region
    local x0, y0 = zx * ancho, zy * ancho
    -- Cada yacimiento, en la región en la que cae (como `Recursos:deRegion`),
    -- en el mismo orden.
    local listas = {}
    for _, d in ipairs(datos.depositos or {}) do
        local k = math.floor(d.x / lado) .. ',' .. math.floor(d.y / lado)
        listas[k] = listas[k] or {}
        local lista = listas[k]
        lista[#lista + 1] = d
    end
    local regiones = self.recursos.regiones
    for ry = math.floor(y0 / lado), math.floor((y0 + ancho - 1) / lado) do
        for rx = math.floor(x0 / lado), math.floor((x0 + ancho - 1) / lado) do
            local k = rx .. ',' .. ry
            if regiones[k] == nil then
                regiones[k] = listas[k] or {}
            end
        end
    end
    if ciudades then
        -- La capital es la misma tabla que su candidata (`Ciudades:deRegion`).
        local propias = self.ciudades
        for k, candidata in pairs(ciudades.candidatas) do
            if propias.regiones[k] == nil then
                propias.regiones[k] = candidata
            end
        end
        for k, es in pairs(ciudades.capitales) do
            if propias.capitales[k] == nil then
                propias.capitales[k] = es and propias.regiones[k] or false
            end
        end
    end
end

--- Registra la nación de una región y las de alrededor (sin seguir más lejos).
function Mundo:registrarNacionDe(rx, ry)
    local zx, zy = math.floor(rx / Mundo.zona), math.floor(ry / Mundo.zona)
    for dy = -1, 1 do
        for dx = -1, 1 do
            local clave = (zx + dx) .. ',' .. (zy + dy)
            if not self.zonasRegistradas[clave] then
                self.zonasRegistradas[clave] = true
                self.sim:registrarZona(self:datosZona(zx + dx, zy + dy))
            end
        end
    end
end

-- Trozos -------------------------------------------------------------------------------------

--- Sitios donde no crecen plantas en un trozo: depósitos e instalaciones cercanas.
function Mundo:despejados(tx, ty)
    local lista = {}
    local cx, cy = (tx + 0.5) * LADO, (ty + 0.5) * LADO
    local rx0, ry0 = math.floor(cx / Recursos.region), math.floor(cy / Recursos.region)
    for dy = -1, 1 do
        for dx = -1, 1 do
            for _, d in ipairs(self.recursos:deRegion(rx0 + dx, ry0 + dy)) do
                lista[#lista + 1] = { x = d.x, y = d.y, r = 170 }
            end
        end
    end
    -- Sin ordenar: el filtro solo pregunta si algún despejado toca, así que el
    -- orden no cambia nada (y ordenar en cada trozo cuesta).
    for _, i in pairs(self.sim.estado.instalaciones) do
        if math.abs(i.x - cx) < LADO * 1.5 and math.abs(i.y - cy) < LADO * 1.5 then
            lista[#lista + 1] = { x = i.x, y = i.y, r = i.tipo == 'base' and 200 or 170 }
        end
    end
    for _, c in pairs(self.sim.estado.ciudades) do
        local h = c.huerto
        if h and math.abs(h.x - cx) < LADO * 1.5 and math.abs(h.y - cy) < LADO * 1.5 then
            lista[#lista + 1] = { x = h.x, y = h.y, r = 150 }
        end
    end
    return lista
end

--- Filtro de plantas de un trozo: ¿(x, y) cae en una ciudad, un depósito o una
-- instalación, donde no crece nada?
function Mundo:sinPlantas(tx, ty)
    local despejados = self:despejados(tx, ty)
    return function(x, y)
        for _, d in ipairs(despejados) do
            if (d.x - x) ^ 2 + (d.y - y) ^ 2 < d.r * d.r then
                return true
            end
        end
        return self.ciudades:dentro(x, y)
    end
end

function Mundo:plantasTrozo(tx, ty)
    return Plantas.mallaTrozo(self.terreno, tx, ty, self:sinPlantas(tx, ty))
end

--- Explora un trozo sin dibujarlo: sus ciudades se construyen, su nación
-- entra en la simulación y sus depósitos se ven. Lo usa `explorarComarca`.
function Mundo:explorarTrozo(tx, ty)
    local clave = tx .. ',' .. ty

    -- Las ciudades que tocan este trozo se construyen ya y su nación entra en la simulación.
    local ciudades = self.ciudades:cercanas((tx + 0.5) * LADO, (ty + 0.5) * LADO)
    for _, ciudad in ipairs(ciudades) do
        self.ciudades:construir(ciudad)
        self.ciudadesVistas[ciudad.nombre] = ciudad
        self.ciudadesPorId[ciudad.region] = ciudad
        local rx, ry = ciudad.region:match('(-?%d+),(-?%d+)')
        self:registrarNacionDe(tonumber(rx), tonumber(ry))
    end
    local rx = math.floor((tx + 0.5) * LADO / Recursos.region)
    local ry = math.floor((ty + 0.5) * LADO / Recursos.region)
    local depositos = self.recursos:deRegion(rx, ry)
    for _, d in ipairs(depositos) do
        self.depositosVistos[d.id] = d
    end

    return clave, ciudades, depositos
end

--- Una comarca acaba de quedar lista (o se ha rehecho): se exploran sus
-- trozos y quedan apuntados para el territorio. Lo llama `Comarcas:instalar`.
function Mundo:explorarComarca(c)
    self.plantas = self.plantas - (c.plantasContadas or 0) + (c.cuantas or 0)
    c.plantasContadas = c.cuantas or 0
    if c.trozos then
        return
    end
    c.trozos, c.ciudades, c.depositos = {}, {}, {}
    local visto = {}
    local n = Comarcas.trozos
    for j = 0, n - 1 do
        for i = 0, n - 1 do
            local tx, ty = c.cx * n + i, c.cy * n + j
            local clave, ciudades, depositos = self:explorarTrozo(tx, ty)
            for _, d in ipairs(depositos) do
                -- Los de la región que caen en esta comarca (una sola vez).
                if not visto[d] and math.floor(d.x / Comarcas.lado) == c.cx and math.floor(d.y / Comarcas.lado) == c.cy then
                    visto[d] = true
                    c.depositos[#c.depositos + 1] = d
                end
            end
            for _, ciudad in ipairs(ciudades) do
                if not visto[ciudad] then
                    visto[ciudad] = true
                    c.ciudades[#c.ciudades + 1] = ciudad
                end
            end
            local t = { tx = tx, ty = ty, comarca = c, i0 = i * Terreno.celdasPorTrozo, j0 = j * Terreno.celdasPorTrozo }
            self.trozos[clave] = t
            c.trozos[#c.trozos + 1] = t
        end
    end
    self.cuantos = self.cuantos + #c.trozos
end

--- La comarca se descarta de la memoria: se olvidan sus trozos.
function Mundo:olvidarComarca(c)
    for _, t in ipairs(c.trozos or {}) do
        if t.territorio then
            t.territorio:release()
        end
        self.trozos[t.tx .. ',' .. t.ty] = nil
    end
    self.cuantos = self.cuantos - #(c.trozos or {})
    self.plantas = self.plantas - (c.plantasContadas or 0)
    c.trozos, c.plantasContadas = nil, nil
end

--- Comarcas que no se descartan nunca: las de tu capital y tus instalaciones.
function Mundo:comarcasFijas()
    local fijas = {}
    local l = Comarcas.lado
    local function fijar(x, y)
        fijas[math.floor(x / l) .. ',' .. math.floor(y / l)] = true
    end
    local mia = self.mira and self.sim:nacion(self.mira)
    if mia then
        local capital = mia.capital and self.sim:ciudad(mia.capital)
        if capital then
            fijar(capital.x, capital.y)
        end
        for _, i in pairs(self.sim.estado.instalaciones) do
            if i.nacion == self.mira then
                fijar(i.x, i.y)
            end
        end
    end
    return fijas
end

--- Cambia la simulación por otra (una partida cargada): el mundo físico es el
-- mismo, las ciudades se vuelven a enlazar por su id de región.
function Mundo:usarSimulacion(sim)
    self.sim = sim
    local opciones = self:opcionesSimulacion()
    sim.sitioValido = opciones.sitioValido
    self.choques, self.enChoque = {}, {}
    self.batallasVistas = {}
    self.generacionTerritorio = (self.generacionTerritorio or 0) + 1
    for _, t in pairs(self.trozos) do
        t.versionTerritorio, t.firmaTerritorio, t.firmaPedida = nil, nil, nil
    end
end

--- Cuando aparece una obra nueva en un trozo cargado, se apartan sus plantas.
-- Va en cada cuadro: sin listas ni orden (27-nov: ordenar todas las obras en
-- cada cuadro costaba más cuanto más larga la partida; da igual en qué orden
-- se rehagan las nuevas).
function Mundo:apartarPlantas()
    local e = self.sim.estado
    local vistas = self.obrasVistas
    for id, sitio in pairs(e.instalaciones) do
        if not vistas[id] then
            vistas[id] = true
            self.comarcas:rehacerCerca(sitio.x, sitio.y)
        end
    end
    local huertos = self.huertosVistos
    for id, ciudad in pairs(e.ciudades) do
        local h = ciudad.huerto
        if h and huertos[id] ~= h then
            huertos[id] = h
            self.comarcas:rehacerCerca(h.x, h.y)
        end
    end
end

--- Pide a los hilos lo que falta por delante de la cámara, sube a la GPU lo
-- que ya está hecho (con `presupuesto` ms como mucho) y descarta lo que sobra.
-- `vista` es lo que se ve; `self.movimiento` ({ vx, vy } en px de vista por
-- segundo), hacia dónde va la cámara.
function Mundo:generar(vista, presupuesto, dt)
    local mov = self.movimiento or {}
    local zoom = self.zoom or 1
    local zona, px, py =
        Comarcas.zona(vista, vista.w * zoom, vista.h * zoom, math.min(Mundo.zoomMinimo, zoom), mov.vx, mov.vy)
    local ms = presupuesto or Comarcas.presupuesto
    -- Tras un salto de la cámara (ir a una noticia, a una capital...) puede
    -- faltar algo a la vista: hasta llenarlo, más tiempo para subirlo.
    if self.comarcas:huecos(vista) > 0 then
        ms = math.max(ms, Comarcas.presupuestoHuecos)
    end
    self.msGenerar = self.comarcas:recibir(ms)
    self.pendientes = self.comarcas:actualizar(vista, zona, px, py, dt)
    self.comarcas:detalle(vista, zoom, math.max(1, ms - self.msGenerar))
end

--- ¿Está generado todo lo que se ve? (La pantalla de carga espera a esto.)
function Mundo:listo(vista)
    return self.comarcas:huecos(vista) == 0
end

Mundo.radioPrecargaMinimo = 190000 -- px (19 km): unos 30 s de generar la primera vez en un Ryzen 5 5500

--- Radio de la precarga alrededor de (x, y): hasta la capital más lejana de
-- las naciones vecinas (la propia y las 8 de alrededor) y dos comarcas más, y
-- al menos `radioPrecargaMinimo`.
function Mundo:radioPrecarga(x, y)
    local lado = Mundo.zona * Ciudades.region
    local zx, zy = math.floor(x / lado), math.floor(y / lado)
    local radio = lado
    for dy = -1, 1 do
        for dx = -1, 1 do
            local capital = self:datosZona(zx + dx, zy + dy).ciudades[1]
            if capital then
                radio = math.max(radio, math.sqrt((capital.x - x) ^ 2 + (capital.y - y) ^ 2))
            end
        end
    end
    return math.max(radio + 2 * Comarcas.lado, Mundo.radioPrecargaMinimo)
end

--- Pantalla de carga: solo genera (sin tiempo de juego), con un presupuesto
-- grande: la zona de la cámara (en memoria) y la precarga hasta las naciones
-- vecinas (en disco). Devuelve la fracción hecha y { hechas, total, radio }.
function Mundo:cargar(vista)
    if not self.comarcas.precarga then
        local x, y = Iso.mundo(vista.x + vista.w / 2, vista.y + vista.h / 2)
        self.comarcas:precargar(x, y, self:radioPrecarga(x, y))
    end
    self:generar(vista, Comarcas.presupuestoCarga, 0)
    local total, hechas = 0, 0
    for k in pairs(self.comarcas.enZona or {}) do
        total = total + 1
        local c = self.comarcas.lista[k]
        if c and c.lista then
            hechas = hechas + 1
        end
    end
    local ph, pt = self.comarcas:progresoPrecarga()
    hechas, total = hechas + ph, total + pt
    return total > 0 and hechas / total or 0, { hechas = hechas, total = total, radio = self.comarcas.precarga.radio }
end

--- Pantalla de carga: rehace todo el territorio que se ve (sin presupuesto
-- corto). ¿Ya está?
function Mundo:territorioAlDia(vista)
    local x0, y0, x1, y1 = cajaMundo(vista)
    local m = Mundo.margen
    return self:repintarTerritorio(x0 + m, y0 + m, x1 - m, y1 - m, vista, 40) == 0
end

--- Genera lo que falta cerca de la cámara, olvida lo lejano y avanza el tiempo.
function Mundo:actualizar(dt, vista)
    local x0, y0, x1, y1 = cajaMundo(vista)
    self:generar(vista, nil, dt)

    -- El paso del tiempo: economía, obras, diplomacia y guerras.
    self.sim:actualizar(dt, self.velocidad)
    -- La simulación ya no manda eventos de salvas ni incursiones.
    self.sim.eventos = {}
    self:recibirBatallas()
    -- Ejércitos trabados en campo abierto (`sim:choques()`): sus fichas se
    -- dibujan juntas y enfrentadas.
    self.choques = Choques.lista(self)
    self.enChoque = Choques.indice(self.choques)
    self:apartarPlantas()
    self.tiempo = (self.tiempo or 0) + dt
    if (self.velocidad or 0) > 0 then
        self.relojCombate = self.relojCombate + math.min(dt, 0.1)
    end

    self:repintarTerritorio(x0 + Mundo.margen, y0 + Mundo.margen, x1 - Mundo.margen, y1 - Mundo.margen, vista)

    -- Ciudades de las comarcas a la vista (con margen): se dibujan y su
    -- bandera ondea.
    self.activas = {}
    local visto = {}
    local m = 2000
    local amplia = { x = vista.x - m, y = vista.y - m, w = vista.w + m * 2, h = vista.h + m * 2 }
    for _, c in ipairs(self.comarcas:visibles(amplia)) do
        for _, ciudad in ipairs(c.ciudades or {}) do
            if ciudad.plaza and not visto[ciudad] then
                visto[ciudad] = true
                self.activas[#self.activas + 1] = ciudad
                self.ciudades:actualizar(ciudad, dt)
            end
        end
    end
end

--- Rehace la malla de territorio de los trozos que la tienen vieja: solo
-- cuando cambia `versionTerritorio` (una celda que cambia de dueño) o el
-- grosor de las franjas (el zoom cruza su umbral). Primero los trozos que se
-- ven (caja x0, y0, x1, y1 del mundo), con `presupuesto` ms por cuadro como
-- mucho (3 si no se da), y después uno o dos de los de fuera (de las comarcas
-- que tocan la `vista` con un margen). Las mallas las hacen los hilos
-- (`Territorio.pedir`); mientras llega la nueva, se sigue viendo la de antes.
-- Devuelve cuántos de los que se ven quedan por rehacer o esperan al hilo.
function Mundo:repintarTerritorio(x0, y0, x1, y1, vista, presupuesto)
    local inicio = love.timer.getTime()
    local limite = (presupuesto or 3) / 1000
    self:recibirTerritorio()
    local grosor = Territorio.grosor(self.zoom)
    local version = (self.sim.estado.versionTerritorio or 0) .. ':' .. grosor
    local m = 2000
    local amplia = { x = vista.x - m, y = vista.y - m, w = vista.w + m * 2, h = vista.h + m * 2 }
    local dentro, fuera = {}, {}
    local esperando = 0
    for _, c in ipairs(self.comarcas:visibles(amplia)) do
        for _, t in ipairs(c.trozos or {}) do
            if t.firmaPedida and inicio - t.pedidoEn > ESPERA_TERRITORIO then
                -- La respuesta no llegó: se vuelve a pedir.
                t.firmaPedida, t.versionTerritorio = nil, nil
            end
            local ax, ay = t.tx * LADO, t.ty * LADO
            local seVe = ax + LADO >= x0 and ax <= x1 and ay + LADO >= y0 and ay <= y1
            if t.versionTerritorio ~= version then
                if seVe then
                    dentro[#dentro + 1] = t
                else
                    fuera[#fuera + 1] = t
                end
            elseif t.firmaPedida and seVe then
                esperando = esperando + 1
            end
        end
    end
    -- ¿Se queda esperando al hilo?
    local function rehacer(t)
        -- Solo se rehace si cambió alguna de sus celdas (o el grosor).
        local firma = Territorio.firma(self.sim, t) .. '|' .. grosor
        if firma == t.firmaTerritorio then
            -- Lo que se pidió antes ya no hace falta (volvió a como estaba).
            t.firmaPedida = nil
        elseif firma ~= t.firmaPedida then
            self:pedirTerritorio(t, firma, grosor)
        end
        t.versionTerritorio = version
        return t.firmaPedida ~= nil
    end
    local quedan = #dentro
    for _, t in ipairs(dentro) do
        if rehacer(t) then
            esperando = esperando + 1
        end
        quedan = quedan - 1
        if love.timer.getTime() - inicio > limite then
            return quedan + esperando
        end
    end
    for k = 1, math.min(2, #fuera) do
        rehacer(fuera[k])
    end
    return esperando
end

--- Pone la malla de territorio del trozo (suelta la que tenía).
local function ponerTerritorio(t, malla, firma)
    if t.territorio then
        t.territorio:release()
    end
    t.territorio = malla
    t.firmaTerritorio, t.firmaPedida = firma, nil
end

--- Pide a los hilos la malla de territorio del trozo con esta `firma`. Sin
-- nada que pintar no hace falta el hilo, y sin hilos se hace aquí.
function Mundo:pedirTerritorio(t, firma, grosor)
    local p = Territorio.pedido(self.sim, t, grosor)
    if not p then
        ponerTerritorio(t, nil, firma)
        return
    end
    if self.territorioSinHilos or not Territorio.arrancarHilos() then
        local datos = Territorio.construir(p)
        ponerTerritorio(t, datos and Territorio.malla(datos), firma)
        return
    end
    p.canal = self.canalTerritorio
    p.firma = firma
    p.generacion = self.generacionTerritorio
    Territorio.pedir(p)
    t.firmaPedida = firma
    t.pedidoEn = love.timer.getTime()
end

--- Las mallas de territorio que han terminado los hilos. Las que ya no hacen
-- falta (el trozo se olvidó o se pidió otra después) se tiran.
function Mundo:recibirTerritorio()
    local canal = love.thread.getChannel(self.canalTerritorio)
    local r = canal:pop()
    while r do
        local t = self.trozos[r.tx .. ',' .. r.ty]
        local vale = t and r.generacion == self.generacionTerritorio and t.firmaPedida == r.firma
        if r.error then
            -- No debería pasar: se avisa y desde aquí se hace sin hilos.
            print('Territorio: error en el hilo: ' .. r.error)
            self.territorioSinHilos = true
            if vale then
                t.firmaPedida, t.versionTerritorio = nil, nil
            end
        elseif vale then
            ponerTerritorio(t, r.datos and Territorio.malla(r.datos), r.firma)
        elseif r.datos then
            r.datos:release()
        end
        r = canal:pop()
    end
end

-- Dibujo -------------------------------------------------------------------------------------

function Mundo:cargado(x, y)
    return self.comarcas:en(x, y) ~= nil
end

--- ¿Se dibuja lo que está en (x, y) del mundo? Su comarca está lista y cae
-- cerca de la vista (con margen para lo alto: montes, torres y humo).
function Mundo:dibujable(x, y)
    local v = self.vista
    if v then
        local vx, vy = Iso.vista(x, y, 0)
        local m = 800
        if not (vx > v.x - m and vx < v.x + v.w + m and vy > v.y - m and vy < v.y + v.h + Comarcas.alturaMaxima) then
            return false
        end
    end
    return self:cargado(x, y)
end

--- Trozos con territorio de las comarcas `lista`, de atrás adelante.
local function trozosConTerritorio(lista)
    local trozos = {}
    for _, c in ipairs(lista) do
        for _, t in ipairs(c.trozos or {}) do
            if t.territorio then
                trozos[#trozos + 1] = t
            end
        end
    end
    table.sort(trozos, function(a, b)
        if a.tx + a.ty ~= b.tx + b.ty then
            return a.tx + a.ty < b.tx + b.ty
        end
        return a.tx < b.tx
    end)
    return trozos
end

--- Lienzo del tamaño de la pantalla para fundir los objetos de cerca al pasar
-- a la capa media (se crea al usarlo y se rehace si cambia la ventana).
function Mundo:lienzoFundido()
    local w, h = love.graphics.getDimensions()
    if not self.lienzo or self.lienzo:getWidth() ~= w or self.lienzo:getHeight() ~= h then
        self.lienzo = love.graphics.newCanvas(w, h)
    end
    return self.lienzo
end

function Mundo:dibujar()
    local g = love.graphics
    local vista = self.vista or { x = -1e9, y = -1e9, w = 2e9, h = 2e9 }
    local lista = self.comarcas:visibles(vista)
    -- Capas (mundo/capas.lua): cuánto se ve del mapa de cerca, de la capa
    -- media (iconos) y del mapa estratégico.
    local cerca, media, lejos = Capas.pesos(self.zoom or 1)
    self.pesosCapas = { cerca = cerca, media = media, lejos = lejos }
    -- De cerca, con todo el detalle si ya está su malla; de lejos, la
    -- sencilla; entre medias, la de cerca fundida encima (`Comarcas.fundido`).
    local fundido = Comarcas.fundido(self.zoom or 1)
    g.setColor(1, 1, 1, 1)
    g.setShader(Sombreado.para(self.terreno))
    Sombreado.capas(1 - cerca, lejos)
    for _, c in ipairs(lista) do
        if fundido >= 1 and c.suelo then
            g.draw(c.suelo)
        else
            g.draw(c.lejos)
            if fundido > 0 and c.suelo then
                g.setColor(1, 1, 1, fundido)
                g.draw(c.suelo)
                g.setColor(1, 1, 1, 1)
            end
        end
    end
    g.setShader()
    if self.mostrarTerritorio then
        for _, t in ipairs(trozosConTerritorio(lista)) do
            g.draw(t.territorio)
        end
    end
    -- Las fichas se calculan siempre (las usan los clics y la interfaz).
    self.dibujos.zoom = self.zoom
    self:fichasGrupos()
    if cerca > 0 then
        -- Mientras se funde con la capa media, los objetos de cerca se dibujan
        -- en un lienzo que se pone encima con transparencia.
        local lienzo = cerca < 1 and self:lienzoFundido()
        if lienzo then
            g.setCanvas(lienzo)
            g.clear(0, 0, 0, 0)
        end
        self:dibujarObjetosCerca(lista, fundido)
        if lienzo then
            g.setCanvas()
            g.push()
            g.origin()
            g.setColor(cerca, cerca, cerca, cerca)
            g.setBlendMode('alpha', 'premultiplied')
            g.draw(lienzo)
            g.setBlendMode('alpha')
            g.pop()
            g.setColor(1, 1, 1, 1)
        end
    end
    if cerca < 1 then
        self:dibujarIconos(media, lejos)
    end
    self:dibujarResto(lejos)
end

--- Lo que solo se ve de cerca: huertos, bases de las ciudades, árboles,
-- torres, instalaciones, yacimientos y vehículos, ordenados por profundidad.
function Mundo:dibujarObjetosCerca(lista, fundido)
    local g = love.graphics
    -- Huertos de emergencia junto a las ciudades.
    for _, id in ipairs(Simulacion.ordenadas(self.sim.estado.ciudades)) do
        local c = self.sim.estado.ciudades[id]
        if c.huerto and self:dibujable(c.huerto.x, c.huerto.y) then
            Instalaciones.dibujarHuerto(c.huerto, self.terreno:altura(c.huerto.x, c.huerto.y), self.sim.estado.dia)
        end
    end
    -- La base de la torre de cada ciudad.
    for _, ciudad in ipairs(self.activas) do
        ciudad.datos = self.sim:ciudad(ciudad.region)
        local nacion = ciudad.datos and self.sim:nacion(ciudad.datos.nacion)
        ciudad.color = nacion and nacion.color or { 0.8, 0.8, 0.8 }
        ciudad.esCapital = nacion and nacion.capital == ciudad.region
        self.ciudades:construir(ciudad)
        g.setColor(1, 1, 1, 1)
        g.draw(ciudad.suelo)
    end
    g.setColor(1, 1, 1, 1)
    for _, c in ipairs(lista) do
        local plantas = c.plantasLejos
        if fundido >= 0.5 and c.suelo then
            plantas = c.plantas
        end
        if plantas then
            g.draw(plantas)
        end
    end

    local piezas = {}
    for _, ciudad in ipairs(self.activas) do
        self.ciudades:piezas(ciudad, piezas)
    end
    self:piezasDepositos(piezas)
    self:piezasLanzacohetes(piezas)
    table.sort(piezas, function(a, b)
        return a.profundidad < b.profundidad
    end)
    for _, p in ipairs(piezas) do
        if p.malla then
            g.setColor(1, 1, 1, 1)
            g.draw(p.malla)
        elseif p.dibujar then
            p.dibujar()
        end
    end
end

-- Iconos de la capa media y del mapa estratégico ------------------------------------------------

local NOMBRE_INSTALACION = {
    base = 'Base',
    campamento = 'Campamento',
    bandera = 'Bandera',
    petroleo = 'Pozo',
    metal = 'Mina',
    oro = 'Mina de oro',
    comida = 'Granja',
}
local ICONO_INSTALACION = {
    base = 'escudo',
    campamento = 'construir',
    bandera = 'bandera',
    petroleo = 'petroleo',
    metal = 'metal',
    oro = 'dinero',
    comida = 'comida',
}

--- Imagen blanca de 32 px del kit de iconos (`assets/ui/iconos`), cacheada.
local imagenesIcono = {}
local function imagenIcono(nombre)
    if imagenesIcono[nombre] == nil then
        local entrada = Indice.iconos[nombre]
        local ok, imagen = pcall(love.graphics.newImage, 'assets/ui/' .. (entrada and entrada.archivos['32'] or ''))
        imagenesIcono[nombre] = ok and imagen or false
        if ok then
            imagen:setFilter('linear', 'linear')
        end
    end
    return imagenesIcono[nombre] or nil
end

--- Icono redondo de tamaño fijo en pantalla: disco oscuro, aro del color
-- `color` y el icono blanco `nombre` (o una estrella, con `estrella`). En
-- coordenadas de pantalla; `alfa` para los fundidos.
local function iconoRedondo(sx, sy, radio, color, nombre, alfa, estrella)
    local g = love.graphics
    g.setColor(0.07, 0.08, 0.06, 0.85 * alfa)
    g.circle('fill', sx, sy, radio)
    g.setColor(color[1], color[2], color[3], alfa)
    g.setLineWidth(math.max(1.5, radio * 0.2))
    g.circle('line', sx, sy, radio)
    g.setLineWidth(1)
    if estrella then
        g.setColor(0.99, 0.86, 0.39, alfa)
        dibujarEstrella(sx, sy, radio * 0.62)
    else
        local imagen = nombre and imagenIcono(nombre)
        if imagen then
            local k = radio * 1.25 / imagen:getWidth()
            g.setColor(1, 1, 1, alfa)
            g.draw(imagen, sx, sy, 0, k, k, imagen:getWidth() / 2, imagen:getHeight() / 2)
        end
    end
end

--- Capa media y mapa estratégico: las instalaciones (solo en la media) como
-- iconos pequeños con su nombre, cada ciudad con su icono (la estrella en la
-- capital) y, en el estratégico, las batallas. Tamaño fijo en pantalla.
function Mundo:dibujarIconos(media, lejos)
    local g = love.graphics
    local zoom = self.zoom or 1
    local anterior = g.getFont()
    local fuente = Tema.fuente('sans', 13)
    g.push()
    g.origin()
    local camara = self.camara
    local w, h = g.getDimensions()
    local function pantalla(x, y, z)
        local vx, vy = Iso.vista(x, y, z)
        return (vx - camara.x) * zoom + w / 2, (vy - camara.y) * zoom + h / 2
    end
    local alfa = 1 - (self.pesosCapas and self.pesosCapas.cerca or 0)
    -- Instalaciones: solo en la capa media (en el estratégico, lo importante).
    if media > 0 then
        local e = self.sim.estado
        local nombres = math.max(0, math.min(1, (zoom - 0.06) / 0.01)) * media
        g.setFont(fuente)
        for _, id in ipairs(self:instalacionesCerca()) do
            local inst = e.instalaciones[id]
            local nacion = self.sim:nacion(inst.nacion)
            if inst.tipo ~= 'bandera' and nacion then
                local deposito = inst.deposito and e.depositos[inst.deposito]
                local tipo = (inst.tipo == 'base' or inst.tipo == 'campamento') and inst.tipo
                    or (deposito and deposito.tipo)
                    or inst.tipo
                local sx, sy = pantalla(inst.x, inst.y, math.max(0, self.terreno:altura(inst.x, inst.y)))
                iconoRedondo(sx, sy, Tema.px(20), nacion.color, ICONO_INSTALACION[tipo], media)
                local texto = NOMBRE_INSTALACION[tipo]
                if texto and nombres > 0.02 then
                    local tx = math.floor(sx - fuente:getWidth(texto) / 2)
                    local ty = math.floor(sy + Tema.px(22))
                    g.setColor(0.07, 0.08, 0.05, 0.9 * nombres)
                    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
                        g.print(texto, tx + d[1], ty + d[2])
                    end
                    g.setColor(1, 1, 0.95, nombres)
                    g.print(texto, tx, ty)
                end
            end
        end
    end
    -- Ciudades: su icono en el suelo (el nombre lo pone `dibujarNombres`).
    for _, ciudad in ipairs(self.activas) do
        local datos = self.sim:ciudad(ciudad.region)
        local nacion = datos and self.sim:nacion(datos.nacion)
        if nacion then
            local sx, sy = pantalla(ciudad.x, ciudad.y, ciudad.altura)
            iconoRedondo(sx, sy, Tema.px(24), nacion.color, 'escudo', alfa, nacion.capital == datos.id)
        end
    end
    -- Batallas, en el mapa estratégico (con su casilla).
    if lejos > 0 and self.capas.batallas then
        for _, id in ipairs(Simulacion.ordenadas(self.sim.estado.batallas or {})) do
            local b = self.sim.estado.batallas[id]
            if b.x and b.y then
                local sx, sy = pantalla(b.x, b.y, math.max(0, self.terreno:altura(b.x, b.y)))
                if sx > -40 and sx < w + 40 and sy > -40 and sy < h + 40 then
                    iconoRedondo(sx, sy, Tema.px(24), { 0.85, 0.2, 0.18 }, 'batallas', lejos)
                end
            end
        end
    end
    g.pop()
    g.setColor(1, 1, 1, 1)
    g.setFont(anterior)
end

--- Encima de todo: nombres, yacimientos, banderas y fichas. En el mapa
-- estratégico, solo lo que piden sus casillas (`self.capas`).
function Mundo:dibujarResto(lejos)
    local g = love.graphics
    local estrategico = lejos >= 0.5
    self:dibujarNombres()
    if not estrategico or self.capas.yacimientos then
        self:dibujarYacimientos()
    else
        self.anclasMinas, self.cajasMinas = {}, {}
    end
    if not estrategico then
        self:dibujarBanderas()
    end
    -- Lo que va bajo las fichas (selección), en coordenadas de pantalla.
    if self.antesDeFichas then
        g.push()
        g.origin()
        self.antesDeFichas()
        g.pop()
    end
    if not estrategico or self.capas.ejercitos then
        self:dibujarFichas()
        self:dibujarAviones()
    end
    g.setColor(1, 1, 1, 1)
end

-- Aviones de transporte (mundo/simulacion/aviones.lua) ----------------------------------------
-- El modelo 3D del avión visto con el ángulo del mapa en 16 rumbos
-- (tools/blender/avion_mapa.py), de tamaño fijo en pantalla como las fichas,
-- en el aire sobre su sombra. Despega y aterriza en el primer y el último
-- tramo de cada viaje.

Mundo.anchoAvion = 130 -- px de pantalla de un cuadro de la hoja
Mundo.alturaAvion = 46 -- px de pantalla sobre su sombra en vuelo
Mundo.rampaAvion = 0.12 -- parte del viaje que tarda en subir (y en bajar)

local avionMapa -- { hoja, cuadros, indice } (se carga al primer uso)

local function cargarAvion()
    if avionMapa == nil then
        local indice = require('assets.mapa.avion.indice')
        if love.filesystem.getInfo(indice.hoja) then
            local hoja = love.graphics.newImage(indice.hoja, { mipmaps = true })
            hoja:setFilter('linear', 'linear')
            hoja:setMipmapFilter('linear')
            local cuadros = {}
            local w, h = hoja:getDimensions()
            for k = 0, indice.rumbos - 1 do
                cuadros[k] = love.graphics.newQuad(
                    (k % 4) * indice.cuadro,
                    math.floor(k / 4) * indice.cuadro,
                    indice.cuadro,
                    indice.cuadro,
                    w,
                    h
                )
            end
            avionMapa = { hoja = hoja, cuadros = cuadros, indice = indice }
        else
            avionMapa = false
        end
    end
    return avionMapa or nil
end

--- Dónde va el vuelo `v` ahora (entre el paso anterior y el actual), su
-- rumbo (rad, en el plano del mapa) y cuánto lleva del viaje (0 a 1).
function Mundo:posicionVuelo(v, fraccion)
    local e = self.sim.estado
    local x = v.antesX + (v.x - v.antesX) * fraccion
    local y = v.antesY + (v.y - v.antesY) * fraccion
    local dx, dy, t
    local gr = e.grupos[v.grupo]
    if v.fase == 'llevar' and gr and gr.largo and gr.largo > 0 then
        local r = gr.ruta
        dx, dy = r[#r - 1] - r[1], r[#r] - r[2]
        t = gr.recorrido / gr.largo
    else
        dx, dy = v.dx - v.ox, v.dy - v.oy
        t = v.largo > 0 and v.recorrido / v.largo or 1
    end
    if dx == 0 and dy == 0 then
        dx, dy = v.x - v.antesX, v.y - v.antesY
    end
    return x, y, math.atan2(dy, dx), t
end

function Mundo:dibujarAviones()
    local e = self.sim.estado
    local avion = e.vuelos and next(e.vuelos) and cargarAvion()
    if not avion then
        return
    end
    local g = love.graphics
    local k = 1 / math.max(0.05, self.zoom or 1)
    local fraccion = self.sim:fraccionPaso()
    local cuadro = avion.indice.cuadro
    local escala = Mundo.anchoAvion / cuadro * k
    local rumbos = avion.indice.rumbos
    local lista = {}
    -- Vuelos parados en el mismo sitio (aparcados en una mina): uno al lado
    -- del otro, no encima.
    local enSitio = {}
    for _, id in ipairs(Simulacion.ordenadas(e.vuelos)) do
        local v = e.vuelos[id]
        local x, y, rumbo, t = self:posicionVuelo(v, fraccion)
        local vx, vy = Iso.vista(x, y, self.terreno:altura(x, y))
        if self:enVista(vx, vy) then
            -- Sube al salir y baja al llegar.
            local rampa = Mundo.rampaAvion
            local alto = math.max(0, math.min(1, t / rampa, (1 - t) / rampa))
            local paso = Mundo.anchoAvion * 0.8 * k
            if alto <= 0 then
                local clave = math.floor(vx / paso) .. ':' .. math.floor(vy / paso)
                local n = enSitio[clave] or 0
                enSitio[clave] = n + 1
                vx = vx + n * paso * 1.15
            end
            -- Todos los aviones del vuelo, en formación sobre el suelo: el
            -- primero delante y los demás detrás, alternando a cada lado.
            local c, sn = math.cos(rumbo), math.sin(rumbo)
            for i = 1, #v.aviones do
                local fila = math.floor(i / 2)
                local lado = (i % 2 == 0) and 1 or -1
                local atras = fila * paso * 1.0
                local costado = (i == 1) and 0 or lado * fila * paso * 1.4
                local ox, oy = -c * atras - sn * costado, -sn * atras + c * costado
                local dx, dy = Iso.vista(ox, oy, 0)
                lista[#lista + 1] = {
                    v = v, primero = i == 1, rumbo = rumbo, alto = alto,
                    vx = vx + dx,
                    vy = vy + dy,
                }
            end
        end
    end
    -- Las sombras primero (en el suelo), luego los aviones, de atrás adelante.
    table.sort(lista, function(a, b)
        return a.vy < b.vy
    end)
    for _, a in ipairs(lista) do
        local cuadroK = math.floor(((a.rumbo % (2 * math.pi)) / (2 * math.pi)) * rumbos + 0.5) % rumbos
        a.cuadro = avion.cuadros[cuadroK]
        g.setColor(0, 0, 0, 0.28 * (0.4 + 0.6 * a.alto))
        g.draw(avion.hoja, a.cuadro, a.vx, a.vy, 0, escala, escala * 0.55, cuadro / 2, cuadro / 2)
    end
    for _, a in ipairs(lista) do
        local sobre = a.vy - Mundo.alturaAvion * k * a.alto
        g.setColor(1, 1, 1, 1)
        g.draw(avion.hoja, a.cuadro, a.vx, sobre, 0, escala, escala, cuadro / 2, cuadro / 2)
        -- Su nación: un disco de su color encima del primero del vuelo.
        if a.primero then
            local n = e.naciones[a.v.nacion]
            local color = n and n.color or { 0.8, 0.8, 0.8 }
            local r = 6 * k
            local cy = sobre - 30 * k
            g.setColor(0.08, 0.08, 0.09, 0.9)
            g.circle('fill', a.vx, cy, r + 2 * k)
            g.setColor(color[1], color[2], color[3], 1)
            g.circle('fill', a.vx, cy, r)
        end
    end
    g.setColor(1, 1, 1, 1)
end

--- Estrella de cinco puntas rellena, centrada en (x, y), de radio `r`.
function dibujarEstrella(x, y, r)
    local puntos = {}
    for k = 0, 9 do
        local a = -math.pi / 2 + k * math.pi / 5
        local radio = k % 2 == 0 and r or r * 0.42
        puntos[#puntos + 1] = x + math.cos(a) * radio
        puntos[#puntos + 1] = y + math.sin(a) * radio
    end
    for _, t in ipairs(love.math.triangulate(puntos)) do
        love.graphics.polygon('fill', t)
    end
end

--- Texto blanco con contorno oscuro (se lee sobre cualquier terreno).
local function textoContorno(fuente, texto, x, y, color)
    local g = love.graphics
    g.setFont(fuente)
    g.setColor(0.07, 0.08, 0.05, 0.95)
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        g.print(texto, x + d[1], y + d[2])
    end
    g.setColor(color[1], color[2], color[3], color[4] or 1)
    g.print(texto, x, y)
end

--- Nombre de cada ciudad a la vista y, sobre la capital, una estrella y el
-- nombre de su país: texto blanco con contorno sobre un rótulo oscuro, y el
-- color de la nación en una franja a la izquierda (el color solo no se lee
-- sobre el terreno). Se leen igual con cualquier zoom.
function Mundo:dibujarNombres()
    local g = love.graphics
    local barlow = Indice.tipografia.archivos
    self.fuenteNombre = self.fuenteNombre or g.newFont(barlow.subtitulo, 17)
    self.fuentePais = self.fuentePais or g.newFont(barlow.subtitulo, 22)
    -- De cerca, sobre la torre y con el tamaño de antes; en la capa media y el
    -- mapa estratégico, sobre el icono de la ciudad y de tamaño fijo en pantalla.
    local zoom = self.zoom or 1
    local cerca = self.pesosCapas and self.pesosCapas.cerca or 1
    local k = cerca / math.max(0.15, zoom) + (1 - cerca) * 0.85 / zoom
    local anterior = g.getFont()
    -- Cajas de los nombres en coordenadas de la vista: las fichas de los grupos
    -- se apartan de ellas (ver `dibujarFichas`).
    self.cajasNombres = {}
    for _, ciudad in ipairs(self.activas) do
        local datos = self.sim:ciudad(ciudad.region)
        local nacion = datos and self.sim:nacion(datos.nacion)
        -- `sinNombre`: la ciudad del menú radial abierto (su nombre va en la placa del menú).
        if nacion and datos.id ~= self.sinNombre then
            local capital = nacion.capital == datos.id
            local vx, vy = Iso.vista(ciudad.x, ciudad.y, ciudad.altura + 350 * cerca)
            vy = vy - (1 - cerca) * Tema.px(44) / zoom
            local nombre = ciudad.nombre
            -- La estrella se dibuja: la fuente no tiene el carácter ★.
            local estrella = capital and 18 or 0
            g.push()
            g.translate(vx, vy)
            g.scale(k)
            local ancho = self.fuenteNombre:getWidth(nombre) + 16 + estrella
            local anchoCaja = ancho
            if capital then
                anchoCaja = math.max(ancho, self.fuentePais:getWidth(nacion.nombre) + 32)
            end
            local arribaCaja = capital and -48 or -12
            self.cajasNombres[#self.cajasNombres + 1] = {
                x = vx - anchoCaja / 2 * k,
                y = vy + arribaCaja * k,
                w = anchoCaja * k,
                h = (12 - arribaCaja) * k,
            }
            g.setColor(0.09, 0.11, 0.06, 0.78)
            g.rectangle('fill', -ancho / 2, -12, ancho, 24, 4, 4)
            if capital then
                g.setColor(0.99, 0.86, 0.39)
                dibujarEstrella(-ancho / 2 + 15, 0, 7)
            end
            textoContorno(
                self.fuenteNombre,
                nombre,
                -ancho / 2 + 8 + estrella,
                -self.fuenteNombre:getHeight() / 2,
                { 1, 1, 0.95 }
            )
            if capital then
                local pais = nacion.nombre
                local anchoPais = self.fuentePais:getWidth(pais) + 32
                g.setColor(0.09, 0.11, 0.06, 0.82)
                g.rectangle('fill', -anchoPais / 2, -48, anchoPais, 32, 4, 4)
                -- Franja con el color de la nación.
                g.setColor(nacion.color)
                g.rectangle('fill', -anchoPais / 2, -48, 6, 32, 3, 3)
                textoContorno(
                    self.fuentePais,
                    pais,
                    -anchoPais / 2 + 16,
                    -32 - self.fuentePais:getHeight() / 2,
                    { 1, 1, 0.95 }
                )
            end
            g.pop()
        end
    end
    g.setFont(anterior)
end

--- Iconos de los yacimientos explorados (3.8): gota, pico, pepita o espiga,
-- del mismo tamaño en pantalla a cualquier zoom, con el aro del color de su
-- dueño (gris si es de nadie) y un fondo más claro si son tuyos. Encima, lo
-- que queda, el escudo de quien recolecta, las espadas de una batalla, el
-- bonus de tu territorio y, si está cerrada, los días que le faltan (ver
-- `Senales.yacimiento`). Solo los de la vista (`yacimientosEn`).
function Mundo:dibujarYacimientos()
    self.anclasMinas = {}
    if not self.vista then
        return
    end
    local g = love.graphics
    local zoom = self.zoom or 1
    local k = 1 / math.max(0.05, zoom)
    local x0, y0, x1, y1 = cajaMundo(self.vista)
    local lado = Senales.ladoYacimiento(zoom)
    local puntos = zoom >= 0.14
    self.cajasNombres = self.cajasNombres or {}
    self.cajasMinas = {}
    for _, y in ipairs(self.sim:yacimientosEn(x0, y0, x1, y1)) do
        local d = self.depositosVistos[y.id]
        if d then
            local vx, vy = Iso.vista(y.x, y.y, d.altura or 0)
            if self:enVista(vx, vy) then
                local duena = y.dueno and self.sim:nacion(y.dueno)
                local escudo = y.principal and Estandartes.escudoDe(self.semilla, y.principal)
                g.push()
                g.translate(vx, vy)
                g.scale(k)
                -- Alzado sobre el dibujo del yacimiento, como una chincheta.
                local cy = -lado * 1.6
                g.setColor(0, 0, 0, 0.35)
                g.setLineWidth(1)
                g.line(0, 0, 0, cy + lado / 2)
                local caja = Senales.yacimiento(y, 0, cy, lado, {
                    aro = duena and duena.color,
                    tuyo = self.mira ~= nil and y.dueno == self.mira,
                    puntos = puntos,
                    escudo = escudo,
                    naciones = #y.recolectores,
                    bonus = self.mira ~= nil and y.bonus == self.mira,
                })
                g.pop()
                local vista = { x = vx + caja.x * k, y = vy + caja.y * k, w = caja.w * k, h = caja.h * k }
                self.cajasMinas[#self.cajasMinas + 1] = { id = y.id, caja = vista }
                self.anclasMinas[y.id] = vista
                if #y.recolectores > 0 or y.batalla or y.cerrada then
                    -- Las fichas se apartan de las minas con algo que leer.
                    self.cajasNombres[#self.cajasNombres + 1] = vista
                end
            end
        end
    end
end

--- Yacimiento cuyo icono está bajo el punto (vx, vy) de la vista, o nil.
function Mundo:minaEn(vx, vy)
    for i = #(self.cajasMinas or {}), 1, -1 do
        local c = self.cajasMinas[i].caja
        if vx >= c.x and vx <= c.x + c.w and vy >= c.y and vy <= c.y + c.h then
            return self.cajasMinas[i].id
        end
    end
    return nil
end

--- Banderas plantadas (3.7): un mástil con el paño y el escudo de su nación,
-- de tamaño fijo en pantalla, con la barra de obra y, si la atacan, la de
-- vida. De cerca (zoom ≥ Instalaciones.zoomBandera) ya se ve el mástil del
-- mundo: solo las barras.
-- Sus cajas se suman a las de los nombres para que las fichas se aparten.
function Mundo:dibujarBanderas()
    local g = love.graphics
    local zoom = self.zoom or 1
    local k = 1 / math.max(0.05, zoom)
    local soloBarras = zoom >= Instalaciones.zoomBandera
    self.cajasNombres = self.cajasNombres or {}
    for _, b in ipairs(self.sim:banderas()) do
        local z = self.terreno:altura(b.x, b.y)
        local vx, vy = Iso.vista(b.x, b.y, z)
        local nacion = self.sim:nacion(b.nacion)
        if nacion and self:enVista(vx, vy) then
            local escudo = Estandartes.escudoDe(self.semilla, b.nacion)
            g.push()
            g.translate(vx, vy)
            g.scale(k)
            local caja = Senales.bandera(b, 0, 0, nacion.color, escudo, soloBarras)
            g.pop()
            self.cajasNombres[#self.cajasNombres + 1] = {
                x = vx + caja.x * k,
                y = vy + caja.y * k,
                w = caja.w * k,
                h = caja.h * k,
            }
        end
    end
end

--- Ids (ordenados) de las instalaciones cerca de la vista y en comarcas listas.
function Mundo:instalacionesCerca()
    local cerca = {}
    for id, inst in pairs(self.sim.estado.instalaciones) do
        if self:dibujable(inst.x, inst.y) then
            cerca[id] = true
        end
    end
    return Simulacion.ordenadas(cerca)
end

--- Yacimientos e instalaciones (bases, campamentos y banderas). Ya no hay
-- extracciones: los yacimientos se recolectan con grupos
-- (diseno/recoleccion-y-batallas.md).
function Mundo:piezasDepositos(piezas)
    local e = self.sim.estado
    -- Solo los de las comarcas que se ven (con miles explorados, recorrerlos y
    -- ordenarlos todos cada cuadro costaba milisegundos).
    local v = self.vista or { x = 0, y = 0, w = 0, h = 0 }
    local m = 800
    local amplia = { x = v.x - m, y = v.y - m, w = v.w + m * 2, h = v.h + m * 2 }
    local depositos = {}
    for _, c in ipairs(self.comarcas:visibles(amplia)) do
        for _, d in ipairs(c.depositos or {}) do
            if self:dibujable(d.x, d.y) then
                depositos[#depositos + 1] = d
            end
        end
    end
    table.sort(depositos, function(a, b)
        return a.id < b.id
    end)
    for _, d in ipairs(depositos) do
        piezas[#piezas + 1] = {
            profundidad = Iso.profundidad(d.x, d.y),
            dibujar = function()
                Recursos.dibujar(d, nil, self.tiempo or 0)
            end,
        }
    end
    for _, id in ipairs(self:instalacionesCerca()) do
        local inst = e.instalaciones[id]
        do
            local nacion = self.sim:nacion(inst.nacion)
            local deposito = inst.deposito and e.depositos[inst.deposito]
            local z = self.terreno:altura(inst.x, inst.y)
            piezas[#piezas + 1] = {
                profundidad = Iso.profundidad(inst.x, inst.y),
                dibujar = function()
                    Instalaciones.dibujar(inst, deposito, nacion.color, z, self.tiempo or 0, self.dibujos)
                end,
            }
        end
    end
end

-- Lanzacohetes -------------------------------------------------------------------------------

Mundo.lanzacohetesPorCiudad = 4 -- como mucho se dibujan estos junto a una ciudad
-- Una base tiene sus plataformas fijas: se dibujan todos los que tiene (hasta el tope).
Mundo.lanzacohetesPorBase = Simulacion.defensasBase.topeLanzacohetes
Mundo.radioPuestosBase = 250 -- fuera de la losa (esquinas a 226 px) y de la valla de la base
Mundo.separacionPuestos = 130 -- distancia mínima entre dos lanzacohetes aparcados

--- La ciudad física de `id`: la de la región ('rx,ry', sale de la semilla) o
-- una fundada durante la partida (si ya se vio).
function Mundo:ciudadFisica(id)
    local rx, ry = tostring(id):match('^(-?%d+),(-?%d+)$')
    if rx then
        return self.ciudades:deRegion(tonumber(rx), tonumber(ry))
    end
    return self.ciudadesPorId[id]
end

--- Puestos (x, y, z) de los lanzacohetes de un sitio: en un anillo alrededor de
-- una ciudad o por fuera de la losa de una base, siempre en tierra y separados
-- entre sí. Salen de su id, así que no cambian.
function Mundo:puestosLanzacohetes(sitio)
    self.puestos = self.puestos or {}
    if self.puestos[sitio.id] then
        return self.puestos[sitio.id]
    end
    local esBase = sitio.tipo == 'base'
    local cuantos = esBase and Mundo.lanzacohetesPorBase or Mundo.lanzacohetesPorCiudad
    -- En una ciudad, a 120 px de su borde (que depende de su forma).
    local fisica = not esBase and self:ciudadFisica(sitio.id)
    local function radioEn(angulo)
        if esBase then
            return Mundo.radioPuestosBase
        end
        return (fisica and Ciudades.borde(fisica, angulo) or Simulacion.casco(sitio)) + 120
    end
    local semilla = 0
    for k = 1, #sitio.id do
        semilla = semilla + sitio.id:byte(k) * k
    end
    local inicio = (semilla % 628) / 100
    local puestos = {}
    local function libre(x, y)
        for _, otro in ipairs(puestos) do
            if (otro.x - x) ^ 2 + (otro.y - y) ^ 2 < Mundo.separacionPuestos ^ 2 then
                return false
            end
        end
        return true
    end
    for k = 0, cuantos - 1 do
        local angulo = inicio + k * 2 * math.pi / cuantos
        -- Si cae en el agua o encima de otro, sigue girando (como mucho una vuelta).
        for _ = 1, 18 do
            local radio = radioEn(angulo)
            local x, y = sitio.x + math.cos(angulo) * radio, sitio.y + math.sin(angulo) * radio
            local z = self.terreno:altura(x, y)
            if z > 4 and libre(x, y) then
                -- Aparcado de lado respecto al centro.
                puestos[#puestos + 1] = { x = x, y = y, z = z, angulo = angulo + math.pi / 2 }
                break
            end
            angulo = angulo + 0.35
        end
    end
    self.puestos[sitio.id] = puestos
    return puestos
end

--- Cuántos lanzacohetes se ven en un sitio: los de la ciudad (hasta 4) o los
-- de una base terminada (hasta 6).
function Mundo:lanzacohetesVisibles(sitio)
    if sitio.tipo == 'base' then
        if sitio.progreso < 1 then
            return 0
        end
        return math.min(sitio.lanzacohetes or 0, Mundo.lanzacohetesPorBase)
    end
    return math.min(sitio.lanzacohetes or 0, Mundo.lanzacohetesPorCiudad)
end

function Mundo:piezasLanzacohetes(piezas)
    local e = self.sim.estado
    local sitios = {}
    for _, ciudad in ipairs(self.activas) do
        if ciudad.datos then
            sitios[#sitios + 1] = ciudad.datos
        end
    end
    -- Sin orden: las piezas se ordenan por profundidad al dibujarlas.
    for _, inst in pairs(e.instalaciones) do
        if inst.tipo == 'base' and self:dibujable(inst.x, inst.y) then
            sitios[#sitios + 1] = inst
        end
    end
    for _, sitio in ipairs(sitios) do
        local visibles = self:lanzacohetesVisibles(sitio)
        if visibles > 0 then
            local puestos = self:puestosLanzacohetes(sitio)
            local nacion = self.sim:nacion(sitio.nacion)
            local color = nacion and nacion.color
            for k = 1, math.min(visibles, #puestos) do
                local puesto = puestos[k]
                piezas[#piezas + 1] = {
                    profundidad = Iso.profundidad(puesto.x, puesto.y),
                    dibujar = function()
                        Modelos.dibujarLanzacohetes(puesto.x, puesto.y, puesto.z, puesto.angulo, 0, color)
                    end,
                }
            end
        end
    end
end

--- Sitio (ciudad o base) que está en (x, y): de ahí sale una salva.
function Mundo:sitioEn(x, y)
    local e = self.sim.estado
    for _, id in ipairs(Simulacion.ordenadas(e.ciudades)) do
        local c = e.ciudades[id]
        if c.x == x and c.y == y then
            return c
        end
    end
    for _, id in ipairs(Simulacion.ordenadas(e.instalaciones)) do
        local i = e.instalaciones[id]
        if i.x == x and i.y == y then
            return i
        end
    end
end

Mundo.despliegue = 300 -- px fuera del borde de su ciudad donde forma un ejército que sale a atacar

--- ¿Vuelve un grupo a casa tras retirarse de un combate?
local function enRetirada(gr)
    return gr.retirada == true and gr.mision == 'regreso'
end

--- Lo recorrido de la ruta que se ve ahora: entre el paso de marcha anterior
-- y el actual (`fraccion`, de `sim:fraccionPaso()`).
local function recorridoVisible(gr, fraccion)
    local antes = gr.antesRecorrido or gr.recorrido
    if antes > gr.recorrido then
        -- Ruta nueva a mitad de paso (una orden): desde su principio.
        antes = gr.recorrido
    end
    return antes + (gr.recorrido - antes) * fraccion
end

--- Dónde se ve un grupo en retirada, y hacia dónde mira; nil si no se ve. Como
-- los ataques, no recorre el mapa: el día que se retira sigue donde combatía
-- (el principio de su ruta de vuelta); después desaparece y, el último día de
-- viaje, aparece formado junto a su casa y entra en ella. Si solo lleva
-- heridos (ningún soldado sano), no se dibuja como ejército.
function Mundo:posicionRetirada(gr, fraccion)
    if not enRetirada(gr) or gr.soldados <= 0 or not gr.ruta then
        return nil
    end
    local recorrido = recorridoVisible(gr, fraccion)
    if recorrido < Simulacion.velocidadEjercito and gr.largo > 2 * Simulacion.velocidadEjercito then
        -- El primer día de vuelta sigue donde combatía.
        local x, y = gr.ruta[1], gr.ruta[2]
        return x, y, math.atan2(gr.destinoY - y, gr.destinoX - x)
    end
    if gr.largo - recorrido > Simulacion.velocidadEjercito then
        return nil
    end
    local casa = self.sim:sitio(gr.desde)
    if not casa then
        return nil
    end
    -- Llega por el lado por el que viene y mira hacia la ciudad.
    local angulo = math.atan2(gr.y - casa.y, gr.x - casa.x)
    local fisica = self:ciudadFisica(casa.id)
    local borde = fisica and Ciudades.borde(fisica, angulo) or 200
    -- El último día de viaje se acerca desde `despliegue` hasta el borde.
    local llegada = 1 - (gr.largo - recorrido) / Simulacion.velocidadEjercito
    local d = borde + Mundo.despliegue * (1 - math.max(0, math.min(1, llegada)))
    return casa.x + math.cos(angulo) * d, casa.y + math.sin(angulo) * d, angulo + math.pi
end

--- Dónde se ve un grupo, y hacia dónde mira; nil si no se ve. Los grupos no
-- recorren el mapa: un ejército que sale a atacar se despliega unos metros
-- fuera de su ciudad, mirando al objetivo, mientras dura el viaje; al llegar
-- aparece allí. Obras, entregas, refuerzos y regresos no se ven por el camino,
-- salvo los ejércitos en retirada (ver `posicionRetirada`). El cuarto valor
-- dice si es un ejército que ataca ya formado (desplegado en su punto de
-- salida o en su objetivo).
function Mundo:posicionVisible(gr, fraccion)
    if gr.mision == 'regreso' then
        return self:posicionRetirada(gr, fraccion)
    end
    if gr.recorrido >= gr.largo then
        local x, y, angulo = Simulacion.posicionGrupo(gr, 1)
        return x, y, angulo, gr.mision == 'atacar' and not gr.detenido
    end
    if gr.mision ~= 'atacar' then
        return nil
    end
    local origen = self.sim:sitio(gr.desde)
    local ox, oy = origen and origen.x or gr.ruta[1], origen and origen.y or gr.ruta[2]
    local angulo = math.atan2(gr.destinoY - oy, gr.destinoX - ox)
    local fisica = self:ciudadFisica(gr.desde)
    local salida = (fisica and Ciudades.borde(fisica, angulo) or 200) + Mundo.despliegue
    local recorrido = recorridoVisible(gr, fraccion)
    local d = math.min(recorrido, salida)
    return ox + math.cos(angulo) * d, oy + math.sin(angulo) * d, angulo, recorrido >= salida and not gr.detenido
end

--- Dónde se dibuja la ficha de un grupo y hacia dónde va; nil si no tiene
-- camino. La ficha recorre su camino entre el día anterior y el actual (como
-- `Simulacion.posicionGrupo`). Un ejército que ya pelea en su objetivo (un
-- sitio o una mina) se planta fuera de él, por el lado por el que llegó, para
-- no tapar la ciudad o la mina.
function Mundo:posicionFicha(gr, fraccion)
    if not gr.ruta then
        return nil
    end
    local x, y, angulo = Simulacion.posicionGrupo(gr, fraccion)
    if gr.mision == 'atacar' and gr.recorrido >= gr.largo then
        local objetivo = self.sim:sitio(gr.objetivo)
        local mina = not objetivo and self.sim.estado.depositos[gr.objetivo]
        if mina then
            -- En una mina: fuera del yacimiento, por el lado por el que llegó,
            -- para no tapar la mina ni a los recolectores.
            local vuelta = angulo + math.pi
            local d = Mundo.despliegue + 50
            x, y = mina.x + math.cos(vuelta) * d, mina.y + math.sin(vuelta) * d
        elseif objetivo then
            local fisica = self:ciudadFisica(objetivo.id)
            local vuelta = angulo + math.pi
            local borde = fisica and Ciudades.borde(fisica, vuelta) or 300
            local d = borde + Mundo.despliegue
            x, y = objetivo.x + math.cos(vuelta) * d, objetivo.y + math.sin(vuelta) * d
        end
    end
    return x, y, angulo
end

--- Mina en la que está un grupo que recolecta en ella (fase 'recolectando')
-- o un ejército que ya la ataca; nil si no. Los que van o vuelven siguen en
-- su camino.
function Mundo:minaDeGrupo(gr)
    local depositos = self.sim.estado.depositos
    if gr.mision == 'recolectar' and gr.fase == 'recolectando' then
        return depositos[gr.yacimiento]
    end
    if gr.mision == 'atacar' and gr.recorrido >= gr.largo and not self.sim:sitio(gr.objetivo) then
        return depositos[gr.objetivo]
    end
    return nil
end

--- Fichas de los grupos a la vista (una por grupo). Se dibujan al final, con
-- tamaño fijo en pantalla (ver `dibujarFichas`). Los dos ejércitos de un choque van en una sola entrada (`par`), en el punto del
-- choque.
function Mundo:fichasGrupos()
    local fraccion = self.sim:fraccionPaso()
    self.fichas = {}
    local enChoque = self.enChoque or {}
    local hechos = {}
    local inicios = {}
    for _, gid in ipairs(Simulacion.ordenadas(self.sim.estado.grupos)) do
        local gr = self.sim.estado.grupos[gid]
        local c = enChoque[gid]
        if c then
            if not hechos[c] then
                hechos[c] = true
                local par = self:fichaPar(c, fraccion, inicios)
                if par then
                    self.fichas[#self.fichas + 1] = par
                end
            end
        elseif Simulacion.Aviones.vuela(gr) then
            -- Va en avión (o lo espera): se ve el avión, no su ficha
            -- (`dibujarAviones`).
        else
            -- La altura sale de la semilla: la ficha se ve aunque su trozo de
            -- terreno aún no se haya generado.
            local x, y, angulo = self:posicionFicha(gr, fraccion)
            if x then
                -- Recolectando o atacando una mina: la ficha se ancla en
                -- pantalla al icono de la mina (ver `dibujarFichas`), así que
                -- también cuenta si la mina está a la vista.
                local mina = self:minaDeGrupo(gr)
                local vx, vy = Iso.vista(x, y, self.terreno:altura(x, y))
                local visible = self:enVista(vx, vy)
                if mina and not visible then
                    visible = self:enVista(Iso.vista(mina.x, mina.y, self.terreno:altura(mina.x, mina.y)))
                end
                if visible then
                    self.fichas[#self.fichas + 1] = {
                        grupo = gr,
                        vx = vx,
                        vy = vy,
                        pose = pose,
                        -- En pantalla, x crece con (x - y): va a la izquierda si baja.
                        izquierda = math.cos(angulo) - math.sin(angulo) < 0,
                        mina = mina and mina.id,
                        recolecta = mina ~= nil and gr.mision == 'recolectar',
                    }
                end
            end
        end
    end
    self.inicioChoques = inicios
    table.sort(self.fichas, function(a, b)
        return a.vy < b.vy
    end)
end

Mundo.acercarChoque = 0.6 -- segundos (del reloj del combate) que tardan en juntarse las dos fichas

--- Entrada de un choque para `dibujarFichas`: el punto del choque en la vista
-- y, a cada lado, la ficha que viene de ese lado de la pantalla. `inicios`
-- recoge cuándo empezó a verse cada choque (para que se junten poco a poco).
function Mundo:fichaPar(c, fraccion, inicios)
    local grupos = self.sim.estado.grupos
    local ga, gb = grupos[c.a], grupos[c.b]
    local vx, vy = Iso.vista(c.x, c.y, self.terreno:altura(c.x, c.y))
    if not (ga and gb and self:enVista(vx, vy)) then
        return nil
    end
    local function lado(gr)
        local x, y = self:posicionFicha(gr, fraccion)
        x, y = x or c.x, y or c.y
        local fx, fy = Iso.vista(x, y, self.terreno:altura(x, y))
        return { grupo = gr, vx = fx, vy = fy, pose = gr.retirada and 'retirada' or 'combate' }
    end
    local izq, der = lado(ga), lado(gb)
    if izq.vx > der.vx then
        izq, der = der, izq
    end
    -- Cada una mira a la otra: la de la izquierda hacia la derecha y al revés.
    izq.izquierda, der.izquierda = false, true
    local clave = Choques.clave(c)
    local anteriores = self.inicioChoques or {}
    inicios[clave] = anteriores[clave] or self.relojCombate or 0
    return {
        par = true,
        choque = c,
        clave = clave,
        grupo = izq.grupo,
        vx = vx,
        vy = vy,
        lados = { izq, der },
        inicio = inicios[clave],
    }
end

local function chocan(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

--- ¿Debe apartarse una ficha de naciones `naciones` de la caja ocupada `o`?
-- Los nombres de ciudad (sin nación) apartan siempre; las fichas, solo si
-- alguna de sus naciones no está en guerra con alguna de `naciones` (misma
-- nación, aliadas o neutrales). Dos enemigas no se apartan: se buscan.
function Mundo:repele(o, naciones)
    if not o.naciones then
        return true
    end
    for _, a in ipairs(o.naciones) do
        for _, b in ipairs(naciones) do
            if a == b or not self.sim:guerraEntre(a, b) then
                return true
            end
        end
    end
    return false
end

--- Desplazamiento horizontal (px de pantalla) para que la caja de `w` x `h`
-- (px de pantalla), centrada en `vx` y con su borde de arriba `arriba` px
-- sobre `vy`, no tape lo que la repele. `k` pasa de px de pantalla a la vista.
function Mundo:apartar(vx, vy, w, h, arriba, naciones, ocupados, k)
    local dx = 0
    for _ = 1, 8 do
        local caja = { x = vx + (dx - w / 2) * k, y = vy - arriba * k, w = w * k, h = h * k }
        local otra
        for _, o in ipairs(ocupados) do
            if chocan(caja, o) and self:repele(o, naciones) then
                otra = o
            end
        end
        if not otra then
            break
        end
        local centro = otra.x + otra.w / 2
        if vx + dx * k >= centro then
            dx = (otra.x + otra.w - vx) / k + w / 2 + 2
        else
            dx = (otra.x - vx) / k - w / 2 - 2
        end
    end
    return dx
end

--- Unión de cajas en px de pantalla alrededor de (vx, vy), pasada a la vista.
local function unionCajas(cajas, vx, vy, k)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, c in ipairs(cajas) do
        x0, y0 = math.min(x0, c.x), math.min(y0, c.y)
        x1, y1 = math.max(x1, c.x + c.w), math.max(y1, c.y + c.h)
    end
    return { x = vx + x0 * k, y = vy + y0 * k, w = (x1 - x0) * k, h = (y1 - y0) * k }
end

--- Dibuja las fichas: estandarte y etiqueta de los ejércitos, banderín de los
-- convoyes. Se leen igual con cualquier zoom (como los nombres de las
-- ciudades). Si una taparía un nombre de ciudad o una ficha amiga, se corre a
-- un lado; las enemigas no se apartan. Guarda las cajas (en coordenadas de la
-- vista) para el clic.
function Mundo:dibujarFichas()
    local g = love.graphics
    -- Escala fija en pantalla a cualquier zoom (el mínimo de la cámara es 0,1).
    local k = 1 / math.max(0.05, self.zoom or 1)
    local anterior = g.getFont()
    local ocupados = {}
    for _, caja in ipairs(self.cajasNombres or {}) do
        ocupados[#ocupados + 1] = caja
    end
    self.cajasFichas = {}
    self.apartados = {}
    -- Primero las ancladas a su mina, que no se mueven: las demás se apartan de ellas.
    local anclas = self.anclasMinas or {}
    local enMina = {}
    local sueltas = {}
    for _, f in ipairs(self.fichas or {}) do
        local id = not f.par and f.mina
        if id and anclas[id] then
            enMina[id] = enMina[id] or { recolectores = {}, atacantes = {} }
            local lista = f.recolecta and enMina[id].recolectores or enMina[id].atacantes
            lista[#lista + 1] = f
        else
            sueltas[#sueltas + 1] = f
        end
    end
    for _, id in ipairs(Simulacion.ordenadas(enMina)) do
        local mitad = self:dibujarRecolectoresMina(anclas[id], enMina[id].recolectores, k, ocupados)
        self:dibujarAtacantesMina(anclas[id], enMina[id].atacantes, mitad, k, ocupados)
    end
    for _, f in ipairs(sueltas) do
        if f.par then
            self:dibujarPar(f, k, ocupados)
        else
            self:dibujarFicha(f, k, ocupados)
        end
    end
    g.setFont(anterior)
end

Mundo.huecoMina = 4 -- px de pantalla entre el icono de una mina y lo que se ancla a él

--- Ordena fichas por el id de su grupo (el orden no depende de la cámara).
local function porGrupo(fichas)
    table.sort(fichas, function(a, b)
        return a.grupo.id < b.grupo.id
    end)
    return fichas
end

--- Los recolectores que recolectan en una mina, anclados en pantalla justo
-- debajo de su icono (`ancla`, caja en la vista), a cualquier zoom: una ficha
-- por nación, una junto a otra, que resume sus grupos («×3» y la carga total).
-- Devuelve la mitad del ancho (px de pantalla) que ocupan el icono y ellas.
function Mundo:dibujarRecolectoresMina(ancla, fichas, k, ocupados)
    local g = love.graphics
    local mitad = ancla.w / k / 2
    if #fichas == 0 then
        return mitad
    end
    local porNacion = {}
    local orden = {}
    for _, f in ipairs(porGrupo(fichas)) do
        local ficha = Inteligencia.ficha(self.sim, f.grupo.id, self.mira)
        if ficha then
            local n = f.grupo.nacion
            local r = porNacion[n]
            if not r then
                r = { ficha = {}, grupos = {}, pose = f.pose }
                for clave, valor in pairs(ficha) do
                    r.ficha[clave] = valor
                end
                r.ficha.carga, r.ficha.capacidad, r.ficha.cuantos = 0, 0, 0
                porNacion[n] = r
                orden[#orden + 1] = n
            end
            r.ficha.carga = r.ficha.carga + (ficha.carga or 0)
            r.ficha.capacidad = r.ficha.capacidad + (ficha.capacidad or 0)
            r.ficha.cuantos = r.ficha.cuantos + 1
            r.grupos[#r.grupos + 1] = f.grupo.id
            if f.pose == 'combate' then
                r.pose = 'combate'
            end
        end
    end
    -- Medidas con el pie en (0, 0) para repartirlas centradas bajo el icono.
    local separacion = Mundo.huecoMina
    local total = -separacion
    for _, n in ipairs(orden) do
        local r = porNacion[n]
        r.caja = Estandartes.cajaRecolector(0, 0, r.ficha, false, r.pose)
        total = total + r.caja.w + separacion
    end
    local cx, cy = ancla.x + ancla.w / 2, ancla.y + ancla.h
    local x = -total / 2
    g.push()
    g.translate(cx, cy)
    g.scale(k)
    for _, n in ipairs(orden) do
        local r = porNacion[n]
        local sx = x - r.caja.x
        local sy = Mundo.huecoMina - r.caja.y
        local caja = Estandartes.dibujarRecolector(sx, sy, r.ficha, false, r.pose)
        x = x + r.caja.w + separacion
        local vista = unionCajas({ caja }, cx, cy, k)
        vista.naciones = { n }
        self.cajasFichas[#self.cajasFichas + 1] = { caja = vista, grupo = r.grupos[1] }
        ocupados[#ocupados + 1] = vista
    end
    g.pop()
    return math.max(mitad, total / 2)
end

--- Los ejércitos que atacan una mina, a un lado de su icono (`ancla`) y a
-- `huecoMina` px de pantalla de él y de sus recolectores (que ocupan `mitad`
-- px a cada lado del centro), a cualquier zoom: del lado por el que llegaron,
-- mirando a la mina; si hay varios en un lado, uno tras otro hacia fuera.
function Mundo:dibujarAtacantesMina(ancla, fichas, mitad, k, ocupados)
    local g = love.graphics
    local cx, cy = ancla.x + ancla.w / 2, ancla.y + ancla.h
    local alto = ancla.h / k
    local hueco = Mundo.huecoMina * 2
    local fuera = { [-1] = mitad + hueco, [1] = mitad + hueco }
    for _, f in ipairs(porGrupo(fichas)) do
        local ficha = Inteligencia.ficha(self.sim, f.grupo.id, self.mira)
        if ficha then
            local recolector = not ficha.ejercito and Estandartes.esRecolector(ficha)
            -- Dónde queda (pie y caja en la vista) del lado `lado` de la mina.
            local function colocar(lado)
                local izquierda = lado > 0
                local medida
                if recolector then
                    medida = Estandartes.cajaRecolector(0, 0, ficha, izquierda, f.pose)
                else
                    medida = Estandartes.cajaEjercito(0, 0, ficha, izquierda)
                end
                local sx = lado > 0 and fuera[1] - medida.x or -fuera[-1] - (medida.x + medida.w)
                -- Arriba a la altura del icono.
                local sy = -alto - medida.y
                local vista =
                    unionCajas({ { x = sx + medida.x, y = sy + medida.y, w = medida.w, h = medida.h } }, cx, cy, k)
                return sx, sy, medida.w, vista
            end
            local function libre(vista)
                for _, o in ipairs(ocupados) do
                    if chocan(vista, o) and self:repele(o, { f.grupo.nacion }) then
                        return false
                    end
                end
                return true
            end
            -- Del lado por el que llegó (si llegó moviéndose a la izquierda,
            -- viene de la derecha), mirando a la mina; si ahí tapa un nombre o
            -- una ficha amiga, del otro lado.
            local lado = f.izquierda and 1 or -1
            local sx, sy, ancho, vista = colocar(lado)
            if not libre(vista) then
                local sx2, sy2, ancho2, vista2 = colocar(-lado)
                if libre(vista2) then
                    lado, sx, sy, ancho = -lado, sx2, sy2, ancho2
                end
            end
            local izquierda = lado > 0
            fuera[lado] = fuera[lado] + ancho + hueco
            g.push()
            g.translate(cx, cy)
            g.scale(k)
            local cajas = {}
            if ficha.ejercito then
                cajas[1] = Estandartes.dibujarEstandarte(sx, sy, ficha, f.pose, izquierda, self.semilla)
                cajas[2] = Estandartes.dibujarEtiqueta(sx, sy, ficha, izquierda)
            elseif recolector then
                cajas[1] = Estandartes.dibujarRecolector(sx, sy, ficha, izquierda, f.pose, Ondear.faseDe(f.grupo.id))
            else
                cajas[1] = Estandartes.dibujarBanderin(sx, sy, ficha.color, izquierda, Ondear.faseDe(f.grupo.id))
            end
            g.pop()
            local caja = unionCajas(cajas, cx, cy, k)
            caja.naciones = { f.grupo.nacion }
            self.cajasFichas[#self.cajasFichas + 1] = { caja = caja, grupo = f.grupo.id }
            ocupados[#ocupados + 1] = caja
        end
    end
    -- Halo dorado sobre la ficha del grupo que el jugador seleccionó para
end

--- Una ficha sola (ver `dibujarFichas`).
function Mundo:dibujarFicha(f, k, ocupados)
    local g = love.graphics
    local ficha = Inteligencia.ficha(self.sim, f.grupo.id, self.mira)
    if not ficha then
        return
    end
    -- Caja aproximada (estandarte y etiqueta) para apartarse de las demás.
    local hoja, s = Estandartes.escala()
    local datos = Estandartes.medidas()
    local w = datos.ancho * hoja * s
    local h = (datos.alto + 18) * hoja * s
    local naciones = { f.grupo.nacion }
    local dx = self:apartar(f.vx, f.vy, w, h, datos.ancla.y * hoja * s, naciones, ocupados, k)
    -- Lo que se apartó (px de la vista): la línea de su camino sale de aquí.
    self.apartados[f.grupo.id] = dx * k
    g.push()
    g.translate(f.vx, f.vy)
    g.scale(k)
    local cajas = {}
    if ficha.ejercito then
        cajas[1] = Estandartes.dibujarEstandarte(dx, 0, ficha, f.pose, f.izquierda, self.semilla)
        cajas[2] = Estandartes.dibujarEtiqueta(dx, 0, ficha, f.izquierda)
    elseif Estandartes.esRecolector(ficha) then
        cajas[1] = Estandartes.dibujarRecolector(dx, 0, ficha, f.izquierda, f.pose, Ondear.faseDe(f.grupo.id))
    else
        cajas[1] = Estandartes.dibujarBanderin(dx, 0, ficha.color, f.izquierda, Ondear.faseDe(f.grupo.id))
    end
    g.pop()
    local caja = unionCajas(cajas, f.vx, f.vy, k)
    caja.naciones = naciones
    self.cajasFichas[#self.cajasFichas + 1] = { caja = caja, grupo = f.grupo.id }
    ocupados[#ocupados + 1] = caja
end

--- Las dos fichas de un choque, enfrentadas en el punto del choque a
-- `Choques.separacion` px de pantalla, con el polvo y los destellos entre
-- ellas. Al empezar el choque, cada una llega desde donde estaba.
function Mundo:dibujarPar(f, k, ocupados)
    local g = love.graphics
    local fichas = {}
    local naciones = {}
    for i, l in ipairs(f.lados) do
        fichas[i] = Inteligencia.ficha(self.sim, l.grupo.id, self.mira)
        naciones[i] = l.grupo.nacion
    end
    if not (fichas[1] and fichas[2]) then
        return
    end
    local hoja, s = Estandartes.escala()
    local m = hoja * s -- px de pantalla por px de la hoja 1x
    local datos = Estandartes.medidas()
    local medio = Choques.separacion / 2
    local w = Choques.separacion + datos.ancho * m * 2
    local h = (datos.alto + 18) * m
    local dx = self:apartar(f.vx, f.vy, w, h, datos.ancla.y * m, naciones, ocupados, k)
    -- Se juntan en `acercarChoque` segundos, frenando al final.
    local t = math.min(1, math.max(0, ((self.relojCombate or 0) - f.inicio) / Mundo.acercarChoque))
    local e = 1 - (1 - t) ^ 3
    g.push()
    g.translate(f.vx, f.vy)
    g.scale(k)
    if e >= 1 then
        self:dibujarPolvoChoque(dx, 0, m, f.clave)
    end
    local cajas = {}
    for i, l in ipairs(f.lados) do
        local lado = i == 1 and -1 or 1
        local x = dx + lado * medio
        local x0, y0 = (l.vx - f.vx) / k, (l.vy - f.vy) / k
        local sx, sy = x0 + (x - x0) * e, y0 * (1 - e)
        local ficha = fichas[i]
        local caja = Estandartes.dibujarEstandarte(sx, sy, ficha, l.pose, l.izquierda, self.semilla)
        -- Las etiquetas, una a cada lado del punto de encuentro.
        local pegada = e >= 1 and { x = dx + lado * 3, lado = lado } or nil
        local etiqueta = Estandartes.dibujarEtiqueta(sx, sy, ficha, l.izquierda, pegada)
        cajas[#cajas + 1] = caja
        cajas[#cajas + 1] = etiqueta
        local propia = unionCajas({ caja, etiqueta }, f.vx, f.vy, k)
        self.cajasFichas[#self.cajasFichas + 1] = { caja = propia, grupo = l.grupo.id }
    end
    if e >= 1 then
        self:dibujarDestellosChoque(dx, 0, m, f.clave)
    end
    g.pop()
    local caja = unionCajas(cajas, f.vx, f.vy, k)
    caja.naciones = naciones
    ocupados[#ocupados + 1] = caja
end

--- Número entre 0 y 1 que sale de un choque, un efecto y su ciclo (solo vista).
local function azarChoque(clave, a, b)
    local h = 0
    for i = 1, #clave do
        h = (h * 31 + clave:byte(i)) % 2147483647
    end
    return (Ruido.hash(h, a, b, 977) % 10000) / 10000
end

Mundo.polvoChoque = 6 -- nubecillas de polvo a la vez al pie de dos fichas trabadas
Mundo.destellosChoque = 3 -- destellos a la vez entre las espadas

--- Polvo al pie de las dos fichas trabadas, centrado en (x, y) px de pantalla.
-- Va con el reloj del combate: se para en pausa.
function Mundo:dibujarPolvoChoque(x, y, m, clave)
    local g = love.graphics
    local reloj = self.relojCombate or 0
    for i = 1, Mundo.polvoChoque do
        local fase = reloj * 0.55 + i / Mundo.polvoChoque
        local ciclo = math.floor(fase)
        local f = fase - ciclo
        local px = x + (azarChoque(clave, i, ciclo) - 0.5) * 60 * m
        local py = y - 1 * m - f * 6 * m
        local r = (3 + 8 * math.sqrt(f)) * m
        g.setColor(0.66, 0.57, 0.43, 0.38 * (1 - f))
        g.ellipse('fill', px, py, r, r * 0.6)
    end
end

--- Destellos pequeños entre las espadas de las dos fichas.
function Mundo:dibujarDestellosChoque(x, y, m, clave)
    local g = love.graphics
    local reloj = self.relojCombate or 0
    local periodo = 0.7
    for i = 1, Mundo.destellosChoque do
        local fase = reloj / periodo + i / Mundo.destellosChoque
        local ciclo = math.floor(fase)
        local f = fase - ciclo
        -- Cada destello dura un cuarto de su ciclo; el resto, nada.
        if f < 0.25 then
            local u = f / 0.25
            local px = x + (azarChoque(clave, 50 + i, ciclo) - 0.5) * 22 * m
            local py = y - (50 + azarChoque(clave, 90 + i, ciclo) * 14) * m
            local r = (2 + 5 * u) * m
            local a = 1 - u
            g.setColor(1, 0.86, 0.45, 0.8 * a)
            g.setLineWidth(math.max(1, 1.4 * m))
            g.line(px - r, py, px + r, py)
            g.line(px, py - r, px, py + r)
            g.line(px - r * 0.6, py - r * 0.6, px + r * 0.6, py + r * 0.6)
            g.line(px - r * 0.6, py + r * 0.6, px + r * 0.6, py - r * 0.6)
            g.setColor(1, 1, 0.9, a)
            g.circle('fill', px, py, 1.3 * m)
        end
    end
    g.setLineWidth(1)
end

--- Grupo cuya ficha está bajo el punto (vx, vy) de la vista, o nil. Si hay
-- varias, la de delante (la última dibujada).
function Mundo:fichaEn(vx, vy)
    for i = #(self.cajasFichas or {}), 1, -1 do
        local c = self.cajasFichas[i].caja
        if vx >= c.x and vx <= c.x + c.w and vy >= c.y and vy <= c.y + c.h then
            return self.cajasFichas[i].grupo
        end
    end
    return nil
end

-- Hora del juego y avisos ---------------------------------------------------------------------------
--
-- En el mapa 2D ya no hay ataques a distancia (diseno/recoleccion-y-batallas.md,
-- 3.6): ni salvas ni incursiones. Toda batalla es de campo y se ve con las
-- fichas de los grupos y el sello de la mina o del sitio.

--- Hora del juego (días con decimales): los visuales de guerra se miden con
-- ella, así que van al ritmo de la velocidad elegida y se congelan en pausa.
function Mundo:ahora()
    return self.sim:ahora()
end

--- Apunta dónde hubo acción (para la tecla X, que lleva a la última).
function Mundo:avisarAccion(x, y)
    self.avisos = self.avisos or {}
    table.insert(self.avisos, 1, { x = x, y = y })
    self.avisos[13] = nil
end

--- Batallas nuevas (de cualquiera): se apuntan para la tecla X.
function Mundo:recibirBatallas()
    self.batallasVistas = self.batallasVistas or {}
    for _, b in ipairs(self.sim:batallasEnCurso()) do
        if not self.batallasVistas[b.id] then
            self.batallasVistas[b.id] = true
            self:avisarAccion(b.x, b.y)
        end
    end
end

--- ¿Cae el punto de vista (vx, vy) dentro de lo que se ve (con margen)?
function Mundo:enVista(vx, vy)
    local v = self.vista
    if not v then
        return true
    end
    local m = 400
    return vx > v.x - m and vx < v.x + v.w + m and vy > v.y - m and vy < v.y + v.h + m
end

--- Comarcas que tocan la vista y aún no están generadas (para medir).
function Mundo:huecos(vista)
    return self.comarcas:huecos(vista)
end

--- Ciudad descubierta más cercana a un punto de mundo, con su distancia.
function Mundo:ciudadMasCercana(x, y)
    local mejor, distancia
    for _, ciudad in pairs(self.ciudadesVistas) do
        local d = math.sqrt((ciudad.x - x) ^ 2 + (ciudad.y - y) ^ 2)
        if not mejor or d < distancia then
            mejor, distancia = ciudad, d
        end
    end
    return mejor, distancia
end

return Mundo
