-- Anillos holográficos en la GPU: el anillo de datos de cada unidad elegida
-- y el anillo que late en el destino de su cinta (batalla/marcas_holo.lua
-- los pide). Copia de `anilloDatosVida` y `anilloDestino` de la referencia
-- del dueño (ruta-y-seleccion.html):
--
--   datos    arco de fondo de 270° (hueco a la izquierda de la pantalla) y
--            encima la vida, de 3 px con brillo, en menta, amarillo o rojo
--            según la vida (> 60 %, 30-60 %, < 30 %); 24 marcas de 1 px a 7
--            unidades por fuera que giran a 1,2 rad/s, una de cada cuatro
--            más viva; entrada de 0,4 s (y 0,7 s el arco de la vida).
--   destino  un anillo de radio 8 y otro que se abre de 8 a 24 y se apaga,
--            de 1,6 px.
--
-- La CPU apoya en el suelo una corona de 32 sectores por anillo (sigue las
-- lomas) con el ángulo y el radio en unidades de la referencia en cada
-- vértice; el shader dibuja por píxel con los grosores en px de pantalla.

local ffi = require('ffi')

local AnilloHolo = {}
AnilloHolo.__index = AnilloHolo

-- Sectores de la corona: uno cada `pxPorSector` px de su radio en
-- pantalla, entre `sectoresMinimos` y `sectores` (nivel de detalle).
AnilloHolo.sectores = 32
AnilloHolo.sectoresMinimos = 12
AnilloHolo.pxPorSector = 4
-- Radios de la corona (unidades de la referencia) de cada clase de anillo:
-- lo que cabe del dibujo más el brillo.
AnilloHolo.corona = {
    datos = { 14, 40 },
    destino = { 4, 28 },
}

local FORMATO = {
    { 'VertexPosition', 'float', 2 },
    { 'Datos', 'float', 4 }, -- ángulo, radio, vida (0 a 1), segundos desde que se eligió
    { 'Clase', 'float', 1 }, -- 0 datos, 1 destino
    { 'Profundidad', 'float', 1 }, -- distancia al ojo en la vista (px del mundo)
}
local FLOTANTES = 8

local CODIGO = [[
varying vec4 vDatos;
varying float vClase;
varying float vProfundidad;

#ifdef VERTEX
attribute vec4 Datos;
attribute float Clase;
attribute float Profundidad;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vDatos = Datos;
    vClase = Clase;
    vProfundidad = Profundidad;
    return transform_projection * vertex_position;
}
#endif

#ifdef PIXEL
uniform float ui;
uniform float giro;
uniform float pulso;
uniform vec3 menta;
uniform vec3 amarillo;
uniform vec3 rojo;
uniform Image profundidadEscena;
uniform float escalaProfundidad;
uniform vec2 rangoProfundidad;
uniform float conProfundidad;

// Como en la cinta: lo que tapa la escena se ve tenue.
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

const float PI = 3.14159265;

float suave(float x)
{
    float v = clamp(x, 0.0, 1.0);
    return 1.0 - pow(1.0 - v, 3.0);
}

vec4 encima(vec4 debajo, vec3 color, float alfa)
{
    return vec4(color * alfa, alfa) + debajo * (1.0 - alfa);
}

// Trazo de `ancho` px a `d` px de su centro, con brillo opcional.
float trazo(float d, float ancho, float brillo)
{
    float nucleo = clamp(0.5 * ancho + 0.5 - d, 0.0, 1.0);
    if (brillo <= 0.0) {
        return nucleo;
    }
    float sigma = brillo;
    return max(nucleo, 0.35 * exp(-d * d / (2.0 * sigma * sigma)));
}

// ¿Está el ángulo `a` (0 a 2π) dentro del arco que empieza en `desde` y
// mide `largo`? Con borde suave de un píxel.
float enArco(float a, float desde, float largo, float porPx)
{
    float rel = mod(a - desde + 4.0 * PI, 2.0 * PI);
    float dentro = clamp((largo - rel) / porPx + 0.5, 0.0, 1.0);
    return dentro * clamp(rel / porPx + 0.5, 0.0, 1.0);
}

vec4 effect(vec4 colorBase, Image textura, vec2 coordenada, vec2 pantalla)
{
    float a = vDatos.x;
    float r = vDatos.y;
    float porPxR = max(fwidth(r), 0.0001);
    float porPxA = max(fwidth(a), 0.0001);
    vec4 total = vec4(0.0);

    if (vClase > 0.5) {
        // Destino: anillo fijo y anillo que se abre.
        float d0 = abs(r - 8.0) / porPxR;
        total = encima(total, menta, 0.9 * trazo(d0, 1.6 * ui, 0.0));
        float d1 = abs(r - (8.0 + pulso * 16.0)) / porPxR;
        total = encima(total, menta, (1.0 - pulso) * 0.8 * trazo(d1, 1.6 * ui, 0.0));
        return total * tapado(pantalla);
    }

    float vida = vDatos.z;
    float edad = vDatos.w;
    float k = suave(edad / 0.4);
    float brillo = 3.5 * ui;
    float inicio = -0.75 * PI;
    // Arco de fondo (270°) y la vida encima.
    float dArco = abs(r - 24.0) / porPxR;
    float fondo = trazo(dArco, 3.0 * ui, brillo) * enArco(a, inicio, 1.5 * PI, porPxA);
    total = encima(total, menta, 0.25 * k * fondo);
    vec3 colorVida = vida > 0.6 ? menta : (vida > 0.3 ? amarillo : rojo);
    float largoVida = 1.5 * PI * vida * suave(edad / 0.7);
    float arcoVida = trazo(dArco, 3.0 * ui, brillo) * enArco(a, inicio, largoVida, porPxA);
    total = encima(total, colorVida, k * arcoVida);
    // 24 marcas que giran; una de cada cuatro, más viva.
    float paso = PI / 12.0;
    float rel = mod(a - giro + 4.0 * PI, 2.0 * PI);
    float indice = floor(rel / paso);
    float dentro = rel - indice * paso;
    float enMarca = clamp((0.08 - dentro) / porPxA + 0.5, 0.0, 1.0) * clamp(dentro / porPxA + 0.5, 0.0, 1.0);
    float viva = mod(indice, 4.0) < 0.5 ? 0.75 : 0.25;
    float dMarca = abs(r - 31.0) / porPxR;
    total = encima(total, menta, k * viva * enMarca * trazo(dMarca, ui, brillo));
    return total * tapado(pantalla);
}
#endif
]]

function AnilloHolo.nuevos()
    local self = setmetatable({}, AnilloHolo)
    self.cuantos = 0
    self.capacidad = 0
    self.shader = love.graphics.newShader(CODIGO)
    self:crecer(4096)
    return self
end

--- Sitio para `capacidad` vértices (lo escrito se conserva).
function AnilloHolo:crecer(capacidad)
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

function AnilloHolo:vaciar()
    self.cuantos = 0
end

function AnilloHolo:vertice(x, y, angulo, radio, vida, edad, clase, profundidad)
    local n = self.cuantos
    if n >= self.capacidad then
        self:crecer(self.capacidad * 2)
    end
    local p = self.p
    local k = n * FLOTANTES
    p[k] = x
    p[k + 1] = y
    p[k + 2] = angulo
    p[k + 3] = radio
    p[k + 4] = vida
    p[k + 5] = edad
    p[k + 6] = clase
    p[k + 7] = profundidad
    self.cuantos = n + 1
end

--- Añade un anillo en (x, y) del suelo. `escala`: px del mundo por unidad
-- de la referencia; `clase`: 'datos' o 'destino'. `marcas` da la
-- proyección (`proyectarXY`) y los ejes del suelo que en pantalla son
-- derecha y abajo.
function AnilloHolo:anadir(marcas, x, y, escala, clase, vida, edad)
    local corona = AnilloHolo.corona[clase]
    local dentro = corona[1]
    local fuera = corona[2]
    local numero = clase == 'destino' and 1 or 0
    local dx, dy = marcas.derechaX, marcas.derechaY
    local bx, by = marcas.abajoX, marcas.abajoY
    -- Tamaño en pantalla: cuántos sectores hacen falta y si se ve.
    local ox, oy = marcas:proyectarXY(x, y)
    if not ox then
        return
    end
    local rx, ry = marcas:proyectarXY(x + dx * fuera * escala, y + dy * fuera * escala)
    if not rx then
        return
    end
    local radio = math.sqrt((rx - ox) ^ 2 + (ry - oy) ^ 2)
    if ox + radio < 0 or oy + radio < 0 or ox - radio > marcas.ancho or oy - radio > marcas.alto then
        return
    end
    local sectores = math.ceil(radio / AnilloHolo.pxPorSector)
    sectores = math.max(AnilloHolo.sectoresMinimos, math.min(AnilloHolo.sectores, sectores))
    local ax0, ay0, ax1, ay1, angulo0, aw0, aw1
    for k = 0, sectores do
        local angulo = k / sectores * math.pi * 2
        local c = math.cos(angulo) * escala
        local s = math.sin(angulo) * escala
        local ex = c * dx + s * bx
        local ey = c * dy + s * by
        local px0, py0, _, pw0 = marcas:proyectarXY(x + ex * dentro, y + ey * dentro)
        local px1, py1, _, pw1 = marcas:proyectarXY(x + ex * fuera, y + ey * fuera)
        if not (px0 and px1) then
            px0 = nil
        end
        if ax0 and px0 then
            self:vertice(ax0, ay0, angulo0, dentro, vida, edad, numero, aw0)
            self:vertice(ax1, ay1, angulo0, fuera, vida, edad, numero, aw1)
            self:vertice(px0, py0, angulo, dentro, vida, edad, numero, pw0)
            self:vertice(ax1, ay1, angulo0, fuera, vida, edad, numero, aw1)
            self:vertice(px1, py1, angulo, fuera, vida, edad, numero, pw1)
            self:vertice(px0, py0, angulo, dentro, vida, edad, numero, pw0)
        end
        ax0, ay0, ax1, ay1, angulo0, aw0, aw1 = px0, py0, px1, py1, angulo, pw0, pw1
    end
end

--- Dibuja los anillos del cuadro. `t`: reloj en segundos; `ui`: grosor
-- de las líneas; `colores`: menta, amarillo y rojo.
function AnilloHolo:dibujar(t, ui, colores, profundidad)
    local n = self.cuantos
    if n == 0 then
        return
    end
    local g = love.graphics
    local shader = self.shader
    shader:send('ui', ui)
    shader:send('giro', (t * 1.2) % (math.pi * 2))
    shader:send('pulso', (t * 0.9) % 1)
    shader:send('menta', colores.menta)
    shader:send('amarillo', colores.amarillo)
    shader:send('rojo', colores.rojo)
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

return AnilloHolo
