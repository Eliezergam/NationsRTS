-- Física de verdad para los robots (el dueño, 18-nov: «para que aprenda a
-- moverse tiene que tener toda la física»): Jolt Physics 5.6.0, el motor de
-- Horizon Forbidden West, desde LuaJIT (lib/jolt/libjoltc.so, tools/jolt/).
--
-- El mundo físico de la batalla (`Fisica.batalla`), uno solo:
--   * el terreno, con los mismos triángulos que se dibujan (batalla/rejilla.lua);
--   * un cuerpo fijo por cada colisión declarada (batalla/colisiones.lua:
--     árboles, rocas, edificios, muro... con sus etiquetas), que se quita
--     cuando la colisión se quita (un árbol que cae);
--   * lo que se mueve: cuerpos con masa (cajas, cilindros, cápsulas) que el
--     robot irá usando como piezas de su cuerpo.
-- Los sensores y los ojos de los robots lanzan rayos aquí (`Fisica:rayo`):
-- lo que toca devuelve su distancia, el punto y las etiquetas de su colisión.
--
-- Coordenadas: las de los robots (m, x este, y norte, z arriba), con el
-- origen en el centro del mundo físico para no perder precisión. Jolt va
-- con y arriba: (X, Y, Z) de Jolt = (x - ox, z, -(y - oy)).
-- Paso fijo de 1/60 s (determinista).

local ffi = require('ffi')
-- Fuera del juego (pruebas con luajit: tools/jolt/prueba_*.lua) no hay
-- terreno: el mundo se crea con `plano = true`.
local Mundo = love and require('batalla.robots.mundo')

local Fisica = {}
Fisica.__index = Fisica

Fisica.paso = 1 / 60
Fisica.pasoTerreno = 2 -- m entre vértices de la malla del terreno
Fisica.maxCuerpos = 65536

local J

--- Carga la biblioteca y registra los tipos de Jolt (una vez).
local function cargar()
    if J then
        return J
    end
    local ruta
    if love then
        ffi.cdef(love.filesystem.load('lib/jolt/joltc_cdef.lua')())
        ruta = love.filesystem.getSource() .. '/lib/jolt/libjoltc.so'
    else
        ffi.cdef(dofile('lib/jolt/joltc_cdef.lua'))
        ruta = './lib/jolt/libjoltc.so'
    end
    J = ffi.load(ruta)
    J.JPC_RegisterDefaultAllocator()
    J.JPC_FactoryInit()
    J.JPC_RegisterTypes()
    return J
end

local err = nil

local function crearForma(settings, crear)
    err = err or ffi.new('JPC_String*[1]')
    local forma = ffi.new('JPC_Shape*[1]')
    if not crear(settings, forma, err) then
        error('Jolt: ' .. ffi.string(J.JPC_String_c_str(err[0])))
    end
    return forma[0]
end

--- Mundo vacío con su origen en (cx, cy) m.
function Fisica.crear(cx, cy)
    cargar()
    local self = setmetatable({}, Fisica)
    self.ox, self.oy = cx, cy
    self.temp = J.JPC_TempAllocatorImpl_new(32 * 1024 * 1024)
    self.trabajos = ffi.cast('JPC_JobSystem*', J.JPC_JobSystemThreadPool_new2(2048, 8))
    self.sistema = J.JPC_PhysicsSystem_new()
    J.JPC_PhysicsSystem_Init(self.sistema, Fisica.maxCuerpos, 0, 8192, 8192, J.NJ_CapasAmplias(), J.NJ_FiltroObjetoAmplia(), J.NJ_FiltroObjetos())
    self.cuerpos = J.JPC_PhysicsSystem_GetBodyInterface(self.sistema)
    self.consultas = J.JPC_PhysicsSystem_GetNarrowPhaseQuery(self.sistema)
    self.acumulado = 0
    self.lista = {} -- los cuerpos que se mueven: { id, forma, medidas }
    self.colisionDe = {} -- id de cuerpo -> colisión (batalla/colisiones.lua)
    self.cuerpoDe = {} -- colisión -> id de cuerpo
    return self
end

--- Pruebas sin el juego (tools/jolt/prueba_*.lua): suelo plano a z = 0.
function Fisica.nuevo(cx, cy, radio)
    local self = Fisica.crear(cx, cy)
    self.radio = radio
    self.plano = true
    self:crearPlano()
    J.JPC_PhysicsSystem_OptimizeBroadPhase(self.sistema)
    return self
end

--- El mundo físico de la batalla de `suelo`: su terreno y todas sus
-- colisiones (Suelo:getColisiones), siguiendo las que se pongan o quiten.
function Fisica.batalla(suelo)
    local inicio = love.timer.getTime()
    local self = Fisica.crear(suelo.cx / 10, -suelo.cy / 10)
    self:crearTerrenoRejilla(suelo.relieve)
    local colisiones = suelo:getColisiones()
    for _, c in ipairs(colisiones.lista) do
        if not c.quitada then
            self:ponerColision(c)
        end
    end
    colisiones:escuchar(function(suceso, c)
        if suceso == 'puesta' then
            self:ponerColision(c)
        else
            self:quitarColision(c)
        end
    end)
    J.JPC_PhysicsSystem_OptimizeBroadPhase(self.sistema)
    print(string.format('FISICA mundo de la batalla: %d triángulos de terreno y %d colisiones en %.2f s',
        self.triangulosTerreno, #colisiones.lista, love.timer.getTime() - inicio))
    if os.getenv('FISICA_DEPURAR') then
        self:comprobar(suelo, colisiones)
    end
    return self
end

--- Comprobación con números (`FISICA_DEPURAR=1`): un rayo a 10 m de una caja
-- y de un cilindro (a media altura, hacia su centro) y otro hacia el suelo
-- desde 5 m: las distancias tienen que salir 10, 10 y 5.
function Fisica:comprobar(suelo, colisiones)
    local vistas = {}
    for _, c in ipairs(colisiones.lista) do
        local f = c.forma
        if not vistas[f.tipo] then
            vistas[f.tipo] = true
            local ux, uy = 1, 0
            local r = f.r
            if f.tipo == 'caja' then
                ux, uy = math.cos(f.rumbo), math.sin(f.rumbo)
                r = f.hx
            end
            local x, y, z = f.x + ux * (r + 10), f.y + uy * (r + 10), (f.z0 + f.z1) / 2
            local d, col = self:rayo(x, y, z, -ux, -uy, 0, 30)
            print(string.format('FISICA rayo a una %s: %s m (esperado 10), toca %s', f.tipo, d and string.format('%.2f', d) or 'nada',
                col == c and 'esa colisión' or 'OTRA cosa'))
        end
    end
    local x, y = self.ox + 37, self.oy - 21
    local h = suelo:altura(x * 10, -y * 10) / 10
    local d, col = self:rayo(x, y, h + 5, 0, 0, -1, 20)
    print(string.format('FISICA rayo al suelo: %s m (esperado 5), toca %s', d and string.format('%.2f', d) or 'nada',
        col and col.etiquetas.suelo and 'el suelo' or 'OTRA cosa'))
end

--- De los robots a Jolt y vuelta.
function Fisica:aJolt(x, y, z)
    return x - self.ox, z, -(y - self.oy)
end

function Fisica:deJolt(X, Y, Z)
    return X + self.ox, -Z + self.oy, Y
end

local function anadir(self, settings, activar)
    local cuerpo = J.JPC_BodyInterface_CreateBody(self.cuerpos, settings)
    local id = J.JPC_Body_GetID(cuerpo)
    J.JPC_BodyInterface_AddBody(self.cuerpos, id, activar and J.JPC_ACTIVATION_ACTIVATE or J.JPC_ACTIVATION_DONT_ACTIVATE)
    return id, cuerpo
end
Fisica.anadir = anadir

--- El terreno con los triángulos de la rejilla que se dibuja (la misma
-- partición en tablero de batalla/rejilla.lua): lo que el robot pisa y lo que
-- ve es exactamente lo que hay en pantalla.
function Fisica:crearTerrenoRejilla(rej)
    local lado = rej.lado
    local filas = rej.total / lado
    local vertices = ffi.new('JPC_Float3[?]', rej.total)
    for k = 0, rej.total - 1 do
        local X, Y, Z = self:aJolt(rej.x[k] / 10, -rej.y[k] / 10, rej.h[k] / 10)
        vertices[k].x, vertices[k].y, vertices[k].z = X, Y, Z
    end
    local triangulos = ffi.new('JPC_IndexedTriangle[?]', (lado - 1) * (filas - 1) * 2)
    local t = 0
    -- Cara hacia arriba (Jolt no choca por detrás): se da la vuelta al
    -- triángulo cuya normal sale hacia abajo.
    local function tri(a, b, c)
        local ax, az = vertices[a].x, vertices[a].z
        local ux, uz = vertices[b].x - ax, vertices[b].z - az
        local vx, vz = vertices[c].x - ax, vertices[c].z - az
        -- Componente Y (arriba) de u × v.
        if uz * vx - ux * vz < 0 then
            b, c = c, b
        end
        triangulos[t].idx[0], triangulos[t].idx[1], triangulos[t].idx[2] = a, b, c
        t = t + 1
    end
    for j = 0, filas - 2 do
        for i = 0, lado - 2 do
            local a, c = j * lado + i, (j + 1) * lado + i
            if (i + j) % 2 == 0 then
                tri(a, a + 1, c + 1)
                tri(a, c + 1, c)
            else
                tri(a, a + 1, c)
                tri(a + 1, c + 1, c)
            end
        end
    end
    local ms = ffi.new('JPC_MeshShapeSettings')
    J.JPC_MeshShapeSettings_default(ms)
    ms.TriangleVertices, ms.TriangleVerticesLen = vertices, rej.total
    ms.IndexedTriangles, ms.IndexedTrianglesLen = triangulos, t
    local bs = ffi.new('JPC_BodyCreationSettings')
    J.JPC_BodyCreationSettings_default(bs)
    bs.MotionType = J.JPC_MOTION_TYPE_STATIC
    bs.ObjectLayer = 0
    bs.Shape = crearForma(ms, J.JPC_MeshShapeSettings_Create)
    bs.Friction = 0.8
    self.terreno = anadir(self, bs, false)
    self.triangulosTerreno = t
    self.colisionDe[self.terreno] = Fisica.colisionSuelo
end

-- El terreno, para quien lo toque con un rayo.
Fisica.colisionSuelo = { etiquetas = { suelo = true, solido = true, cobertura = true } }

--- Cuerpo fijo para una colisión (forma en metros, ejes de los robots).
function Fisica:ponerColision(c)
    local f = c.forma
    local bs = ffi.new('JPC_BodyCreationSettings')
    J.JPC_BodyCreationSettings_default(bs)
    local alto = (f.z1 - f.z0) / 2
    if f.tipo == 'cilindro' then
        local cs = ffi.new('JPC_CylinderShapeSettings')
        J.JPC_CylinderShapeSettings_default(cs)
        cs.HalfHeight = alto
        cs.Radius = f.r
        cs.ConvexRadius = math.min(0.05, f.r * 0.5)
        bs.Shape = crearForma(cs, J.JPC_CylinderShapeSettings_Create)
    else
        local s = ffi.new('JPC_BoxShapeSettings')
        J.JPC_BoxShapeSettings_default(s)
        -- Paneles finos (chapas del almacén): medio grosor mínimo de 1 mm y
        -- el redondeo de las aristas, nunca mayor que la mitad del lado.
        local hx, hy, hz = math.max(f.hx, 0.001), math.max(alto, 0.001), math.max(f.hy, 0.001)
        s.HalfExtent.x, s.HalfExtent.y, s.HalfExtent.z = hx, hy, hz
        s.ConvexRadius = math.min(s.ConvexRadius, hx * 0.5, hy * 0.5, hz * 0.5)
        bs.Shape = crearForma(s, J.JPC_BoxShapeSettings_Create)
        -- Giro en z de los robots = giro en Y de Jolt.
        bs.Rotation.x, bs.Rotation.y, bs.Rotation.z, bs.Rotation.w = 0, math.sin(f.rumbo / 2), 0, math.cos(f.rumbo / 2)
    end
    bs.Position.x, bs.Position.y, bs.Position.z = self:aJolt(f.x, f.y, (f.z0 + f.z1) / 2)
    bs.MotionType = J.JPC_MOTION_TYPE_STATIC
    bs.ObjectLayer = 0
    bs.Friction = 0.7
    local id = anadir(self, bs, false)
    self.colisionDe[id] = c
    self.cuerpoDe[c] = id
    return id
end

function Fisica:quitarColision(c)
    local id = self.cuerpoDe[c]
    if id then
        J.JPC_BodyInterface_RemoveBody(self.cuerpos, id)
        J.JPC_BodyInterface_DestroyBody(self.cuerpos, id)
        self.cuerpoDe[c] = nil
        self.colisionDe[id] = nil
    end
end

local rayoArgs

--- Rayo desde (x, y, z) m en la dirección (dx, dy, dz) hasta `alcance` m:
-- distancia, la colisión que toca ({ etiquetas, dueno, forma }) y el punto;
-- nil si no toca nada.
function Fisica:rayo(x, y, z, dx, dy, dz, alcance)
    local n = math.sqrt(dx * dx + dy * dy + dz * dz)
    if n < 1e-9 then
        return nil
    end
    local s = alcance / n
    rayoArgs = rayoArgs or ffi.new('JPC_NarrowPhaseQuery_CastRayArgs')
    local a = rayoArgs
    a.Ray.Origin.x, a.Ray.Origin.y, a.Ray.Origin.z = self:aJolt(x, y, z)
    -- Dirección en ejes de Jolt (x, z, -y), con su largo: el rayo es Origin + Direction · f.
    a.Ray.Direction.x, a.Ray.Direction.y, a.Ray.Direction.z = dx * s, dz * s, -dy * s
    a.Result.Fraction = 1 + 1e-5
    a.BroadPhaseLayerFilter, a.ObjectLayerFilter, a.BodyFilter, a.ShapeFilter = nil, nil, nil, nil
    if not J.JPC_NarrowPhaseQuery_CastRay(self.consultas, a) then
        return nil
    end
    local d = a.Result.Fraction * alcance
    local c = self.colisionDe[a.Result.BodyID] or Fisica.colisionNada
    return d, c, x + dx / n * d, y + dy / n * d, z + dz / n * d
end

-- Lo que toca un rayo que no es ninguna colisión declarada (una caja suelta).
Fisica.colisionNada = { etiquetas = { solido = true } }

function Fisica:crearPlano()
    local s = ffi.new('JPC_BoxShapeSettings')
    J.JPC_BoxShapeSettings_default(s)
    s.HalfExtent.x, s.HalfExtent.y, s.HalfExtent.z = self.radio, 1, self.radio
    local bs = ffi.new('JPC_BodyCreationSettings')
    J.JPC_BodyCreationSettings_default(bs)
    bs.Position.y = -1
    bs.MotionType = J.JPC_MOTION_TYPE_STATIC
    bs.ObjectLayer = 0
    bs.Shape = crearForma(s, J.JPC_BoxShapeSettings_Create)
    bs.Friction = 0.8
    self.terreno = anadir(self, bs, false)
    self.triangulosTerreno = 0
    self.colisionDe[self.terreno] = Fisica.colisionSuelo
end

--- Lo que necesita quien construya cuerpos propios (cuerpoRobot.lua).
function Fisica.jolt()
    return cargar(), ffi
end
Fisica.crearForma = function(settings, crear)
    return crearForma(settings, crear)
end

--- Una caja que se mueve: centro (x, y, z) m, medias medidas (hx a lo
-- largo de x, hy de y, hz de z) y masa en kg. Devuelve su id.
function Fisica:caja(x, y, z, hx, hy, hz, masa)
    local s = ffi.new('JPC_BoxShapeSettings')
    J.JPC_BoxShapeSettings_default(s)
    -- Ejes de Jolt: (x, z, y).
    s.HalfExtent.x, s.HalfExtent.y, s.HalfExtent.z = hx, hz, hy
    s.Density = masa / (8 * hx * hy * hz)
    local bs = ffi.new('JPC_BodyCreationSettings')
    J.JPC_BodyCreationSettings_default(bs)
    bs.Position.x, bs.Position.y, bs.Position.z = self:aJolt(x, y, z)
    bs.MotionType = J.JPC_MOTION_TYPE_DYNAMIC
    bs.ObjectLayer = 1
    bs.Shape = crearForma(s, J.JPC_BoxShapeSettings_Create)
    bs.Friction = 0.6
    local id = anadir(self, bs, true)
    self.lista[#self.lista + 1] = { id = id, forma = 'caja', hx = hx, hy = hy, hz = hz }
    return id
end

--- Empuja (impulso en N·s, en ejes de los robots).
function Fisica:empujar(id, ix, iy, iz)
    local v = ffi.new('JPC_Vec3')
    v.x, v.y, v.z = ix, iz, -iy
    J.JPC_BodyInterface_AddImpulse(self.cuerpos, id, v)
end

--- Matriz 4x4 por filas (la de las piezas de los robots) del cuerpo `id`,
-- en m de los robots. `salida`: tabla a rellenar.
function Fisica:matriz(id, salida)
    local m = J.JPC_BodyInterface_GetWorldTransform(self.cuerpos, id)
    -- Jolt guarda columnas: col[0..2] ejes (X, Y, Z de Jolt), col[3] posición.
    local c0, c1, c2, c3 = m.col[0], m.col[1], m.col[2], m.col3
    -- Cambio de base: robot = P · Jolt · P⁻¹, con P (X, Y, Z) -> (X, -Z, Y).
    -- Ejes del robot: x = X, y = -Z, z = Y, expresados en el robot.
    local function v(c)
        return c.x, -c.z, c.y
    end
    local ax, ay, az = v(c0) -- eje x del robot (X de Jolt)
    local bx, by, bz = v(c2) -- eje y del robot = -Z de Jolt
    bx, by, bz = -bx, -by, -bz
    local cx, cy, cz = v(c1) -- eje z del robot (Y de Jolt)
    local px, py, pz = self:deJolt(c3.x, c3.y, c3.z)
    salida = salida or {}
    salida[1], salida[2], salida[3], salida[4] = ax, bx, cx, px
    salida[5], salida[6], salida[7], salida[8] = ay, by, cy, py
    salida[9], salida[10], salida[11], salida[12] = az, bz, cz, pz
    salida[13], salida[14], salida[15], salida[16] = 0, 0, 0, 1
    return salida
end

--- Comprobación: por cada caja, lo que queda entre su punto más bajo y el
-- terreno (m; negativo: se ha hundido).
function Fisica:informe()
    local m = {}
    for k, c in ipairs(self.lista) do
        self:matriz(c.id, m)
        local abajo = math.huge
        for _, sx in ipairs({ -1, 1 }) do
            for _, sy in ipairs({ -1, 1 }) do
                for _, sz in ipairs({ -1, 1 }) do
                    local x, y, z = sx * c.hx, sy * c.hy, sz * c.hz
                    local wx = m[1] * x + m[2] * y + m[3] * z + m[4]
                    local wy = m[5] * x + m[6] * y + m[7] * z + m[8]
                    local wz = m[9] * x + m[10] * y + m[11] * z + m[12]
                    abajo = math.min(abajo, wz - Mundo.altura(wx, wy))
                end
            end
        end
        print(string.format('FISICA caja %d: centro a %.2f m del suelo, esquina más baja %.2f m', k, m[12] - Mundo.altura(m[4], m[8]), abajo))
    end
end

--- Avanza `dt` s en pasos fijos.
-- `antesDePaso(paso)`: lo que se hace antes de cada paso (el control de los
-- robots, que tiene que ir al ritmo de la física).
function Fisica:actualizar(dt, antesDePaso)
    self.acumulado = self.acumulado + dt
    local pasos = 0
    while self.acumulado >= Fisica.paso and pasos < 4 do
        self.acumulado = self.acumulado - Fisica.paso
        if antesDePaso then
            antesDePaso(Fisica.paso)
        end
        J.JPC_PhysicsSystem_Update(self.sistema, Fisica.paso, 1, self.temp, self.trabajos)
        pasos = pasos + 1
    end
    if pasos == 4 then
        self.acumulado = 0
    end
end

return Fisica
