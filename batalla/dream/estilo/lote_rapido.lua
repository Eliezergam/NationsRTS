-- Lote de instancias que se rellena por FFI (de la prueba de estrés de Camila,
-- batalla/pruebas_estilo/lote_rapido.lua), con el tono por copia de la
-- batalla: cada copia son 15 flotantes (tres columnas de giro, la posición y
-- el tono, el formato de batalla/dream/instancias_tono.lua) escritos en un
-- ByteData y subidos con una sola llamada a Mesh:setVertices.
--
-- El recorte lo hace quien rellena el lote (por celdas, por frustum y por
-- distancia, batalla/dream/vegetacion.lua): la esfera del lote queda a cero
-- para que 3Dream no lo vuelva a recortar.

local ffi = require('ffi')
local InstanciasTono = require('batalla.dream.instancias_tono')

local LoteRapido = {}
LoteRapido.__index = LoteRapido

-- Flotantes por copia.
LoteRapido.ancho = InstanciasTono.flotantes
local ANCHO = LoteRapido.ancho
local BYTES = ANCHO * 4

--- `opciones.soloSombra`: el lote no se dibuja, solo proyecta sombra.
-- `opciones.sinSombra`: se dibuja pero no proyecta sombra.
function LoteRapido.nuevo(dream, malla, capacidad, opciones)
    opciones = opciones or {}
    local self = setmetatable({}, LoteRapido)
    malla:setVertexShader('vientoBatalla')
    self.malla = InstanciasTono.nuevas(dream, malla)
    self.malla:setVertexShader('vientoBatalla')
    self.malla.boundingSphere = dream:newBoundingSphere()
    if opciones.soloSombra then
        self.malla:setRenderVisibility(false)
        self.malla:setShadowVisibility(true)
    elseif opciones.sinSombra then
        self.malla:setShadowVisibility(false)
    end
    self.dream = dream
    self.cantidad = 0
    self.triangulosCopia = opciones.triangulos or 0
    self:reservar(math.max(16, capacidad))
    -- Los lotes de sombra guardan sus copias por cascada (sombra_cascadas.lua):
    -- primero las que caen en la cascada 1, luego en la 2 y luego en la 3.
    -- Cada cascada dibuja solo el principio del lote que le toca.
    if opciones.soloSombra then
        self.porCascada = true
        self.cuentas = { 0, 0, 0 }
        self.cortes = { 0, 0, 0 }
        self.claseActual = 1
        self.buffers = {}
        self:reservarCascadas(self.capacidad)
        self.puntero = self.buffers[1]
    end
    self.tipo = opciones.tipo or '?'
    return self
end

--- Memoria para `capacidad` copias (sin conservar las que hubiera).
function LoteRapido:reservar(capacidad)
    self.capacidad = capacidad
    self:reservarDatos(capacidad)
    self.puntero = ffi.cast('float*', self.datos:getFFIPointer())
end

--- Memoria que se sube a la GPU y búfer de copias de la malla.
function LoteRapido:reservarDatos(capacidad)
    self.capacidadDatos = capacidad
    self.datos = love.data.newByteData(capacidad * BYTES)
    self.malla:resize(capacidad)
end

function LoteRapido:reservarCascadas(capacidad)
    for c = 1, 3 do
        self.buffers[c] = ffi.new('float[?]', capacidad * ANCHO)
    end
end

--- Dobla la capacidad conservando las copias ya escritas.
function LoteRapido:crecer()
    local nueva = self.capacidad * 2
    if self.porCascada then
        self.cuentas[self.claseActual] = self.cantidad
        local viejos = self.buffers
        self.buffers = {}
        self:reservarCascadas(nueva)
        for c = 1, 3 do
            ffi.copy(self.buffers[c], viejos[c], self.cuentas[c] * BYTES)
        end
        self.capacidad = nueva
        self.puntero = self.buffers[self.claseActual]
        return
    end
    local viejo, cantidad = self.puntero, self.cantidad
    local guardado = ffi.new('float[?]', cantidad * ANCHO)
    ffi.copy(guardado, viejo, cantidad * BYTES)
    self:reservar(nueva)
    ffi.copy(self.puntero, guardado, cantidad * BYTES)
end

function LoteRapido:vaciar()
    self.cantidad = 0
    if self.porCascada then
        self.cuentas[1], self.cuentas[2], self.cuentas[3] = 0, 0, 0
        self.claseActual = 1
        self.puntero = self.buffers[1]
    end
end

--- En un lote de sombra, las copias siguientes van a la cascada `clase`.
function LoteRapido:clase(clase)
    if clase == self.claseActual then
        return
    end
    self.cuentas[self.claseActual] = self.cantidad
    self.claseActual = clase
    self.puntero = self.buffers[clase]
    self.cantidad = self.cuentas[clase]
end

--- Copia la instancia `indice` (desde 0) de un arreglo de flotantes con el
-- mismo formato.
function LoteRapido:copiar(fuente, indice)
    local n = self.cantidad
    if n >= self.capacidad then
        self:crecer()
    end
    ffi.copy(self.puntero + n * ANCHO, fuente + indice * ANCHO, BYTES)
    self.cantidad = n + 1
end

--- Copia `n` copias seguidas desde `fuente` (un paquete de una celda).
function LoteRapido:copiarBloque(fuente, n)
    local cantidad = self.cantidad
    while cantidad + n > self.capacidad do
        self:crecer()
    end
    ffi.copy(self.puntero + cantidad * ANCHO, fuente, n * BYTES)
    self.cantidad = cantidad + n
end

--- Sube las copias a la GPU. Hay que llamarlo antes de dream:draw.
function LoteRapido:subir()
    local malla = self.malla
    if self.porCascada then
        self.cuentas[self.claseActual] = self.cantidad
        local suma = self.cuentas[1] + self.cuentas[2] + self.cuentas[3]
        if suma > self.capacidadDatos then
            self:reservarDatos(suma * 2)
        end
        local destino = ffi.cast('float*', self.datos:getFFIPointer())
        local total = 0
        for c = 1, 3 do
            local n = self.cuentas[c]
            if n > 0 then
                ffi.copy(destino + total * ANCHO, self.buffers[c], n * BYTES)
            end
            total = total + n
            self.cortes[c] = total
        end
        self.cantidad = total
        self.claseActual = 1
        self.puntero = self.buffers[1]
    end
    if self.cantidad > 0 then
        malla.instanceMesh:setVertices(self.datos, 1, self.cantidad)
    end
    malla.instancesCount = self.cantidad
end

function LoteRapido:dibujar(dream)
    if self.cantidad > 0 then
        dream:draw(self.malla)
    end
end

function LoteRapido:triangulos()
    return self.cantidad * self.triangulosCopia
end

return LoteRapido
