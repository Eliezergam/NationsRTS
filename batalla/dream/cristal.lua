-- Sombreador de mundo de los cristales (`cristalBatalla`, Valeria): vidrio
-- fino como el de Unreal (material «Thin Translucent»), para los materiales
-- de la biblioteca con `alpha` (las ventanillas y el parabrisas del camión de
-- 4 misiles, assets/modelos3d/materiales/unidadCamion4Cristal).
--
-- Con el PBR de 3Dream el cristal era una capa oscura al 35 %: el reflejo
-- del cielo también se multiplicaba por el alfa, y con el metálico 0,3 y el
-- color casi negro su F0 bajaba al 3 %. Ahora:
--   * Reflejo: el cielo prefiltrado (IBL) con el Fresnel de un dieléctrico
--     (F0 = 0,04) de la tabla BRDF, más el brillo del sol (`light`); no se
--     atenúa con el alfa. Una lámina tiene dos caras (fuera y dentro) y el
--     cristal es una caja de la que solo se dibuja la de fuera: su reflejo
--     es el de las dos, 2R / (1 + R) (un 7,7 % de frente). Al ras refleja
--     casi todo.
--   * Paso de la luz: lo de detrás llega por (1 - alfa) x (1 - reflejo), con
--     el alfa del material como lo que tiñe el vidrio.
-- Se compone con la mezcla premultiplicada del paso alfa (base.glsl
-- multiplica `color` por `alpha`): color = (reflejo + tinte) / cubre y
-- alpha = cubre = 1 - (1 - alfa) x (1 - reflejo).
--
-- Sin la luz del cielo física (IBL_FISICO) o fuera del paso alfa (el fundido
-- entre niveles, tramado), el PBR de siempre. El resto (getLight, uniforms)
-- es el del PBR de 3Dream.

local Cristal = {}

Cristal.type = 'world'

local function pbr()
    return _3DreamEngine:getShader('PBR')
end

function Cristal:buildDefines(material, sombra)
    return pbr():buildDefines(material, sombra)
end

function Cristal:buildFlags(material, sombra)
    return pbr():buildFlags(material, sombra)
end

function Cristal:buildVertex(material, sombra)
    return pbr():buildVertex(material, sombra)
end

function Cristal:buildPixel(material, sombra)
    local original = pbr():buildPixel(material, sombra)
    if sombra then
        return original
    end
    return [[
    #if defined(IBL_FISICO) && defined(ALPHA_PASS)
    {
        float NoV = clamp(-dot(normal, viewVec), 0.0, 1.0);
        vec3 reflectVec = reflect(viewVec, normal);
        vec3 irr = gammaCorrectedTexel(irradianceTexture, normal * vec3(1.0, 1.0, -1.0), 0.0).rgb;
        vec2 brdf = textureLod(brdfLUT, vec2(NoV, roughness), 0.0).rg;
        float cara = 0.04 * brdf.x + brdf.y;
        float reflejo = 2.0 * cara / (1.0 + cara);
        vec3 geom = normalize(gl_FrontFacing ? varyingNormal : -varyingNormal);
        float horizon = clamp(1.0 + dot(reflectVec, geom), 0.0, 1.0);
        vec3 especular = reflection(reflectVec, roughness) * reflejo * horizon * horizon;
        vec3 tinte = irr * albedo.rgb * alpha * (1.0 - reflejo);
        float cubre = 1.0 - (1.0 - alpha) * (1.0 - reflejo);
        color = (especular + light + emission + tinte) / max(cubre, 0.001);
        alpha = cubre;
    }
    #else
    ]] .. original .. [[
    #endif
    ]]
end

function Cristal:perShader(objeto)
    pbr():perShader(objeto)
end

function Cristal:perMaterial(objeto, material)
    pbr():perMaterial(objeto, material)
end

function Cristal:perTask(objeto, tarea)
    pbr():perTask(objeto, tarea)
end

return Cristal
