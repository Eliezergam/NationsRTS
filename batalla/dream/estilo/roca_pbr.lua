-- Sombreador de píxeles de las rocas (`rocaPBR`, Valeria): la textura PBR de
-- roca de Camila (assets/texturas/batalla/roca, batalla/dream/texturas_pbr.lua)
-- proyectada desde los tres ejes del mundo (triplanar: no se estira ni tiene
-- costuras, sirva la forma que sirva), con su mapa de normales (mezcla
-- «whiteout») y su rugosidad. Las copias son estáticas: proyectar en el
-- espacio del mundo no hace que la textura «resbale».
--
-- Color: la foto se normaliza por su color medio y se lleva al de la roca
-- pintada de antes por el color del material (la misma paleta), y se tiñe con
-- el tono de cada copia (VaryingColor: quemada, derribada...). Como antes, la
-- normal se inclina un poco hacia la cámara (`haciaCamara`) para que las
-- caras de canto no se llenen del reflejo del cielo. Hasta `cercaHasta` m,
-- normales y material enteros; desde `lejosDesde` m, solo el color.
--
-- Normales de detalle (Fase 3 de PLAN-RENDER-UE.md, calidad media y alta:
-- `RocaPBR.opciones.detalle`, que pone batalla/dream/escena.lua): la misma
-- roca a `escalaDetalle` veces su escala, girada para que no coincida con la
-- grande, en las tres proyecciones y sumada a la normal («whiteout»). De
-- cerca las grietas y los granos tienen relieve; se apaga hacia `detalleHasta` m.

local RocaPBR = {}

RocaPBR.type = 'pixel'
RocaPBR.meshFormat = 'textured'
RocaPBR.cercaHasta = 40
RocaPBR.lejosDesde = 140
RocaPBR.haciaCamara = 0.15
-- Color medio (lineal) de la roca pintada de antes (batalla/dream/estilo/texturas.lua).
RocaPBR.mediaAntes = { 0.2315, 0.2509, 0.1941 }
RocaPBR.opciones = {}
RocaPBR.escalaDetalle = 3.3
RocaPBR.detalleHasta = 30 -- m
RocaPBR.fuerzaDetalle = 0.7

function RocaPBR:buildDefines(_, sombra)
    if sombra then
        return ''
    end
    local defines = ''
    if RocaPBR.opciones.detalle then
        defines = string.format(
            '#define ROCA_DETALLE\n#define ROCA_DETALLE_DESDE %.3f\n#define ROCA_DETALLE_HASTA %.3f\n'
                .. '#define ROCA_DETALLE_FUERZA %.3f\n#define ROCA_DETALLE_ESCALA %.3f\n',
            RocaPBR.detalleHasta * 0.5,
            RocaPBR.detalleHasta,
            RocaPBR.fuerzaDetalle,
            RocaPBR.escalaDetalle
        )
    end
    local codigo = [[
        #ifdef PIXEL
        uniform Image rocaAlbedo;
        uniform Image rocaNormal;
        uniform Image rocaMaterial;
        uniform vec4 albedoColor;
        uniform vec3 rocaMedia;
        uniform vec3 rocaMediaAntes;
        uniform float rocaEscala;
        uniform float haciaCamara;
        uniform vec2 rocaDistancias;
        #endif
    ]]
    return defines .. codigo
end

function RocaPBR:buildPixel(_, sombra)
    if sombra then
        return [[
            albedo = vec3(0.5);
            alpha = 1.0;
        ]]
    end
    -- vertexPos va en unidades de 3Dream (10 m): se pasa a metros.
    return [[
        vec3 nRoca = normalize(normal);
        vec3 pRoca = vertexPos * 10.0 * rocaEscala;
        vec3 dxRoca = dFdx(pRoca);
        vec3 dyRoca = dFdy(pRoca);
        float lejosRoca = length(viewPos - vertexPos) * 10.0;
        float cercaRoca = 1.0 - smoothstep(rocaDistancias.x, rocaDistancias.y, lejosRoca);
        vec3 pesosRoca = pow(abs(nRoca), vec3(4.0));
        pesosRoca /= pesosRoca.x + pesosRoca.y + pesosRoca.z;
        vec3 cRoca;
        if (cercaRoca > 0.0) {
            vec3 cx = textureGrad(rocaAlbedo, pRoca.zy, dxRoca.zy, dyRoca.zy).rgb;
            vec3 cy = textureGrad(rocaAlbedo, pRoca.xz, dxRoca.xz, dyRoca.xz).rgb;
            vec3 cz = textureGrad(rocaAlbedo, pRoca.xy, dxRoca.xy, dyRoca.xy).rgb;
            cRoca = cx * pesosRoca.x + cy * pesosRoca.y + cz * pesosRoca.z;
        } else if (pesosRoca.y >= pesosRoca.x && pesosRoca.y >= pesosRoca.z) {
            // Lejos, una sola proyección: la del eje dominante.
            cRoca = textureGrad(rocaAlbedo, pRoca.xz, dxRoca.xz, dyRoca.xz).rgb;
        } else if (pesosRoca.x >= pesosRoca.z) {
            cRoca = textureGrad(rocaAlbedo, pRoca.zy, dxRoca.zy, dyRoca.zy).rgb;
        } else {
            cRoca = textureGrad(rocaAlbedo, pRoca.xy, dxRoca.xy, dyRoca.xy).rgb;
        }
    #ifdef GAMMA_CORRECTION
        cRoca = pow(cRoca, vec3(2.2));
    #endif
        albedo = cRoca / max(rocaMedia, vec3(0.002)) * rocaMediaAntes * albedoColor.rgb * VaryingColor.rgb;
        alpha = 1.0;
        emission = vec3(0.0);
        metallic = 0.0;
        vec3 mRoca = vec3(0.0, 0.9, 1.0);
        if (cercaRoca > 0.0) {
            vec3 nx = textureGrad(rocaNormal, pRoca.zy, dxRoca.zy, dyRoca.zy).xyz * 2.0 - 1.0;
            vec3 ny = textureGrad(rocaNormal, pRoca.xz, dxRoca.xz, dyRoca.xz).xyz * 2.0 - 1.0;
            vec3 nz = textureGrad(rocaNormal, pRoca.xy, dxRoca.xy, dyRoca.xy).xyz * 2.0 - 1.0;
        #ifdef ROCA_DETALLE
            float detRoca = (1.0 - smoothstep(ROCA_DETALLE_DESDE, ROCA_DETALLE_HASTA, lejosRoca)) * ROCA_DETALLE_FUERZA;
            if (detRoca > 0.0) {
                const mat2 GIRO_ROCA = mat2(0.8, -0.6, 0.6, 0.8);
                float ed = ROCA_DETALLE_ESCALA;
                vec3 qx = textureGrad(rocaNormal, GIRO_ROCA * pRoca.zy * ed, GIRO_ROCA * dxRoca.zy * ed, GIRO_ROCA * dyRoca.zy * ed).xyz * 2.0 - 1.0;
                vec3 qy = textureGrad(rocaNormal, GIRO_ROCA * pRoca.xz * ed, GIRO_ROCA * dxRoca.xz * ed, GIRO_ROCA * dyRoca.xz * ed).xyz * 2.0 - 1.0;
                vec3 qz = textureGrad(rocaNormal, GIRO_ROCA * pRoca.xy * ed, GIRO_ROCA * dxRoca.xy * ed, GIRO_ROCA * dyRoca.xy * ed).xyz * 2.0 - 1.0;
                // «Whiteout»: suma de pendientes, producto de las z.
                nx = normalize(vec3(nx.xy + qx.xy * GIRO_ROCA * detRoca, nx.z * qx.z));
                ny = normalize(vec3(ny.xy + qy.xy * GIRO_ROCA * detRoca, ny.z * qy.z));
                nz = normalize(vec3(nz.xy + qz.xy * GIRO_ROCA * detRoca, nz.z * qz.z));
            }
        #endif
            nx = vec3(nx.xy + nRoca.zy, abs(nx.z) * nRoca.x);
            ny = vec3(ny.xy + nRoca.xz, abs(ny.z) * nRoca.y);
            nz = vec3(nz.xy + nRoca.xy, abs(nz.z) * nRoca.z);
            vec3 nMapa = normalize(nx.zyx * pesosRoca.x + ny.xzy * pesosRoca.y + nz.xyz * pesosRoca.z);
            nRoca = normalize(mix(nRoca, nMapa, cercaRoca));
            mRoca = textureGrad(rocaMaterial, pRoca.xz, dxRoca.xz, dyRoca.xz).xyz * pesosRoca.y
                + textureGrad(rocaMaterial, pRoca.zy, dxRoca.zy, dyRoca.zy).xyz * pesosRoca.x
                + textureGrad(rocaMaterial, pRoca.xy, dxRoca.xy, dyRoca.xy).xyz * pesosRoca.z;
        }
        roughness = mix(0.92, clamp(mRoca.y, 0.7, 1.0), cercaRoca);
        ao = mix(1.0, mix(1.0, mRoca.z, 0.8), cercaRoca);
        normal = normalize(mix(nRoca, -viewVec, haciaCamara));
    ]]
end

function RocaPBR:buildVertex()
    return ''
end

function RocaPBR:perMaterial(objetoSombreador, material)
    local sombreador = objetoSombreador.shader
    local t = material.texturaPbr
    if not t then
        return
    end
    local valores = t.uniformesRoca
    if not valores then
        valores = {
            rocaAlbedo = t.albedo,
            rocaNormal = t.normal,
            rocaMaterial = t.material,
            rocaMedia = t.media,
            rocaMediaAntes = RocaPBR.mediaAntes,
            rocaEscala = t.escala,
            rocaDistancias = { RocaPBR.cercaHasta, RocaPBR.lejosDesde },
        }
        t.uniformesRoca = valores
    end
    for nombre, valor in pairs(valores) do
        if sombreador:hasUniform(nombre) then
            sombreador:send(nombre, valor)
        end
    end
    if sombreador:hasUniform('albedoColor') then
        sombreador:send('albedoColor', material.color)
    end
    if sombreador:hasUniform('haciaCamara') then
        sombreador:send('haciaCamara', material.haciaCamara or RocaPBR.haciaCamara)
    end
end

return RocaPBR
