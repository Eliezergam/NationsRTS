-- Cinta de rejilla holográfica en la GPU (la línea de la orden de mover;
-- batalla/marcas_holo.lua la pide para cada unidad elegida que va a algún
-- sitio). Copia de `holoRejilla` de la referencia del dueño
-- (ruta-y-seleccion.html): dos bordes de luz con brillo, líneas
-- transversales cada 5 que avanzan a 18/s con una banda brillante que las
-- recorre a 90/s cada 60, y flechas macizas cada 46 que avanzan a 46/s hacia
-- el destino, todo con el `desvanecer` de allí (nada junto al vehículo,
-- entero en medio, algo menos al llegar).
--
-- La CPU solo apoya en el suelo una tira a lo largo de la ruta (dos puntos
-- cada 8 unidades de la referencia, proyectados a pantalla: sigue las
-- lomas) con, en cada vértice, la distancia a lo largo y a lo ancho en
-- unidades de la referencia; el shader dibuja lo demás por píxel, con los
-- grosores en px de pantalla como en la referencia (`fwidth`). Todas las
-- cintas de un cuadro van en una malla y una llamada de dibujo.

local ffi = require('ffi')

local CintaHolo = {}
CintaHolo.__index = CintaHolo

-- Puntos de la tira: uno cada `pxPorPaso` px de pantalla, entre `paso` y
-- `pasoMaximo` px del mundo (de cerca, uno cada 1,5 m, que sigue bien las
-- lomas; de lejos, menos: nivel de detalle). El dibujo de la cinta no
-- depende de esto (lo hace el shader por píxel).
CintaHolo.paso = 15
CintaHolo.pasoMaximo = 150
CintaHolo.pasoFuera = 400 -- px del mundo entre puntos fuera de la pantalla
CintaHolo.pxPorPaso = 28
CintaHolo.margen = 6 -- medio ancho de la tira (la cinta mide 9; el resto es para el brillo)

local FORMATO = {
    { 'VertexPosition', 'float', 2 },
    { 'Datos', 'float', 4 }, -- a lo largo, a lo ancho, largo de la ruta, inicio de los bordes
    { 'Profundidad', 'float', 1 }, -- distancia al ojo en la vista (px del mundo)
}
local FLOTANTES = 7

local CODIGO = [[
varying vec4 vDatos;
varying float vProfundidad;

#ifdef VERTEX
attribute vec4 Datos;
attribute float Profundidad;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vDatos = Datos;
    vProfundidad = Profundidad;
    return transform_projection * vertex_position;
}
#endif

#ifdef PIXEL
uniform float ui;
uniform float desfaseLineas;
uniform float barrido;
uniform float desfaseFlechas;
uniform vec3 menta;
uniform vec3 mentaClaro;
uniform Image profundidadEscena;
uniform float escalaProfundidad;
uniform vec2 rangoProfundidad;
uniform float conProfundidad;

// Lo que tapa la escena (el vehículo, una loma, un árbol) se ve tenue, como
// a través: la profundidad de 3Dream es la distancia en la vista (unidades
// de 3Dream) y la nuestra, en px del mundo por `escalaProfundidad`.
float tapado(vec2 pantalla)
{
    if (conProfundidad < 0.5) {
        return 1.0;
    }
    float escena = Texel(profundidadEscena, pantalla / love_ScreenSize.xy).r;
    // 3Dream guarda la z de recorte: (f + n) / (f - n) * d - 2 f n / (f - n).
    float d = vProfundidad * escalaProfundidad;
    float mia = rangoProfundidad.x * d + rangoProfundidad.y;
    return escena < mia - 0.05 - 0.01 * d ? 0.3 : 1.0;
}

float desvanecer(float s, float largo)
{
    return clamp(min(s / 26.0, (largo - s) / 14.0 + 0.35), 0.0, 1.0);
}

vec4 encima(vec4 debajo, vec3 color, float alfa)
{
    return vec4(color * alfa, alfa) + debajo * (1.0 - alfa);
}

vec4 effect(vec4 colorBase, Image textura, vec2 coordenada, vec2 pantalla)
{
    float s = vDatos.x;
    float v = vDatos.y;
    float largo = vDatos.z;
    float inicio = vDatos.w;
    float porPxS = max(fwidth(s), 0.0001);
    float porPxV = max(fwidth(v), 0.0001);
    vec4 total = vec4(0.0);

    // Bordes de luz: 1,3 px y brillo (shadowBlur 8).
    if (s >= inicio) {
        float d = abs(abs(v) - 9.0) / porPxV;
        float nucleo = clamp(0.65 * ui + 0.5 - d, 0.0, 1.0);
        float sigma = 3.5 * ui;
        float brillo = 0.35 * exp(-d * d / (2.0 * sigma * sigma));
        total = encima(total, menta, 0.75 * max(nucleo, brillo));
    }

    // Líneas transversales con la banda del barrido.
    if (abs(v) <= 9.0) {
        float k = floor((s - desfaseLineas) / 5.0 + 0.5);
        float sk = desfaseLineas + k * 5.0;
        if (k >= 0.0 && sk < largo - 6.0) {
            float a = desvanecer(sk, largo);
            if (a > 0.02) {
                float banda = abs(mod(mod(sk - barrido, 60.0) + 60.0, 60.0) - 30.0) / 30.0;
                float alfa = a * (0.12 + 0.5 * pow(1.0 - banda, 3.0));
                float d = abs(s - sk) / porPxS;
                total = encima(total, menta, alfa * clamp(0.5 * ui + 0.5 - d, 0.0, 1.0));
            }
        }
    }

    // Flechas macizas: punta 6 delante, base 4 detrás y 5 a cada lado.
    float k = floor((s - desfaseFlechas) / 46.0 + 0.5);
    float centro = desfaseFlechas + k * 46.0;
    if (k >= 0.0 && centro < largo - 6.0) {
        float a = desvanecer(centro, largo);
        if (a > 0.02) {
            float x = s - centro;
            float y = abs(v);
            float atras = -4.0 - x;
            float lado = (y + 0.5 * x - 3.0) / 1.118034;
            float porPx = 0.5 * (porPxS + porPxV);
            float d = max(atras, lado) / porPx;
            float relleno = clamp(0.5 - d, 0.0, 1.0);
            float sigma = 4.0 * ui;
            float fuera = max(d, 0.0);
            float halo = 0.4 * exp(-fuera * fuera / (2.0 * sigma * sigma));
            total = encima(total, menta, a * halo * (1.0 - relleno));
            total = encima(total, mentaClaro, a * relleno);
        }
    }
    return total * tapado(pantalla);
}
#endif
]]

function CintaHolo.nueva()
    local self = setmetatable({}, CintaHolo)
    self.cuantos = 0
    self.capacidad = 0
    self.shader = love.graphics.newShader(CODIGO)
    -- Listas de trabajo de `anadir` (puntos en pantalla y distancias).
    self.xs = {}
    self.ys = {}
    self.ss = {}
    self.ws = {}
    self:crecer(6144)
    return self
end

--- Sitio para `capacidad` vértices (lo escrito se conserva).
function CintaHolo:crecer(capacidad)
    local datos = love.data.newByteData(capacidad * FLOTANTES * 4)
    local p = ffi.cast('float*', datos:getFFIPointer())
    if self.p and self.cuantos > 0 then
        ffi.copy(p, self.p, self.cuantos * FLOTANTES * 4)
    end
    if self.datos then
        self.datos:release()
    end
    if self.malla then
        self.malla:release()
    end
    self.datos = datos
    self.p = p
    self.capacidad = capacidad
    self.malla = love.graphics.newMesh(FORMATO, capacidad, 'triangles', 'stream')
end

function CintaHolo:vaciar()
    self.cuantos = 0
end

function CintaHolo:vertice(x, y, s, v, largo, inicio, profundidad)
    local n = self.cuantos
    if n >= self.capacidad then
        self:crecer(self.capacidad * 2)
    end
    local p = self.p
    local k = n * FLOTANTES
    p[k] = x
    p[k + 1] = y
    p[k + 2] = s
    p[k + 3] = v
    p[k + 4] = largo
    p[k + 5] = inicio
    p[k + 6] = profundidad
    self.cuantos = n + 1
end

--- Añade la cinta de una ruta. `marcas` da la proyección al suelo
-- (`proyectarXY`) y el tamaño de la cinta en cada punto
-- (`escalaCinta(x, y, factor)`: px del mundo por unidad de la referencia,
-- según la distancia al ojo, para que en pantalla mida casi lo mismo de
-- cerca y de lejos); `ruta` y `enS`, la ruta medida y su punto a una
-- distancia; `inicio` (px del mundo), dónde empieza: lo de antes lo taparía
-- el vehículo, como en la referencia. `punto`: tabla de trabajo para `enS`.
-- Devuelve la escala en el destino (para su anillo).
--
-- Con la escala cambiando a lo largo, la distancia que ve el shader (`s`,
-- en unidades de la referencia) se acumula tramo a tramo: las líneas y las
-- flechas quedan a la misma separación en pantalla.
function CintaHolo:anadir(marcas, ruta, enS, factor, inicio, punto)
    local largo = ruta.largo
    local margen = CintaHolo.margen
    local xs, ys, ss, ws = self.xs, self.ys, self.ss, self.ws
    local n = 0
    local sMundo = inicio
    local sRef = 0
    local e
    local anteriorS
    while true do
        enS(ruta, sMundo, punto)
        e = marcas:escalaCinta(punto.x, punto.y, factor)
        if anteriorS then
            sRef = sRef + (sMundo - anteriorS) / e
        else
            sRef = inicio / e
        end
        anteriorS = sMundo
        local ox = punto.nx * margen * e
        local oy = punto.ny * margen * e
        local cx, cy, cVisible, cw = marcas:proyectarXY(punto.x + ox, punto.y + oy)
        local dx, dy, dVisible, dw = marcas:proyectarXY(punto.x - ox, punto.y - oy)
        n = n + 1
        if cx and dx then
            xs[2 * n - 1], ys[2 * n - 1] = cx, cy
            xs[2 * n], ys[2 * n] = dx, dy
            ws[2 * n - 1], ws[2 * n] = cw, dw
        else
            xs[2 * n - 1] = false
        end
        ss[n] = sRef
        if sMundo >= largo then
            break
        end
        -- El paso: unos `pxPorPaso` px de pantalla, entre `paso` y
        -- `pasoMaximo` px del mundo; fuera de la pantalla, `pasoFuera`.
        local paso = CintaHolo.paso
        if cx and dx then
            local ancho = math.sqrt((cx - dx) ^ 2 + (cy - dy) ^ 2)
            local pxPorMundo = ancho / (2 * margen * e)
            paso = math.max(paso, math.min(CintaHolo.pasoMaximo, CintaHolo.pxPorPaso / math.max(pxPorMundo, 0.0001)))
            if not (cVisible or dVisible) then
                paso = CintaHolo.pasoFuera
            end
        end
        sMundo = math.min(largo, sMundo + paso)
    end
    local largoRef = ss[n]
    local inicioRef = ss[1]
    for k = 2, n do
        if xs[2 * k - 3] and xs[2 * k - 1] then
            local ax, ay, bx, by = xs[2 * k - 3], ys[2 * k - 3], xs[2 * k - 2], ys[2 * k - 2]
            local cx, cy, dx, dy = xs[2 * k - 1], ys[2 * k - 1], xs[2 * k], ys[2 * k]
            local aw, bw, cw, dw = ws[2 * k - 3], ws[2 * k - 2], ws[2 * k - 1], ws[2 * k]
            local sa, sb = ss[k - 1], ss[k]
            self:vertice(ax, ay, sa, margen, largoRef, inicioRef, aw)
            self:vertice(bx, by, sa, -margen, largoRef, inicioRef, bw)
            self:vertice(cx, cy, sb, margen, largoRef, inicioRef, cw)
            self:vertice(bx, by, sa, -margen, largoRef, inicioRef, bw)
            self:vertice(dx, dy, sb, -margen, largoRef, inicioRef, dw)
            self:vertice(cx, cy, sb, margen, largoRef, inicioRef, cw)
        end
    end
    return e
end

--- Dibuja las cintas del cuadro. `t`: reloj en segundos; `ui`: grosor de
-- las líneas (px por px de la referencia).
function CintaHolo:dibujar(t, ui, menta, mentaClaro, profundidad)
    local n = self.cuantos
    if n == 0 then
        return
    end
    local g = love.graphics
    local shader = self.shader
    -- Los desfases, ya reducidos en la CPU: en el shader, `tiempo * 90` con
    -- el reloj de horas perdería precisión.
    shader:send('ui', ui)
    shader:send('desfaseLineas', (t * 18) % 5 + 10)
    shader:send('barrido', (t * 90) % 60)
    shader:send('desfaseFlechas', (t * 46) % 46 + 10)
    shader:send('menta', menta)
    shader:send('mentaClaro', mentaClaro)
    profundidad.enviar(shader)
    self.malla:setVertices(self.datos, 1, n)
    self.malla:setDrawRange(1, n)
    g.push('all')
    g.setShader(shader)
    g.setBlendMode('alpha', 'premultiplied')
    g.setColor(1, 1, 1, 1)
    g.draw(self.malla)
    g.pop()
end

return CintaHolo
