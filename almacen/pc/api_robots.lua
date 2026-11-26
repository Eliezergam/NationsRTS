-- La API `robots` que ven los programas de Lua de los ordenadores de la sala
-- (y el programa Robots): mandar a los robots del almacén por su nombre corto
-- ('almacen', 'soldado'), como el `rednet` de CC: Tweaked manda a las
-- tortugas.
--
--   robots.lista()                    { 'almacen', 'soldado' }
--   robots.estado(nombre)             modo ('trabajo' | 'guion' | 'parado'),
--                                     tarea (texto), guion (nombre o nil)
--   robots.posicion(nombre)           x, y, rumbo en grados
--   robots.trabajar(nombre)           ejecuta lo de siempre (trabajar.lua...)
--   robots.parar(nombre)              se queda quieto esperando órdenes
--   robots.ejecutar(nombre, archivo)  le ejecuta un guion (un .lua de
--                                     ~/guiones o de /red/almacen/guiones):
--                                     deja lo que ejecutaba y pasa a ese.
--                                     Devuelve true o false y el error
--   robots.salida(nombre)             lo último que ha escrito su guion
--
-- Un guion es una especialización (onLoad, onUpdate, self = el robot) que
-- sustituye a su trabajo: almacen/robots/especializaciones/guion.lua.

local Archivos = require('almacen.pc.archivos')

local ApiRobots = {}

--- Los robots que obedecen órdenes, en orden: { { nombre, robot }, ... }.
function ApiRobots.robots()
    local Guion = require('almacen.robots.especializaciones.guion')
    local lista = {}
    for _, r in ipairs(GestorRobots and GestorRobots.getRobots() or {}) do
        -- Solo los que tienen la especialización de guiones.
        if r.datos.guion then
            lista[#lista + 1] = { nombre = Guion.nombres[r.tipo] or tostring(r.tipo), titulo = Guion.titulos[r.tipo] or tostring(r.tipo), robot = r }
        end
    end
    table.sort(lista, function(a, b)
        return a.nombre < b.nombre
    end)
    return lista
end

function ApiRobots.buscar(nombre)
    for _, e in ipairs(ApiRobots.robots()) do
        if e.nombre == nombre then
            return e.robot
        end
    end
end

--- Manda el archivo `ruta` del ordenador como guion al robot `nombre`.
function ApiRobots.ejecutar(ordenador, nombre, ruta)
    local r = ApiRobots.buscar(nombre)
    if not r then
        return false, 'no hay ningún robot «' .. tostring(nombre) .. '»'
    end
    local nodo = ordenador.archivos:buscar(ruta)
    if not nodo or nodo.carpeta or nodo.tipo ~= 'texto' then
        return false, 'no existe el guion ' .. tostring(ruta)
    end
    -- Uno del juego (/red/almacen/guiones).
    if nodo.ejecutable then
        return r:setEjecutable(nodo.ejecutable)
    end
    local codigo = table.concat(ordenador.archivos:leer(ruta) or {}, '\n')
    return r:setGuion(codigo, ruta:match('[^/]+$'))
end

--- La tabla `robots` para un programa del ordenador `ordenador`; las rutas
-- relativas van desde `carpeta` (la de la terminal).
function ApiRobots.para(ordenador, carpeta)
    local api = {}
    local function robot(nombre)
        local r = ApiRobots.buscar(nombre)
        if not r then
            error('no hay ningún robot «' .. tostring(nombre) .. '» (mira robots.lista())', 3)
        end
        return r
    end
    function api.lista()
        local t = {}
        for k, e in ipairs(ApiRobots.robots()) do
            t[k] = e.nombre
        end
        return t
    end
    function api.estado(nombre)
        local r = robot(nombre)
        return r:getModo(), r.getTarea and r:getTarea() or '', r:getGuion()
    end
    function api.posicion(nombre)
        local r = robot(nombre)
        return math.floor(r.x * 100 + 0.5) / 100, math.floor(r.y * 100 + 0.5) / 100, math.floor(math.deg(r.rumbo) * 10 + 0.5) / 10
    end
    function api.trabajar(nombre)
        robot(nombre):setOrden('trabajar')
    end
    function api.parar(nombre)
        robot(nombre):setOrden('parar')
    end
    function api.ejecutar(nombre, archivo)
        robot(nombre)
        return ApiRobots.ejecutar(ordenador, nombre, Archivos.resolver(carpeta or '/home/operador', tostring(archivo)))
    end
    function api.salida(nombre)
        local t = {}
        for k, l in ipairs(robot(nombre):getSalida()) do
            t[k] = l
        end
        return t
    end
    return api
end

return ApiRobots
