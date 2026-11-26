-- Matrices 4x4 de la escena de batalla, en tablas planas por filas (se mandan
-- al shader con 'row'). El mundo es el del mapa: x, y en el suelo y z hacia
-- arriba, en px (1 px = 10 cm).

local Matriz = {}

--- Matriz identidad (en `r` si se da).
function Matriz.identidad(r)
    r = r or {}
    for k = 1, 16 do
        r[k] = 0
    end
    r[1], r[6], r[11], r[16] = 1, 1, 1, 1
    return r
end

--- a * b en `r` (`r` no puede ser `a` ni `b`).
function Matriz.multiplicar(a, b, r)
    r = r or {}
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

--- Traslación a (x, y, z), giro `rumbo` sobre z y escala `escala` (un número
-- o tres), en `r`.
function Matriz.colocar(x, y, z, rumbo, escala, r)
    r = r or {}
    local c, s = math.cos(rumbo or 0), math.sin(rumbo or 0)
    local ex, ey, ez = escala or 1, escala or 1, escala or 1
    if type(escala) == 'table' then
        ex, ey, ez = escala[1], escala[2], escala[3]
    end
    r[1], r[2], r[3], r[4] = c * ex, -s * ey, 0, x
    r[5], r[6], r[7], r[8] = s * ex, c * ey, 0, y
    r[9], r[10], r[11], r[12] = 0, 0, ez, z
    r[13], r[14], r[15], r[16] = 0, 0, 0, 1
    return r
end

--- Traslación (x, y, z) y giro `angulo` sobre el eje y (cabeceo), en `r`.
-- Con un ángulo negativo, lo que mira a +x sube.
function Matriz.cabecear(angulo, x, y, z, r)
    r = r or {}
    local c, s = math.cos(angulo), math.sin(angulo)
    r[1], r[2], r[3], r[4] = c, 0, s, x
    r[5], r[6], r[7], r[8] = 0, 1, 0, y
    r[9], r[10], r[11], r[12] = -s, 0, c, z
    r[13], r[14], r[15], r[16] = 0, 0, 0, 1
    return r
end

--- Pieza alargada de `desde` a `hasta` (x, y, z), con un grosor `grosor`: la
-- malla unidad (de -0,5 a 0,5 en x) queda estirada entre los dos puntos.
function Matriz.entre(ax, ay, az, bx, by, bz, grosor, r)
    r = r or {}
    local fx, fy, fz = bx - ax, by - ay, bz - az
    local largo = math.max(0.001, math.sqrt(fx * fx + fy * fy + fz * fz))
    fx, fy, fz = fx / largo, fy / largo, fz / largo
    -- Un eje de lado cualquiera perpendicular a f, y el tercero.
    local sx, sy, sz = -fy, fx, 0
    local ls = math.sqrt(sx * sx + sy * sy)
    if ls < 0.001 then
        sx, sy, sz, ls = 1, 0, 0, 1
    end
    sx, sy, sz = sx / ls, sy / ls, sz / ls
    local ux, uy, uz = fy * sz - fz * sy, fz * sx - fx * sz, fx * sy - fy * sx
    r[1], r[2], r[3], r[4] = fx * largo, sx * grosor, ux * grosor, (ax + bx) / 2
    r[5], r[6], r[7], r[8] = fy * largo, sy * grosor, uy * grosor, (ay + by) / 2
    r[9], r[10], r[11], r[12] = fz * largo, sz * grosor, uz * grosor, (az + bz) / 2
    r[13], r[14], r[15], r[16] = 0, 0, 0, 1
    return r
end

--- Coloca un modelo que mira a +x en (bx, by, bz), orientado en la dirección
-- que va desde (ax, ay, az), con escala uniforme. Se usa para proyectiles 3D
-- que conservan sus proporciones mientras siguen una trayectoria curva.
function Matriz.orientar(ax, ay, az, bx, by, bz, escala, r)
    r = r or {}
    local fx, fy, fz = bx - ax, by - ay, bz - az
    local largo = math.max(0.001, math.sqrt(fx * fx + fy * fy + fz * fz))
    fx, fy, fz = fx / largo, fy / largo, fz / largo
    local sx, sy, sz = -fy, fx, 0
    local lado = math.sqrt(sx * sx + sy * sy)
    if lado < 0.001 then
        sx, sy, sz, lado = 1, 0, 0, 1
    end
    sx, sy, sz = sx / lado, sy / lado, sz / lado
    local ux = fy * sz - fz * sy
    local uy = fz * sx - fx * sz
    local uz = fx * sy - fy * sx
    escala = escala or 1
    r[1], r[2], r[3], r[4] = fx * escala, sx * escala, ux * escala, bx
    r[5], r[6], r[7], r[8] = fy * escala, sy * escala, uy * escala, by
    r[9], r[10], r[11], r[12] = fz * escala, sz * escala, uz * escala, bz
    r[13], r[14], r[15], r[16] = 0, 0, 0, 1
    return r
end

--- Punto (x, y, z) pasado por la matriz `m`.
function Matriz.aplicar(m, x, y, z)
    return m[1] * x + m[2] * y + m[3] * z + m[4],
        m[5] * x + m[6] * y + m[7] * z + m[8],
        m[9] * x + m[10] * y + m[11] * z + m[12]
end

--- Perspectiva de OpenGL: campo vertical `campo` (radianes), proporción
-- `aspecto` y planos `cerca` y `lejos`.
function Matriz.perspectiva(campo, aspecto, cerca, lejos, r)
    r = Matriz.identidad(r)
    local f = 1 / math.tan(campo / 2)
    r[1] = f / aspecto
    r[6] = f
    r[11] = (lejos + cerca) / (cerca - lejos)
    r[12] = 2 * lejos * cerca / (cerca - lejos)
    r[15] = -1
    r[16] = 0
    return r
end

--- Cámara en (ex, ey, ez) mirando a (tx, ty, tz) con z hacia arriba.
--
-- El mapa isométrico ve el mundo en espejo respecto a una cámara normal (x va
-- a la derecha y abajo, y a la izquierda y abajo): el eje de lado se invierte
-- para que la escena de batalla y el mapa se vean con la misma orientación.
function Matriz.mirar(ex, ey, ez, tx, ty, tz, r)
    r = r or {}
    local fx, fy, fz = tx - ex, ty - ey, tz - ez
    local l = math.sqrt(fx * fx + fy * fy + fz * fz)
    fx, fy, fz = fx / l, fy / l, fz / l
    -- s = f x arriba (arriba = z), invertido por el espejo.
    local sx, sy = fy, -fx
    local ls = math.sqrt(sx * sx + sy * sy)
    sx, sy = -sx / ls, -sy / ls
    local sz = 0
    -- u = s x f (con s ya invertido, se invierte también para que suba).
    local ux, uy, uz = -(sy * fz - sz * fy), -(sz * fx - sx * fz), -(sx * fy - sy * fx)
    r[1], r[2], r[3], r[4] = sx, sy, sz, -(sx * ex + sy * ey + sz * ez)
    r[5], r[6], r[7], r[8] = ux, uy, uz, -(ux * ex + uy * ey + uz * ez)
    r[9], r[10], r[11], r[12] = -fx, -fy, -fz, fx * ex + fy * ey + fz * ez
    r[13], r[14], r[15], r[16] = 0, 0, 0, 1
    return r
end

return Matriz
