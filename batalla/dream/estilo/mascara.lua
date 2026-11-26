-- Máscara del suelo de la batalla (R = tierra, G = hierba seca), 2 m por
-- píxel sobre los 3 km del área: pinocha y tierra al pie de los pinos y los
-- abetos (como la máscara de la prueba de estrés de Camila,
-- batalla/pruebas_estilo/terreno_grande.lua), y algo de hierba seca bajo los
-- demás árboles. La lee el sombreador del terreno (textura_terreno.lua).

local ffi = require('ffi')
local Vegetacion = require('batalla.vegetacion')

local Mascara = {}

Mascara.metros = 2 -- metros por píxel

local M = 10 -- px por metro

--- Imagen de la máscara del suelo `suelo` y su rectángulo en metros desde
-- el centro del área (x, y, ancho, alto), como lo pide el sombreador.
function Mascara.crear(suelo)
    local inicio = love.timer.getTime()
    local metros = Mascara.metros
    local ladoM = suelo.lado / M
    local lado = math.ceil(ladoM / metros)
    local datos = love.image.newImageData(lado, lado, 'rgba8')
    local p = ffi.cast('uint8_t*', datos:getFFIPointer())
    for k = 0, lado * lado - 1 do
        p[k * 4 + 3] = 255
    end
    local mitad = ladoM / 2
    local pino = Vegetacion.porNombre.Pino.indice
    local abeto = Vegetacion.porNombre.Abeto.indice
    local arboles = {}
    for _, nombre in ipairs({ 'Roble', 'Alamo', 'Abedul', 'AbetoNevado' }) do
        arboles[Vegetacion.porNombre[nombre].indice] = true
    end
    for _, c in ipairs(suelo.copias) do
        local conifera = c.e == pino or c.e == abeto
        if conifera or arboles[c.e] then
            local cx = ((c.x - suelo.cx) / M + mitad) / metros
            local cy = ((c.y - suelo.cy) / M + mitad) / metros
            local escala = c.escala or 1
            local radioSeca = (conifera and 7 or 5) * escala / metros
            local radioTierra = (conifera and 4 or 0) * escala / metros
            local fuerzaSeca = conifera and 1 or 0.6
            local r = math.ceil(radioSeca)
            for y = math.max(0, math.floor(cy - r)), math.min(lado - 1, math.floor(cy + r)) do
                for x = math.max(0, math.floor(cx - r)), math.min(lado - 1, math.floor(cx + r)) do
                    local d = math.sqrt((x + 0.5 - cx) ^ 2 + (y + 0.5 - cy) ^ 2)
                    local k = (y * lado + x) * 4
                    if radioTierra > 0 then
                        local tierra = math.floor(math.max(0, 1 - d / radioTierra) * 255)
                        if tierra > p[k] then
                            p[k] = tierra
                        end
                    end
                    local seca = math.floor(math.max(0, 1 - d / radioSeca) * 255 * fuerzaSeca)
                    if seca > p[k + 1] then
                        p[k + 1] = seca
                    end
                end
            end
        end
    end
    local imagen = love.graphics.newImage(datos)
    imagen:setFilter('linear', 'linear')
    imagen:setWrap('clamp', 'clamp')
    print(string.format('ESTILO máscara del suelo %d x %d en %.2f s', lado, lado, love.timer.getTime() - inicio))
    return imagen, { -mitad, -mitad, lado * metros, lado * metros }
end

return Mascara
