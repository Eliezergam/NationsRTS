-- Vehículos en 3D real (prueba): mallas de assets/modelos3d/*.lua dibujadas
-- con la misma proyección isométrica que el resto del mundo (`Iso.vista`).
--
-- Formato del archivo (tools/blender/exportar_lua3d.py):
--   boca    boca del cañón en coordenadas de la pieza 'canon'
--   piezas  lista de { nombre, padre, pivote, vertices }; `vertices` es una
--           lista plana de triángulos y cada vértice es
--           { x, y, z, nx, ny, nz, r, g, b, nacion } en px del juego, relativo
--           al pivote de su pieza. El pivote va en coordenadas de la pieza padre.
--           El modelo mira a +x, y es la y del juego y z sube.
--
-- Cada pieza es una malla estática que se carga una sola vez. Por tanque solo
-- cambian tres matrices (casco, torreta y cañón) que se mandan al shader: el
-- shader pasa el vértice al mundo, lo proyecta como `Iso.vista` y le pone una
-- profundidad para el depth test. Las piezas 2D del mundo no escriben
-- profundidad: el tanque entra en el orden de piezas como una más y el depth
-- test solo ordena sus propias caras (y las de otros tanques).

local Iso = require('mundo.iso')

local Modelos3d = {}

-- Los tanques del pack Synty y el tanque A de respaldo ya no están (el dueño,
-- 21-nov: en el juego solo robots y lo hecho por el estudio): no hay modelo
-- de tanque por defecto; quien dibuje uno pasa el suyo (`Modelos3d.modelo`).
Modelos3d.retroceso = 8 -- px que retrocede el cañón al disparar
-- Mitades del casco (largo y ancho) donde se mide la pendiente del suelo.
Modelos3d.medioLargo = 38
Modelos3d.medioAncho = 18
-- Rango de profundidad (px del mundo) que cabe en el buffer, a cada lado de la
-- referencia del cuadro (el centro de la vista).
Modelos3d.rangoProfundidad = 65536

-- Luz de la tarde desde arriba a la izquierda, la misma del terreno.
local LUZ = { -0.45, -0.55, 0.7 }
do
    local l = math.sqrt(LUZ[1] ^ 2 + LUZ[2] ^ 2 + LUZ[3] ^ 2)
    LUZ = { LUZ[1] / l, LUZ[2] / l, LUZ[3] / l }
end

local FORMATO = {
    { 'VertexPosition', 'float', 3 },
    { 'NormalModelo', 'float', 3 },
    { 'ColorModelo', 'float', 3 },
    { 'NacionModelo', 'float', 1 },
}

local CODIGO_SHADER = [[
varying vec3 normalMundo;
varying vec3 colorBase;
varying float nacion;

#ifdef VERTEX
attribute vec3 NormalModelo;
attribute vec3 ColorModelo;
attribute float NacionModelo;

uniform mat4 modelo;
uniform float referencia;
uniform float rango;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vec4 mundo = modelo * vec4(vertex_position.xyz, 1.0);
    // Iso.vista: x - y, (x + y) / 2 - z * sqrt(1.5).
    vec2 vista = vec2(mundo.x - mundo.y, (mundo.x + mundo.y) * 0.5 - mundo.z * 1.2247449);
    vec4 posicion = transform_projection * vec4(vista, 0.0, 1.0);
    // Lo que está más hacia la cámara (x + y mayor, z mayor) queda más cerca.
    float hondo = mundo.x + mundo.y + mundo.z * 0.8164966 - referencia;
    posicion.z = -hondo / rango * posicion.w;
    normalMundo = mat3(modelo) * NormalModelo;
    colorBase = ColorModelo;
    nacion = NacionModelo;
    return posicion;
}
#endif

#ifdef PIXEL
uniform vec3 luz;
uniform vec3 colorNacion;

vec4 effect(vec4 color, Image textura, vec2 uv, vec2 pantalla)
{
    vec3 n = normalize(normalMundo);
    float difusa = max(dot(n, luz), 0.0);
    // La luz se suma en espacio lineal (como en el render de Blender) y se
    // vuelve a sRGB.
    vec3 base = pow(mix(colorBase, colorNacion, nacion), vec3(2.2));
    // Sol cálido y cielo rosado de ambiente, como en los sprites.
    vec3 ambiente = vec3(0.96, 0.7, 0.6) * 0.75;
    vec3 sol = vec3(1.0, 0.84, 0.68) * 2.0;
    vec3 lineal = base * (ambiente + sol * difusa);
    return vec4(pow(lineal, vec3(1.0 / 2.2)), 1.0) * color;
}
#endif
]]

-- Sombra en el suelo: la planta del casco, un poco más grande, corrida hacia
-- donde no da el sol.
Modelos3d.sombra = { largo = 44, ancho = 23, corrida = 7, alfa = 0.3 }

local shader

--- Lee el archivo de un modelo. Uno muy grande (el camión de 4 misiles con
-- todas sus piezas) pasa de las 65 536 constantes por función de LuaJIT: se
-- vuelve a leer con los vértices de cada pieza en una función propia
-- (`vertices = (function() return { ... } end)()`), que no cambia los datos.
local function leerModelo(archivo)
    local ok, cargador = pcall(love.filesystem.load, archivo)
    if ok then
        return cargador()
    end
    if not tostring(cargador):find('constants', 1, true) then
        error(cargador, 0)
    end
    local texto = assert(love.filesystem.read(archivo))
    texto = texto:gsub('vertices = {\n', 'vertices = (function() return {\n')
    texto = texto:gsub('\n(%s*)} },', '\n%1} end)() },')
    return assert(loadstring(texto, '@' .. archivo))()
end

--- Carga un modelo del formato de arriba: una malla por pieza. Los demás
-- campos del archivo (boca, bocas, elevacion...) se copian tal cual.
local function cargarModelo(archivo)
    local datos = leerModelo(archivo)
    -- La ruta sin .lua: con ella batalla/vehiculos/gestorVehiculos.lua sabe
    -- qué tipo de vehículo es.
    local modelo = { piezas = {}, archivo = archivo:gsub('%.lua$', '') }
    for clave, valor in pairs(datos) do
        if clave ~= 'piezas' then
            modelo[clave] = valor
        end
    end
    for _, p in ipairs(datos.piezas) do
        local malla = love.graphics.newMesh(FORMATO, p.vertices, 'triangles', 'static')
        modelo.piezas[p.nombre] = {
            malla = malla,
            padre = p.padre,
            pivote = p.pivote or { 0, 0, 0 },
        }
    end
    return modelo
end

local function cargar()
    if shader then
        return
    end
    shader = love.graphics.newShader(CODIGO_SHADER)
    shader:send('luz', LUZ)
    shader:send('rango', Modelos3d.rangoProfundidad)
    shader:send('referencia', 0)
end

-- Matrices 4x4 en tablas planas por filas ---------------------------------------------------

--- a * b (4x4 por filas) en `r`.
local function multiplicar(a, b, r)
    for i = 0, 3 do
        for j = 1, 4 do
            r[i * 4 + j] = a[i * 4 + 1] * b[j]
                + a[i * 4 + 2] * b[4 + j]
                + a[i * 4 + 3] * b[8 + j]
                + a[i * 4 + 4] * b[12 + j]
        end
    end
    return r
end

--- Traslación (tx, ty, tz) y giro `angulo` sobre z, en `r`.
local function girarZ(angulo, tx, ty, tz, r)
    local c, s = math.cos(angulo), math.sin(angulo)
    r[1], r[2], r[3], r[4] = c, -s, 0, tx
    r[5], r[6], r[7], r[8] = s, c, 0, ty
    r[9], r[10], r[11], r[12] = 0, 0, 1, tz
    r[13], r[14], r[15], r[16] = 0, 0, 0, 1
    return r
end

--- Punto (x, y, z) pasado por la matriz `m`.
local function aplicar(m, x, y, z)
    return m[1] * x + m[2] * y + m[3] * z + m[4],
        m[5] * x + m[6] * y + m[7] * z + m[8],
        m[9] * x + m[10] * y + m[11] * z + m[12]
end

local function normalizar(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    return x / l, y / l, z / l
end

-- Tablas de trabajo: nada de basura por cuadro.
local local1, local2 = {}, {}
local matrizTorreta, matrizCanon = {}, {}

--- Postura de un tanque en el punto (x, y) del suelo con el casco mirando a
-- `rumbo`: apoyado en el terreno e inclinado con la pendiente. La normal del
-- suelo sale de la altura delante, detrás y a los lados, en el tamaño del
-- casco. Devuelve la matriz del casco (modelo -> mundo). `z` es la altura del
-- centro (si ya se tiene); `r`, una tabla para reutilizar.
function Modelos3d.postura(terreno, x, y, z, rumbo, r)
    local ca, sa = math.cos(rumbo), math.sin(rumbo)
    local l, a = Modelos3d.medioLargo, Modelos3d.medioAncho
    local delante = terreno:altura(x + ca * l, y + sa * l)
    local detras = terreno:altura(x - ca * l, y - sa * l)
    local izquierda = terreno:altura(x - sa * a, y + ca * a)
    local derecha = terreno:altura(x + sa * a, y - ca * a)
    -- Ejes del suelo bajo el tanque: adelante (f) y de lado (s); la normal, f x s.
    local fx, fy, fz = ca * 2 * l, sa * 2 * l, delante - detras
    local sx, sy, sz = -sa * 2 * a, ca * 2 * a, izquierda - derecha
    local nx, ny, nz = normalizar(fy * sz - fz * sy, fz * sx - fx * sz, fx * sy - fy * sx)
    fx, fy, fz = normalizar(fx, fy, fz)
    -- y = n x f: queda perpendicular a los dos.
    local yx, yy, yz = ny * fz - nz * fy, nz * fx - nx * fz, nx * fy - ny * fx
    -- Apoyado: ni hundido en una loma ni flotando en un hoyo.
    local suelo = math.max(z or terreno:altura(x, y), (delante + detras + izquierda + derecha) / 4)
    r = r or {}
    r[1], r[2], r[3], r[4] = fx, yx, nx, x
    r[5], r[6], r[7], r[8] = fy, yy, ny, y
    r[9], r[10], r[11], r[12] = fz, yz, nz, suelo
    r[13], r[14], r[15], r[16] = 0, 0, 0, 1
    return r
end

--- Matrices de la torreta y del cañón de un tanque con casco `casco`, la
-- torreta girada `torreta` respecto al casco y el cañón retrocedido
-- `retroceso` (0 a 1). `modelo`: el del tanque (`Modelos3d.modelo`).
local function matricesTorreta(casco, torreta, retroceso, modelo)
    local piezas = modelo.piezas
    local pt, pc = piezas.torreta.pivote, piezas.canon.pivote
    multiplicar(casco, girarZ(torreta, pt[1], pt[2], pt[3], local1), matrizTorreta)
    local atras = (retroceso or 0) * Modelos3d.retroceso
    multiplicar(matrizTorreta, girarZ(0, pc[1] - atras, pc[2], pc[3], local2), matrizCanon)
end

--- Formato de vértice de las mallas de los modelos (lo usa también la escena
-- de batalla para sus propias mallas).
Modelos3d.formato = FORMATO
Modelos3d.cargarModelo = cargarModelo

--- Matrices (modelo -> mundo) de la torreta y del cañón de un tanque con casco
-- `casco`. Son tablas de trabajo: hay que usarlas antes de la siguiente llamada.
-- `modelo`: el modelo cargado del tanque (`Modelos3d.modelo`).
function Modelos3d.matricesTanque(casco, torreta, retroceso, modelo)
    cargar()
    matricesTorreta(casco, torreta, retroceso, modelo)
    return matrizTorreta, matrizCanon
end

local cargados = {}

--- Modelo de vértices del archivo `archivo` (con o sin `.lua`), cargado una
-- sola vez: los de cada vehículo del catálogo en la batalla.
function Modelos3d.modelo(archivo)
    local ruta = archivo:match('%.lua$') and archivo or (archivo .. '.lua')
    local modelo = cargados[ruta]
    if not modelo then
        modelo = cargarModelo(ruta)
        cargados[ruta] = modelo
    end
    return modelo
end

--- Profundidad de referencia del cuadro (x + y del centro de la vista): el
-- buffer guarda la profundidad relativa a ella.
function Modelos3d.empezarCuadro(referencia)
    cargar()
    shader:send('referencia', referencia)
end

local esquinas = { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } }
local puntosSombra = {}

--- Sombra del tanque con el casco en `casco`: la planta del casco sobre el
-- suelo inclinado, corrida al lado contrario del sol.
function Modelos3d.dibujarSombra(casco)
    local s = Modelos3d.sombra
    local dx, dy = -LUZ[1] * s.corrida, -LUZ[2] * s.corrida
    for k, e in ipairs(esquinas) do
        local x, y, z = aplicar(casco, e[1] * s.largo, e[2] * s.ancho, 0)
        puntosSombra[k * 2 - 1], puntosSombra[k * 2] = Iso.vista(x + dx, y + dy, z)
    end
    love.graphics.setColor(0.1, 0.12, 0.05, s.alfa)
    love.graphics.polygon('fill', puntosSombra)
end

return Modelos3d
