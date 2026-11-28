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
local Recolector = require('batalla.recolector')

local MedirRobots = {}
MedirRobots.__index = MedirRobots
MedirRobots.espera = tonumber(os.getenv('BATALLA_ROBOTS_MEDIR_ESPERA') or '') or 8
-- BATALLA_ROBOTS_MEDIR_BASURA=<s>: además, durante <s> segundos (5 si no se
-- dice) con el recolector de Lua parado, cuánta memoria nueva crea cada parte
-- por cuadro: la basura que luego hay que recoger (los tirones). Líneas
-- `MEDIR_BASURA`.
MedirRobots.basura = os.getenv('BATALLA_ROBOTS_MEDIR_BASURA') and (tonumber(os.getenv('BATALLA_ROBOTS_MEDIR_BASURA')) or 5)

--- BATALLA_ROBOTS_MEDIR_PARTES=1: además, el tiempo de cada especialización
-- y evento (onUpdate de 'lanzador'…) en el cuadro de lógica más lento.
local function medirEspecializaciones(medidor)
    local Robot = require('robots.nucleo').Robot
    function Robot:llamar(evento, ...)
        for _, e in ipairs(self.especializaciones) do
            local f = e.tabla[evento]
            if f then
                self.actual = e.nombre
                local m0 = medidor.basuraActiva and collectgarbage('count')
                local t0 = love.timer.getTime()
                f(self, ...)
                local clave = e.nombre .. '.' .. evento
                medidor.porParte[clave] = (medidor.porParte[clave] or 0) + (love.timer.getTime() - t0) * 1000
                if m0 then
                    medidor.kbEspecializacion[clave] = (medidor.kbEspecializacion[clave] or 0) + collectgarbage('count') - m0
                end
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
        kbParte = {},
        kbTramo = {},
        kbEspecializacion = {},
    }, MedirRobots)
    if os.getenv('BATALLA_ROBOTS_MEDIR_PARTES') or MedirRobots.basura then
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
    -- La basura de cada tramo, de una marca a la siguiente.
    local marca = m.marca
    local medidor = self
    function m.marca(marcas, nombre)
        if medidor.basuraActiva then
            local ahora = collectgarbage('count')
            if medidor.kbUltimaMarca then
                medidor.kbTramo[nombre] = (medidor.kbTramo[nombre] or 0) + ahora - medidor.kbUltimaMarca
            end
            medidor.kbUltimaMarca = ahora
        end
        return marca(marcas, nombre)
    end
    local dream = require('lib.3DreamEngine')
    -- Las mallas que 3Dream crea al dibujarlas por primera vez (tangentes y
    -- vértices en Lua): cada una que tarde más de 5 ms, con su nombre
    -- (líneas `MEDIR_MALLA`).
    local crear = dream.classes.mesh.create
    local function crearMedido(malla, ...)
        local t0 = love.timer.getTime()
        crear(malla, ...)
        local ms = (love.timer.getTime() - t0) * 1000
        if ms > 5 then
            local material = malla.material
            print(string.format('MEDIR_MALLA %.0f ms creando %s, material %s (%d vértices) a los %.1f s', ms, tostring(malla.name),
                tostring(material and material.name), malla.vertices and malla.vertices:getSize() or 0, medidor.reloj))
        end
    end
    for _, meta in pairs(dream.meta) do
        if meta.__index.create == crear then
            meta.__index.create = crearMedido
        end
    end
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
    local m0 = self.basuraActiva and collectgarbage('count')
    local t0 = love.timer.getTime()
    f(...)
    self.actual[nombre] = self.actual[nombre] + (love.timer.getTime() - t0) * 1000
    if m0 then
        self.kbParte[nombre] = (self.kbParte[nombre] or 0) + collectgarbage('count') - m0
    end
end

--- Con el recolector parado `MedirRobots.basura` s tras la espera: la
-- memoria nueva de cada cuadro, y al acabar la imprime.
function MedirRobots:contarBasura()
    local ahora = collectgarbage('count')
    if self.basuraActiva then
        self.kbCuadros = self.kbCuadros + 1
        self.kbTotal = self.kbTotal + ahora - self.kbCuadro
        if self.reloj > self.basuraHasta then
            self.basuraActiva = false
            self:imprimirBasura()
            Recolector.parado = false
            collectgarbage('restart')
        end
    elseif not self.basuraHecha and self.reloj > MedirRobots.espera then
        self.basuraHecha = true
        self.basuraActiva = true
        self.basuraHasta = self.reloj + MedirRobots.basura
        self.kbTotal, self.kbCuadros = 0, 0
        Recolector.parado = true
        collectgarbage('stop')
    end
    self.kbCuadro = collectgarbage('count')
end

-- BATALLA_ROBOTS_MEDIR_CENSO=1: al acabar la espera, un censo de la memoria
-- viva de Lua (líneas `MEDIR_CENSO`): qué módulo la tiene y cuáles son las
-- tablas más grandes. El recolector de LuaJIT recorre cada tabla de una vez:
-- las de millones de entradas son parones.
MedirRobots.conCenso = os.getenv('BATALLA_ROBOTS_MEDIR_CENSO') ~= nil

local function referencia(v)
    local t = type(v)
    return t == 'table' or t == 'function' or t == 'userdata' or t == 'thread'
end

function MedirRobots:censo()
    local ffi = require('ffi')
    local t0 = love.timer.getTime()
    collectgarbage('collect')
    local total = collectgarbage('count')
    collectgarbage('stop')
    local visto = {}
    local porRaiz, raices = {}, {}
    local grandes = {}
    local porNombre = {}
    local pila, nombres = {}, {}
    local function recorrer(raiz, inicio)
        if not referencia(inicio) or visto[inicio] then
            return
        end
        visto[inicio] = true
        local cuenta = { entradas = 0, tablas = 0, cdata = 0, cadenas = 0 }
        local n = 1
        pila[1], nombres[1] = inicio, raiz
        local function empujar(v, nombre)
            if referencia(v) and not visto[v] then
                visto[v] = true
                n = n + 1
                pila[n], nombres[n] = v, nombre
            elseif type(v) == 'cdata' then
                cuenta.cdata = cuenta.cdata + (ffi.sizeof(v) or 0)
            end
        end
        while n > 0 do
            local o, nombre = pila[n], nombres[n]
            pila[n], nombres[n] = nil, nil
            n = n - 1
            local tipo = type(o)
            if tipo == 'table' then
                cuenta.tablas = cuenta.tablas + 1
                local entradas = 0
                for k, v in next, o do
                    entradas = entradas + 1
                    if type(k) == 'string' then
                        cuenta.cadenas = cuenta.cadenas + #k
                    end
                    if type(v) == 'string' then
                        cuenta.cadenas = cuenta.cadenas + #v
                    end
                    empujar(k, nombre)
                    empujar(v, type(k) == 'string' and k or nombre)
                end
                cuenta.entradas = cuenta.entradas + entradas
                local pn = porNombre[nombre]
                if not pn then
                    pn = { tablas = 0, entradas = 0 }
                    porNombre[nombre] = pn
                end
                pn.tablas, pn.entradas = pn.tablas + 1, pn.entradas + entradas
                if entradas >= 20000 then
                    grandes[#grandes + 1] = { entradas, raiz, nombre }
                end
                empujar(debug.getmetatable(o), nombre)
            elseif tipo == 'function' then
                local i = 1
                while true do
                    local nombreUp, v = debug.getupvalue(o, i)
                    if not nombreUp then
                        break
                    end
                    empujar(v, nombreUp)
                    i = i + 1
                end
                empujar(debug.getfenv(o), nombre)
            elseif tipo == 'userdata' then
                empujar(debug.getmetatable(o), nombre)
                empujar(debug.getfenv(o), nombre)
            end
        end
        porRaiz[raiz] = cuenta
        raices[#raices + 1] = raiz
    end
    -- Raíces: cada módulo cargado, cada global, cada función de `love` y el
    -- registro. Lo compartido cuenta para el primero que llega.
    local nombresModulos = {}
    for nombre in pairs(package.loaded) do
        if nombre ~= '_G' then
            nombresModulos[#nombresModulos + 1] = nombre
        end
    end
    table.sort(nombresModulos)
    for _, nombre in ipairs(nombresModulos) do
        recorrer(nombre, package.loaded[nombre])
    end
    for nombre, f in pairs(love) do
        if type(f) == 'function' then
            recorrer('love.' .. nombre, f)
        end
    end
    for nombre, v in pairs(_G) do
        recorrer('_G.' .. tostring(nombre), v)
    end
    recorrer('registro', debug.getregistry())
    table.sort(raices, function(a, b)
        return porRaiz[a].entradas > porRaiz[b].entradas
    end)
    local entradas = 0
    for _, raiz in ipairs(raices) do
        entradas = entradas + porRaiz[raiz].entradas
    end
    print(string.format('MEDIR_CENSO memoria Lua viva %.0f MB; %.1f millones de entradas en tablas; censo en %.1f s',
        total / 1024, entradas / 1e6, love.timer.getTime() - t0))
    for k = 1, math.min(30, #raices) do
        local c = porRaiz[raices[k]]
        print(string.format('MEDIR_CENSO raíz %-45s %9d entradas %8d tablas %7.1f MB cdata %6.1f MB texto',
            raices[k], c.entradas, c.tablas, c.cdata / 1048576, c.cadenas / 1048576))
    end
    -- Por el campo del que cuelgan (las de claves numéricas heredan el nombre
    -- de su lista): qué colecciones tienen las tablas.
    local claves = {}
    for nombre in pairs(porNombre) do
        claves[#claves + 1] = nombre
    end
    table.sort(claves, function(a, b)
        return porNombre[a].tablas > porNombre[b].tablas
    end)
    for k = 1, math.min(40, #claves) do
        local pn = porNombre[claves[k]]
        print(string.format('MEDIR_CENSO campo %-28s %8d tablas %9d entradas', tostring(claves[k]), pn.tablas, pn.entradas))
    end
    table.sort(grandes, function(a, b)
        return a[1] > b[1]
    end)
    for k = 1, math.min(30, #grandes) do
        local g = grandes[k]
        print(string.format('MEDIR_CENSO tabla de %9d entradas en %s (%s)', g[1], g[2], tostring(g[3])))
    end
    visto, pila, nombres = nil, nil, nil
    collectgarbage('restart')
end

-- BATALLA_ROBOTS_MEDIR_PILAS=<ms>: el perfilador por muestreo de LuaJIT
-- (jit.profile, una muestra cada 2 ms) y, en cada cuadro de más de
-- <ms> ms (150 si no se dice), las pilas de llamadas que más se repitieron en
-- él (líneas `MEDIR_PILAS`): qué se comió ese cuadro.
MedirRobots.pilas = os.getenv('BATALLA_ROBOTS_MEDIR_PILAS') and (tonumber(os.getenv('BATALLA_ROBOTS_MEDIR_PILAS')) or 150)

function MedirRobots:empezarPilas()
    local perfil = require('jit.profile')
    self.muestras, self.muestrasPrevio = {}, {}
    -- Delante de cada pila, lo que hacía la máquina de Lua (`G`: el recolector
    -- de basura; `N`, código compilado; `I`, interpretado; `C`, en C).
    perfil.start('fi2', function(hilo, cuantas, estado)
        local pila = '[' .. estado .. '] ' .. perfil.dumpstack(hilo, 'pl;', 12)
        self.muestras[pila] = (self.muestras[pila] or 0) + cuantas
    end)
end

function MedirRobots:imprimirPilas(dt)
    local muestras = self.muestrasPrevio
    local pilas = {}
    local total = 0
    for pila, n in pairs(muestras) do
        pilas[#pilas + 1] = pila
        total = total + n
    end
    table.sort(pilas, function(a, b)
        return muestras[a] > muestras[b]
    end)
    print(string.format('MEDIR_PILAS cuadro de %.0f ms a los %.1f s: %d muestras', dt * 1000, self.reloj, total))
    for k = 1, math.min(6, #pilas) do
        print(string.format('MEDIR_PILAS   %4d  %s', muestras[pilas[k]], pilas[k]))
    end
end

function MedirRobots:imprimirBasura()
    local n = math.max(1, self.kbCuadros)
    print(string.format('MEDIR_BASURA %d cuadros en %.0f s: %.0f KB por cuadro (%.0f MB/s); memoria Lua %.0f MB',
        n, MedirRobots.basura, self.kbTotal / n, self.kbTotal / 1024 / MedirRobots.basura, collectgarbage('count') / 1024))
    for _, grupo in ipairs({ { 'parte', self.kbParte }, { 'tramo', self.kbTramo }, { 'especialización', self.kbEspecializacion } }) do
        local claves = {}
        for clave in pairs(grupo[2]) do
            claves[#claves + 1] = clave
        end
        table.sort(claves, function(a, b)
            return grupo[2][a] > grupo[2][b]
        end)
        for _, clave in ipairs(claves) do
            print(string.format('MEDIR_BASURA %s %s: %.1f KB por cuadro', grupo[1], clave, grupo[2][clave] / n))
        end
    end
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
    if MedirRobots.basura then
        self:contarBasura()
    end
    if MedirRobots.pilas then
        if not self.muestras then
            self:empezarPilas()
        elseif dt * 1000 > MedirRobots.pilas then
            self:imprimirPilas(dt)
        end
        -- `dt` es lo que duró el cuadro anterior: sus muestras, en `muestrasPrevio`.
        self.muestrasPrevio, self.muestras = self.muestras, {}
    end
    if MedirRobots.conCenso and not self.censoHecho and self.reloj > MedirRobots.espera then
        self.censoHecho = true
        self:censo()
    end
    if self.reloj > MedirRobots.espera then
        self.cuadros[#self.cuadros + 1] = dt * 1000
        if dt > 0.2 then
            -- Qué se comió ese cuadro y si el recolector de Lua limpió en él.
            -- `dt` es lo que duró el cuadro anterior (de su comienzo al de
            -- este): lo suyo está en `previo`.
            local a = self.previo or self.actual
            print(string.format('MEDIR_ROBOTS tirón de %.0f ms a los %.1f s (lógica %.1f, mallas %.1f, capa %.1f, vegetación %.1f ms; memoria Lua %.0f MB, %+.1f MB en ese cuadro)',
                dt * 1000, self.reloj, a.logica, a.mallas, a.capa, a.vegetacion, collectgarbage('count') / 1024, (self.previoMemoria or 0) / 1024))
        end
        for nombre, lista in pairs(self.partes) do
            lista[#lista + 1] = self.actual[nombre]
        end
    end
    local memoria = collectgarbage('count')
    self.previoMemoria = memoria - (self.memoriaAnterior or memoria)
    self.memoriaAnterior = memoria
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
    self.previo = self.previo or {}
    for nombre, valor in pairs(self.actual) do
        self.previo[nombre] = valor
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
    local memoria = collectgarbage('count')
    collectgarbage('collect')
    print(string.format('MEDIR_ROBOTS memoria Lua %.0f MB; viva %.0f MB (tras recoger toda la basura)', memoria / 1024,
        collectgarbage('count') / 1024))
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
