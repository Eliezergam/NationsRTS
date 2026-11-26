-- Mapeo tonal de la batalla 3D (Valeria). 3DreamEngine no tiene uno: su
-- `setExposure` es 1 - e^(-x), que aplana los medios, y sin él la imagen salía
-- sin negros (ningún píxel por debajo de 20/255) y con el blanco recortado.
--
-- La escena se dibuja en un lienzo rgba16f (`Tono:empezar`, guarda valores por
-- encima de 1) y `Tono:terminar` lo pasa a la pantalla con la exposición y la
-- curva fílmica de Unreal Engine (FilmToneMap de TonemapCommon.ush, la que da
-- su aspecto por defecto), con los parámetros de la referencia que se sacó en
-- Unreal 5.8 con nuestros modelos: pendiente 0,88, pie 0,55, hombro 0,26,
-- recorte de negro 0 y de blanco 0,04. Trabaja como Unreal en los primarios
-- AP1 (ACEScg), con su desaturación antes (0,96) y después (0,93) de la curva.
-- 0,18 sale 0,18; 0,05 sale 0,025 (sombras hondas) y 1 sale 0,72 (las luces
-- no se queman). Sin nitidez añadida, salvo con el AA temporal en calidad
-- alta (`Tono.afilado`): el afilado suave de TSR/TAA de Unreal, limitado a
-- los valores de los cuatro vecinos (no hace halos).
--
-- 3Dream entrega el color con su gamma (x^(1/2,2)); aquí se pasa a lineal y se
-- vuelve a codificar al final. Cuesta un pase de pantalla completa con una
-- lectura por píxel.

local Tono = {}
Tono.__index = Tono

-- Multiplica la luz antes de la curva. La referencia de Unreal deja la hierba
-- al sol a ~185/255 (exposición 3,2), pero con nuestra paleta, más clara en
-- lo seco, la curva comprime los claros y la imagen sale pastel. Con 1,8 y la
-- luz de cielo anterior (un 33 % de la del suelo) la imagen media quedaba a
-- ~125/255; con la luz del cielo física (un 13 %) hace falta 2,4 para el
-- mismo brillo.
-- Campo de batalla hostil y apagado (el dueño, 17-nov: «no quiero tanta
-- claridad, que se sienta el campo de batalla hostil, apagado»): antes 2,4.
Tono.exposicion = 1.7
-- Saturación tras la curva (1 = la de antes; menos, colores más apagados).
Tono.saturacion = 0.72

-- Exposición por la luz que llega (Valeria, con la atmósfera física de
-- batalla/dream/atmosfera.lua): como un fotómetro de luz incidente, la
-- exposición sube cuando baja la iluminancia del suelo horizontal (el sol y
-- la luna directos más el cielo) respecto a la de referencia, la del sol a
-- 49,5° de la referencia de Unreal (`Tono.luzReferencia`). Con el exponente
-- 0,75 la adaptación es parcial: el atardecer sigue algo más oscuro que el
-- mediodía, y el factor queda entre `Tono.factorMin` y `Tono.factorMax`.
-- La exposición automática por histograma es la Fase 4 del plan
-- (batalla/dream/PLAN-RENDER-UE.md).
Tono.luzReferencia = 3.4
Tono.adaptacion = 0.75
Tono.factorMin = 0.6
Tono.factorMax = 2.5
-- De noche no se compensa (la noche se ve de noche): batalla/dream/luz.lua
-- baja el tope hasta `Tono.factorNoche` según lo hundido que esté el sol.
Tono.factorNoche = 1
Tono.noche = 0
-- Los pone batalla/dream/luz.lua: la irradiancia del cielo (lienzo de 1 x 1)
-- y la luz directa sobre el suelo horizontal.
Tono.luzCielo = nil
Tono.luzDirecta = nil

Tono.pendiente = 0.88
Tono.pie = 0.55
Tono.hombro = 0.26
Tono.recorteNegro = 0
Tono.recorteBlanco = 0.04
-- Afilado tras el AA temporal (0 = nada); lo pone batalla/dream/escena.lua
-- según la calidad (batalla/dream/calidad.lua: `afilado`).
Tono.afilado = 0

--- Constantes de la curva (las de FilmToneMap) para el sombreador.
local function constantes()
    local pendiente, pie, hombro = Tono.pendiente, Tono.pie, Tono.hombro
    local negro, blanco = Tono.recorteNegro, Tono.recorteBlanco
    local escalaPie = 1 + negro - pie
    local escalaHombro = 1 + blanco - hombro
    local entrada, salida = 0.18, 0.18
    local encajePie
    if pie > 0.8 then
        encajePie = (1 - pie - salida) / pendiente + math.log10(entrada)
    else
        local bt = (salida + negro) / escalaPie - 1
        encajePie = math.log10(entrada) - 0.5 * math.log((1 + bt) / (1 - bt)) * (escalaPie / pendiente)
    end
    local encajeRecta = (1 - pie) / pendiente - encajePie
    local encajeHombro = hombro / pendiente - encajeRecta
    return string.format(
        [[
const float PENDIENTE = %.6f;
const float NEGRO = %.6f;
const float BLANCO = %.6f;
const float ESCALA_PIE = %.6f;
const float ESCALA_HOMBRO = %.6f;
const float ENCAJE_PIE = %.6f;
const float ENCAJE_RECTA = %.6f;
const float ENCAJE_HOMBRO = %.6f;
]],
        pendiente,
        negro,
        blanco,
        escalaPie,
        escalaHombro,
        encajePie,
        encajeRecta,
        encajeHombro
    )
end

local codigo = [[
uniform float exposicion;
uniform float saturacion;
#ifdef AFILADO
uniform float afilado;
uniform vec2 texelAfilado;
#endif
#ifdef LUZ_INCIDENTE
uniform Image luzCielo;
uniform float luzDirecta;
uniform vec4 medidor; // referencia, adaptación, factor mínimo y máximo
#endif

// sRGB lineal (D65) a AP1 (D60, adaptación de Bradford) y vuelta, por filas.
const vec3 A_AP1_R = vec3(0.613097, 0.339523, 0.047379);
const vec3 A_AP1_G = vec3(0.070194, 0.916354, 0.013452);
const vec3 A_AP1_B = vec3(0.020616, 0.109570, 0.869815);
const vec3 A_SRGB_R = vec3(1.704859, -0.621716, -0.083299);
const vec3 A_SRGB_G = vec3(-0.130077, 1.140735, -0.010560);
const vec3 A_SRGB_B = vec3(-0.023964, -0.128975, 1.153014);
const vec3 LUMA_AP1 = vec3(0.272229, 0.674082, 0.053690);

float elegir(bool condicion, float si, float no) {
    return condicion ? si : no;
}

vec3 curvaFilmica(vec3 color) {
    vec3 c = max(color, vec3(0.0));
    c = max(mix(vec3(dot(c, LUMA_AP1)), c, 0.96), vec3(1e-10));
    vec3 l = log(c) / log(10.0);
    vec3 recta = PENDIENTE * (l + ENCAJE_RECTA);
    vec3 pie = -NEGRO + (2.0 * ESCALA_PIE) / (1.0 + exp((-2.0 * PENDIENTE / ESCALA_PIE) * (l - ENCAJE_PIE)));
    vec3 hombro = (1.0 + BLANCO) - (2.0 * ESCALA_HOMBRO) / (1.0 + exp((2.0 * PENDIENTE / ESCALA_HOMBRO) * (l - ENCAJE_HOMBRO)));
    pie = vec3(
        elegir(l.x < ENCAJE_PIE, pie.x, recta.x),
        elegir(l.y < ENCAJE_PIE, pie.y, recta.y),
        elegir(l.z < ENCAJE_PIE, pie.z, recta.z)
    );
    hombro = vec3(
        elegir(l.x > ENCAJE_HOMBRO, hombro.x, recta.x),
        elegir(l.y > ENCAJE_HOMBRO, hombro.y, recta.y),
        elegir(l.z > ENCAJE_HOMBRO, hombro.z, recta.z)
    );
    vec3 t = clamp((l - ENCAJE_PIE) / (ENCAJE_HOMBRO - ENCAJE_PIE), 0.0, 1.0);
    if (ENCAJE_HOMBRO < ENCAJE_PIE) {
        t = 1.0 - t;
    }
    t = (3.0 - 2.0 * t) * t * t;
    vec3 tono = mix(pie, hombro, t);
    tono = mix(vec3(dot(tono, LUMA_AP1)), tono, 0.93);
    return max(tono, vec3(0.0));
}

vec4 effect(vec4 color, Image lienzo, vec2 uv, vec2 sc) {
    vec3 c = Texel(lienzo, uv).rgb;
#ifdef AFILADO
    {
        // Afilado de cruz limitado a los vecinos, con la gamma de 3Dream.
        vec3 n = Texel(lienzo, uv - vec2(0.0, texelAfilado.y)).rgb;
        vec3 s = Texel(lienzo, uv + vec2(0.0, texelAfilado.y)).rgb;
        vec3 o = Texel(lienzo, uv - vec2(texelAfilado.x, 0.0)).rgb;
        vec3 e = Texel(lienzo, uv + vec2(texelAfilado.x, 0.0)).rgb;
        vec3 mn = min(c, min(min(n, s), min(o, e)));
        vec3 mx = max(c, max(max(n, s), max(o, e)));
        c = clamp(c + (c * 4.0 - n - s - o - e) * (afilado * 0.25), mn, mx);
    }
#endif
    float e = exposicion;
#ifdef LUZ_INCIDENTE
    float luz = luzDirecta + dot(Texel(luzCielo, vec2(0.5)).rgb, vec3(0.2126, 0.7152, 0.0722));
    e *= clamp(pow(medidor.x / max(luz, 1e-5), medidor.y), medidor.z, medidor.w);
#endif
    vec3 lineal = pow(max(c, vec3(0.0)), vec3(2.2)) * e;
    vec3 ap1 = vec3(dot(A_AP1_R, lineal), dot(A_AP1_G, lineal), dot(A_AP1_B, lineal));
    vec3 tono = curvaFilmica(ap1);
    vec3 srgb = vec3(dot(A_SRGB_R, tono), dot(A_SRGB_G, tono), dot(A_SRGB_B, tono));
    srgb = mix(vec3(dot(srgb, vec3(0.2126, 0.7152, 0.0722))), srgb, saturacion);
    return vec4(pow(clamp(srgb, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0) * color;
}
]]

function Tono.nuevo()
    local self = setmetatable({}, Tono)
    self.sombreador = love.graphics.newShader(constantes() .. codigo)
    self.sombreadorMedidor = love.graphics.newShader('#define LUZ_INCIDENTE\n' .. constantes() .. codigo)
    self.sombreadorAfilado = love.graphics.newShader('#define AFILADO\n' .. constantes() .. codigo)
    self.sombreadorMedidorAfilado =
        love.graphics.newShader('#define AFILADO\n#define LUZ_INCIDENTE\n' .. constantes() .. codigo)
    local formatos = love.graphics.getCanvasFormats()
    self.formato = formatos.rgba16f and 'rgba16f' or 'rgba8'
    return self
end

--- Desde aquí, lo que se dibuje va al lienzo del tono (del tamaño de la
-- ventana, o de `ancho` × `alto` px si la escena se dibuja más pequeña).
function Tono:empezar(ancho, alto)
    if not ancho then
        ancho, alto = love.graphics.getPixelDimensions()
    end
    local lienzo = self.lienzo
    if not lienzo or lienzo:getPixelWidth() ~= ancho or lienzo:getPixelHeight() ~= alto then
        if lienzo then
            lienzo:release()
        end
        self.lienzo = love.graphics.newCanvas(ancho, alto, { format = self.formato, dpiscale = 1 })
    end
    self.anterior = love.graphics.getCanvas()
    love.graphics.setCanvas(self.lienzo)
    love.graphics.clear(0, 0, 0, 1)
end

--- Pasa el lienzo (o `fuente`, del mismo tamaño: la imagen del AA temporal)
-- a la pantalla (o al lienzo que hubiera antes, o a `destino`: el del
-- escalado, del tamaño de la fuente) con la exposición y la curva.
function Tono:terminar(fuente, destino)
    love.graphics.setCanvas(destino or self.anterior)
    fuente = fuente or self.lienzo
    love.graphics.push('all')
    love.graphics.origin()
    love.graphics.setBlendMode('replace', 'premultiplied')
    local afilar = Tono.afilado > 0
    local sombreador
    if Tono.luzCielo then
        sombreador = afilar and self.sombreadorMedidorAfilado or self.sombreadorMedidor
    else
        sombreador = afilar and self.sombreadorAfilado or self.sombreador
    end
    if afilar then
        sombreador:send('afilado', Tono.afilado)
        sombreador:send('texelAfilado', { 1 / fuente:getPixelWidth(), 1 / fuente:getPixelHeight() })
    end
    if Tono.luzCielo then
        sombreador:send('luzCielo', Tono.luzCielo)
        sombreador:send('luzDirecta', Tono.luzDirecta or 0)
        local tope = Tono.factorMax + (Tono.factorNoche - Tono.factorMax) * Tono.noche
        sombreador:send('medidor', { Tono.luzReferencia, Tono.adaptacion, math.min(Tono.factorMin, tope), tope })
    end
    love.graphics.setShader(sombreador)
    sombreador:send('exposicion', Tono.exposicion)
    sombreador:send('saturacion', Tono.saturacion)
    love.graphics.setColor(1, 1, 1, 1)
    local ancho = destino and destino:getWidth() or love.graphics.getDimensions()
    love.graphics.draw(fuente, 0, 0, 0, ancho / fuente:getPixelWidth())
    love.graphics.pop()
end

return Tono
