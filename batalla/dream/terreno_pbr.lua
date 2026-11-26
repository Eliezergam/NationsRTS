-- Sombreador del suelo de la batalla con las texturas PBR de Camila
-- (`terrenoPBR`, Valeria). Sustituye a las texturas pintadas por código de
-- batalla/dream/textura_terreno.lua en los trozos del terreno y el faldón.
--
-- Cada vértice lleva, además de su color del mapa (batalla/color_terreno.lua),
-- el peso de cada capa que calculó ColorTerreno.cara, en un formato de malla
-- propio (`terrenoPesos`): seca, bosque, pedregoso y camino; arena, barro,
-- roca y nieve; y fondo del agua. Con ellos se mezclan las capas del
-- ArrayImage (batalla/dream/texturas_pbr.lua):
--   1 hierba  2 hierba seca  3 barro  4 acantilado  5 arena  6 nieve  7 tierra pedregosa
--
-- - Suelo: proyección desde arriba, a dos escalas (la segunda girada) que se
--   funden con un ruido de 15 m contra la repetición.
-- - Roca de las pendientes: proyección triplanar (no se estira en las laderas).
-- - Cerca (hasta `cercaHasta` m): mapas de normales y una textura de detalle
--   (la capa dominante a 3,7 veces su escala). De ahí a `lejosDesde` m se
--   apagan: lejos solo cuenta el albedo, y los mipmaps hacen el resto.
-- - Tinte: cada capa se tiñe hacia el color del mapa (dividido por su color
--   medio) al 45 %, como el estilo anterior: el mapa sigue mandando (verdes,
--   secos, flores, orillas) y la textura pone el detalle.
-- - La máscara `mascaraSuelo` pone pinocha (barro) y hierba seca al pie de los pinos.
--
-- Materiales de cerca (Fase 3 de PLAN-RENDER-UE.md), según la calidad
-- (`TerrenoPBR.opciones`, que pone batalla/dream/escena.lua):
-- - `altura` (media y alta): mezcla por altura. Cada capa lleva su altura en
--   el alfa de la normal (texturas_pbr.lua); de cerca, la hierba, la hierba
--   seca, la tierra, las piedras y la roca se reparten por quién sobresale
--   (la tierra asoma entre las matas, la roca entre la tierra), y la normal
--   es la mezcla de las normales de todas las capas con esos pesos. De lejos
--   (con la altura ya promediada por los mipmaps) queda el reparto de antes.
-- - `detalle` (media y alta): normal de detalle, la capa dominante a 3,7
--   veces su escala, sumada a la normal («whiteout»); en la roca, triplanar.
-- - `pom` (alta): parallax occlusion mapping hasta `pomHasta` m. El rayo de
--   la vista baja por la altura de la capa dominante (de 8 a 16 pasos según
--   lo rasante y un ajuste lineal) y el suelo se lee donde lo corta: relieve
--   real de cerca sin más triángulos. Se apaga sobre la roca y lejos.
-- En baja, nada de esto (el suelo de antes).

local ffi = require('ffi')

local TerrenoPBR = {}

TerrenoPBR.type = 'pixel'
TerrenoPBR.meshFormat = 'terrenoPesos'
TerrenoPBR.cercaHasta = 70 -- m: normales y detalle enteros
TerrenoPBR.lejosDesde = 220 -- m: desde aquí solo el albedo
TerrenoPBR.tinte = 0.2 -- (antes 0,45: la hierba se teñía del marrón del mapa)
TerrenoPBR.macro = 0.4 -- fuerza de las manchas macro
TerrenoPBR.rocaGrande = 0.27 -- escala de la segunda lectura de la roca (unos 15 m)
-- Brillo de la roca sobre el color del mapa (0,22 lineal): roca real de
-- 0,2 a 0,3 de albedo.
TerrenoPBR.brilloRoca = 1.15
TerrenoPBR.ampliar = 0.35 -- la textura del suelo, 1 / 0,35 veces más grande que su escala de foto
-- Materiales de cerca: { altura = bool, detalle = bool, pom = bool } (calidad).
TerrenoPBR.opciones = {}
TerrenoPBR.pomDesde = 9 -- m: parallax entero hasta aquí
TerrenoPBR.pomHasta = 16 -- m: sin parallax desde aquí
TerrenoPBR.pomPasos = { 6, 12 } -- mirando de frente y rasante
-- Profundidad (m) del relieve de cada capa con el parallax (de su mapa de
-- desplazamiento: hojas de hierba, terrones, chinas).
TerrenoPBR.profundidad = { 0.035, 0.04, 0.05, 0, 0.025, 0.03, 0.06 }
TerrenoPBR.contrasteAltura = 0.18 -- ancho del borde de la mezcla por altura
TerrenoPBR.fuerzaDetalle = 0.6 -- de la normal de detalle

local registrado = false

-- Formato de vértice: 32 bytes.
TerrenoPBR.formato = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexNormal', 'byte', 4 },
    { 'VertexColor', 'byte', 4 },
    { 'VertexPesoA', 'byte', 4 },
    { 'VertexPesoB', 'byte', 4 },
    { 'VertexPesoC', 'byte', 4 },
}

--- Registra el formato de malla y el sombreador (antes de `dream:init`).
function TerrenoPBR.registrar(dream)
    if registrado then
        return
    end
    local formato = dream:newMeshFormat(TerrenoPBR.formato)
    -- Las mallas del terreno traen sus vértices ya escritos (`datosTerreno`).
    function formato:create(malla)
        return malla.datosTerreno
    end
    TerrenoPBR.estructura = formato:getCStruct()
    dream:registerMeshFormat(formato, 'terrenoPesos')
    -- 3Dream hace require de la ruta con barras: que sea esta misma tabla
    -- (si no, serían dos copias y no le llegarían `TerrenoPBR.opciones`).
    package.loaded['batalla/dream/terreno_pbr'] = TerrenoPBR
    dream:registerShader('batalla/dream/terreno_pbr', 'terrenoPBR')
    registrado = true
end

--- Datos de `cantidad` vértices en el formato, y su puntero FFI.
function TerrenoPBR.datos(cantidad)
    local datos = love.data.newByteData(math.max(1, cantidad) * ffi.sizeof(TerrenoPBR.estructura))
    return datos, ffi.cast(TerrenoPBR.estructura .. '*', datos:getFFIPointer())
end

--- Los #define de los materiales de cerca según `TerrenoPBR.opciones`.
local function definesCerca()
    local o = TerrenoPBR.opciones
    local lineas = {}
    if o.altura then
        lineas[#lineas + 1] = '#define MATERIAL_ALTURA'
    end
    if o.detalle then
        lineas[#lineas + 1] = '#define MATERIAL_DETALLE'
    end
    if o.pom and o.altura then
        lineas[#lineas + 1] = '#define MATERIAL_POM'
    end
    lineas[#lineas + 1] = string.format('#define CONTRASTE_ALTURA %.3f', TerrenoPBR.contrasteAltura)
    lineas[#lineas + 1] = string.format('#define FUERZA_DETALLE %.3f', TerrenoPBR.fuerzaDetalle)
    return table.concat(lineas, '\n') .. '\n'
end

function TerrenoPBR:buildDefines(_, sombra)
    if sombra then
        return ''
    end
    local codigo = [[
        varying vec4 vPesoA;
        varying vec4 vPesoB;
        varying vec4 vPesoC;

        #ifdef VERTEX
        attribute vec4 VertexPesoA;
        attribute vec4 VertexPesoB;
        attribute vec4 VertexPesoC;
        #endif

        #ifdef PIXEL
        uniform ArrayImage pbrAlbedo;
        uniform ArrayImage pbrNormal;
        uniform ArrayImage pbrMaterial;
        uniform float pbrEscala[7];
        uniform vec3 pbrMedia[7];
        uniform Image mascaraSuelo;
        uniform vec4 mascaraRect;
        uniform vec2 pbrDistancias;
        #ifdef MATERIAL_ALTURA
        uniform float pbrAlturaMedia[7];
        #endif
        #ifdef MATERIAL_POM
        uniform float pbrProfundidad[7];
        uniform vec2 pbrPom;
        uniform vec2 pbrPomPasos;
        #endif

        float hashSuelo(vec2 p) {
            vec3 q = fract(vec3(p.xyx) * 0.1031);
            q += dot(q, q.yzx + 33.33);
            return fract((q.x + q.y) * q.z);
        }

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

        vec3 linealPBR(vec3 c) {
        #ifdef GAMMA_CORRECTION
            return pow(c, vec3(2.2));
        #else
            return c;
        #endif
        }

        // Las derivadas (dx, dy) de `m` se calculan una vez, fuera de las
        // ramas: dentro de un `if` que no toman todos los píxeles vecinos,
        // dFdx no está definido.
        const mat2 GIRO_PBR = mat2(0.8, -0.6, 0.6, 0.8);

        // Albedo de la capa `capa` en `m` (metros): dos escalas fundidas.
        vec3 albedoCapa(float capa, vec2 m, vec2 dx, vec2 dy, float cambio) {
            // Más grande que la escala de la foto: a la distancia de la
            // cámara se sigue viendo su dibujo (el detalle fino va aparte).
            float e = pbrEscala[int(capa)] * ]] .. TerrenoPBR.ampliar .. [[;
            vec3 ca = textureGrad(pbrAlbedo, vec3(m * e, capa), dx * e, dy * e).rgb;
            float e2 = e * 0.37;
            vec2 b = GIRO_PBR * m * e2 + vec2(0.37, 0.71);
            vec3 cb = textureGrad(pbrAlbedo, vec3(b, capa), GIRO_PBR * dx * e2, GIRO_PBR * dy * e2).rgb;
            return linealPBR(mix(ca, cb, cambio));
        }

        // Normal (espacio tangente, de -1 a 1) y material de la capa desde arriba.
        vec3 normalCapa(float capa, vec2 m, vec2 dx, vec2 dy) {
            float e = pbrEscala[int(capa)] * ]] .. TerrenoPBR.ampliar .. [[;
            return textureGrad(pbrNormal, vec3(m * e, capa), dx * e, dy * e).xyz * 2.0 - 1.0;
        }

        // Normal (espacio tangente, de -1 a 1) y altura (alfa) de la capa, a
        // su escala principal (como la normal de antes: la segunda escala,
        // 2,7 veces más grande, deja el relieve de luz borroso de cerca).
        vec4 normalAlturaCapa(float capa, vec2 m, vec2 dx, vec2 dy) {
            float e = pbrEscala[int(capa)] * ]] .. TerrenoPBR.ampliar .. [[;
            vec4 a = textureGrad(pbrNormal, vec3(m * e, capa), dx * e, dy * e);
            a.xyz = a.xyz * 2.0 - 1.0;
            return a;
        }

        // Solo la altura (para el parallax).
        float alturaCapa(float capa, vec2 m, vec2 dx, vec2 dy) {
            float e = pbrEscala[int(capa)] * ]] .. TerrenoPBR.ampliar .. [[;
            return textureGrad(pbrNormal, vec3(m * e, capa), dx * e, dy * e).a;
        }

        // Mezcla por altura de B sobre A con el peso `t`: gana la que más
        // sobresale (altura más peso), con un borde de `contraste`.
        float mezclaAltura(float t, float ha, float hb, float contraste) {
            float a = ha + 1.0 - t;
            float b = hb + t;
            float tope = max(a, b) - contraste;
            float wa = max(a - tope, 0.0);
            float wb = max(b - tope, 0.0);
            return wb / max(wa + wb, 1e-5);
        }

        // Suma de normales del espacio tangente («whiteout», Barré-Brisebois).
        vec3 sumarNormal(vec3 n1, vec3 n2) {
            return normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
        }

        vec3 materialCapa(float capa, vec2 m, vec2 dx, vec2 dy) {
            float e = pbrEscala[int(capa)] * ]] .. TerrenoPBR.ampliar .. [[;
            return textureGrad(pbrMaterial, vec3(m * e, capa), dx * e, dy * e).xyz;
        }
        #endif
    ]]
    return definesCerca() .. codigo
end

function TerrenoPBR:buildPixel(_, sombra)
    if sombra then
        return [[
            albedo = vec3(0.5);
            alpha = 1.0;
        ]]
    end
    -- vertexPos y viewPos van en unidades de 3Dream (10 m): se pasan a metros.
    -- Es el algoritmo de batalla/dream/textura_terreno.lua (manchas, claros,
    -- brillo y tintes), con las texturas PBR en vez de las pintadas: cada una
    -- se normaliza por su color medio (queda su relieve de luz) y se lleva al
    -- color de referencia de antes.
    return [[
        vec3 base = VaryingColor.rgb;
        vec3 normalMundo = normalize(normal);
        vec2 m = vertexPos.xz * 10.0;
        vec2 dmx = dFdx(m);
        vec2 dmy = dFdy(m);
        vec3 pPbr = vertexPos * 10.0;
        vec3 dpx = dFdx(pPbr);
        vec3 dpy = dFdy(pPbr);
        float lejosPbr = length(viewPos - vertexPos) * 10.0;
        float cercaPbr = 1.0 - smoothstep(pbrDistancias.x, pbrDistancias.y, lejosPbr);

        // Zonas según el color del mapa, como antes, más los pesos explícitos.
        float gr = base.g / max(base.r, 0.0001);
        float hierbaPbr = smoothstep(0.55, 0.7, (base.g - base.b) / max(base.g, 0.0001)) * smoothstep(0.6, 0.8, gr);
        float sequedad = smoothstep(1.35, 0.85, gr);
        // Tierra a la vista solo en los caminos de verdad (el dueño, 19-nov:
        // «esa tierra color marrón no me gusta, que se vea más realista», con
        // una foto de pradera verde): antes el color seco del mapa volvía
        // tierra zonas enteras.
        float caminoPbr = vPesoA.w;

        float cambioPbr = smoothstep(0.3, 0.7, ruidoSuelo(m * 0.066));
        vec4 mascaraPbr = Texel(mascaraSuelo, (m - mascaraRect.xy) / mascaraRect.zw);
        // Manchas de hierba seca (de 10 a 40 m) y claros de tierra (de 3 a 15 m).
        float nSeca = fbmSuelo(m * 0.03 + vec2(3.1, 8.7));
        float nTierra = fbmSuelo(m * 0.07 + vec2(-11.0, 4.0));
        float baseSeca = nSeca + mascaraPbr.g * 0.4 + sequedad * 0.2;
        float baseTierra = nTierra * 0.75 + mascaraPbr.r * 0.4 + caminoPbr * 0.7;
        float rocaPbr = clamp(vPesoB.z * 1.1, 0.0, 1.0);

    #ifdef MATERIAL_POM
        // Parallax occlusion mapping con la altura de la capa dominante
        // (de los pesos sin altura, que aún no se conocen). Sus manchas son
        // de metros: moverse unos centímetros no las cambia.
        float pomPbr = (1.0 - smoothstep(pbrPom.x, pbrPom.y, lejosPbr)) * (1.0 - rocaPbr);
        if (pomPbr > 0.0) {
            float capaPom = baseTierra > 0.67 ? 2.0 : (baseSeca > 0.66 ? 1.0 : 0.0);
            capaPom = vPesoA.z * (baseTierra > 0.67 ? 0.0 : 1.0) > 0.5 ? 6.0 : capaPom;
            capaPom = vPesoB.x > 0.5 ? 4.0 : (vPesoB.w > 0.5 ? 5.0 : capaPom);
            vec3 vistaPom = normalize(viewPos - vertexPos);
            vec3 tanPom = normalize(vec3(1.0, 0.0, 0.0) - normalMundo * normalMundo.x);
            vec3 bitPom = cross(tanPom, normalMundo);
            float frente = max(dot(vistaPom, normalMundo), 0.15);
            vec2 recorrido = -vec2(dot(vistaPom, tanPom), dot(vistaPom, bitPom)) / frente
                * pbrProfundidad[int(capaPom)] * pomPbr;
            float pasos = floor(mix(pbrPomPasos.y, pbrPomPasos.x, frente));
            float dPaso = 1.0 / pasos;
            vec2 mPom = m + (capaPom == 1.0 ? vec2(13.7, 5.3) : (capaPom == 2.0 ? vec2(-7.1, 21.9) : vec2(0.0)));
            float hondo = 0.0;
            float h = alturaCapa(capaPom, mPom, dmx, dmy);
            float hondoAntes = 0.0;
            float hAntes = h;
            for (float k = 0.0; k < 12.0; k += 1.0) {
                if (k >= pasos || hondo >= 1.0 - h) {
                    break;
                }
                hondoAntes = hondo;
                hAntes = h;
                hondo += dPaso;
                h = alturaCapa(capaPom, mPom + recorrido * hondo, dmx, dmy);
            }
            // Corte entre el último paso por encima y el primero por debajo.
            float arriba = (1.0 - hAntes) - hondoAntes;
            float abajo = (1.0 - h) - hondo;
            float corteAntes = arriba / max(arriba - abajo, 1e-5);
            hondo = hondo > 0.0 ? mix(hondoAntes, hondo, clamp(corteAntes, 0.0, 1.0)) : 0.0;
            m += recorrido * hondo;
        }
    #endif

        vec3 verde = albedoCapa(0.0, m, dmx, dmy, cambioPbr) / pbrMedia[0];
        vec3 seca = albedoCapa(1.0, m + vec2(13.7, 5.3), dmx, dmy, 1.0 - cambioPbr) / pbrMedia[1];
        vec3 tierra = albedoCapa(2.0, m + vec2(-7.1, 21.9), dmx, dmy, cambioPbr) / pbrMedia[2];
        // «Altura» de cada textura para quebrar los bordes de las manchas: el
        // relieve de luz de la foto (media 1), centrado en el alfa medio de
        // las texturas pintadas de antes (0,75), con su misma amplitud.
        float hVerde = 0.75 + (dot(verde, vec3(0.2126, 0.7152, 0.0722)) - 1.0) * 0.3;
        float hSeca = 0.75 + (dot(seca, vec3(0.2126, 0.7152, 0.0722)) - 1.0) * 0.3;
        float hTierra = 0.75 + (dot(tierra, vec3(0.2126, 0.7152, 0.0722)) - 1.0) * 0.3;

        float pesoSeca = smoothstep(0.6, 0.72, baseSeca + (hSeca - hVerde) * 0.25);
        float alturaHierba = mix(hVerde, hSeca, pesoSeca);
        float pesoTierra = smoothstep(0.64, 0.7, baseTierra + (hTierra - alturaHierba) * 0.3);
        // Tierra con piedras en lo más seco del mapa.
        float pesoPiedras = clamp(vPesoA.z, 0.0, 1.0) * (1.0 - pesoTierra);

    #ifdef MATERIAL_ALTURA
        // De cerca, mezcla por altura con las alturas de verdad (centradas en
        // su media: de lejos, promediadas, el reparto queda el de arriba).
        vec4 nhVerde = vec4(0.0, 0.0, 1.0, 0.5);
        vec4 nhSeca = nhVerde;
        vec4 nhTierra = nhVerde;
        vec4 nhPiedras = nhVerde;
        if (cercaPbr > 0.0) {
            // Solo se leen las capas que pueden asomar (en las manchas
            // puras, una sola lectura).
            float tSeca = smoothstep(0.5, 0.82, baseSeca);
            float tTierra = smoothstep(0.55, 0.79, baseTierra);
            if (tTierra < 1.0 && tSeca < 1.0) {
                nhVerde = normalAlturaCapa(0.0, m, dmx, dmy);
            }
            if (tTierra < 1.0 && tSeca > 0.0) {
                nhSeca = normalAlturaCapa(1.0, m + vec2(13.7, 5.3), dmx, dmy);
            }
            if (tTierra > 0.0) {
                nhTierra = normalAlturaCapa(2.0, m + vec2(-7.1, 21.9), dmx, dmy);
            }
            float aVerde = nhVerde.w - pbrAlturaMedia[0] + 0.5;
            float aSeca = nhSeca.w - pbrAlturaMedia[1] + 0.5;
            float aTierra = nhTierra.w - pbrAlturaMedia[2] + 0.5;
            float k = CONTRASTE_ALTURA;
            float secaAltura = tSeca <= 0.0 ? 0.0 : (tSeca >= 1.0 ? 1.0 : mezclaAltura(tSeca, aVerde, aSeca, k));
            float aHierba = mix(aVerde, aSeca, secaAltura);
            float tierraAltura = tTierra <= 0.0 ? 0.0 : (tTierra >= 1.0 ? 1.0 : mezclaAltura(tTierra, aHierba, aTierra, k));
            pesoSeca = mix(pesoSeca, secaAltura, cercaPbr);
            pesoTierra = mix(pesoTierra, tierraAltura, cercaPbr);
            float aSuelo = mix(aHierba, aTierra, tierraAltura);
            float piedrasBase = clamp(vPesoA.z, 0.0, 1.0) * (1.0 - pesoTierra);
            float piedrasAltura = piedrasBase;
            if (piedrasBase > 0.003) {
                nhPiedras = normalAlturaCapa(6.0, m, dmx, dmy);
                piedrasAltura = mezclaAltura(piedrasBase, aSuelo, nhPiedras.w - pbrAlturaMedia[6] + 0.5, k);
            }
            pesoPiedras = mix(piedrasBase, piedrasAltura, cercaPbr);
        }
    #endif

        // Cada textura con el color medio de la pintada de antes (medido en
        // batalla/dream/estilo/texturas.lua, lineal): la misma paleta, con el
        // detalle de la foto.
        vec3 mediaVerde = vec3(0.0562, 0.0740, 0.0121);
        vec3 mediaSeca = vec3(0.1469, 0.1146, 0.0337);
        vec3 mediaTierra = vec3(0.1130, 0.0437, 0.0177);
        vec3 colorHierba = mix(verde * mediaVerde, seca * mediaSeca, pesoSeca);
        vec3 colorTextura = mix(colorHierba, tierra * mediaTierra, pesoTierra);
        if (pesoPiedras > 0.003) {
            vec3 piedras = albedoCapa(6.0, m, dmx, dmy, cambioPbr) / pbrMedia[6];
            colorTextura = mix(colorTextura, piedras * mediaTierra * 1.3, pesoPiedras);
        }
        // Tintes hacia el mapa, con las referencias de antes.
        vec3 refHierba = mix(vec3(0.13, 0.25, 0.03), vec3(0.43, 0.35, 0.09), sequedad);
        vec3 refTierra = vec3(0.19, 0.105, 0.04);
        float brilloPbr = 0.82 + 0.36 * ruidoSuelo(m * 0.02 + vec2(40.0, 9.0));
        vec3 tinteHierba = clamp(base / refHierba, vec3(0.45), vec3(1.8));
        vec3 tinteTierra = clamp(base / refTierra, vec3(0.5), vec3(1.8));
        vec3 tintePbr = mix(tinteHierba, tinteTierra, pesoTierra * (1.0 - hierbaPbr * 0.5));
        vec3 suelo = colorTextura * mix(vec3(1.0), tintePbr, ]] .. TerrenoPBR.tinte .. [[) * brilloPbr;
        // Manchas «macro» (unos 11 m): la foto de la capa leída a 1/8 de su
        // escala, en luminancia. A media distancia los mipmaps dejan la foto
        // lisa; estas manchas sí se ven (como las de las texturas pintadas).
        float eMacro = pbrEscala[0] * 0.125;
        vec2 uvMacro = m * eMacro + vec2(0.31, 0.17);
        vec3 macro = linealPBR(textureGrad(pbrAlbedo, vec3(uvMacro, pesoTierra > 0.5 ? 2.0 : 0.0),
            dmx * eMacro, dmy * eMacro).rgb);
        float lumMacro = dot(macro / pbrMedia[pesoTierra > 0.5 ? 2 : 0], vec3(0.2126, 0.7152, 0.0722));
        suelo *= mix(1.0, clamp(lumMacro, 0.55, 1.6), ]] .. TerrenoPBR.macro .. [[);

        // Orillas, nieve y fondo del agua: su color del mapa, con el relieve
        // de luz de su textura (arena, barro o nieve).
        float wArena = vPesoB.x;
        float wBarro = vPesoB.y + vPesoC.x;
        float wNieve = vPesoB.w;
        float wOtro = clamp(wArena + wBarro + wNieve, 0.0, 1.0);
        vec3 grano = vec3(1.0);
        if (wOtro > 0.003) {
            vec3 g = vec3(0.0);
            if (wArena > 0.003) {
                g += albedoCapa(4.0, m, dmx, dmy, cambioPbr) / pbrMedia[4] * wArena;
            }
            if (wBarro > 0.003) {
                g += tierra * wBarro;
            }
            if (wNieve > 0.003) {
                g += albedoCapa(5.0, m, dmx, dmy, cambioPbr) / pbrMedia[5] * wNieve;
            }
            grano = g / max(wArena + wBarro + wNieve, 0.0001);
        }
        vec3 otro = base * mix(vec3(1.0), grano, 0.7) * mix(1.0, brilloPbr, 0.6);
        // La arena y la nieve no son hierba aunque su color lo parezca.
        float textura = max(hierbaPbr, caminoPbr) * (1.0 - wOtro);
        vec3 colorPbr = mix(otro, suelo, textura);

        // Roca de las pendientes y de lo alto: triplanar, con el tono del mapa.
        vec3 normalRocaPbr = normalMundo;
        vec3 matRoca = vec3(0.0, 0.9, 1.0);
        vec3 pesosRocaPbr = pow(abs(normalMundo), vec3(4.0));
        pesosRocaPbr /= pesosRocaPbr.x + pesosRocaPbr.y + pesosRocaPbr.z;
        if (rocaPbr > 0.003) {
            float e = pbrEscala[3];
            vec2 ux = pPbr.zy * e;
            vec2 uy = pPbr.xz * e;
            vec2 uz = pPbr.xy * e;
            vec2 gxx = dpx.zy * e, gxy = dpy.zy * e;
            vec2 gyx = dpx.xz * e, gyy = dpy.xz * e;
            vec2 gzx = dpx.xy * e, gzy = dpy.xy * e;
            vec3 r = linealPBR(textureGrad(pbrAlbedo, vec3(ux, 3.0), gxx, gxy).rgb) * pesosRocaPbr.x
                + linealPBR(textureGrad(pbrAlbedo, vec3(uy, 3.0), gyx, gyy).rgb) * pesosRocaPbr.y
                + linealPBR(textureGrad(pbrAlbedo, vec3(uz, 3.0), gzx, gzy).rgb) * pesosRocaPbr.z;
            // Contra la repetición de lejos (las «f» en filas por la ladera,
            // el dueño 19-nov): la misma foto girada y ROCA_GRANDE veces más
            // grande, mezclada a manchas y más cuanto más lejos (la «distance
            // blend» de los paisajes de Unreal).
            float eg = ]] .. TerrenoPBR.rocaGrande .. [[;
            vec3 rg = linealPBR(textureGrad(pbrAlbedo, vec3(GIRO_PBR * ux * eg + vec2(0.37, 0.71), 3.0), GIRO_PBR * gxx * eg, GIRO_PBR * gxy * eg).rgb) * pesosRocaPbr.x
                + linealPBR(textureGrad(pbrAlbedo, vec3(GIRO_PBR * uy * eg + vec2(0.37, 0.71), 3.0), GIRO_PBR * gyx * eg, GIRO_PBR * gyy * eg).rgb) * pesosRocaPbr.y
                + linealPBR(textureGrad(pbrAlbedo, vec3(GIRO_PBR * uz * eg + vec2(0.37, 0.71), 3.0), GIRO_PBR * gzx * eg, GIRO_PBR * gzy * eg).rgb) * pesosRocaPbr.z;
            float grandeRoca = max(smoothstep(0.35, 0.65, ruidoSuelo(pPbr.xz * 0.045 + pPbr.y * 0.03)) * 0.6,
                smoothstep(40.0, 250.0, lejosPbr) * 0.75);
            r = mix(r, rg, grandeRoca);
            // El color del mapa con el dibujo de la foto (media 1), por
            // `brilloRoca`. Antes iba por 2,7 (de las texturas pintadas) y la
            // roca salía con albedo 0,6, blanquecina (el dueño, 19-nov).
            vec3 colorRoca = base * clamp(r / pbrMedia[3] * ]] .. TerrenoPBR.brilloRoca .. [[, vec3(0.15), vec3(2.0));
            if (cercaPbr > 0.0) {
                // Normales de las tres proyecciones, mezcla «whiteout»
                // (Ben Golus, «Normal Mapping for a Triplanar Shader»).
                vec4 hx = textureGrad(pbrNormal, vec3(ux, 3.0), gxx, gxy);
                vec4 hy = textureGrad(pbrNormal, vec3(uy, 3.0), gyx, gyy);
                vec4 hz = textureGrad(pbrNormal, vec3(uz, 3.0), gzx, gzy);
                vec3 nx = hx.xyz * 2.0 - 1.0;
                vec3 ny = hy.xyz * 2.0 - 1.0;
                vec3 nz = hz.xyz * 2.0 - 1.0;
            #ifdef MATERIAL_DETALLE
                // Detalle: la misma roca a 3,3 veces su escala, girada, en las
                // tres proyecciones (hasta la mitad de la distancia de cerca).
                float detRoca = (1.0 - smoothstep(pbrDistancias.x * 0.5, pbrDistancias.x, lejosPbr))
                    * FUERZA_DETALLE;
                if (detRoca > 0.0) {
                    float ed = 3.3;
                    vec3 dx3 = textureGrad(pbrNormal, vec3(GIRO_PBR * ux * ed, 3.0), GIRO_PBR * gxx * ed, GIRO_PBR * gxy * ed).xyz * 2.0 - 1.0;
                    vec3 dy3 = textureGrad(pbrNormal, vec3(GIRO_PBR * uy * ed, 3.0), GIRO_PBR * gyx * ed, GIRO_PBR * gyy * ed).xyz * 2.0 - 1.0;
                    vec3 dz3 = textureGrad(pbrNormal, vec3(GIRO_PBR * uz * ed, 3.0), GIRO_PBR * gzx * ed, GIRO_PBR * gzy * ed).xyz * 2.0 - 1.0;
                    nx = sumarNormal(nx, vec3(dx3.xy * GIRO_PBR * detRoca, dx3.z));
                    ny = sumarNormal(ny, vec3(dy3.xy * GIRO_PBR * detRoca, dy3.z));
                    nz = sumarNormal(nz, vec3(dz3.xy * GIRO_PBR * detRoca, dz3.z));
                }
            #endif
                nx = vec3(nx.xy + normalMundo.zy, abs(nx.z) * normalMundo.x);
                ny = vec3(ny.xy + normalMundo.xz, abs(ny.z) * normalMundo.y);
                nz = vec3(nz.xy + normalMundo.xy, abs(nz.z) * normalMundo.z);
                normalRocaPbr = normalize(nx.zyx * pesosRocaPbr.x + ny.xzy * pesosRocaPbr.y + nz.xyz * pesosRocaPbr.z);
                matRoca = textureGrad(pbrMaterial, vec3(uy, 3.0), gyx, gyy).xyz;
            #ifdef MATERIAL_ALTURA
                // La roca asoma entre la tierra por su altura.
                float aRoca = dot(vec3(hx.w, hy.w, hz.w), pesosRocaPbr) - pbrAlturaMedia[3] + 0.5;
                float aSueloRoca = mix(mix(nhVerde.w - pbrAlturaMedia[0], nhSeca.w - pbrAlturaMedia[1], pesoSeca),
                    nhTierra.w - pbrAlturaMedia[2], pesoTierra) + 0.5;
                rocaPbr = mix(rocaPbr, mezclaAltura(rocaPbr, aSueloRoca, aRoca, CONTRASTE_ALTURA), cercaPbr);
            #endif
            }
            colorPbr = mix(colorPbr, colorRoca * mix(1.0, brilloPbr, 0.4), rocaPbr);
        }

        // Relieve y material de cerca: de la capa que más pesa en el suelo.
        vec3 nSueloPbr = normalMundo;
        vec3 matPbr = vec3(0.0, 0.92, 1.0);
        float capa = pesoTierra > 0.5 ? 2.0 : (pesoSeca > 0.5 ? 1.0 : 0.0);
        capa = wArena > 0.5 ? 4.0 : (wNieve > 0.5 ? 5.0 : capa);
        if (cercaPbr > 0.0) {
        #ifdef MATERIAL_ALTURA
            // La normal de todas las capas con sus pesos (la arena, la nieve
            // y el barro de las orillas, la de su capa).
            vec3 tn = mix(mix(nhVerde.xyz, nhSeca.xyz, pesoSeca), nhTierra.xyz, pesoTierra);
            tn = mix(tn, nhPiedras.xyz, pesoPiedras);
            if (capa > 3.0 && capa < 6.0) {
                tn = normalCapa(capa, m, dmx, dmy);
            }
        #else
            vec3 tn = normalCapa(capa, m, dmx, dmy);
        #endif
            matPbr = materialCapa(capa, m, dmx, dmy);
            // Detalle: la misma capa a 3,7 veces su escala, en luminancia.
            float edPbr = pbrEscala[int(capa)] * 3.7;
            vec3 detPbr = linealPBR(textureGrad(pbrAlbedo, vec3(m * edPbr, capa), dmx * edPbr, dmy * edPbr).rgb);
            float lumPbr = dot(detPbr / pbrMedia[int(capa)], vec3(0.2126, 0.7152, 0.0722));
            colorPbr *= mix(1.0, clamp(lumPbr, 0.6, 1.5), 0.3 * cercaPbr * (1.0 - rocaPbr));
        #ifdef MATERIAL_DETALLE
            // Normal de detalle de la misma capa y escala.
            vec3 detN = textureGrad(pbrNormal, vec3(m * edPbr, capa), dmx * edPbr, dmy * edPbr).xyz * 2.0 - 1.0;
            tn = sumarNormal(tn, vec3(detN.xy * FUERZA_DETALLE, detN.z));
        #endif
            vec3 tanPbr = normalize(vec3(1.0, 0.0, 0.0) - normalMundo * normalMundo.x);
            vec3 bitPbr = cross(tanPbr, normalMundo);
            nSueloPbr = normalize(tanPbr * tn.x + bitPbr * tn.y + normalMundo * max(tn.z, 0.2));
        }

        albedo = colorPbr;
        vec3 nMezclaPbr = normalize(mix(nSueloPbr, normalRocaPbr, rocaPbr));
        normal = normalize(mix(normalMundo, nMezclaPbr, cercaPbr));
        // Sin reflejo rasante del cielo a lo lejos (como el follaje).
        normal = normalize(mix(normal, -viewVec, 0.25));
        vec3 mPbr = mix(matPbr, matRoca, rocaPbr);
        // La hierba y la tierra no brillan (con la rugosidad de las fotos, de
        // 0,6 a 0,8, el suelo reflejaba el cielo y se veía azulado).
        roughness = mix(0.95, clamp(mPbr.y, 0.88, 1.0), cercaPbr);
        metallic = 0.0;
        ao = mix(1.0, mix(1.0, mPbr.z, 0.7), cercaPbr);
        alpha = 1.0;

        // PBR_PESOS=1 (depuración): rojo camino, verde roca, azul hierba seca.
        ]] .. (os.getenv('PBR_PESOS') and 'albedo = vec3(vPesoA.w, vPesoB.z, vPesoA.x); normal = normalMundo;' or '') .. [[

        // Horizonte: como el estilo anterior (batalla/dream/textura_terreno.lua).
        float horizontePbr = smoothstep(5000.0, 8800.0, lejosPbr);
        albedo = mix(albedo, vec3(0.0), horizontePbr);
        emission = mix(vec3(0.0), vec3(0.612, 0.736, 0.893), horizontePbr);
        // PBR_ALBEDO=1 (depuración): el albedo sin luz.
        ]] .. (os.getenv('PBR_ALBEDO') and 'emission = albedo * 3.0; albedo = vec3(0.0);' or '') .. [[

    ]]
end

function TerrenoPBR:buildVertex(_, sombra)
    if sombra then
        return ''
    end
    return [[
        vPesoA = VertexPesoA;
        vPesoB = VertexPesoB;
        vPesoC = VertexPesoC;
    ]]
end

function TerrenoPBR:perMaterial(objetoSombreador, material)
    local sombreador = objetoSombreador.shader
    local t = material.texturasPbr
    if t then
        -- Cada uniforme solo si el compilador lo dejó (quita los que no se usan).
        local valores = t.uniformes
        if not valores then
            valores = {
                pbrAlbedo = { t.albedo },
                pbrNormal = { t.normal },
                pbrMaterial = { t.material },
                pbrEscala = t.escalas,
                pbrMedia = t.medias,
                pbrDistancias = { { TerrenoPBR.cercaHasta, TerrenoPBR.lejosDesde } },
                pbrAlturaMedia = t.alturasMedias or { 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 },
                pbrProfundidad = TerrenoPBR.profundidad,
                pbrPom = { { TerrenoPBR.pomDesde, TerrenoPBR.pomHasta } },
                pbrPomPasos = { TerrenoPBR.pomPasos },
            }
            t.uniformes = valores
        end
        for nombre, valor in pairs(valores) do
            if sombreador:hasUniform(nombre) then
                sombreador:send(nombre, unpack(valor))
            end
        end
    end
    if sombreador:hasUniform('mascaraSuelo') then
        local TexturaTerreno = require('batalla.dream.textura_terreno')
        sombreador:send('mascaraSuelo', material.mascaraSuelo or TexturaTerreno.blanca())
        sombreador:send('mascaraRect', material.mascaraRect or { -1, -1, 2, 2 })
    end
end

return TerrenoPBR
