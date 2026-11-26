-- Tiempo de GPU de cada cuadro con consultas GL_TIME_ELAPSED de OpenGL,
-- pedidas por FFI a SDL_GL_GetProcAddress. LÖVE no las usa, así que no se
-- pisan. Se lee el resultado de hace unos cuadros para no esperar a la GPU.
-- Si el contexto no las tiene (OpenGL ES sin la extensión), `disponible` es
-- falso y el informe dice "sin medir".

local ffi = require('ffi')

local TiempoGpu = {}
TiempoGpu.__index = TiempoGpu

local GL_TIME_ELAPSED = 0x88BF
local GL_QUERY_RESULT = 0x8866
local GL_QUERY_RESULT_AVAILABLE = 0x8867
local RONDA = 5

ffi.cdef([[
    void *SDL_GL_GetProcAddress(const char *proc);
    typedef void (*pmeGenQueries)(int n, unsigned int *ids);
    typedef void (*pmeBeginQuery)(unsigned int target, unsigned int id);
    typedef void (*pmeEndQuery)(unsigned int target);
    typedef void (*pmeGetQueryObjectiv)(unsigned int id, unsigned int pname, int *params);
    typedef void (*pmeGetQueryObjectui64v)(unsigned int id, unsigned int pname, uint64_t *params);
    typedef void (*pmeQueryCounter)(unsigned int id, unsigned int target);
]])

local function buscar(nombre, tipo)
    local ok, puntero = pcall(function()
        return ffi.C.SDL_GL_GetProcAddress(nombre)
    end)
    if not ok then
        local sdl = ffi.load('SDL2-2.0.so.0')
        puntero = sdl.SDL_GL_GetProcAddress(nombre)
    end
    if puntero == nil then
        return nil
    end
    return ffi.cast(tipo, puntero)
end

function TiempoGpu.nuevo()
    local self = setmetatable({}, TiempoGpu)
    local ok = pcall(function()
        self.generar = buscar('glGenQueries', 'pmeGenQueries')
        self.empezar = buscar('glBeginQuery', 'pmeBeginQuery')
        self.terminar = buscar('glEndQuery', 'pmeEndQuery')
        self.estado = buscar('glGetQueryObjectiv', 'pmeGetQueryObjectiv')
        self.resultado = buscar('glGetQueryObjectui64v', 'pmeGetQueryObjectui64v')
            or buscar('glGetQueryObjectui64vEXT', 'pmeGetQueryObjectui64v')
    end)
    self.disponible = ok and self.generar and self.empezar and self.terminar and self.estado and self.resultado
    if not self.disponible then
        return self
    end
    self.consultas = ffi.new('unsigned int[?]', RONDA)
    self.generar(RONDA, self.consultas)
    self.usadas = {}
    self.actual = 0
    self.valor = ffi.new('uint64_t[1]')
    self.listo = ffi.new('int[1]')
    self.ultimoMs = nil
    return self
end

function TiempoGpu:inicio()
    if not self.disponible then
        return
    end
    self.actual = self.actual % RONDA + 1
    local k = self.actual
    -- Resultado pendiente de este hueco (de hace RONDA cuadros).
    if self.usadas[k] then
        self.estado(self.consultas[k - 1], GL_QUERY_RESULT_AVAILABLE, self.listo)
        if self.listo[0] ~= 0 then
            self.resultado(self.consultas[k - 1], GL_QUERY_RESULT, self.valor)
            self.ultimoMs = tonumber(self.valor[0]) / 1e6
        end
    end
    self.empezar(GL_TIME_ELAPSED, self.consultas[k - 1])
end

function TiempoGpu:fin()
    if not self.disponible then
        return
    end
    self.terminar(GL_TIME_ELAPSED)
    self.usadas[self.actual] = true
end

-- Marcas de tiempo (GL_TIMESTAMP) a lo largo del cuadro, para repartir lo
-- que tarda la tarjeta entre sus partes (sombras, escena, efectos...). Cada
-- `marca(nombre)` cierra el tramo que empezó en la marca anterior; `cuadro()`
-- empieza otro cuadro y lee el de hace RONDA cuadros. `tramos[nombre]` suma
-- los ms de cada tramo y `cuadros` cuántos cuadros se han leído.
local GL_TIMESTAMP = 0x8E28
local Marcas = {}
Marcas.__index = Marcas
TiempoGpu.Marcas = Marcas

function Marcas.nuevas()
    local self = setmetatable({}, Marcas)
    local ok = pcall(function()
        self.generar = buscar('glGenQueries', 'pmeGenQueries')
        self.contar = buscar('glQueryCounter', 'pmeQueryCounter')
        self.estado = buscar('glGetQueryObjectiv', 'pmeGetQueryObjectiv')
        self.resultado = buscar('glGetQueryObjectui64v', 'pmeGetQueryObjectui64v')
    end)
    self.disponible = ok and self.generar and self.contar and self.estado and self.resultado
    self.huecos = {}
    for k = 1, RONDA do
        self.huecos[k] = { nombres = {}, ids = {}, n = 0 }
    end
    self.actual = 0
    self.valor = ffi.new('uint64_t[1]')
    self.listo = ffi.new('int[1]')
    self.idNuevo = ffi.new('unsigned int[1]')
    self.tramos = {}
    self.orden = {}
    self.cuadros = 0
    return self
end

function Marcas:leer(h)
    if h.n < 2 then
        return
    end
    self.estado(h.ids[h.n], GL_QUERY_RESULT_AVAILABLE, self.listo)
    if self.listo[0] == 0 then
        return
    end
    local previo
    for k = 1, h.n do
        self.resultado(h.ids[k], GL_QUERY_RESULT, self.valor)
        local v = tonumber(self.valor[0])
        if previo then
            local nombre = h.nombres[k]
            if not self.tramos[nombre] then
                self.tramos[nombre] = 0
                self.orden[#self.orden + 1] = nombre
            end
            self.tramos[nombre] = self.tramos[nombre] + (v - previo) / 1e6
        end
        previo = v
    end
    self.cuadros = self.cuadros + 1
end

--- Empieza un cuadro (lee el resultado del hueco que se reutiliza).
function Marcas:cuadro()
    if not self.disponible then
        return
    end
    self.actual = self.actual % RONDA + 1
    local h = self.huecos[self.actual]
    if self.usado then
        self:leer(h)
    end
    h.n = 0
    self.usado = self.usado or self.actual == RONDA
    self:marca('inicio')
end

function Marcas:marca(nombre)
    if not self.disponible or self.actual == 0 then
        return
    end
    local h = self.huecos[self.actual]
    h.n = h.n + 1
    if not h.ids[h.n] then
        self.generar(1, self.idNuevo)
        h.ids[h.n] = self.idNuevo[0]
    end
    h.nombres[h.n] = nombre
    self.contar(h.ids[h.n], GL_TIMESTAMP)
end

return TiempoGpu
