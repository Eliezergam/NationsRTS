-- Sombreador del suelo del mapa de campaña (`mapaCampana`, Valeria): el
-- `textured` de 3DreamEngine con su propio color y su propia normal.
--
-- 1. Color y normal del mapa (tools/mapa/caucaso.py, ~185 m por píxel). El
--    mapa de normales ya es la normal del mundo (rojo: este, verde: norte,
--    azul: arriba) y se lee tal cual, sin la base tangente: los vértices
--    llevan la normal de la malla (campana/relieve.lua), que usan el sesgo de
--    la sombra del sol y el horizonte de los reflejos. De cerca (hasta
--    `normalMalla` km) manda la normal de la malla, que allí tiene las
--    alturas a 92 m, más finas que el mapa de normales.
-- 2. Detalle de cerca con las texturas PBR de la batalla (Camila,
--    batalla/dream/texturas_pbr.lua): hierba, hierba seca, acantilado, arena,
--    nieve y tierra pedregosa. La capa sale del color del mapa (verde: hierba;
--    amarillo: hierba seca; pardo: tierra; gris: roca; blanco: nieve), de la
--    pendiente de la malla (roca, con el color de su foto) y de la distancia
--    al mar (la arena, ~150 m, a cualquier distancia: el mapa de color ya no
--    trae la franja de playa a escalones; assets/mapa/caucaso_costa.png). La
--    textura no pone su color:
--    multiplica el del mapa por su variación respecto a su color medio (como
--    el tinte del suelo de la batalla), así el mapa sigue mandando y no se
--    lava. Dos escalas (`escalas`, en km) contra la repetición; la roca, en
--    proyección triplanar para que no se estire en las laderas. Las normales
--    de las capas se suman a la del mapa. Se apaga entre `distancias` km del
--    ojo (de lejos los mipmaps ya lo promedian a su color medio).
-- 3. Normal enderezada hacia la cámara. El mapa de normales tiene más
--    detalle que la malla lejana: en las laderas que la malla aún enseña, la
--    normal fina puede mirar de espaldas al ojo, y el reflejo del cielo
--    (Fresnel) pintaba una raya clara en cada cresta. Si mira a menos de
--    `minimo` hacia el ojo, se gira hacia él lo justo.
--
-- 3Dream registra el sombreador con `setmetatable(tabla, meta.shader)`: una
-- metatabla propia se perdería (y con ella `type`), así que se copian los
-- campos del `textured`.

local TexturasPbr = require('batalla.dream.texturas_pbr')

local base = love.filesystem.load('lib/3DreamEngine/shaders/inbuilt/textured.lua')()

local Sombreador = {}

for clave, valor in pairs(base) do
    Sombreador[clave] = valor
end

Sombreador.minimo = 0.2
-- La normal de la malla hasta el primer valor (km del ojo) y la del mapa de
-- normales desde el segundo.
Sombreador.normalMalla = { 10, 20 }
-- Tamaño de las dos escalas de las texturas de detalle, en km.
Sombreador.escalas = { 0.09, 0.55 }
-- El detalle entero hasta el primer valor (km del ojo) y nada desde el segundo.
Sombreador.distancias = { 25, 70 }
-- Fuerza del detalle en el color y en la normal.
Sombreador.fuerzaColor = 1.0
Sombreador.fuerzaNormal = 0.55

--- Las capas PBR de la batalla (en calidad media, 1024 px).
function Sombreador.cargarDetalle()
    return TexturasPbr.terreno({ nombre = 'alta' })
end

function Sombreador:getId(material, sombra)
    if sombra or not material.detalleCampana then
        return base.getId(self, material, sombra)
    end
    return base.getId(self, material, sombra) + 64
end

function Sombreador:buildDefines(material, sombra)
    local codigo = base.buildDefines(self, material, sombra)
    if sombra or not material.detalleCampana then
        return codigo
    end
    return codigo
        .. [[
#ifdef PIXEL
#define DETALLE_CAMPANA
uniform ArrayImage detalleAlbedo;
uniform ArrayImage detalleNormal;
uniform vec3 detalleMedia[7];
uniform vec2 detalleEscalas;
uniform vec2 detalleDistancias;
uniform vec2 detalleFuerza;
uniform Image costaTexture;

const mat2 GIRO_DETALLE = mat2(0.8, -0.6, 0.6, 0.8);

vec3 linealDetalle(vec3 c) {
#ifdef GAMMA_CORRECTION
    return pow(c, vec3(2.2));
#else
    return c;
#endif
}

// Variación de la capa en `p` (metros de un plano): su color entre su color
// medio, en las dos escalas (la segunda girada).
vec3 variacionCapa(int capa, vec2 p, vec2 dx, vec2 dy) {
    float ea = detalleEscalas.x;
    float eb = detalleEscalas.y;
    vec3 a = linealDetalle(textureGrad(detalleAlbedo, vec3(p * ea, float(capa)), dx * ea, dy * ea).rgb);
    vec2 q = GIRO_DETALLE * p * eb + vec2(0.37, 0.71);
    vec3 b = linealDetalle(textureGrad(detalleAlbedo, vec3(q, float(capa)), GIRO_DETALLE * dx * eb, GIRO_DETALLE * dy * eb).rgb);
    vec3 media = max(detalleMedia[capa], vec3(0.002));
    return (a / media) * mix(vec3(1.0), b / media, 0.6);
}

// Normal de la capa (de -1 a 1, z hacia fuera del plano) en la escala fina.
vec3 normalCapa(int capa, vec2 p, vec2 dx, vec2 dy) {
    float ea = detalleEscalas.x;
    return textureGrad(detalleNormal, vec3(p * ea, float(capa)), dx * ea, dy * ea).xyz * 2.0 - 1.0;
}
#endif
]]
end

function Sombreador:buildPixel(material, sombra)
    local codigo = string.format(
        [[
	vec4 c = gammaCorrectedTexel(albedoTexture, VaryingTexCoord.xy) * albedoColor;
	vec3 colorMapa = Texel(albedoTexture, VaryingTexCoord.xy).rgb;
	albedo = c.rgb;
	alpha = c.a;
	metallic = materialColor.x;
	roughness = materialColor.y;
	emission = albedoColor.rgb * emissionColor;
#ifdef NORMAL_TEXTURE
	{
		// De cerca, la normal de la malla (las alturas a 92 m, más finas que
		// el mapa de normales); desde `normalMalla` km, la del mapa.
		vec3 mapa = Texel(normalTexture, VaryingTexCoord.xy).xyz * 2.0 - 1.0;
		vec3 normalMapa = normalize(vec3(mapa.x, mapa.z, -mapa.y));
		float malla = 1.0 - smoothstep(%.1f, %.1f, distance(vertexPos, viewPos));
		normal = normalize(mix(normalMapa, normal, malla));
	}
#endif
#ifdef DETALLE_CAMPANA
	{
		// Metros del mundo en los tres planos y sus derivadas (fuera de las
		// ramas: dentro de un if que no toman los vecinos, dFdx no vale).
		vec3 m = vertexPos * 1000.0;
		vec2 pArriba = m.xz;
		vec2 pFrente = m.xy;
		vec2 pLado = m.zy;
		vec2 dxArriba = dFdx(pArriba);
		vec2 dyArriba = dFdy(pArriba);
		vec2 dxFrente = dFdx(pFrente);
		vec2 dyFrente = dFdy(pFrente);
		vec2 dxLado = dFdx(pLado);
		vec2 dyLado = dFdy(pLado);
		// Playa: ~150 m junto al mar, de la distancia a la orilla
		// (caucaso_costa.png, un campo de distancias: interpolado, la orilla
		// sale suave a cualquier escala), con el borde suavizado al píxel.
		float costa = Texel(costaTexture, VaryingTexCoord.xy).r * 2.55;
		float bordeCosta = fwidth(costa);
		float arena = (1.0 - smoothstep(0.15 - bordeCosta, 0.15 + bordeCosta, costa)) * (1.0 - smoothstep(0.02, 0.05, vertexPos.y));
		albedo = mix(albedo, linealDetalle(vec3(0.66, 0.60, 0.45)), arena);
		float cerca = 1.0 - smoothstep(detalleDistancias.x, detalleDistancias.y, distance(vertexPos, viewPos));
		if (cerca > 0.0) {
			// Capas por el color del mapa (con su gamma, como lo pinta caucaso.py).
			float mayor = max(colorMapa.r, max(colorMapa.g, colorMapa.b));
			float menor = min(colorMapa.r, min(colorMapa.g, colorMapa.b));
			float saturacion = (mayor - menor) / max(mayor, 0.001);
			float bajo = smoothstep(0.02, 0.04, vertexPos.y);
			float nieve = smoothstep(0.6, 0.78, menor) * (1.0 - arena);
			// En lo bajo no hay roca por color (la orilla del mapa mezcla el mar
			// y sale gris).
			float rocaColor = (1.0 - smoothstep(0.13, 0.22, saturacion)) * bajo;
			// Pendiente de la malla de cerca: con la exageración x3, n.y 0,45 es
			// una ladera real de ~33°. Ahí la roca pone su propio color (el del
			// mapa, a 185 m por píxel, la emborrona).
			float rocaPendiente = 1.0 - smoothstep(0.42, 0.52, normal.y);
			float roca = max(rocaColor, rocaPendiente) * (1.0 - nieve) * (1.0 - arena);
			float resto = max(1.0 - nieve - roca - arena, 0.0);
			float hierba = smoothstep(0.02, 0.1, colorMapa.g - colorMapa.r) * resto;
			resto -= hierba;
			float tierra = smoothstep(0.03, 0.08, colorMapa.r - colorMapa.g) * resto;
			float seca = resto - tierra;
			// Pesos de la proyección triplanar (la roca).
			vec3 pesoPlano = pow(abs(normal), vec3(4.0));
			pesoPlano /= pesoPlano.x + pesoPlano.y + pesoPlano.z;

			vec3 variacion = vec3(0.0);
			vec3 inclinar = vec3(0.0);
			// Capas del ArrayImage: 0 hierba, 1 hierba seca, 4 arena, 5 nieve, 6 tierra pedregosa.
			if (hierba > 0.01) {
				variacion += hierba * variacionCapa(0, pArriba, dxArriba, dyArriba);
				vec3 n = normalCapa(0, pArriba, dxArriba, dyArriba);
				inclinar += hierba * vec3(n.x, 0.0, n.y);
			}
			if (seca > 0.01) {
				variacion += seca * variacionCapa(1, pArriba, dxArriba, dyArriba);
				vec3 n = normalCapa(1, pArriba, dxArriba, dyArriba);
				inclinar += seca * vec3(n.x, 0.0, n.y);
			}
			if (arena > 0.01) {
				variacion += arena * variacionCapa(4, pArriba, dxArriba, dyArriba);
				vec3 n = normalCapa(4, pArriba, dxArriba, dyArriba);
				inclinar += arena * vec3(n.x, 0.0, n.y);
			}
			if (nieve > 0.01) {
				variacion += nieve * variacionCapa(5, pArriba, dxArriba, dyArriba);
				vec3 n = normalCapa(5, pArriba, dxArriba, dyArriba);
				inclinar += nieve * vec3(n.x, 0.0, n.y);
			}
			if (tierra > 0.01) {
				variacion += tierra * variacionCapa(6, pArriba, dxArriba, dyArriba);
				vec3 n = normalCapa(6, pArriba, dxArriba, dyArriba);
				inclinar += tierra * vec3(n.x, 0.0, n.y);
			}
			if (roca > 0.01) {
				// Acantilado (capa 3) en los tres planos.
				vec3 v = variacionCapa(3, pArriba, dxArriba, dyArriba) * pesoPlano.y;
				v += variacionCapa(3, pFrente, dxFrente, dyFrente) * pesoPlano.z;
				v += variacionCapa(3, pLado, dxLado, dyLado) * pesoPlano.x;
				variacion += roca * v;
				vec3 na = normalCapa(3, pArriba, dxArriba, dyArriba);
				vec3 nf = normalCapa(3, pFrente, dxFrente, dyFrente);
				vec3 nl = normalCapa(3, pLado, dxLado, dyLado);
				inclinar += roca * (vec3(na.x, 0.0, na.y) * pesoPlano.y + vec3(nf.x, nf.y, 0.0) * pesoPlano.z + vec3(0.0, nl.y, nl.x) * pesoPlano.x);
			}
			// La roca de las pendientes, con el color de la foto del acantilado.
			albedo = mix(albedo, detalleMedia[3], rocaPendiente * (1.0 - nieve) * (1.0 - arena) * cerca);
			// Sin cambiar el tono del mapa: la variación, a medias hacia su luminancia.
			float luz = dot(variacion, vec3(0.2126, 0.7152, 0.0722));
			variacion = clamp(mix(vec3(luz), variacion, 0.5), vec3(0.35), vec3(2.2));
			albedo *= mix(vec3(1.0), variacion, detalleFuerza.x * cerca);
			normal = normalize(normal + inclinar * detalleFuerza.y * cerca);
		}
	}
#endif
	{
		vec3 haciaOjo = -viewVec;
		float frente = dot(normal, haciaOjo);
		if (frente < %.3f) {
			normal = normalize(normal + haciaOjo * (%.3f - frente));
		}
	}
]],
        Sombreador.normalMalla[1],
        Sombreador.normalMalla[2],
        Sombreador.minimo,
        Sombreador.minimo
    )
    if sombra then
        return base.buildPixel(self, material, sombra)
    end
    return codigo
end

function Sombreador:perMaterial(objetoSombreador, material)
    base.perMaterial(self, objetoSombreador, material)
    local detalle = material.detalleCampana
    local sombreador = objetoSombreador.shader
    if not detalle or not sombreador:hasUniform('detalleAlbedo') then
        return
    end
    sombreador:send('detalleAlbedo', detalle.albedo)
    if sombreador:hasUniform('detalleNormal') then
        sombreador:send('detalleNormal', detalle.normal)
    end
    sombreador:send('detalleMedia', unpack(detalle.medias))
    sombreador:send('detalleEscalas', { 0.001 / Sombreador.escalas[1], 0.001 / Sombreador.escalas[2] })
    sombreador:send('detalleDistancias', Sombreador.distancias)
    sombreador:send('detalleFuerza', { Sombreador.fuerzaColor, Sombreador.fuerzaNormal })
    if material.costaCampana and sombreador:hasUniform('costaTexture') then
        sombreador:send('costaTexture', material.costaCampana)
    end
end

return Sombreador
