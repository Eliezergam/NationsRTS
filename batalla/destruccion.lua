-- Restos del lanzamisiles: piezas originales, daño variable y caída física.
-- El azar visual es independiente de la puntería y de la simulación del mundo.

local Matriz = require('batalla.matriz')

local Destruccion = {}
Destruccion.__index = Destruccion

--- Rotación sobre el eje longitudinal, reutilizando una matriz de trabajo.
local function ladear(angulo, salida)
    Matriz.identidad(salida)
    local coseno = math.cos(angulo)
    local seno = math.sin(angulo)
    salida[6] = coseno
    salida[7] = -seno
    salida[10] = seno
    salida[11] = coseno
    return salida
end

--- Geometría de las ruedas preparada una vez, antes de cualquier destrucción.
-- `nombres`: las piezas del camión; las ruedas, desde `primera` (5 en el
-- Scud-B, con su misil cargado; 4 en los camiones sin él). `pivotes`
-- (opcional): el pivote de cada pieza en el chasis, si los del modelo son
-- relativos a su padre (el camión de 4 misiles, batalla/articulacion_camion.lua).
function Destruccion.nueva(modelo, suelo, nombres, primera, pivotes)
    local self = setmetatable({}, Destruccion)
    self.suelo = suelo
    self.modelo = modelo
    self.pivotes = pivotes
    self.nombres = nombres
    self.primera = primera or 5
    self.geometria = {}
    self.giro = {}
    self.ladeo = {}
    self.localPieza = {}
    for indice = self.primera, #nombres do
        local nombre = nombres[indice]
        local malla = modelo.piezas[nombre].malla
        local radio = 0
        local semiancho = 0
        for vertice = 1, malla:getVertexCount() do
            local x, y, z = malla:getVertex(vertice)
            radio = math.max(radio, math.sqrt(x * x + z * z))
            semiancho = math.max(semiancho, math.abs(y))
        end
        self.geometria[nombre] = { radio = radio, semiancho = semiancho }
    end
    return self
end

--- Sortea de una a todas las ruedas sin repetición y conserva su pose al separarse.
function Destruccion:iniciar(unidad, fisica)
    if unidad.destruccion then
        return
    end
    -- Las ruedas salen de su pose de ahora: con el camión ya caído, la
    -- articulación las compone todas (de lejos solo componía las de su nivel).
    if unidad.lanzador and unidad.lanzador.articulacion then
        unidad.lanzador:actualizarMatrices(unidad)
    end
    local semilla = math.floor(math.abs(unidad.x * 7 + unidad.y * 13 + unidad.caida * 31)) % 2147483646 + 1
    local azar = love.math.newRandomGenerator(semilla)
    local dano = {
        tiempo = 0,
        ruedas = {},
        porNombre = {},
        casco = {},
        elevacionInicial = unidad.elevacion,
        cantidad = azar:random(1, #self.nombres - self.primera + 1),
    }
    unidad.destruccion = dano
    unidad.misilCargado = false
    unidad.fase = 'destruido'
    unidad.blanco = nil
    local candidatas = {}
    for indice = self.primera, #self.nombres do
        candidatas[#candidatas + 1] = self.nombres[indice]
    end
    local laterales = 0
    local longitudinales = 0
    for _ = 1, dano.cantidad do
        local indice = azar:random(1, #candidatas)
        local nombre = table.remove(candidatas, indice)
        local matriz = unidad.matricesLanza[nombre]
        local pivote = self.pivotes and self.pivotes[nombre] or self.modelo.piezas[nombre].pivote
        local lado = pivote[2] < 0 and -1 or 1
        local angulo = unidad.rumbo + lado * math.pi / 2 + (azar:random() - 0.5) * 0.7
        local velocidad = 55 + azar:random() * 95
        local geometria = self.geometria[nombre]
        local giroInicial = unidad.giroRuedas[nombre]
        Matriz.cabecear(-giroInicial, 0, 0, 0, self.giro)
        local base = Matriz.multiplicar(matriz, self.giro, {})
        local rueda = {
            nombre = nombre,
            x = matriz[4],
            y = matriz[8],
            z = matriz[12],
            vx = math.cos(angulo) * velocidad,
            vy = math.sin(angulo) * velocidad,
            vz = 160 + azar:random() * 160,
            radio = geometria.radio,
            semiancho = geometria.semiancho,
            alturaApoyo = geometria.radio,
            giro = giroInicial,
            ladeo = 0,
            lado = lado,
            velocidadGiro = lado * (5 + azar:random() * 8),
            base = base,
            matriz = { unpack(matriz) },
            tiempo = 0,
        }
        dano.ruedas[#dano.ruedas + 1] = rueda
        dano.porNombre[nombre] = rueda
        laterales = laterales + lado
        longitudinales = longitudinales + (pivote[1] > 0 and 1 or -1)
        if fisica then
            fisica:crearResto(rueda)
        end
    end
    dano.ladeo = -laterales * 0.028
    dano.cabeceo = longitudinales * 0.012
    local ruedas = #self.nombres - self.primera + 1
    dano.hundimiento = self.geometria[self.nombres[self.primera]].radio * (0.2 + 0.6 * dano.cantidad / ruedas)
    self:actualizar(unidad, 0)
end

--- Respaldo sin 3Dream: gravedad y contacto con el mismo suelo del juego.
function Destruccion:caerSinMotor(rueda, dt)
    rueda.vz = rueda.vz - 700 * dt
    local freno = math.exp(-1.6 * dt)
    rueda.vx = rueda.vx * freno
    rueda.vy = rueda.vy * freno
    rueda.x = rueda.x + rueda.vx * dt
    rueda.y = rueda.y + rueda.vy * dt
    rueda.z = rueda.z + rueda.vz * dt
    local apoyo = self.suelo:altura(rueda.x, rueda.y) + rueda.alturaApoyo
    if rueda.z <= apoyo then
        rueda.z = apoyo
        rueda.vz = -rueda.vz * 0.22
        if rueda.tiempo > 2 and math.abs(rueda.vx) + math.abs(rueda.vy) < 2 then
            rueda.quieta = true
        end
    end
end

--- Asienta el casco, deja caer la rampa y anima las ruedas ya independientes.
function Destruccion:actualizar(unidad, dt)
    local dano = unidad.destruccion
    dano.tiempo = dano.tiempo + dt
    local progreso = math.min(1, dano.tiempo / 1.4)
    local suavizado = progreso * progreso * (3 - 2 * progreso)
    unidad.elevacion = dano.elevacionInicial * (1 - suavizado)
    ladear(dano.ladeo * suavizado, self.ladeo)
    Matriz.cabecear(dano.cabeceo * suavizado, 0, 0, -dano.hundimiento * suavizado, self.giro)
    Matriz.multiplicar(self.giro, self.ladeo, self.localPieza)
    Matriz.multiplicar(unidad.casco, self.localPieza, dano.casco)
    for _, rueda in ipairs(dano.ruedas) do
        if not rueda.quieta then
            rueda.tiempo = rueda.tiempo + dt
            rueda.giro = rueda.giro + rueda.velocidadGiro * math.exp(-rueda.tiempo * 1.8) * dt
            rueda.ladeo = rueda.lado * math.pi / 2 * math.min(1, rueda.tiempo / 1.1)
            rueda.alturaApoyo = rueda.radio * math.abs(math.cos(rueda.ladeo))
                + rueda.semiancho * math.abs(math.sin(rueda.ladeo))
            if not rueda.fisica and dt > 0 then
                self:caerSinMotor(rueda, dt)
            end
            ladear(rueda.ladeo, self.ladeo)
            Matriz.cabecear(rueda.giro, 0, 0, 0, self.giro)
            Matriz.multiplicar(self.ladeo, self.giro, self.localPieza)
            Matriz.multiplicar(rueda.base, self.localPieza, rueda.matriz)
            rueda.matriz[4] = rueda.x
            rueda.matriz[8] = rueda.y
            rueda.matriz[12] = rueda.z
        end
    end
end

return Destruccion
