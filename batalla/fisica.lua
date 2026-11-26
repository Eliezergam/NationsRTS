-- Mundo físico 3Dream de la batalla. La extensión integra el movimiento en
-- X/Z con Box2D y resuelve la altura Y contra una malla simplificada del
-- relieve. Las posiciones públicas de Tropas siguen expresadas en píxeles.

local Malla = require('batalla.malla')
local Derribo = require('batalla.derribo')
local Conversor = require('batalla.dream.conversor')

local dream = require('lib.3DreamEngine')
local physics = require('lib.3DreamEngine.extensions.physics')

local Fisica = {}
Fisica.__index = Fisica

Fisica.pasoTerreno = 900
Fisica.radioTanque = 0.38
Fisica.radioLanzacohetes = 0.58 -- envuelve el chasis Synty de 11 m
Fisica.resistenciaRodadura = 0.015
Fisica.rozamientoFreno = 0.82
Fisica.gananciaMotor = 8
Fisica.gananciaGiro = 12
Fisica.frenoGiro = 5
Fisica.gananciaDireccion = 18
Fisica.agarreLateral = 10
Fisica.radioMapaTanque = 68
Fisica.radioMapaLanzacohetes = 96

local MUESTRAS_TRANSITABLES = {
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
}

local function diferenciaAngular(destino, actual)
    return (destino - actual + math.pi) % (math.pi * 2) - math.pi
end

--- Separa la resistencia de las ruedas del agarre al bloquear los frenos.
local function rozamientoRuedas(unidad, coeficiente)
    if unidad.tipo == 'lanzacohetes' then
        local colision = unidad.colision
        local masa = colision:getBody():getMass()
        colision.staticFriction = coeficiente / masa
        colision.slidingFriction = coeficiente / masa
    end
end

local function radioMapa(unidad)
    if unidad.tipo == 'lanzacohetes' then
        return Fisica.radioMapaLanzacohetes
    end
    return Fisica.radioMapaTanque
end

local function crearMallaTerreno(suelo, paso)
    local celdas = math.ceil(suelo.lado / paso)
    local malla = Malla.nueva(celdas * celdas * 6)
    local color = { 1, 1, 1 }

    for fila = 0, celdas - 1 do
        local y0 = suelo.y0 + fila * suelo.lado / celdas
        local y1 = suelo.y0 + (fila + 1) * suelo.lado / celdas
        for columna = 0, celdas - 1 do
            local x0 = suelo.x0 + columna * suelo.lado / celdas
            local x1 = suelo.x0 + (columna + 1) * suelo.lado / celdas
            local altura00 = suelo:altura(x0, y0)
            local altura10 = suelo:altura(x1, y0)
            local altura01 = suelo:altura(x0, y1)
            local altura11 = suelo:altura(x1, y1)
            malla:triangulo(x0, y0, altura00, x1, y0, altura10, x1, y1, altura11, color)
            malla:triangulo(x0, y0, altura00, x1, y1, altura11, x0, y1, altura01, color)
        end
    end

    return malla:crear()
end

function Fisica.nueva(suelo, unidades)
    local self = setmetatable({}, Fisica)
    self.suelo = suelo
    self.unidades = unidades
    self.restos = {}
    self.conversor = Conversor.nuevo(dream, suelo.cx, suelo.cy)
    self.mundo = physics:newWorld()
    self.mundo:setGravity(9.8)
    self.unidadDe = {} -- Derribo (Valeria): cuerpo Box2D -> vehículo
    self:crearTerreno()
    self:crearArboles()
    self:crearLimite()
    self:crearEdificios()
    self:crearAgua() -- Agua (Valeria)
    self:crearUnidades()
    self.derribo = Derribo.nuevo(self, self.unidadDe) -- Derribo (Valeria)
    return self
end

function Fisica:crearTerreno()
    local mallaLove = crearMallaTerreno(self.suelo, Fisica.pasoTerreno)
    local mallaDream = self.conversor:desdeMalla(mallaLove, {
        nombre = 'colision_terreno',
    })
    self.mallaTerrenoDream = mallaDream
    local colision = dream:newCollisionMesh(mallaDream, 'height')
    local forma = physics:newMesh(colision)
    self.terreno = self.mundo:add(forma, 'static', 0, 0, 0)
    -- Agua (Valeria): la malla de colisión tiene celdas de 88 m y en las
    -- costas y laderas se aparta metros del suelo dibujado. Donde queda más
    -- alta que el paso de un vehículo, la extensión activa el contacto y
    -- Box2D saca el casco del triángulo entero de golpe (hasta 25 m en un
    -- cuadro, cruzando las orillas). Los vehículos no la tocan (categoría 4
    -- en su máscara) y se apoyan en el suelo real (`apoyar`); los restos
    -- sí rebotan en ella.
    for _, fixture in ipairs(self.terreno.fixtures) do
        fixture:setCategory(4)
    end
    mallaLove:release()

    local mallaRayLove = crearMallaTerreno(self.suelo, 3000)
    self.mallaRayosDream = self.conversor:desdeMalla(mallaRayLove, {
        nombre = 'rayos_terreno',
    })
    mallaRayLove:release()
end

function Fisica:crearArboles()
    self.arboles = {}
    local cuerpos = {}
    local tamanoCelda = 20
    for _, planta in ipairs(self.suelo.plantasFisicas) do
        local x, _, z = self.conversor:punto(planta.x, planta.y, 0)
        local columna = math.floor(x / tamanoCelda)
        local fila = math.floor(z / tamanoCelda)
        local clave = columna .. ',' .. fila
        local cuerpo = cuerpos[clave]
        if not cuerpo then
            cuerpo = love.physics.newBody(self.mundo:getWorld(), 0, 0, 'static')
            cuerpo:setUserData({ arboles = true })
            cuerpos[clave] = cuerpo
            self.arboles[#self.arboles + 1] = cuerpo
        end
        local forma = love.physics.newCircleShape(x, z, 0.18)
        local fixture = love.physics.newFixture(cuerpo, forma, 1)
        fixture:setFriction(0.9)
        planta.fixture = fixture -- Impactos (Valeria): el árbol derribado deja de estorbar
        fixture:setUserData(planta) -- Derribo (Valeria): el vehículo sabe qué árbol pisa
    end
end

--- Límite (Valeria): aro estático de Box2D en el borde de `suelo.limite`
-- (batalla/limite.lua). Sin rozamiento ni rebote: el vehículo que llega se
-- frena contra él y se desliza a lo largo. No tiene techo.
function Fisica:crearLimite()
    local limite = self.suelo.limite
    if not limite then
        return
    end
    local puntos = {}
    local lados = 128
    for k = 0, lados - 1 do
        local angulo = k / lados * math.pi * 2
        local x = limite.cx + math.cos(angulo) * limite.radio
        local y = limite.cy + math.sin(angulo) * limite.radio
        local px, _, pz = self.conversor:punto(x, y, 0)
        puntos[#puntos + 1] = px
        puntos[#puntos + 1] = pz
    end
    local cuerpo = love.physics.newBody(self.mundo:getWorld(), 0, 0, 'static')
    cuerpo:setUserData({ limite = true })
    local fixture = love.physics.newFixture(cuerpo, love.physics.newChainShape(true, unpack(puntos)), 1)
    fixture:setFriction(0)
    fixture:setRestitution(0)
    self.limite = cuerpo
end

--- Edificios y muro de la ciudad o mina (batalla/sitios/plano.lua): un
-- polígono estático por sólido (caja girada). Los portones quedan abiertos.
function Fisica:crearEdificios()
    local plano = self.suelo.plano
    if not plano or not plano.listaHuellas then
        return
    end
    local cuerpo = love.physics.newBody(self.mundo:getWorld(), 0, 0, 'static')
    cuerpo:setUserData({ edificio = true })
    local n = 0
    for _, h in ipairs(plano.listaHuellas) do
        if h.solido then
            local puntos = {}
            for _, e in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
                local u, v = e[1] * h.hx, e[2] * h.hy
                local px, _, pz = self.conversor:punto(h.cx + u * h.c - v * h.s, h.cy + u * h.s + v * h.c, 0)
                puntos[#puntos + 1] = px
                puntos[#puntos + 1] = pz
            end
            local ok, forma = pcall(love.physics.newPolygonShape, unpack(puntos))
            if ok then
                local fixture = love.physics.newFixture(cuerpo, forma, 1)
                fixture:setFriction(0.3)
                fixture:setRestitution(0)
                n = n + 1
            end
        end
    end
    self.edificios = cuerpo
    print(string.format('FISICA %d sólidos de edificios y muro', n))
    if os.getenv('PLANO_DEPURAR') then
        -- Prueba: una bola de 2 m a 10 m/s contra la fachada de un edificio.
        for _, h in ipairs(plano.listaHuellas) do
            if h.solido and not h.muro then
                local fx, fy = h.cx + (h.hy + 100) * -h.s, h.cy + (h.hy + 100) * h.c
                local x, _, z = self.conversor:punto(fx, fy, 0)
                local b = love.physics.newBody(self.mundo:getWorld(), x, z, 'dynamic')
                love.physics.newFixture(b, love.physics.newCircleShape(0.1), 1):setMask(4)
                local cx, _, cz = self.conversor:punto(h.cx, h.cy, 0)
                local dx, dz = cx - x, cz - z
                local l = math.sqrt(dx * dx + dz * dz)
                b:setLinearVelocity(dx / l * 3, dz / l * 3)
                for _ = 1, 300 do
                    self.mundo:getWorld():update(1 / 60)
                end
                local bx, bz = b:getPosition()
                local ex = math.sqrt((bx - cx) ^ 2 + (bz - cz) ^ 2) * 100
                print(string.format('FISICA prueba: bola a %.0f px del centro del edificio (fachada a %.0f px): %s', ex, h.hy, ex > h.hy and 'choca' or 'ATRAVIESA'))
                b:destroy()
                local imp = require('batalla.impactos').rayo(self.suelo, fx, fy, h.z0 + 20, h.cx, h.cy, h.z0 + 20)
                print(string.format('FISICA rayo bala: %s en t %.2f (fachada en t %.2f)', imp and imp.tipo or 'nada', imp and imp.t or -1, 100 / (h.hy + 100)))
                break
            end
        end
    end
end

--- Agua (Valeria): paredes estáticas en las orillas (`suelo.agua.bordes`,
-- batalla/agua.lua), sin rozamiento ni rebote como el límite: ningún
-- vehículo entra en el agua.
function Fisica:crearAgua()
    local agua = self.suelo.agua
    if not agua or #agua.bordes == 0 then
        return
    end
    local cuerpo = love.physics.newBody(self.mundo:getWorld(), 0, 0, 'static')
    cuerpo:setUserData({ agua = true })
    for _, b in ipairs(agua.bordes) do
        local ax, _, az = self.conversor:punto(b[1], b[2], 0)
        local bx, _, bz = self.conversor:punto(b[3], b[4], 0)
        local fixture = love.physics.newFixture(cuerpo, love.physics.newEdgeShape(ax, az, bx, bz), 1)
        fixture:setFriction(0)
        fixture:setRestitution(0)
    end
    self.agua = cuerpo
end

--- ¿Acepta el terreno a `unidad` en (x, y)? El suelo no cambia: la última
-- respuesta se guarda en la unidad y, si no se ha movido (quieta, parada a
-- disparar o averiada), no se vuelve a muestrear (se pregunta dos veces por
-- cuadro y unidad).
function Fisica:transitable(unidad, x, y)
    if unidad.transitableX == x and unidad.transitableY == y then
        return unidad.transitableSi
    end
    local si = self:muestrearTransitable(unidad, x, y)
    unidad.transitableX, unidad.transitableY, unidad.transitableSi = x, y, si
    return si
end

function Fisica:muestrearTransitable(unidad, x, y)
    local s = self.suelo
    local radio = radioMapa(unidad)
    if s.limite and not s.limite:dentro(x, y, radio) then
        return false
    end
    if s.transitable and not s:transitable(x, y) then
        return false
    end
    if s.agua and s.agua:enAgua(x, y, radio) then
        return false
    end
    for _, muestra in ipairs(MUESTRAS_TRANSITABLES) do
        local px = x + muestra[1] * radio
        local py = y + muestra[2] * radio
        if s.transitable and not s:transitable(px, py) then
            return false
        end
    end
    return true
end

function Fisica:guardarSeguro(unidad)
    if not unidad.colision or not self:transitable(unidad, unidad.x, unidad.y) then
        return
    end
    local colision = unidad.colision
    local cuerpo = colision:getBody()
    local posicion = colision:getPosition()
    unidad.seguroX = unidad.x
    unidad.seguroY = unidad.y
    unidad.seguroZ = unidad.z
    unidad.seguroRumbo = unidad.rumbo
    colision.lastSafeX = posicion.x
    colision.lastSafeY = posicion.y
    colision.lastSafeZ = posicion.z
    colision.lastSafeAngle = cuerpo:getAngle()
    colision.lastSafeVx = 0
    colision.lastSafeVz = 0
    colision.lastSafeVy = 0
    colision.lastSafeAngleVelocity = 0
end

function Fisica:restaurarSeguro(unidad)
    local colision = unidad.colision
    if not colision or not unidad.seguroX then
        return false
    end
    unidad.x = unidad.seguroX
    unidad.y = unidad.seguroY
    unidad.z = self.suelo:altura(unidad.x, unidad.y)
    unidad.rumbo = unidad.seguroRumbo or unidad.rumbo
    local x, y, z = self.conversor:punto(unidad.x, unidad.y, unidad.z)
    local cuerpo = colision:getBody()
    cuerpo:setPosition(x, z)
    cuerpo:setLinearVelocity(0, 0)
    cuerpo:setAngle(unidad.rumbo)
    cuerpo:setAngularVelocity(0)
    colision.y = y
    colision.vy = 0
    colision.lastSafeX = x
    colision.lastSafeY = y
    colision.lastSafeZ = z
    colision.lastSafeAngle = unidad.rumbo
    colision.lastSafeVx = 0
    colision.lastSafeVz = 0
    colision.lastSafeVy = 0
    colision.lastSafeAngleVelocity = 0
    return true
end

function Fisica:crearUnidad(unidad)
    if unidad.tipo == 'soldado' then
        return
    end

    local radio = unidad.tipo == 'tanque' and Fisica.radioTanque or Fisica.radioLanzacohetes
    local forma = physics:newCylinder(radio, 0.35, 0)
    local x, y, z = self.conversor:punto(unidad.x, unidad.y, unidad.z)
    local colision = self.mundo:add(forma, 'dynamic', x, y, z)
    colision:setDensity(unidad.tipo == 'tanque' and 3200 or 2400)
    colision:setFriction(0.82)
    colision:setStepHeight(0.16)
    colision:getBody():setAngle(unidad.rumbo)
    colision:getBody():setLinearDamping(3.5)
    colision:getBody():setAngularDamping(5)
    for _, fixture in ipairs(colision.fixtures) do
        fixture:setCategory(2)
        fixture:setMask(4) -- Agua (Valeria): no choca con la malla gruesa del terreno
    end
    unidad.colision = colision
    self.unidadDe[colision:getBody()] = unidad -- Derribo (Valeria)
    -- La extensión resta masa * gravedad * rozamiento a la velocidad.
    -- Se compensa esa masa sin cambiar el agarre de las fixtures Box2D.
    rozamientoRuedas(unidad, Fisica.rozamientoFreno)
    self:guardarSeguro(unidad)
end

function Fisica:crearUnidades()
    for _, unidad in ipairs(self.unidades) do
        self:crearUnidad(unidad)
    end
end

--- La rueda conserva su tamaño; colisiona con el suelo y árboles, sin empujar tropas.
function Fisica:crearResto(rueda)
    local escala = Conversor.escala
    local radio = rueda.radio * escala
    local forma = physics:newCylinder(radio, 0, -radio)
    local x, y, z = self.conversor:punto(rueda.x, rueda.y, rueda.z)
    local colision = self.mundo:add(forma, 'dynamic', x, y, z)
    colision:setDensity(90)
    colision:setStepHeight(0.2)
    colision:setFriction(0.6)
    local cuerpo = colision:getBody()
    cuerpo:setLinearDamping(1.6)
    cuerpo:setLinearVelocity(rueda.vx * escala, rueda.vy * escala)
    colision.vy = rueda.vz * escala
    local masa = cuerpo:getMass()
    colision.staticFriction = 0.14 / masa
    colision.slidingFriction = 0.14 / masa
    for _, fixture in ipairs(colision.fixtures) do
        fixture:setCategory(3)
        fixture:setMask(2, 3)
    end
    rueda.colision = colision
    rueda.fisica = true
    rueda.rebotes = 0
    self.restos[#self.restos + 1] = rueda
end

--- Recoge la posición física y retira del motor los restos ya apoyados.
function Fisica:sincronizarRestos()
    for indice = #self.restos, 1, -1 do
        local rueda = self.restos[indice]
        local colision = rueda.colision
        local posicion = colision:getPosition()
        rueda.x = self.suelo.cx + posicion.x / Conversor.escala
        rueda.y = self.suelo.cy + posicion.z / Conversor.escala
        rueda.z = posicion.y / Conversor.escala
        if colision.touchedFloor and rueda.velocidadVerticalAnterior < -0.3 and rueda.rebotes < 2 then
            colision.vy = -rueda.velocidadVerticalAnterior * 0.25
            rueda.rebotes = rueda.rebotes + 1
        end
        local vx, vy = colision:getBody():getLinearVelocity()
        if
            colision.touchedFloor
            and rueda.tiempo > 1.2
            and vx * vx + vy * vy < 0.0004
            and math.abs(colision.vy) < 0.1
        then
            rueda.quieta = true
            -- Actualiza también la matriz antes de congelar la animación.
            rueda.matriz[4] = rueda.x
            rueda.matriz[8] = rueda.y
            rueda.matriz[12] = rueda.z
            colision:destroy()
            rueda.colision = nil
            table.remove(self.restos, indice)
        end
    end
end

function Fisica:iniciarCuadro()
    for _, unidad in ipairs(self.unidades) do
        unidad.movimientoFisico = false
    end
end

function Fisica:impulsar(unidad, rumbo, velocidad)
    local colision = unidad.colision
    if not colision or colision:getBody():isDestroyed() then
        return false
    end

    local cuerpo = colision:getBody()
    rozamientoRuedas(unidad, Fisica.resistenciaRodadura)
    local actual = cuerpo:getAngle()
    local diferencia = diferenciaAngular(rumbo, actual)
    local velocidadAngular = cuerpo:getAngularVelocity()
    local masa = cuerpo:getMass()
    colision:applyTorque((diferencia * Fisica.gananciaGiro - velocidadAngular * Fisica.frenoGiro) * masa)

    local velocidadX, _, velocidadZ = colision:getVelocity():unpack()
    local metrosSegundo = velocidad * Conversor.escala
    local factorGiro = math.max(0.25, math.cos(diferencia))
    local objetivoX = math.cos(actual) * metrosSegundo * factorGiro
    local objetivoZ = math.sin(actual) * metrosSegundo * factorGiro
    colision:applyForce(
        (objetivoX - velocidadX) * masa * Fisica.gananciaMotor,
        0,
        (objetivoZ - velocidadZ) * masa * Fisica.gananciaMotor
    )
    unidad.movimientoFisico = true
    return true
end

--- Conduce un vehículo con ruedas delanteras: el giro nace del ángulo de esas ruedas.
function Fisica:conducir(unidad, velocidad, direccionRuedas, entreEjes)
    local colision = unidad.colision
    if not colision or colision:getBody():isDestroyed() then
        return false
    end

    local cuerpo = colision:getBody()
    local masa = cuerpo:getMass()
    local actual = cuerpo:getAngle()
    local frenteX = math.cos(actual)
    local frenteZ = math.sin(actual)
    local ladoX = -frenteZ
    local ladoZ = frenteX
    local velocidadX, _, velocidadZ = colision:getVelocity():unpack()
    local velocidadFrente = velocidadX * frenteX + velocidadZ * frenteZ
    local velocidadLateral = velocidadX * ladoX + velocidadZ * ladoZ
    local metrosSegundo = velocidad * Conversor.escala
    local ajusteGiro = math.max(0.45, math.cos(direccionRuedas))
    local objetivoFrente = metrosSegundo * ajusteGiro

    rozamientoRuedas(unidad, Fisica.resistenciaRodadura)
    colision:applyForce(
        frenteX * (objetivoFrente - velocidadFrente) * masa * Fisica.gananciaMotor
            - ladoX * velocidadLateral * masa * Fisica.agarreLateral,
        0,
        frenteZ * (objetivoFrente - velocidadFrente) * masa * Fisica.gananciaMotor
            - ladoZ * velocidadLateral * masa * Fisica.agarreLateral
    )

    local distancia = math.max(0.01, entreEjes * Conversor.escala)
    local velocidadGiro = velocidadFrente / distancia * math.tan(direccionRuedas)
    local velocidadAngular = cuerpo:getAngularVelocity()
    colision:applyTorque((velocidadGiro - velocidadAngular) * masa * Fisica.gananciaDireccion)
    unidad.movimientoFisico = true
    return true
end

function Fisica:frenar(unidad)
    local colision = unidad.colision
    if not colision then
        return
    end
    rozamientoRuedas(unidad, Fisica.rozamientoFreno)
    local velocidadX, _, velocidadZ = colision:getVelocity():unpack()
    local cuerpo = colision:getBody()
    local masa = cuerpo:getMass()
    colision:applyForce(-velocidadX * masa * 8, 0, -velocidadZ * masa * 8)
    colision:applyTorque(-cuerpo:getAngularVelocity() * masa * 6)
end

function Fisica:sincronizar(unidad)
    if not unidad.colision then
        return
    end

    local posicion = unidad.colision:getPosition()
    local anteriorX = unidad.x
    local anteriorY = unidad.y
    unidad.x = self.suelo.cx + posicion.x / Conversor.escala
    unidad.y = self.suelo.cy + posicion.z / Conversor.escala
    unidad.z = posicion.y / Conversor.escala
    unidad.rumbo = unidad.colision:getBody():getAngle()

    if not unidad.muerto and not self:transitable(unidad, unidad.x, unidad.y) then
        if self:restaurarSeguro(unidad) then
            self:frenar(unidad)
        end
        return
    end
    self:guardarSeguro(unidad)

    if unidad.movimientoFisico and not unidad.muerto then
        local avanceX = unidad.x - anteriorX
        local avanceY = unidad.y - anteriorY
        unidad.avanzado = unidad.avanzado
            + avanceX * math.cos(unidad.rumboBando)
            + avanceY * math.sin(unidad.rumboBando)
    end
end

--- Agua (Valeria): el vehículo se apoya en el suelo real (`Suelo:altura`, la
-- superficie dibujada), no en la malla gruesa de colisión.
function Fisica:apoyar(unidad)
    local colision = unidad.colision
    if not colision or colision:getBody():isDestroyed() then
        return
    end
    local x, z = colision:getBody():getWorldCenter()
    local escala = Conversor.escala
    colision.y = self.suelo:altura(self.suelo.cx + x / escala, self.suelo.cy + z / escala) * escala
    colision.vy = 0
    -- Rozamiento de la extensión contra el suelo: solo el lanzacohetes lo
    -- tiene compensado por su masa (rozamientoRuedas); en el tanque, sin
    -- compensar, lo pararía en seco, y antes casi nunca se aplicaba.
    colision.touchedFloor = unidad.tipo == 'lanzacohetes'
end

function Fisica:actualizar(dt)
    for _, unidad in ipairs(self.unidades) do
        if not unidad.movimientoFisico or unidad.muerto then
            self:frenar(unidad)
        end
    end
    for _, rueda in ipairs(self.restos) do
        rueda.velocidadVerticalAnterior = rueda.colision.vy
        rueda.colision.shape.bottom = -rueda.alturaApoyo * Conversor.escala
        rueda.colision.shape.top = rueda.alturaApoyo * Conversor.escala
    end
    self.mundo:update(dt)
    for _, unidad in ipairs(self.unidades) do
        self:apoyar(unidad) -- Agua (Valeria)
        self:sincronizar(unidad)
    end
    self.derribo:actualizar() -- Derribo (Valeria)
    self:sincronizarRestos()
end

return Fisica
