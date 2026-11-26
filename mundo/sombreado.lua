-- Color y luz del suelo en la GPU.
--
-- La malla del suelo solo lleva, por vértice, su punto del mundo (x, y), su
-- altura y su pendiente (nx, ny). El sombreador de vértices hace lo mismo que
-- hacía `Terreno:color` en Lua: agua, arena, pradera seca, verde o bosque
-- según la humedad, manchas de pasto, roca en lo alto y en las laderas, nieve
-- en las cumbres, y la luz de la tarde según la ladera. La humedad y las
-- manchas son el mismo ruido simplex (las mismas tablas de permutación de la
-- semilla, en una textura), así que el mapa se ve igual que antes.
--
-- También proyecta el vértice a la vista isométrica 2:1 (`Iso.vista`): el
-- agua, plana a su nivel.

local Terreno = require('mundo.terreno')
local Iso = require('mundo.iso')

local Sombreado = {}

local CODIGO = [[
#pragma language glsl3

uniform Image permutaciones; // fila 0: humedad, fila 1: detalle
uniform float escalaAltura;
uniform vec3 luzTarde;
uniform vec3 cHondo, cAgua, cArena, cSeca, cPradera, cBosque, cRoca, cNieve;
// Capas del mapa (mundo/capas.lua): `liso` quita las manchas y vetas (capa
// media); `estrategico` lleva al terreno oscuro con relieve (capa lejana).
uniform float liso;
uniform float estrategico;

varying vec3 colorSuelo;
// Para el color por píxel (capas media y lejana): punto del mundo, altura y
// pendiente interpoladas; así la costa sale lisa también en la malla sencilla.
varying vec2 vMundo;
varying vec3 vSuelo;

const vec2 GRADIENTES[8] = vec2[8](
    vec2(1.0, 1.0), vec2(-1.0, 1.0), vec2(1.0, -1.0), vec2(-1.0, -1.0),
    vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0)
);
const float F2 = 0.36602540378443865;
const float G2 = 0.21132486540518713;

float perm(float k, int fila) {
    int i = int(mod(k, 256.0));
    return floor(texelFetch(permutaciones, ivec2(i, fila), 0).r * 255.0 + 0.5);
}

float esquina(vec2 g, float px, float py) {
    float tt = max(0.0, 0.5 - px * px - py * py);
    tt = tt * tt;
    return tt * tt * (g.x * px + g.y * py);
}

// El mismo simplex que `Ruido:simplex`.
float simplex(float x, float y, int fila) {
    float s = (x + y) * F2;
    float i = floor(x + s);
    float j = floor(y + s);
    float t = (i + j) * G2;
    float x0 = x - (i - t);
    float y0 = y - (j - t);
    float i1 = 0.0;
    float j1 = 1.0;
    if (x0 > y0) {
        i1 = 1.0;
        j1 = 0.0;
    }
    float x1 = x0 - i1 + G2;
    float y1 = y0 - j1 + G2;
    float x2 = x0 - 1.0 + 2.0 * G2;
    float y2 = y0 - 1.0 + 2.0 * G2;
    float ii = mod(i, 256.0);
    float jj = mod(j, 256.0);
    int g0 = int(mod(perm(ii + perm(jj, fila), fila), 8.0));
    int g1 = int(mod(perm(ii + i1 + perm(jj + j1, fila), fila), 8.0));
    int g2 = int(mod(perm(ii + 1.0 + perm(jj + 1.0, fila), fila), 8.0));
    float total = esquina(GRADIENTES[g0], x0, y0) + esquina(GRADIENTES[g1], x1, y1)
        + esquina(GRADIENTES[g2], x2, y2);
    return 70.0 * total;
}

vec3 mezcla(vec3 a, vec3 b, float t) {
    return mix(a, b, clamp(t, 0.0, 1.0));
}

// Color y luz del suelo en un punto (lo que hacía `Terreno:color`), con las
// capas `liso` y `estrategico`.
vec3 colorDe(float x, float y, float h, float nx, float ny) {
    vec3 color;
    float luz;
    if (h < 0.0) {
        color = mezcla(cAgua, cHondo, -h / 90.0);
        luz = 0.95 + 0.1 * max(0.0, 1.0 + h / 40.0);
    } else {
        float pendiente = sqrt(nx * nx + ny * ny);
        if (h < 7.0) {
            color = cArena;
        } else {
            // `Terreno:humedadEn`: fbm de 3 octavas a escala 3000.
            float hx = x / 3000.0;
            float hy = y / 3000.0;
            float humedad = (simplex(hx, hy, 0) + 0.5 * simplex(hx * 2.0, hy * 2.0, 0)
                + 0.25 * simplex(hx * 4.0, hy * 4.0, 0)) / 1.75;
            vec3 verde = mezcla(cSeca, cPradera, (humedad + 0.55) * 2.5);
            verde = mezcla(verde, cBosque, (humedad - 0.15) * 3.0);
            float m = simplex(x / 200.0 + 11.0, y / 200.0, 1) * (1.0 - liso);
            float k = 1.0 + m * 0.11;
            verde = vec3(verde.r * k, verde.g * (1.0 + m * 0.07), verde.b * k);
            float roca = max((h - 140.0) / 60.0, h > 110.0 ? (pendiente - 0.3) / 0.35 : 0.0);
            vec3 piedra = cRoca;
            if (roca > 0.0) {
                float v = 1.0 + simplex(x / 170.0, y / 170.0 + 30.0, 1) * 0.16 * (1.0 - liso);
                piedra = vec3(piedra.r * v, piedra.g * v, piedra.b * v * 1.03);
            }
            color = mezcla(verde, piedra, roca);
            color = mezcla(color, cNieve, (h - 900.0) / 100.0);
        }
        float l = sqrt(nx * nx + ny * ny + 1.0);
        luz = 0.5 + 0.62 * max(0.0, (nx * luzTarde.x + ny * luzTarde.y + luzTarde.z) / l);
    }
    vec3 resultado = color * luz;
    if (estrategico > 0.0) {
        // Mapa estratégico: tierra oscura, gris en lo alto, con el relieve
        // marcado (la pendiente cuenta el triple); agua azul pizarra.
        vec3 oscuro;
        if (h < 0.0) {
            oscuro = mezcla(vec3(0.17, 0.22, 0.25), vec3(0.09, 0.12, 0.15), -h / 90.0);
        } else {
            vec3 tierra = mezcla(vec3(0.26, 0.28, 0.22), vec3(0.45, 0.44, 0.40), (h - 120.0) / 250.0);
            tierra = mezcla(vec3(0.36, 0.36, 0.30), tierra, h / 10.0);
            float rx = nx * 3.0;
            float ry = ny * 3.0;
            float lr = sqrt(rx * rx + ry * ry + 1.0);
            float relieve = 0.35 + 0.95 * max(0.0, (rx * luzTarde.x + ry * luzTarde.y + luzTarde.z) / lr);
            oscuro = tierra * relieve;
        }
        resultado = mix(resultado, oscuro, estrategico);
    }
    return resultado;
}

#ifdef VERTEX
attribute vec3 Suelo; // altura, nx, ny

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    float x = vertex_position.x;
    float y = vertex_position.y;
    float h = Suelo.x;
    vMundo = vec2(x, y);
    vSuelo = Suelo;
    colorSuelo = liso < 1.0 ? colorDe(x, y, h, Suelo.y, Suelo.z) : vec3(0.0);
    float visible = max(h, 0.0);
    vec4 vista = vec4(x - y, (x + y) * 0.5 - visible * escalaAltura, 0.0, 1.0);
    return transform_projection * vista;
}
#endif

#ifdef PIXEL
vec4 effect(vec4 color, Image textura, vec2 coordenada, vec2 pantalla) {
    // Como el color de vértice de antes: en bytes (se satura en 1).
    vec3 c = colorSuelo;
    if (liso > 0.0) {
        vec3 p = colorDe(vMundo.x, vMundo.y, vSuelo.x, vSuelo.y, vSuelo.z);
        c = liso < 1.0 ? mix(c, p, liso) : p;
    }
    return vec4(clamp(c, 0.0, 1.0), 1.0) * color;
}
#endif
]]

--- Formato de los vértices del suelo: punto del mundo y (altura, nx, ny).
Sombreado.formato = {
    { 'VertexPosition', 'float', 2 },
    { 'Suelo', 'float', 3 },
}

local sombreador

--- El sombreador del suelo, listo para la semilla del `terreno`.
function Sombreado.para(terreno)
    if not sombreador then
        sombreador = love.graphics.newShader(CODIGO)
        local l = Terreno.luz
        sombreador:send('luzTarde', { l[1], l[2], l[3] })
        sombreador:send('escalaAltura', Iso.escalaAltura)
        local c = Terreno.colores
        sombreador:send('cHondo', c.hondo)
        sombreador:send('cAgua', c.agua)
        sombreador:send('cArena', c.arena)
        sombreador:send('cSeca', c.seca)
        sombreador:send('cPradera', c.pradera)
        sombreador:send('cBosque', c.bosque)
        sombreador:send('cRoca', c.roca)
        sombreador:send('cNieve', c.nieve)
        Sombreado.capas(0, 0)
    end
    if Sombreado.semilla ~= terreno.semilla then
        Sombreado.semilla = terreno.semilla
        local datos = love.image.newImageData(256, 2)
        for i = 0, 255 do
            datos:setPixel(i, 0, terreno.humedad.perm[i] / 255, 0, 0, 1)
            datos:setPixel(i, 1, terreno.detalle.perm[i] / 255, 0, 0, 1)
        end
        local imagen = love.graphics.newImage(datos)
        imagen:setFilter('nearest', 'nearest')
        sombreador:send('permutaciones', imagen)
        Sombreado.imagen = imagen
    end
    return sombreador
end

--- Capas del mapa: `liso` (0 a 1) quita manchas y vetas del suelo;
-- `estrategico` (0 a 1) lo lleva al mapa estratégico oscuro.
function Sombreado.capas(liso, estrategico)
    if sombreador and (Sombreado.liso ~= liso or Sombreado.estrategico ~= estrategico) then
        Sombreado.liso, Sombreado.estrategico = liso, estrategico
        sombreador:send('liso', liso)
        sombreador:send('estrategico', estrategico)
    end
end

return Sombreado
