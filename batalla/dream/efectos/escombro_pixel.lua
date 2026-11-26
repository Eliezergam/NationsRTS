-- Sombreador de píxeles de los escombros (Camila): color de la copia,
-- rugoso; las chapas (vEfecto.z) algo metálicas. Opacos: van en el paso
-- normal de 3Dream, con su sombra y su niebla.

local Sombreador = {}

Sombreador.type = 'pixel'
Sombreador.meshFormat = 'textured'

function Sombreador:buildPixel()
    return [[
        albedo = VaryingColor.rgb;
        alpha = 1.0;
        metallic = vEfecto.z;
        roughness = 0.9 - vEfecto.z * 0.45;
        emission = vec3(0.0);
    ]]
end

return Sombreador
