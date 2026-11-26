-- Sombreadores del pase de efectos (Camila): partículas (cuadros encarados a
-- la cámara o trazos a lo largo de la velocidad) y la cinta de las estelas.
-- Movimiento, luz, niebla y mezcla: ver `comun.lua`.

local Comun = require('batalla.dream.efectos.comun')

local Sombreadores = {}

-- Partículas -------------------------------------------------------------------------------------
--
-- Atributos por copia (`lote.lua`):
--   ParticulaA        posición inicial (unidades de Dream) y nacimiento (s)
--   ParticulaB        velocidad inicial y vida (s)
--   ParticulaC        tamaño inicial y final, giro inicial y velocidad de giro
--   ParticulaD        arrastre, subida, suelo y fracción del viento
--   ParticulaColor0   color al nacer (sRGB) y alfa máximo
--   ParticulaColor1   color al morir (sRGB) y emisión (0 a 1, × 24)
--   ParticulaExtra    variante del atlas, curva del color, estiramiento y semilla
--
-- Con `efectoEstirar` > 0 cada copia es un trazo que sigue su velocidad (la
-- cabeza en la partícula); con `efectoFijo` no envejece (llamas de tobera y
-- trazadores, que se rehacen cada cuadro).

local VERTICES_PARTICULA = Comun.vertices
    .. [[
    attribute vec4 ParticulaA;
    attribute vec4 ParticulaB;
    attribute vec4 ParticulaC;
    attribute vec4 ParticulaD;
    attribute vec4 ParticulaColor0;
    attribute vec4 ParticulaColor1;
    attribute vec4 ParticulaExtra;
    uniform float efectoEstirar;
    uniform float efectoAtlas;
    uniform float efectoTurbulencia;
    uniform float efectoFijo;

    vec4 position(mat4 _proyeccion, vec4 vertice) {
        float e = efectoTiempo - ParticulaA.w;
        float vida = max(ParticulaB.w, 0.0001);
        float f = e / vida;
        if (efectoFijo > 0.5) {
            e = 0.0;
            f = 0.0;
        }
        if (e < 0.0 || f >= 1.0) {
            vAlfa = 0.0;
            return vec4(0.0, 0.0, -10.0, 1.0);
        }
        vec3 v;
        vec3 p = efectoMover(ParticulaA.xyz, ParticulaB.xyz, e, ParticulaD.x, ParticulaD.y, ParticulaD.w, ParticulaD.z, v);
        float crece = 1.0 - (1.0 - f) * (1.0 - f);
        float tam = mix(ParticulaC.x, ParticulaC.y, crece);
        float semilla = ParticulaExtra.w * 255.0;

        // Remolinos suaves: crecen con la edad y con el tamaño.
        float remolino = efectoTurbulencia * tam * min(e, 4.0) * 0.08;
        p += vec3(sin(e * 0.9 + semilla), 0.4 * sin(e * 0.6 + semilla * 1.7), cos(e * 0.8 + semilla * 2.3)) * remolino;

        // Nunca más fina que un par de píxeles: de lejos se adelgaza el alfa.
        float distancia = length(p - efectoOjo);
        float minimo = distancia * efectoPixel * 1.6;
        float alfa = ParticulaColor0.a;
        vec2 esquina = vertice.xy;
        vec3 posicion;
        if (efectoEstirar > 0.0) {
            vec3 frente = (p - efectoOjo) / max(distancia, 0.0001);
            vec3 plano = v - frente * dot(v, frente);
            float largoPlano = length(plano);
            vec3 eje = largoPlano > 0.00001 ? plano / largoPlano : efectoDerecha;
            vec3 lado = normalize(cross(frente, eje));
            float ancho = max(tam, minimo);
            float largo = max(tam, ancho) + largoPlano * efectoEstirar * (ParticulaExtra.z * 4.0);
            alfa *= tam / ancho;
            // La cabeza queda en p y la cola se estira hacia atrás.
            posicion = p + eje * (esquina.x - 0.5) * largo + lado * esquina.y * ancho;
        } else {
            float giro = ParticulaC.z + ParticulaC.w * e;
            float c = cos(giro);
            float s = sin(giro);
            vec2 r = vec2(esquina.x * c - esquina.y * s, esquina.x * s + esquina.y * c);
            float lado = max(tam, minimo);
            alfa *= (tam * tam) / (lado * lado);
            posicion = p + (efectoDerecha * r.x + efectoArriba * r.y) * lado;
        }

        vec2 uv = VertexTexCoord.xy;
        if (efectoAtlas > 1.5) {
            float variante = floor(ParticulaExtra.x * 255.0 + 0.5);
            uv = (uv + vec2(mod(variante, 2.0), floor(variante / 2.0))) * 0.5;
        }
        VaryingTexCoord = vec4(uv, 0.0, 0.0);

        float curva = 0.25 + ParticulaExtra.y * 4.0;
        vec3 color = mix(pow(ParticulaColor0.rgb, vec3(2.2)), pow(ParticulaColor1.rgb, vec3(2.2)), pow(f, curva));
        float entrada = efectoFijo > 0.5 ? 1.0 : clamp(e / (vida * 0.06 + 0.015), 0.0, 1.0);
        float salida = (1.0 - f) * (1.0 - f * f * 0.5);
        vAlfa = alfa * entrada * salida;
        float emision = ParticulaColor1.a * 24.0 * pow(1.0 - f, 1.6);
        if (ParticulaColor1.a > 0.0) {
            // Fuego: no se ilumina, emite.
            vLuz = vec3(0.0);
            vEmision = color * emision;
        } else {
            vLuz = color * (efectoIluminar(p) + efectoContraluz(p));
            vEmision = vec3(0.0);
        }
        vNiebla = efectoNieblaEn(p);
        return efectoProyectar(posicion);
    }
]]

-- Estelas -----------------------------------------------------------------------------------------
--
-- La cinta une los puntos del recorrido del misil; cada punto lleva su
-- tangente, su nacimiento y su semilla, y los dos tramos que lo comparten
-- calculan exactamente los mismos vértices: sin cortes aunque el misil gire.
--
--   VertexPosition  punto (unidades de Dream) y nacimiento (s)
--   EstelaB         tangente del recorrido y lado de la cinta (-1 o 1)
--   EstelaC         recorrido (m), semilla, vida (s) y escala del ancho

local VERTICES_ESTELA = Comun.vertices
    .. [[
    attribute vec4 EstelaB;
    attribute vec4 EstelaC;
    uniform float estelaArrastre;
    uniform float estelaSubida;
    uniform float estelaViento;
    uniform float estelaTesela;

    vec4 position(mat4 _proyeccion, vec4 vertice) {
        float e = efectoTiempo - vertice.w;
        float vida = max(EstelaC.z, 0.0001);
        float f = e / vida;
        if (e < 0.0 || f >= 1.0) {
            vAlfa = 0.0;
            return vec4(0.0, 0.0, -10.0, 1.0);
        }
        float semilla = EstelaC.y;
        float recorrido = EstelaC.x;
        float escala = EstelaC.w;
        vec3 v;
        vec3 p = efectoMover(vertice.xyz, vec3(0.0), e, estelaArrastre, estelaSubida, estelaViento, -100000.0, v);

        // Ondulación a lo largo del recorrido (unos 40 m entre crestas) y
        // con la edad; empieza en cero en la tobera.
        float onda = 0.05 * sqrt(e) * escala;
        p += vec3(
            sin(recorrido * 0.15 + semilla + e * 0.35),
            0.5 * sin(recorrido * 0.11 + semilla * 1.3 + e * 0.25),
            cos(recorrido * 0.13 + semilla * 2.1 + e * 0.3)
        ) * onda;

        // 0,25 m en la tobera, casi un metro más en el primer medio segundo y
        // después medio metro por segundo (a los 9 s, unos 10 m de ancho).
        float ancho = escala * (0.025 + 0.085 * (1.0 - exp(-e * 3.0)) + 0.045 * e);
        vec3 hastaOjo = efectoOjo - p;
        float distancia = length(hastaOjo);
        vec3 lado = cross(EstelaB.xyz, hastaOjo);
        float largoLado = length(lado);
        lado = largoLado > distancia * 0.0001 ? lado / largoLado : efectoDerecha;
        float minimo = distancia * efectoPixel * 1.4;
        float visible = max(ancho, minimo);
        vec3 posicion = p + lado * visible * EstelaB.w;
        VaryingTexCoord = vec4(recorrido / estelaTesela + semilla * 0.37, EstelaB.w * 0.5 + 0.5, 0.0, 0.0);

        // Temperatura: blanco en la tobera y naranja unos metros (a la
        // velocidad del misil, el fuego ocupa los primeros 10 m).
        float blanco = exp(-e / 0.008);
        float calor = exp(-e / 0.04);
        vec3 fuego = mix(vec3(1.0, 0.36, 0.07), vec3(1.0, 0.82, 0.5), blanco);
        // Humo: gris recién salido del fuego, enseguida gris claro y blanco
        // (el propulsante sólido deja humo muy blanco).
        float gris = mix(0.45, 0.8, smoothstep(0.03, 0.6, e));
        gris = mix(gris, 0.92, smoothstep(0.6, 5.0, e));
        gris *= 0.92 + 0.08 * sin(semilla * 7.0 + recorrido * 0.031);
        vec3 humo = pow(vec3(gris, gris * 0.985, gris * 0.955), vec3(2.2));

        // El mismo humo repartido en más ancho es más tenue.
        float densidad = pow(0.025 * escala / ancho, 0.36);
        float alfa = min(1.0, 0.88 * densidad) * pow(1.0 - f, 1.3);
        alfa *= ancho / visible;
        vAlfa = mix(alfa, 1.0, calor * 0.7);
        vLuz = humo * (efectoIluminar(p) + efectoContraluz(p)) * (1.0 - calor);
        vEmision = pow(fuego, vec3(2.2)) * calor * (3.0 + 12.0 * blanco);
        vNiebla = efectoNieblaEn(p);
        return efectoProyectar(posicion);
    }
]]

function Sombreadores.particula()
    return love.graphics.newShader(Comun.pixeles, VERTICES_PARTICULA)
end

function Sombreadores.estela()
    return love.graphics.newShader(Comun.pixeles, VERTICES_ESTELA)
end

return Sombreadores
