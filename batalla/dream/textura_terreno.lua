-- Shader del terreno de batalla (`terrenoNatural`): el suelo de la prueba de
-- estilo de Camila (batalla/pruebas_estilo/suelo_sombreador.lua) teñido con el
-- color por zona del mapa (batalla/color_terreno.lua, por vértice).
--
-- Tres texturas procedurales (batalla/dream/estilo/texturas.lua: hierba verde,
-- hierba seca y tierra rojiza, con el alfa como altura) se mezclan por altura
-- con máscaras de ruido calculadas aquí con la posición del mundo. Contra la
-- repetición, cada textura se lee a dos escalas (4 m y 11 m, la segunda
-- girada) y se pasa de una a otra con un ruido de 15 m; el brillo cambia con
-- un ruido de 50 m.
--
-- El color del mapa sigue mandando:
-- - hierba (pradera, hierba seca, suelo de bosque): las texturas de hierba,
--   con más hierba seca donde el mapa es seco, y teñidas hacia su color;
-- - caminos y orillas de tierra: la tierra rojiza, teñida hacia su color;
-- - roca: la textura de roca con liquen de las rocas, proyectada desde los
--   tres ejes, con el tono de la roca del mapa;
-- - arena, nieve y fondo del agua: su propio color con el grano y el brillo
--   de las texturas (la paleta de hierba no pega ahí).
-- La máscara `mascaraSuelo` (2 m por píxel, batalla/dream/vegetacion.lua)
-- añade pinocha y tierra al pie de los pinos.

local TexturaTerreno = {}

TexturaTerreno.type = 'pixel'
TexturaTerreno.meshFormat = 'simple'

local blanco

--- Textura de 1 x 1 para la máscara si no hay otra.
function TexturaTerreno.blanca()
    if not blanco then
        local datos = love.image.newImageData(1, 1)
        datos:setPixel(0, 0, 0, 0, 0, 1)
        blanco = love.graphics.newImage(datos)
    end
    return blanco
end

--- Compatibilidad: la escena pedía una textura; ya no se lee.
function TexturaTerreno.crear()
    return TexturaTerreno.blanca()
end

function TexturaTerreno:buildDefines()
    return [[
        varying vec3 VaryingMaterial;

        #ifdef VERTEX
        attribute vec4 VertexMaterial;
        #endif

        #ifdef PIXEL
        uniform Image texVerde;
        uniform Image texSeca;
        uniform Image texTierra;
        uniform Image texRoca;
        uniform Image mascaraSuelo;
        uniform vec4 mascaraRect;

        // Hash de una celda entera a [0, 1).
        float hashSuelo(vec2 p) {
            vec3 q = fract(vec3(p.xyx) * 0.1031);
            q += dot(q, q.yzx + 33.33);
            return fract((q.x + q.y) * q.z);
        }

        // Ruido de valor suavizado, en [0, 1].
        float ruidoSuelo(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            vec2 u = f * f * (3.0 - 2.0 * f);
            float a = hashSuelo(i);
            float b = hashSuelo(i + vec2(1.0, 0.0));
            float c = hashSuelo(i + vec2(0.0, 1.0));
            float d = hashSuelo(i + vec2(1.0, 1.0));
            return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
        }

        float fbmSuelo(vec2 p) {
            return ruidoSuelo(p) * 0.55 + ruidoSuelo(p * 2.03 + 7.1) * 0.3 + ruidoSuelo(p * 4.1 - 3.3) * 0.15;
        }

        // Una textura a dos escalas, fundidas con ruido para que no se note
        // la repetición.
        vec4 muestraSuelo(Image t, vec2 m, float cambio) {
            vec4 a = gammaCorrectedTexel(t, m * 0.25);
            vec2 girada = mat2(0.8, -0.6, 0.6, 0.8) * m * 0.09 + vec2(0.37, 0.71);
            vec4 b = gammaCorrectedTexel(t, girada);
            return mix(a, b, cambio);
        }
        #endif
    ]]
end

function TexturaTerreno:buildPixel()
    -- vertexPos y viewPos van en unidades de 3Dream (10 m): se pasan a metros.
    -- Los colores de referencia son los de color_terreno.lua en lineal.
    return [[
        vec3 base = VaryingColor.rgb;
        vec3 normalMundo = normal;
        vec2 m = vertexPos.xz * 10.0;
        float lejos = length(viewPos - vertexPos) * 10.0;

        // Qué es cada zona según su color: hierba (verde o seca, g alto frente
        // a b y frente a r), tierra de camino u orilla (rojiza) y el resto.
        float gr = base.g / max(base.r, 0.0001);
        float hierba = smoothstep(0.55, 0.7, (base.g - base.b) / max(base.g, 0.0001)) * smoothstep(0.6, 0.8, gr);
        float sequedad = smoothstep(1.35, 0.85, gr);
        float camino = (1.0 - hierba) * smoothstep(0.75, 0.6, gr)
            * smoothstep(0.3, 0.5, (base.r - base.b) / max(base.r, 0.0001));

        float cambio = smoothstep(0.3, 0.7, ruidoSuelo(m * 0.066));
        vec4 verde = muestraSuelo(texVerde, m, cambio);
        vec4 seca = muestraSuelo(texSeca, m + vec2(13.7, 5.3), 1.0 - cambio);
        vec4 tierra = muestraSuelo(texTierra, m + vec2(-7.1, 21.9), cambio);
        vec4 mascara = Texel(mascaraSuelo, (m - mascaraRect.xy) / mascaraRect.zw);

        // Hierba seca a manchas grandes (de 10 a 40 m) y donde el mapa es seco.
        float nSeca = fbmSuelo(m * 0.03 + vec2(3.1, 8.7));
        float pesoSeca = smoothstep(0.6, 0.72, nSeca + (seca.a - verde.a) * 0.25 + mascara.g * 0.4 + sequedad * 0.55);
        vec3 colorHierba = mix(verde.rgb, seca.rgb, pesoSeca);
        float alturaHierba = mix(verde.a, seca.a, pesoSeca);

        // Claros de tierra rojiza (de 3 a 15 m), la pinocha de la máscara y
        // los caminos.
        float nTierra = fbmSuelo(m * 0.07 + vec2(-11.0, 4.0));
        float pesoTierra = smoothstep(0.64, 0.7, nTierra + mascara.r * 0.4 + (tierra.a - alturaHierba) * 0.3 + camino * 0.7);
        vec3 colorTextura = mix(colorHierba, tierra.rgb, pesoTierra);

        // Brillo a gran escala.
        float brillo = 0.82 + 0.36 * ruidoSuelo(m * 0.02 + vec2(40.0, 9.0));

        // Tinte hacia el color del mapa: la hierba hacia su verde (o su seco)
        // y la tierra hacia su marrón. Lo oscuro del bosque también pasa.
        vec3 refHierba = mix(vec3(0.13, 0.25, 0.03), vec3(0.43, 0.35, 0.09), sequedad);
        vec3 tinteHierba = clamp(base / refHierba, vec3(0.45), vec3(1.8));
        vec3 tinteTierra = clamp(base / vec3(0.19, 0.105, 0.04), vec3(0.5), vec3(1.8));
        vec3 tinte = mix(tinteHierba, tinteTierra, pesoTierra * (1.0 - hierba * 0.5));
        vec3 suelo = colorTextura * mix(vec3(1.0), tinte, 0.45) * brillo;

        // Arena, nieve y fondo: su color, con el grano de las texturas.
        float grano = 0.82 + 0.36 * (tierra.a * 0.6 + alturaHierba * 0.4);
        vec3 otro = base * grano * mix(1.0, brillo, 0.6);

        // Roca (gris y no muy clara): la textura de roca con liquen de las
        // rocas, proyectada desde los tres ejes para no estirarse en las
        // laderas, con el tono de la roca del mapa.
        float textura = max(hierba, camino);
        float maximo = max(base.r, max(base.g, base.b));
        float saturacion = (maximo - min(base.r, min(base.g, base.b))) / max(maximo, 0.0001);
        float luminancia = dot(base, vec3(0.2126, 0.7152, 0.0722));
        float esRoca = smoothstep(0.35, 0.2, saturacion) * smoothstep(0.6, 0.4, luminancia) * (1.0 - textura);
        // (Sin `if`: leer con mipmaps dentro de una rama rompe las derivadas.)
        vec3 pr = vertexPos * 10.0 * 0.2;
        vec3 pesos = pow(abs(normalMundo), vec3(4.0));
        pesos /= pesos.x + pesos.y + pesos.z;
        vec3 roca = gammaCorrectedTexel(texRoca, pr.zy).rgb * pesos.x
            + gammaCorrectedTexel(texRoca, pr.xz).rgb * pesos.y
            + gammaCorrectedTexel(texRoca, pr.xy).rgb * pesos.z;
        vec3 colorRoca = base * clamp(roca / vec3(0.085, 0.09, 0.085), vec3(0.3), vec3(2.0));
        otro = mix(otro, colorRoca * mix(1.0, brillo, 0.4), esRoca);

        albedo = mix(otro, suelo, textura);
        alpha = VaryingColor.a;
        roughness = mix(VaryingMaterial.x, 0.95, textura);
        metallic = VaryingMaterial.y;
        emission = VaryingColor.rgb * VaryingMaterial.z;
        // Sin reflejo rasante del cielo a lo lejos (como el follaje).
        normal = normalize(mix(normal, -viewVec, 0.25));

        // Horizonte: el faldón (batalla/suelo.lua) sigue la llanura hasta
        // más allá del plano lejano de la cámara (9 km); de 5 a 8,8 km de la
        // cámara el suelo se funde con el color del horizonte del cielo, para
        // que no se vea dónde lo corta el plano lejano.
        // Allí el suelo no refleja luz: emite el color exacto del horizonte
        // del cielo (lineal), para que no quede una franja más oscura.
        float horizonte = smoothstep(5000.0, 8800.0, lejos);
        albedo = mix(albedo, vec3(0.0), horizonte);
        emission = mix(emission, vec3(0.612, 0.736, 0.893), horizonte);
    ]]
end

function TexturaTerreno:buildVertex()
    return [[
        VaryingMaterial = VertexMaterial.xyz;
    ]]
end

function TexturaTerreno:perMaterial(objetoSombreador, material)
    local sombreador = objetoSombreador.shader
    local blanca = TexturaTerreno.blanca()
    if sombreador:hasUniform('texVerde') then
        sombreador:send('texVerde', material.texVerde or blanca)
        sombreador:send('texSeca', material.texSeca or blanca)
        sombreador:send('texTierra', material.texTierra or blanca)
        sombreador:send('texRoca', material.texRoca or blanca)
    end
    if sombreador:hasUniform('mascaraSuelo') then
        sombreador:send('mascaraSuelo', material.mascaraSuelo or blanca)
        sombreador:send('mascaraRect', material.mascaraRect or { -1, -1, 2, 2 })
    end
end

return TexturaTerreno
