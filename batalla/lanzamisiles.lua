-- El camión de vértices de antes (19-nov: ya no sale en la batalla; 21-nov:
-- sus modelos del pack Synty se quitaron). El camión de misiles de hoy es un
-- robot: batalla/robots/tipos/camionMisiles.lua.
--
-- Articulaciones del camión: rueda según el desplazamiento real y eleva la
-- rampa sin mover el chasis. Ambos renderizadores usan las mismas matrices.
--
-- Hay un `Lanzamisiles` por modelo de camión (assets/modelos3d/catalogo.lua):
-- las piezas y las ruedas salen de su archivo. El BM-21 y el M142 HIMARS
-- llevan seis ruedas (`ruedaDelantera*`, `ruedaMedia*`, `ruedaUltima*`) y
-- los cohetes dentro de los tubos. `self.piezas` es la lista del modelo:
-- primero las fijas y desde `self.primeraRueda`, las ruedas.
--
-- El Scud-B es el camión de 4 misiles (con `rampaLanzador`; sustituye al de
-- un misil, decisión del dueño del 2026-10-02): ocho ruedas con suspensión,
-- amortiguadores, ventiladores, gatos, pistón y sus misiles en la rampa. Sus
-- piezas y matrices salen de batalla/articulacion_camion.lua
-- (`self.articulacion`); el contenedor es su rampa.

local Matriz = require('batalla.matriz')
local Destruccion = require('batalla.destruccion')
local ArticulacionCamion = require('batalla.articulacion_camion')
require('batalla.vehiculos.gestorVehiculos')

local Lanzamisiles = {}
Lanzamisiles.__index = Lanzamisiles
Lanzamisiles.direccionMaxima = 0.45
Lanzamisiles.velocidadDireccion = 1.6

-- Todas las piezas que puede tener un camión de cohetes en tubos, en su
-- orden (el de 4 misiles lleva su propia lista: ArticulacionCamion).
Lanzamisiles.piezas = {
    'chasis',
    'contenedor',
    'insignia',
    'ruedaDelanteraIzquierda',
    'ruedaDelanteraDerecha',
    'ruedaMediaIzquierda',
    'ruedaMediaDerecha',
    'ruedaTraseraIzquierda',
    'ruedaTraseraDerecha',
    'ruedaUltimaIzquierda',
    'ruedaUltimaDerecha',
}

-- Las ruedas que giran con la dirección.
local DELANTERAS = { ruedaDelanteraIzquierda = true, ruedaDelanteraDerecha = true }

--- Conserva pivotes y tablas de trabajo; ninguna malla se crea por cuadro.
function Lanzamisiles.nuevo(modelo, suelo)
    local self = setmetatable({}, Lanzamisiles)
    self.modelo = modelo
    self.localPieza = {}
    self.rotacion = {}
    self.direccion = {}
    local articulacion = ArticulacionCamion.de(modelo)
    if articulacion then
        self.articulacion = articulacion
        self.cuatroMisiles = true
        self.piezas = articulacion.piezas
        self.ruedas = articulacion.ruedas
        self.primeraRueda = articulacion.primeraRueda
        self.cargaVisible = false
        self.radioRueda = articulacion.radioRueda
        self.entreEjes = articulacion.entreEjes
        self.elevacionMaxima = articulacion.elevacion
        self.pivotes = articulacion.abs
        self.destruccion = Destruccion.nueva(modelo, suelo, self.piezas, self.primeraRueda, self.pivotes)
        return self
    end
    self.elevacionMaxima = modelo.elevacion or 35
    self.piezas = {}
    self.ruedas = {}
    for _, nombre in ipairs(Lanzamisiles.piezas) do
        if modelo.piezas[nombre] then
            self.piezas[#self.piezas + 1] = nombre
            if nombre:sub(1, 5) == 'rueda' then
                self.ruedas[#self.ruedas + 1] = nombre
                self.primeraRueda = self.primeraRueda or #self.piezas
            end
        end
    end
    -- Ningún camión de tubos lleva misil a la vista (Tropas aún lo lee).
    self.cargaVisible = false
    self.radioRueda = modelo.piezas.ruedaDelanteraIzquierda.pivote[3]
    self.entreEjes = modelo.piezas.ruedaDelanteraIzquierda.pivote[1] - modelo.piezas.ruedaUltimaIzquierda.pivote[1]
    self.destruccion = Destruccion.nueva(modelo, suelo, self.piezas, self.primeraRueda)
    return self
end

--- Cada camión conserva sus matrices y sus ángulos, también al estar parado.
function Lanzamisiles:inicializar(unidad)
    unidad.misilCargado = true
    unidad.giroRuedas = {}
    unidad.matricesLanza = {}
    unidad.direccionRuedas = 0
    unidad.velocidadRuedas = 0
    unidad.tiempoDespliegue = 0
    unidad.fase = 'despliegue'
    for _, nombre in ipairs(self.piezas) do
        unidad.matricesLanza[nombre] = {}
        unidad.giroRuedas[nombre] = 0
    end
    if self.articulacion then
        self.articulacion:inicializar(unidad)
        -- Su vehículo con sus especializaciones: son las que lo mueven.
        local vehiculo = GestorVehiculos.crear(unidad, self.modelo.archivo, self)
        assert(vehiculo, 'Lanzamisiles: el modelo ' .. tostring(self.modelo.archivo)
            .. ' no tiene tipo en batalla/vehiculos/tipos')
    end
    self:recordarPosicion(unidad)
    self:actualizarMatrices(unidad)
end

--- Guarda la posición anterior a la integración física.
function Lanzamisiles:recordarPosicion(unidad)
    unidad.anteriorRuedasX = unidad.x
    unidad.anteriorRuedasY = unidad.y
    unidad.anteriorRuedasZ = unidad.z
    unidad.anteriorRuedasRumbo = unidad.rumbo
    unidad.direccionRuedasOrdenada = false
end

local function diferenciaAngular(destino, actual)
    return (destino - actual + math.pi) % (math.pi * 2) - math.pi
end

local function acercar(actual, objetivo, paso)
    local diferencia = objetivo - actual
    if diferencia > paso then
        return actual + paso
    end
    if diferencia < -paso then
        return actual - paso
    end
    return objetivo
end

--- Gira las ruedas delanteras hacia el rumbo deseado sin saltos instantáneos.
function Lanzamisiles:dirigir(unidad, rumboDeseado, dt)
    local diferencia = diferenciaAngular(rumboDeseado, unidad.rumbo)
    local objetivo = math.max(-Lanzamisiles.direccionMaxima, math.min(Lanzamisiles.direccionMaxima, diferencia * 0.85))
    local paso = Lanzamisiles.velocidadDireccion * dt
    unidad.direccionRuedas = acercar(unidad.direccionRuedas, objetivo, paso)
    unidad.direccionRuedasOrdenada = true
    return unidad.direccionRuedas
end

--- Rodadura con signo y dirección del eje delantero. Un camión bloqueado
-- no gira las ruedas por tener el motor encendido; tiene que desplazarse.
function Lanzamisiles:medirMovimiento(unidad, dt)
    if unidad.destruccion then
        GestorVehiculos.actualizar(unidad, dt)
        self.destruccion:actualizar(unidad, dt)
        self:actualizarMatrices(unidad)
        return
    end
    local dx = unidad.x - unidad.anteriorRuedasX
    local dy = unidad.y - unidad.anteriorRuedasY
    local dz = unidad.z - unidad.anteriorRuedasZ
    local avance = dx * math.cos(unidad.rumbo) + dy * math.sin(unidad.rumbo)
    local distancia = math.sqrt(avance * avance + dz * dz)
    if math.abs(avance) < 0.00001 then
        distancia = 0
    elseif avance < 0 then
        distancia = -distancia
    end
    local giro = (unidad.rumbo - unidad.anteriorRuedasRumbo + math.pi) % (math.pi * 2) - math.pi
    unidad.velocidadRuedas = dt > 0 and math.sqrt(dx * dx + dy * dy) / dt or 0
    if not unidad.direccionRuedasOrdenada then
        local direccion = 0
        if math.abs(distancia) > 0.001 then
            direccion = math.atan(self.entreEjes * giro / distancia)
        end
        direccion = math.max(-Lanzamisiles.direccionMaxima, math.min(Lanzamisiles.direccionMaxima, direccion))
        local paso = math.max(0, math.min(1, dt * 8))
        unidad.direccionRuedas = unidad.direccionRuedas + (direccion - unidad.direccionRuedas) * paso
    end
    if not unidad.muerto then
        for _, nombre in ipairs(self.ruedas) do
            local pivote = self.pivotes and self.pivotes[nombre] or self.modelo.piezas[nombre].pivote
            local recorrido = distancia - pivote[2] * giro
            unidad.giroRuedas[nombre] = (unidad.giroRuedas[nombre] + recorrido / self.radioRueda) % (math.pi * 2)
        end
    end
    -- Las especializaciones, con la velocidad y lo rodado de este paso.
    GestorVehiculos.actualizar(unidad, dt)
    self:actualizarMatrices(unidad)
end

--- Compone las piezas relativas al chasis (el contenedor, girado en su bisagra).
-- El camión de 4 misiles vivo compone solo las piezas de `unidad.piezasVista`
-- (las del nivel de detalle con que se dibuja; nil, todas: ArticulacionCamion).
function Lanzamisiles:actualizarMatrices(unidad)
    -- Las especializaciones colocan sus piezas con el estado de ahora.
    GestorVehiculos.posar(unidad)
    local matrices = unidad.matricesLanza
    local casco = unidad.destruccion and unidad.destruccion.casco or unidad.casco
    local articulacion = self.articulacion
    if articulacion then
        local filtro = not unidad.muerto and unidad.piezasVista or nil
        -- Parado, asentado y con la rampa, los gatos y los misiles como en el
        -- cálculo anterior (y el mismo casco y filtro): solo giran los
        -- ventiladores.
        local firma = articulacion:firma(unidad)
        local quieta = not unidad.muerto
            and unidad.matricesListas == casco
            and unidad.firmaMatrices == firma
            and unidad.direccionMatrices == unidad.direccionRuedas
            and unidad.filtroMatrices == filtro
        if quieta then
            articulacion:matricesVentiladores(unidad, matrices, filtro)
            return
        end
        local restos = unidad.destruccion and unidad.destruccion.porNombre
        articulacion:matrices(unidad, casco, matrices, restos, filtro)
        unidad.matricesListas = casco
        unidad.firmaMatrices = firma
        unidad.direccionMatrices = unidad.direccionRuedas
        unidad.filtroMatrices = filtro
        return
    end
    matrices.chasis = casco
    matrices.insignia = casco
    local pivote = self.modelo.piezas.contenedor.pivote
    Matriz.cabecear(-math.rad(unidad.elevacion), pivote[1], pivote[2], pivote[3], self.localPieza)
    Matriz.multiplicar(casco, self.localPieza, matrices.contenedor)
    for _, nombre in ipairs(self.ruedas) do
        pivote = self.modelo.piezas[nombre].pivote
        local direccion = DELANTERAS[nombre] and unidad.direccionRuedas or 0
        Matriz.colocar(pivote[1], pivote[2], pivote[3], direccion, 1, self.direccion)
        Matriz.cabecear(unidad.giroRuedas[nombre], 0, 0, 0, self.rotacion)
        Matriz.multiplicar(self.direccion, self.rotacion, self.localPieza)
        local resto = unidad.destruccion and unidad.destruccion.porNombre[nombre]
        if resto then
            matrices[nombre] = resto.matriz
        else
            Matriz.multiplicar(casco, self.localPieza, matrices[nombre])
        end
    end
end

--- Índice de `modelo.bocas` por el que sale el misil de la ranura `ranura`
-- (Tropas.siguienteRanura): en el camión de 4 misiles, las ranuras siguen el
-- orden de disparo de batalla/articulacion_camion.lua y las bocas el de la
-- tabla `misiles` del contrato. Sin articulación, la misma ranura.
function Lanzamisiles:bocaDeRanura(ranura)
    local articulacion = self.articulacion
    local m = articulacion and articulacion.ordenMisiles[ranura]
    if m then
        for indice, datos in ipairs(self.modelo.misiles or {}) do
            if datos.pieza == m.nombre and self.modelo.bocas[indice] then
                return indice
            end
        end
    end
    return math.min(ranura, #self.modelo.bocas)
end

--- Las piezas que se dibujan del camión `unidad`: `filtro` (un conjunto de
-- nombres, el del nivel de detalle; nil, todas). Si su última composición
-- no las tenía todas, se compone ya (el nivel ha cambiado en este cuadro).
function Lanzamisiles:verPiezas(unidad, filtro)
    if unidad.piezasVista == filtro then
        return
    end
    unidad.piezasVista = filtro
    local hecho = unidad.filtroMatrices
    if not self.articulacion or unidad.muerto or hecho == nil then
        return
    end
    if filtro then
        local cubiertas = true
        for nombre in pairs(filtro) do
            if not hecho[nombre] then
                cubiertas = false
                break
            end
        end
        if cubiertas then
            return
        end
    end
    self:actualizarMatrices(unidad)
end

--- Compone todas las piezas aunque de lejos se dibujen solo unas pocas
-- (para leerlas desde un script: batalla/vehiculos/pieza.lua). El siguiente
-- cálculo vuelve a las del nivel que se dibuja.
function Lanzamisiles:actualizarTodas(unidad)
    local vista = unidad.piezasVista
    unidad.piezasVista = nil
    self:actualizarMatrices(unidad)
    unidad.piezasVista = vista
end

--- ¿Se dibuja la pieza `nombre`? Destruido, sin la franja de la nación; en
-- las que oculta una especialización (Pieza:setVisible,
-- batalla/vehiculos/pieza.lua; los misiles de la rampa, `misiles`).
function Lanzamisiles.visible(unidad, nombre)
    if unidad.muerto and nombre == 'insignia' then
        return false
    end
    local ocultas = unidad.piezasOcultas
    if ocultas and ocultas[nombre] then
        return false
    end
    return true
end

return Lanzamisiles
