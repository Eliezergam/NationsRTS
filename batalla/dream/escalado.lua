-- Escalado con nitidez de la batalla 3D: AMD FidelityFX Super Resolution 1
-- (FSR 1.0.2), como en los juegos grandes. La escena, el AA temporal y la
-- curva tonal se hacen a menos resolución (`Calidad.escalaRender`, p. ej.
-- 0,77 = el modo «Ultra Quality» de AMD) y aquí se sube a la de la pantalla
-- en dos pases (el dueño, 19-nov: «todo lo que puedas, pásalo a la tarjeta»;
-- la tarjeta iba llena, a 10,4 ms de 10,7 por cuadro):
--
-- 1. EASU (Edge Adaptive Spatial Upsampling): 12 lecturas por píxel, mira
--    hacia dónde va el borde y estira un núcleo tipo Lanczos a lo largo de
--    él: los bordes quedan limpios, sin la escalera ni el borrón del
--    bilineal.
-- 2. RCAS (Robust Contrast Adaptive Sharpening): afila con una cruz de 5
--    lecturas, limitado por los vecinos (sin halos) y con menos afilado
--    donde hay ruido.
--
-- Trabajan sobre el color ya con la curva y la gamma (en 8 bits, como pide
-- AMD: el espacio perceptual). Portado de ffx_fsr1.h (MIT, Advanced Micro
-- Devices, 2021) a partir de la versión GLSL de agyild para mpv; aquí en RGB:
-- la dirección del borde sale del brillo (r/2 + g + b/2, como en el original)
-- y se filtran los tres canales.

local Escalado = {}
Escalado.__index = Escalado

-- Afilado de RCAS en «paradas»: 0 es el máximo; cada 1 lo reduce a la mitad.
Escalado.nitidez = 0.25

local LICENCIA = [[
#pragma language glsl3
// FidelityFX Super Resolution 1.0.2. Copyright (c) 2021 Advanced Micro Devices, Inc.
// Licencia MIT: se permite usar, copiar, modificar y distribuir con este aviso.
]]

local EASU = LICENCIA
    .. [[
uniform vec2 tamFuente;

float rcpLo(float a) { return uintBitsToFloat(uint(0x7ef07ebb) - floatBitsToUint(a)); }
float rsqLo(float a) { return uintBitsToFloat(uint(0x5f347d74) - (floatBitsToUint(a) >> uint(1))); }
float brillo(vec3 c) { return c.b * 0.5 + (c.r * 0.5 + c.g); }

void toma(inout vec3 aC, inout float aW, vec2 off, vec2 dir, vec2 len, float lob, float clp, vec3 c) {
    vec2 v;
    v.x = off.x * dir.x + off.y * dir.y;
    v.y = off.x * (-dir.y) + off.y * dir.x;
    v *= len;
    float d2 = min(v.x * v.x + v.y * v.y, clp);
    float wB = 0.4 * d2 - 1.0;
    float wA = lob * d2 - 1.0;
    wB *= wB;
    wA *= wA;
    wB = 1.5625 * wB - 0.5625;
    float w = wB * wA;
    aC += c * w;
    aW += w;
}

void direccion(inout vec2 dir, inout float len, float w, float lA, float lB, float lC, float lD, float lE) {
    float dc = lD - lC;
    float cb = lC - lB;
    float lenX = max(abs(dc), abs(cb));
    lenX = rcpLo(lenX);
    float dirX = lD - lB;
    lenX = clamp(abs(dirX) * lenX, 0.0, 1.0);
    lenX *= lenX;
    float ec = lE - lC;
    float ca = lC - lA;
    float lenY = max(abs(ec), abs(ca));
    lenY = rcpLo(lenY);
    float dirY = lE - lA;
    lenY = clamp(abs(dirY) * lenY, 0.0, 1.0);
    lenY *= lenY;
    dir += vec2(dirX, dirY) * w;
    len += (lenX + lenY) * w;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 pt = 1.0 / tamFuente;
    vec2 pp = tc * tamFuente - vec2(0.5);
    vec2 fp = floor(pp);
    pp -= fp;
    //    b c
    //  e f g h
    //  i j k l
    //    n o
    vec3 b = Texel(tex, (fp + vec2(0.5, -0.5)) * pt).rgb;
    vec3 c = Texel(tex, (fp + vec2(1.5, -0.5)) * pt).rgb;
    vec3 e = Texel(tex, (fp + vec2(-0.5, 0.5)) * pt).rgb;
    vec3 f = Texel(tex, (fp + vec2(0.5, 0.5)) * pt).rgb;
    vec3 g = Texel(tex, (fp + vec2(1.5, 0.5)) * pt).rgb;
    vec3 h = Texel(tex, (fp + vec2(2.5, 0.5)) * pt).rgb;
    vec3 i = Texel(tex, (fp + vec2(-0.5, 1.5)) * pt).rgb;
    vec3 j = Texel(tex, (fp + vec2(0.5, 1.5)) * pt).rgb;
    vec3 k = Texel(tex, (fp + vec2(1.5, 1.5)) * pt).rgb;
    vec3 l = Texel(tex, (fp + vec2(2.5, 1.5)) * pt).rgb;
    vec3 n = Texel(tex, (fp + vec2(0.5, 2.5)) * pt).rgb;
    vec3 o = Texel(tex, (fp + vec2(1.5, 2.5)) * pt).rgb;
    float bL = brillo(b), cL = brillo(c), eL = brillo(e), fL = brillo(f), gL = brillo(g), hL = brillo(h);
    float iL = brillo(i), jL = brillo(j), kL = brillo(k), lL = brillo(l), nL = brillo(n), oL = brillo(o);

    vec2 dir = vec2(0.0);
    float len = 0.0;
    direccion(dir, len, (1.0 - pp.x) * (1.0 - pp.y), bL, eL, fL, gL, jL);
    direccion(dir, len, pp.x * (1.0 - pp.y), cL, fL, gL, hL, kL);
    direccion(dir, len, (1.0 - pp.x) * pp.y, fL, iL, jL, kL, nL);
    direccion(dir, len, pp.x * pp.y, gL, jL, kL, lL, oL);

    vec2 dir2 = dir * dir;
    float dirR = dir2.x + dir2.y;
    bool cero = dirR < (1.0 / 32768.0);
    dirR = rsqLo(dirR);
    dirR = cero ? 1.0 : dirR;
    dir.x = cero ? 1.0 : dir.x;
    dir *= vec2(dirR);
    len = len * 0.5;
    len *= len;
    float estira = (dir.x * dir.x + dir.y * dir.y) * rcpLo(max(abs(dir.x), abs(dir.y)));
    vec2 len2 = vec2(1.0 + (estira - 1.0) * len, 1.0 - 0.5 * len);
    float lob = 0.5 + ((1.0 / 4.0 - 0.04) - 0.5) * len;
    float clp = rcpLo(lob);

    vec3 aC = vec3(0.0);
    float aW = 0.0;
    toma(aC, aW, vec2(0.0, -1.0) - pp, dir, len2, lob, clp, b);
    toma(aC, aW, vec2(1.0, -1.0) - pp, dir, len2, lob, clp, c);
    toma(aC, aW, vec2(-1.0, 1.0) - pp, dir, len2, lob, clp, i);
    toma(aC, aW, vec2(0.0, 1.0) - pp, dir, len2, lob, clp, j);
    toma(aC, aW, vec2(0.0, 0.0) - pp, dir, len2, lob, clp, f);
    toma(aC, aW, vec2(-1.0, 0.0) - pp, dir, len2, lob, clp, e);
    toma(aC, aW, vec2(1.0, 1.0) - pp, dir, len2, lob, clp, k);
    toma(aC, aW, vec2(2.0, 1.0) - pp, dir, len2, lob, clp, l);
    toma(aC, aW, vec2(2.0, 0.0) - pp, dir, len2, lob, clp, h);
    toma(aC, aW, vec2(1.0, 0.0) - pp, dir, len2, lob, clp, g);
    toma(aC, aW, vec2(1.0, 2.0) - pp, dir, len2, lob, clp, o);
    toma(aC, aW, vec2(0.0, 2.0) - pp, dir, len2, lob, clp, n);

    // Sin anillos: dentro del rango de los cuatro texels de alrededor.
    vec3 mn = min(min(f, g), min(j, k));
    vec3 mx = max(max(f, g), max(j, k));
    vec3 resultado = clamp(aC / aW, mn, mx);
    return vec4(clamp(resultado, 0.0, 1.0), 1.0);
}
]]

local RCAS = LICENCIA
    .. [[
uniform vec2 texel;
uniform float nitidez;
#define LIMITE (0.25 - (1.0 / 16.0))

float brillo(vec3 c) { return c.b * 0.5 + (c.r * 0.5 + c.g); }

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    //    b
    //  d e f
    //    h
    vec3 b = Texel(tex, tc + vec2(0.0, -texel.y)).rgb;
    vec3 d = Texel(tex, tc + vec2(-texel.x, 0.0)).rgb;
    vec3 e = Texel(tex, tc).rgb;
    vec3 f = Texel(tex, tc + vec2(texel.x, 0.0)).rgb;
    vec3 h = Texel(tex, tc + vec2(0.0, texel.y)).rgb;
    vec3 mn = min(min(b, d), min(f, h));
    vec3 mx = max(max(b, d), max(f, h));
    // Hasta dónde se puede afilar sin salirse del rango de los vecinos.
    vec3 hitMin = min(mn, e) / (4.0 * mx + 1e-5);
    vec3 hitMax = (1.0 - max(mx, e)) / (4.0 * mn - 4.0 - 1e-5);
    vec3 lobeRGB = max(-hitMin, hitMax);
    float lobe = max(-LIMITE, min(max(lobeRGB.r, max(lobeRGB.g, lobeRGB.b)), 0.0)) * exp2(-nitidez);
    // Menos afilado donde hay ruido.
    float bL = brillo(b), dL = brillo(d), eL = brillo(e), fL = brillo(f), hL = brillo(h);
    float nz = 0.25 * (bL + dL + fL + hL) - eL;
    float rango = max(max(max(bL, dL), max(eL, fL)), hL) - min(min(min(bL, dL), min(eL, fL)), hL);
    nz = clamp(abs(nz) / max(rango, 1e-5), 0.0, 1.0);
    lobe *= 1.0 - 0.5 * nz;
    vec3 resultado = (lobe * (b + d + f + h) + e) / (4.0 * lobe + 1.0);
    return vec4(clamp(resultado, 0.0, 1.0), 1.0);
}
]]

--- Parte de la pantalla a la que se dibuja la escena con `calidad` (la
-- elegida si no se da). `BATALLA_ESCALA=<0..1>` la cambia en todas las
-- escenas, para comparar (1 = sin escalado).
function Escalado.escala(calidad)
    calidad = calidad or require('batalla.dream.calidad').actual()
    return tonumber(os.getenv('BATALLA_ESCALA') or '') or calidad.escalaRender or 1
end

--- Pone los lienzos de 3Dream a `escala` de la pantalla; devuelve su tamaño.
function Escalado.ajustar(dream, escala)
    local ancho, alto = love.graphics.getDimensions()
    ancho, alto = math.floor(ancho * escala + 0.5), math.floor(alto * escala + 0.5)
    if dream.canvases.width ~= ancho or dream.canvases.height ~= alto then
        dream:resize(ancho, alto)
    end
    return ancho, alto
end

-- Uno para todas las escenas (batalla, almacén, campaña): sus lienzos se
-- reutilizan al pasar de una a otra.
local compartido

function Escalado.compartido()
    compartido = compartido or Escalado.nuevo()
    return compartido
end

--- `dream:present()` para las escenas sin curva tonal propia (el almacén):
-- a `escala` y subido con FSR al lienzo que hubiera.
function Escalado.presentar(dream, escala)
    escala = escala or Escalado.escala()
    local ancho, alto = Escalado.ajustar(dream, escala)
    if escala >= 1 then
        dream:present()
        return
    end
    local escalado = Escalado.compartido()
    local antes = love.graphics.getCanvas()
    love.graphics.setCanvas(escalado:entrada(ancho, alto))
    love.graphics.clear(0, 0, 0, 1)
    dream:present()
    escalado:subir(antes)
    love.graphics.setCanvas(antes)
end

function Escalado.nuevo()
    local self = setmetatable({}, Escalado)
    self.easu = love.graphics.newShader(EASU)
    self.rcas = love.graphics.newShader(RCAS)
    return self
end

local function lienzo(actual, ancho, alto)
    if actual and actual:getPixelWidth() == ancho and actual:getPixelHeight() == alto then
        return actual
    end
    if actual then
        actual:release()
    end
    local nuevo = love.graphics.newCanvas(ancho, alto, { format = 'rgba8', dpiscale = 1 })
    nuevo:setFilter('nearest', 'nearest')
    return nuevo
end

--- Lienzo donde la curva tonal deja la imagen pequeña (ancho × alto px).
function Escalado:entrada(ancho, alto)
    self.pequeno = lienzo(self.pequeno, ancho, alto)
    return self.pequeno
end

--- Sube el lienzo de entrada a `destino` (o a la pantalla) con EASU + RCAS.
function Escalado:subir(destino)
    local fuente = self.pequeno
    local ancho, alto = love.graphics.getPixelDimensions()
    self.grande = lienzo(self.grande, ancho, alto)
    love.graphics.push('all')
    love.graphics.origin()
    love.graphics.setBlendMode('replace', 'premultiplied')
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setCanvas(self.grande)
    love.graphics.setShader(self.easu)
    self.easu:send('tamFuente', { fuente:getPixelWidth(), fuente:getPixelHeight() })
    love.graphics.draw(fuente, 0, 0, 0, ancho / fuente:getPixelWidth(), alto / fuente:getPixelHeight())
    love.graphics.setCanvas(destino)
    love.graphics.setShader(self.rcas)
    self.rcas:send('texel', { 1 / ancho, 1 / alto })
    self.rcas:send('nitidez', Escalado.nitidez)
    love.graphics.draw(self.grande, 0, 0, 0, love.graphics.getWidth() / ancho)
    love.graphics.pop()
end

return Escalado
