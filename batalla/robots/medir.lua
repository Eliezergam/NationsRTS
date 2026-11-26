--- Medición del rendimiento de la batalla de robots.
--
--   BATALLA_ROBOTS_MEDIR=<segundos> love . 42 --captura 999999 nada.png 0 0 0.3 1 --batalla preparacion 999999
--
-- Espera `espera` segundos a que todo cargue y mide `segundos`: el tiempo de
-- cada cuadro (love.timer.getDelta) y, dentro, cuánto se va en la lógica de
-- los robots (RobotsBatalla.actualizar), en mandar sus mallas a dibujar
-- (RobotsBatalla.dibujar), en su capa 2D (VistaRobots.dibujar), en preparar
-- la vegetación (VegetacionDream:actualizar, en Lua) y el tiempo de la
-- tarjeta gráfica por cuadro (consultas de OpenGL, tiempo_gpu.lua). Al acabar
-- imprime el resumen (líneas `MEDIR_ROBOTS`) y cierra el juego.
local MedirRobots = {}
MedirRobots.__index = MedirRobots
MedirRobots.espera = tonumber(os.getenv('BATALLA_ROBOTS_MEDIR_ESPERA') or '') or 8

--- BATALLA_ROBOTS_MEDIR_PARTES=1: además, el tiempo de cada especialización
-- y evento (onUpdate de 'lanzador'…) en el cuadro de lógica más lento.
local function medirEspecializaciones(medidor)
    local Robot = require('robots.nucleo').Robot
    function Robot:llamar(evento, ...)
        for _, e in ipairs(self.especializaciones) do
            local f = e.tabla[evento]
            if f then
                self.actual = e.nombre
                local t0 = love.timer.getTime()
                f(self, ...)
                local clave = e.nombre .. '.' .. evento
                medidor.porParte[clave] = (medidor.porParte[clave] or 0) + (love.timer.getTime() - t0) * 1000
            end
        end
        self.actual = nil
    end
end

function MedirRobots.nuevo(segundos)
    local medidor = setmetatable({
        segundos = segundos,
        reloj = 0,
        cuadros = {},
        partes = { logica = {}, mallas = {}, capa = {}, vegetacion = {}, gpu = {} },
        actual = { logica = 0, mallas = 0, capa = 0, vegetacion = 0, gpu = 0 },
        porParte = {},
        peorLogica = 0,
        total = {},
    }, MedirRobots)
    if os.getenv('BATALLA_ROBOTS_MEDIR_PARTES') then
        medirEspecializaciones(medidor)
    end
    return medidor
end

--- Marcas de tiempo de la tarjeta en las partes de 3Dream (sin tocar la
-- librería: se envuelven sus métodos). Cada tramo lleva el nombre de lo que
-- acaba de terminar.
function MedirRobots:prepararMarcas()
    local TiempoGpu = require('batalla.dream.estilo.tiempo_gpu')
    local m = TiempoGpu.Marcas.nuevas()
    self.marcas = m
    local dream = require('lib.3DreamEngine')
    local ejecutar = dream.executeJobs
    function dream.executeJobs(lib, ...)
        m:marca('juego antes de 3Dream')
        for nombre, trabajo in pairs(lib.jobs) do
            if not trabajo.medido then
                trabajo.medido = true
                local original = trabajo.execute
                function trabajo.execute(...)
                    original(...)
                    m:marca('trabajo ' .. nombre)
                end
            end
        end
        return ejecutar(lib, ...)
    end
    local render = dream.render
    function dream.render(lib, cam, canvases, dynamic, isShadow, ...)
        if isShadow then
            return render(lib, cam, canvases, dynamic, isShadow, ...)
        end
        m:marca('otros trabajos')
        render(lib, cam, canvases, dynamic, isShadow, ...)
        m:marca('escena (geometría)')
    end
    local completo = dream.renderFull
    function dream.renderFull(lib, ...)
        completo(lib, ...)
        m:marca('oclusión, bloom y final')
    end
end

--- Suma a la parte `nombre` del cuadro lo que tarda `f(...)`.
function MedirRobots:medir(nombre, f, ...)
    local t0 = love.timer.getTime()
    f(...)
    self.actual[nombre] = self.actual[nombre] + (love.timer.getTime() - t0) * 1000
end

local function resumen(lista)
    local orden = {}
    local suma = 0
    for k, v in ipairs(lista) do
        orden[k] = v
        suma = suma + v
    end
    table.sort(orden)
    local n = #orden
    if n == 0 then
        return 0, 0, 0
    end
    local cuantos = math.max(1, math.floor(n / 100))
    local sumaPeor = 0
    for k = n - cuantos + 1, n do
        sumaPeor = sumaPeor + orden[k]
    end
    return suma / n, sumaPeor / cuantos, orden[n]
end

--- Al final de cada cuadro (main.lua, después de dibujar).
function MedirRobots:cuadro(escena)
    local dt = love.timer.getDelta()
    self.reloj = self.reloj + dt
    -- La tarjeta: de un final de cuadro al siguiente (resultado de hace unos
    -- cuadros). Las consultas se crean aquí, con la ventana ya abierta: el
    -- juego la rehace al arrancar y las de antes quedan inválidas.
    if not self.marcas then
        self:prepararMarcas()
    end
    local m = self.marcas
    m:marca('después de 3Dream (interfaz, marcas, 2D)')
    local antes = m.cuadros
    local suma = 0
    for _, ms in pairs(m.tramos) do
        suma = suma + ms
    end
    m:cuadro()
    if m.cuadros > antes then
        local nueva = 0
        for _, ms in pairs(m.tramos) do
            nueva = nueva + ms
        end
        self.actual.gpu = nueva - suma
    end
    if self.reloj > MedirRobots.espera then
        self.cuadros[#self.cuadros + 1] = dt * 1000
        if dt > 0.2 then
            print(string.format('MEDIR_ROBOTS tirón de %.0f ms a los %.1f s (lógica %.1f ms, memoria Lua %.0f MB)', dt * 1000, self.reloj, self.actual.logica, collectgarbage('count') / 1024))
        end
        for nombre, lista in pairs(self.partes) do
            lista[#lista + 1] = self.actual[nombre]
        end
    end
    if self.reloj > MedirRobots.espera then
        for clave, ms in pairs(self.porParte) do
            self.total[clave] = (self.total[clave] or 0) + ms
        end
        if self.actual.logica > self.peorLogica then
            self.peorLogica = self.actual.logica
            self.peorPartes = self.porParte
        end
    end
    self.porParte = {}
    for nombre in pairs(self.actual) do
        self.actual[nombre] = 0
    end
    if self.reloj < MedirRobots.espera + self.segundos then
        return
    end
    local robots = escena.robotsAsalto or {}
    local media, peor, maximo = resumen(self.cuadros)
    local orden = {}
    local lentos = 0
    for k, v in ipairs(self.cuadros) do
        orden[k] = v
        if v > 50 then
            lentos = lentos + 1
        end
    end
    table.sort(orden)
    local mediana = orden[math.max(1, math.floor(#orden / 2))] or 0
    print(string.format('MEDIR_ROBOTS cuadro mediano %.2f ms (%.0f FPS); %d cuadros de más de 50 ms', mediana, 1000 / math.max(mediana, 0.01), lentos))
    print(string.format('MEDIR_ROBOTS robots %d, %d cuadros en %.0f s', #robots, #self.cuadros, self.segundos))
    print(string.format('MEDIR_ROBOTS cuadro: media %.2f ms (%.0f FPS), 1%% peor %.2f ms (%.0f FPS), máx %.2f ms', media, 1000 / media, peor, 1000 / peor, maximo))
    for _, nombre in ipairs({ 'logica', 'mallas', 'capa', 'vegetacion', 'gpu' }) do
        local m, p, x = resumen(self.partes[nombre])
        print(string.format('MEDIR_ROBOTS %s: media %.2f ms, 1%% peor %.2f ms, máx %.2f ms', nombre, m, p, x))
    end
    local marcas = self.marcas
    if marcas and marcas.cuadros > 0 then
        for _, nombre in ipairs(marcas.orden) do
            print(string.format('MEDIR_ROBOTS tarjeta · %s: %.2f ms por cuadro', nombre, marcas.tramos[nombre] / marcas.cuadros))
        end
    end
    if self.peorPartes then
        local claves = {}
        for clave in pairs(self.total) do
            claves[#claves + 1] = clave
        end
        table.sort(claves, function(a, b)
            return self.total[a] > self.total[b]
        end)
        for _, clave in ipairs(claves) do
            print(string.format('MEDIR_ROBOTS parte %s: media %.2f ms por cuadro; en el peor cuadro de lógica (%.1f ms) %.1f ms', clave, self.total[clave] / #self.cuadros, self.peorLogica, self.peorPartes[clave] or 0))
        end
    end
    local stats = love.graphics.getStats()
    print(string.format('MEDIR_ROBOTS GPU: %d llamadas de dibujo, %.0f MB de texturas', stats.drawcalls, stats.texturememory / 1048576))
    print(string.format('MEDIR_ROBOTS memoria Lua %.0f MB', collectgarbage('count') / 1024))
    local niveles = { [0] = 0, 0, 0 }
    for _, r in ipairs(robots) do
        niveles[r.nivel or 0] = niveles[r.nivel or 0] + 1
    end
    print(string.format('MEDIR_ROBOTS copias en el último cuadro: %d de cerca, %d medias, %d lejanas', niveles[0], niveles[1], niveles[2]))
    -- BATALLA_ROBOTS_MOVILES=1: apunta qué piezas movió u ocultó alguna
    -- especialización (<modelo>_moviles.lua), para unir las demás a su
    -- madre en las copias de lejos (tools/blender/robot_soldado.py).
    if os.getenv('BATALLA_ROBOTS_MOVILES') then
        local porModelo = {}
        for _, r in ipairs(robots) do
            local lista = porModelo[r.nombreModelo] or {}
            porModelo[r.nombreModelo] = lista
            for _, p in ipairs(r.orden) do
                if p.movil then
                    lista[p.nombre] = true
                end
            end
        end
        for modelo, lista in pairs(porModelo) do
            local nombres = {}
            for nombre in pairs(lista) do
                nombres[#nombres + 1] = nombre
            end
            table.sort(nombres)
            local ruta = love.filesystem.getSource() .. '/' .. modelo .. '_moviles.lua'
            local f = assert(io.open(ruta, 'w'))
            f:write('-- Piezas que mueve u oculta alguna especialización (batalla/robots/medir.lua\n')
            f:write('-- con BATALLA_ROBOTS_MOVILES=1). Las demás van unidas a su madre en las\n')
            f:write('-- copias de lejos (<modelo>_lod1/2.glb).\nreturn {\n')
            for _, nombre in ipairs(nombres) do
                f:write(string.format("    '%s',\n", nombre))
            end
            f:write('}\n')
            f:close()
            print('MEDIR_ROBOTS móviles', ruta, #nombres)
        end
    end
    love.event.quit()
end

return MedirRobots
