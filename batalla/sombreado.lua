-- Shader de la escena de batalla: perspectiva real, luz del sol de la tarde
-- (la misma de los tanques 3D del mapa) y niebla lineal con la distancia hacia
-- el color del horizonte, suave (a 2-3 km aún se lee la escena). Sirve para todo: terreno, plantas, torre, vehículos
-- y efectos (con `brillo` los fogonazos no reciben sombra).

local Sombreado = {}

-- Luz de la tarde desde arriba a la izquierda, la misma del terreno del mapa.
Sombreado.luz = { -0.45, -0.55, 0.7 }
do
    local l = Sombreado.luz
    local largo = math.sqrt(l[1] ^ 2 + l[2] ^ 2 + l[3] ^ 2)
    Sombreado.luz = { l[1] / largo, l[2] / largo, l[3] / largo }
end

-- Horizonte del cielo de atardecer del mapa: la niebla se funde con él.
Sombreado.colorNiebla = { 0.95, 0.76, 0.62 }

local CODIGO = [[
varying vec3 normalMundo;
varying vec3 colorBase;
varying float nacion;
varying vec3 posicionMundo;

#ifdef VERTEX
attribute vec3 NormalModelo;
attribute vec3 ColorModelo;
attribute float NacionModelo;

uniform mat4 modelo;
uniform mat4 vistaProyeccion;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vec4 mundo = modelo * vec4(vertex_position.xyz, 1.0);
    posicionMundo = mundo.xyz;
    normalMundo = mat3(modelo) * NormalModelo;
    colorBase = ColorModelo;
    nacion = NacionModelo;
    return vistaProyeccion * mundo;
}
#endif

#ifdef PIXEL
uniform vec3 luz;
uniform vec3 colorNacion;
uniform vec3 camara;
uniform vec3 colorNiebla;
uniform vec2 niebla;
uniform float brillo;
uniform float quemado;
uniform float luzMapa;
uniform vec3 area; // centro (x, y) y medio lado del área generada

vec4 effect(vec4 color, Image textura, vec2 uv, vec2 pantalla)
{
    vec3 n = normalize(normalMundo);
    float difusa = max(dot(n, luz), 0.0);
    vec3 base = pow(mix(colorBase, colorNacion, nacion) * color.rgb, vec3(2.2));
    // Un vehículo destruido queda ennegrecido.
    base = mix(base, vec3(0.012, 0.011, 0.01), quemado);
    vec3 ambiente = vec3(0.96, 0.7, 0.6) * 0.75;
    vec3 sol = vec3(1.0, 0.84, 0.68) * 2.0;
    vec3 lineal = mix(base * (ambiente + sol * difusa), base * 1.6, brillo);
    vec3 final = pow(lineal, vec3(1.0 / 2.2));
    // El suelo, las plantas y los edificios, con la luz del mapa (sus colores
    // ya son los que se ven en él): 0,62 en sombra y hasta 1,1 al sol.
    vec3 comoMapa = mix(colorBase, colorNacion, nacion) * color.rgb * (0.62 + 0.48 * difusa);
    final = mix(final, comoMapa, luzMapa);
    float d = distance(posicionMundo, camara);
    float f = clamp((d - niebla.x) / (niebla.y - niebla.x), 0.0, 1.0);
    // Hacia el borde del área todo se funde con la niebla: no se ve dónde acaba.
    vec2 borde = abs(posicionMundo.xy - area.xy) / area.z;
    f = max(f, smoothstep(0.8, 0.99, max(borde.x, borde.y)));
    final = mix(final, colorNiebla, f * (1.0 - brillo * 0.5));
    return vec4(final, color.a);
}
#endif
]]

local shader

function Sombreado.shader()
    if not shader then
        shader = love.graphics.newShader(CODIGO)
        shader:send('luz', Sombreado.luz)
        shader:send('colorNiebla', Sombreado.colorNiebla)
        shader:send('brillo', 0)
        shader:send('quemado', 0)
        shader:send('luzMapa', 0)
        shader:send('colorNacion', { 1, 1, 1 })
    end
    return shader
end

return Sombreado
