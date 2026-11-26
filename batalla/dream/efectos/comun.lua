-- Datos del cuadro y código GLSL comunes de los efectos (Camila).
--
-- El humo, las estelas, el fuego y las chispas se dibujan en un pase propio
-- encima de la imagen que entrega 3DreamEngine (después de `dream:present`),
-- no en su paso translúcido. Motivos, leídos en lib/3DreamEngine:
--   * la niebla del motor se aplica al final con la profundidad de lo opaco;
--     el cielo escribe 65504, así que todo lo translúcido que tuviera el
--     cielo detrás quedaba tapado por la niebla (estelas casi invisibles)
--   * su mezcla translúcida no permite sumar luz (fuego, chispas)
-- Aquí cada partícula calcula su propia niebla, se prueba contra la
-- profundidad de la escena (`dream.canvases.depth`, la misma medida que
-- escribe el motor: la z de recorte) y se mezcla con alfa premultiplicado:
-- el humo tapa lo de detrás y el fuego además suma.
--
-- Movimiento de cada partícula, sin simular nada en la CPU: con el arrastre
-- k, la velocidad tiende a la terminal (viento × fracción + subida / k), y
-- la posición tiene forma cerrada:
--
--   p(e) = p0 + terminal e + (v0 - terminal) (1 - exp(-k e)) / k
--
-- Con subida negativa y k pequeño es la caída con gravedad; con subida
-- positiva, el humo que asciende y se frena. `suelo` es la altura mínima.

local Comun = {
    tiempo = 0,
    viento = { 0, 0, 0 },
    derecha = { 1, 0, 0 },
    arriba = { 0, 1, 0 },
    ojo = { 0, 0, 0 },
    pixel = 0.001,
    voltear = 1,
    solDireccion = { 0, 1, 0 },
    solColor = { 0, 0, 0 },
    lunaDireccion = { 0, 1, 0 },
    lunaColor = { 0, 0, 0 },
    ambiente = { 0.3, 0.3, 0.3 },
    nieblaColor = { 0.7, 0.75, 0.8 },
    niebla = { 0, -1, 1, 0 }, -- densidad, altura mínima, máxima y dispersión
    lucesPosicion = {},
    lucesColor = {},
    luces = 0,
}

Comun.maxLuces = 8
for k = 1, Comun.maxLuces do
    Comun.lucesPosicion[k] = { 0, -1000, 0 }
    Comun.lucesColor[k] = { 0, 0, 0 }
end

-- Uniformes y funciones del sombreador de vértices.
Comun.vertices = [[
    uniform mat4 efectoProyeccion;
    uniform float efectoVoltear;
    uniform float efectoTiempo;
    uniform vec3 efectoViento;
    uniform vec3 efectoDerecha;
    uniform vec3 efectoArriba;
    uniform vec3 efectoOjo;
    uniform float efectoPixel;

    uniform vec3 efectoSolDireccion;
    uniform vec3 efectoSolColor;
    uniform vec3 efectoLunaDireccion;
    uniform vec3 efectoLunaColor;
    uniform vec3 efectoAmbiente;
    uniform vec3 efectoNieblaColor;
    uniform vec4 efectoNiebla;
    uniform vec3 efectoLucesPosicion[8];
    uniform vec3 efectoLucesColor[8];
    uniform int efectoLuces;

    varying vec3 vLuz;
    varying vec3 vEmision;
    varying vec4 vNiebla;
    varying float vProfundidad;
    varying float vAlfa;

    vec3 efectoMover(vec3 p0, vec3 v0, float e, float k, float subida, float fraccionViento, float suelo, out vec3 v) {
        k = max(k, 0.001);
        vec3 terminal = efectoViento * fraccionViento + vec3(0.0, subida / k, 0.0);
        float decae = exp(-k * e);
        vec3 p = p0 + terminal * e + (v0 - terminal) * (1.0 - decae) / k;
        v = terminal + (v0 - terminal) * decae;
        if (p.y < suelo) {
            p.y = suelo;
            v = vec3(0.0);
        }
        return p;
    }

    // Luz que recibe el humo en p (como las partículas de 3Dream: sin cara
    // en sombra): cielo, sol, luna y los destellos de las explosiones.
    vec3 efectoIluminar(vec3 p) {
        vec3 luz = efectoAmbiente + (efectoSolColor + efectoLunaColor) * 0.3183;
        for (int i = 0; i < 8; i++) {
            if (i >= efectoLuces) {
                break;
            }
            float d = length(efectoLucesPosicion[i] - p) + 1.0;
            luz += efectoLucesColor[i] * 0.3183 / (d * d);
        }
        return luz;
    }

    // El humo mirado hacia el sol se ilumina por detrás (dispersión hacia
    // delante): los bordes de las nubes de humo brillan a contraluz.
    vec3 efectoContraluz(vec3 p) {
        vec3 mirada = normalize(p - efectoOjo);
        float haciaSol = max(dot(mirada, efectoSolDireccion), 0.0);
        return efectoSolColor * 0.12 * pow(haciaSol, 6.0);
    }

    // Niebla con altura, como `lib/3DreamEngine/shaders/code/fog.glsl`.
    vec4 efectoNieblaEn(vec3 p) {
        vec3 rayo = p - efectoOjo;
        float distancia = length(rayo);
        float densidad = efectoNiebla.x;
        float bajo = efectoNiebla.y;
        float alto = efectoNiebla.z;
        float recorrido = distancia;
        if (alto > bajo && abs(rayo.y) > 0.0001) {
            vec3 paso = rayo / rayo.y;
            vec3 cerca = efectoOjo;
            vec3 lejos = p;
            float hCerca = clamp(cerca.y, bajo, alto);
            float hLejos = clamp(lejos.y, bajo, alto);
            cerca += paso * (hCerca - cerca.y);
            lejos += paso * (hLejos - lejos.y);
            float grueso = alto - bajo;
            recorrido = distance(lejos, cerca) * ((1.0 - (hCerca - bajo) / grueso) + (1.0 - (hLejos - bajo) / grueso)) * 0.5;
        }
        float cantidad = 1.0 - exp(-recorrido * densidad);
        float haciaSol = max(dot(efectoSolDireccion, rayo / max(distancia, 0.0001)), 0.0);
        vec3 color = efectoNieblaColor + efectoSolColor * pow(haciaSol, 8.0) * efectoNiebla.w;
        return vec4(color, cantidad);
    }

    vec4 efectoProyectar(vec3 p) {
        vec4 recorte = efectoProyeccion * vec4(p, 1.0);
        vProfundidad = recorte.z;
        recorte.y *= efectoVoltear;
        return recorte;
    }
]]

-- Sombreador de píxeles común: textura (alfa = cobertura, rojo = brillo o
-- temperatura), prueba de profundidad y borde suave contra la escena,
-- niebla y mezcla premultiplicada (con `efectoAditivo` también suma).
Comun.pixeles = [[
    uniform Image efectoProfundidad;
    uniform float efectoSuave;
    uniform float efectoAditivo;

    varying vec3 vLuz;
    varying vec3 vEmision;
    varying vec4 vNiebla;
    varying float vProfundidad;
    varying float vAlfa;

    vec4 effect(vec4 color, Image textura, vec2 uv, vec2 pantalla) {
        vec4 muestra = Texel(textura, uv);
        float fondo = Texel(efectoProfundidad, love_PixelCoord.xy / love_ScreenSize.xy).r;
        float cobertura = vAlfa * muestra.a * clamp((fondo - vProfundidad) * efectoSuave, 0.0, 1.0);
        if (cobertura < 0.003) {
            discard;
        }
        vec3 lineal = vLuz * muestra.r + vEmision * (0.3 + muestra.r * 1.2);
        lineal = mix(lineal, vNiebla.rgb, vNiebla.a);
        vec3 pantallaColor = pow(max(lineal, vec3(0.0)), vec3(1.0 / 2.2));
        return vec4(pantallaColor * cobertura, cobertura * (1.0 - efectoAditivo));
    }
]]

local function enviar(sombreador, nombre, ...)
    if sombreador:hasUniform(nombre) then
        sombreador:send(nombre, ...)
    end
end

Comun.enviar = enviar

--- Envía los datos del cuadro a un sombreador de efectos.
function Comun.enviarCuadro(sombreador)
    enviar(sombreador, 'efectoProyeccion', 'row', Comun.proyeccion)
    enviar(sombreador, 'efectoVoltear', Comun.voltear)
    enviar(sombreador, 'efectoTiempo', Comun.tiempo)
    enviar(sombreador, 'efectoViento', Comun.viento)
    enviar(sombreador, 'efectoDerecha', Comun.derecha)
    enviar(sombreador, 'efectoArriba', Comun.arriba)
    enviar(sombreador, 'efectoOjo', Comun.ojo)
    enviar(sombreador, 'efectoPixel', Comun.pixel)
    enviar(sombreador, 'efectoSolDireccion', Comun.solDireccion)
    enviar(sombreador, 'efectoSolColor', Comun.solColor)
    enviar(sombreador, 'efectoLunaDireccion', Comun.lunaDireccion)
    enviar(sombreador, 'efectoLunaColor', Comun.lunaColor)
    enviar(sombreador, 'efectoAmbiente', Comun.ambiente)
    enviar(sombreador, 'efectoNieblaColor', Comun.nieblaColor)
    enviar(sombreador, 'efectoNiebla', Comun.niebla)
    enviar(sombreador, 'efectoLucesPosicion', unpack(Comun.lucesPosicion))
    enviar(sombreador, 'efectoLucesColor', unpack(Comun.lucesColor))
    enviar(sombreador, 'efectoLuces', Comun.luces)
    enviar(sombreador, 'efectoProfundidad', Comun.profundidad)
end

-- Para los escombros, que sí van en 3Dream (opacos, con sombra y niebla del
-- motor): el mismo movimiento como código de su sombreador de vértices.
Comun.movimiento = [[
    vec3 efectoMover(vec3 p0, vec3 v0, float e, float k, float subida, float fraccionViento, float suelo, out vec3 v) {
        k = max(k, 0.001);
        vec3 terminal = efectoViento * fraccionViento + vec3(0.0, subida / k, 0.0);
        float decae = exp(-k * e);
        vec3 p = p0 + terminal * e + (v0 - terminal) * (1.0 - decae) / k;
        v = terminal + (v0 - terminal) * decae;
        if (p.y < suelo) {
            p.y = suelo;
            v = vec3(0.0);
        }
        return p;
    }
]]

Comun.uniformesDream = [[
    uniform float efectoTiempo;
    uniform vec3 efectoViento;
]]

--- Para los sombreadores registrados en 3Dream (escombros).
function Comun.enviarDream(objeto)
    local sombreador = objeto.shader
    enviar(sombreador, 'efectoTiempo', Comun.tiempo)
    enviar(sombreador, 'efectoViento', Comun.viento)
end

return Comun
