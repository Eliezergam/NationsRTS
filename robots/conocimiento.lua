-- Memoria aprendida de un robot (el dueño, 18-nov: «un sistema de .md o JSON
-- para que guarde información y, según lo que necesite saber, busque en esa
-- rama; como una memoria que va creando según aprende, incluso para
-- moverse»). Cada robot la suya.
--
-- Vive en la carpeta de guardado del juego (love.filesystem):
--   memoria_robots/<robot>/yo.json                 lo que sabe de sí mismo
--   memoria_robots/<robot>/enemigos/<tipo>.json    de cada tipo de enemigo
--   memoria_robots/<robot>/mundo/<mapa>.json       de cada mapa (para moverse)
--   memoria_robots/<robot>/experiencias.json       episodios sueltos
--   memoria_robots/<robot>/resumen.md              para leerlo una persona
--
-- Cada rama es un archivo y solo se lee cuando hace falta (la primera vez
-- que se pide); se escribe lo que cambió, cada `guardarCada` s como mucho.
-- Nunca en cada cuadro.
--
--   local saber = Conocimiento.abrir('ROJO')
--   local yo = saber:rama('yo')          -- tabla (vacía si es nueva)
--   yo.batallas = (yo.batallas or 0) + 1
--   saber:cambio('yo')
--   saber:episodio({ que = 'vio', ... })
--   saber:actualizar(dt)                 -- guarda lo pendiente de vez en cuando

local json = require('lib.3DreamEngine.libs.json')

local Conocimiento = {}
Conocimiento.__index = Conocimiento

Conocimiento.carpeta = 'memoria_robots'
Conocimiento.guardarCada = 10 -- s
Conocimiento.maxEpisodios = 300
Conocimiento.abiertas = setmetatable({}, { __mode = 'v' })

local function carpetaDe(ruta)
    return ruta:match('^(.*)/[^/]+$')
end

function Conocimiento.abrir(id)
    local self = setmetatable({}, Conocimiento)
    self.id = tostring(id):gsub('[^%w_%-]', '_')
    self.base = Conocimiento.carpeta .. '/' .. self.id
    self.ramas = {}
    self.pendientes = {}
    self.reloj = 0
    self.leidas = {} -- las ramas consultadas (para el panel)
    love.filesystem.createDirectory(self.base)
    Conocimiento.abiertas[#Conocimiento.abiertas + 1] = self
    return self
end

--- Guarda lo pendiente de todas las memorias abiertas (al salir del juego).
function Conocimiento.guardarTodas()
    for _, c in pairs(Conocimiento.abiertas) do
        c:guardar()
    end
end

--- La rama `ruta` ('yo', 'mundo/semilla42_...', 'enemigos/soldado'): la lee
-- del disco la primera vez; luego, la misma tabla.
function Conocimiento:rama(ruta)
    local t = self.ramas[ruta]
    if t then
        return t
    end
    local archivo = self.base .. '/' .. ruta .. '.json'
    local texto = love.filesystem.getInfo(archivo) and love.filesystem.read(archivo)
    if texto then
        local ok, datos = pcall(json.decode, texto)
        t = ok and type(datos) == 'table' and datos or {}
        print(string.format('MEMORIA %s lee la rama %s', self.id, ruta))
    else
        t = {}
    end
    self.ramas[ruta] = t
    self.leidas[#self.leidas + 1] = ruta
    return t
end

--- La rama cambió: se guardará.
function Conocimiento:cambio(ruta)
    self.pendientes[ruta] = true
end

--- Un episodio (lo que pasó, con su batalla y su momento).
function Conocimiento:episodio(e)
    local lista = self:rama('experiencias')
    lista.episodios = lista.episodios or {}
    table.insert(lista.episodios, e)
    while #lista.episodios > Conocimiento.maxEpisodios do
        table.remove(lista.episodios, 1)
    end
    self:cambio('experiencias')
end

function Conocimiento:guardar()
    local escritas = 0
    for ruta in pairs(self.pendientes) do
        local archivo = self.base .. '/' .. ruta .. '.json'
        local carpeta = carpetaDe(archivo)
        if carpeta then
            love.filesystem.createDirectory(carpeta)
        end
        love.filesystem.write(archivo, json.encode(self.ramas[ruta]))
        escritas = escritas + 1
    end
    if escritas > 0 then
        self.pendientes = {}
        love.filesystem.write(self.base .. '/resumen.md', self:resumen())
    end
end

function Conocimiento:actualizar(dt)
    self.reloj = self.reloj + dt
    if self.reloj >= Conocimiento.guardarCada then
        self.reloj = 0
        self:guardar()
    end
end

--- Lo que sabe, en texto (resumen.md): las ramas cargadas.
function Conocimiento:resumen()
    local l = { '# Memoria de ' .. self.id, '' }
    local nombres = {}
    for ruta in pairs(self.ramas) do
        if ruta ~= 'experiencias' then
            nombres[#nombres + 1] = ruta
        end
    end
    table.sort(nombres)
    for _, ruta in ipairs(nombres) do
        l[#l + 1] = '## ' .. ruta
        local claves = {}
        for k in pairs(self.ramas[ruta]) do
            claves[#claves + 1] = k
        end
        table.sort(claves)
        for _, k in ipairs(claves) do
            local v = self.ramas[ruta][k]
            if type(v) == 'table' then
                local n = 0
                for _ in pairs(v) do
                    n = n + 1
                end
                l[#l + 1] = string.format('- %s: %d entradas', k, n)
            else
                l[#l + 1] = string.format('- %s: %s', k, tostring(v))
            end
        end
        l[#l + 1] = ''
    end
    local ep = self.ramas.experiencias and self.ramas.experiencias.episodios or {}
    l[#l + 1] = '## experiencias (últimas)'
    for k = math.max(1, #ep - 9), #ep do
        local e = ep[k]
        l[#l + 1] = string.format('- batalla %s, %.0f s: %s %s a %.0f m', tostring(e.batalla), e.t or 0, e.que or '?', e.tipo or '', e.distancia or 0)
    end
    return table.concat(l, '\n') .. '\n'
end

return Conocimiento
