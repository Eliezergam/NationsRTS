-- Atmósfera física de la batalla (Valeria): el modelo de Hillaire (2020), el
-- del Sky Atmosphere de Unreal, con sus valores por defecto (los de la
-- referencia de Unreal 5.8, ue_ref/escena_info.json). De ella salen el cielo
-- que se ve, el color del sol (más naranja cuanto más bajo) y, por
-- batalla/dream/ibl.lua, la luz del cielo y la niebla.
--
-- Tablas (sombreadores en batalla/dream/sombreadores/atmosfera_*.glsl):
--   transmitancia  256 x 64   una vez
--   multiple       32 x 32    una vez (dispersión de orden 2 o más)
--   vista          192 x 108  cuando el sol se mueve (el sol y la luna juntos)
--   irradiancia    1 x 1      con la vista: la luz del cielo sobre el suelo
--
-- Unidades: la iluminancia del sol en la cima (`luzSol`) es la de la luz del
-- sol de 3Dream (albedo / pi * color * brillo * coseno). Con transmitancia, el
-- sol a 50° llega con ~0,85 de ella y el cielo pone lo que dé la física.

local Atmosfera = {}
Atmosfera.__index = Atmosfera

Atmosfera.radioSuelo = 6360 -- km, como en los sombreadores
Atmosfera.radioCima = 6420
Atmosfera.alturaOjo = 0.05 -- km: la batalla está a ras de suelo
Atmosfera.radioAngularSol = math.rad(0.2725) -- el del sol real (0,545° de diámetro)
-- Aerosoles (Mie) respecto a los de Unreal por defecto, que son de aire muy
-- limpio (espesor óptico 0,005; en un día claro real, de 0,05 a 0,2). Con 12
-- (0,06) el cielo pone el 15 % de la luz del suelo horizontal con el sol a
-- 50° (con 1, el 8,5 %): lo que se mide en la referencia de Unreal, donde
-- el resto lo añade su iluminación global (Lumen).
Atmosfera.escalaMie = 12
-- Cielo cubierto, gris plomizo (el dueño, 17-nov: «no quiero tanta claridad,
-- que se sienta el campo de batalla hostil, apagado»): mezcla con el físico
-- (0 nada, 1 todo), el gris (un poco frío) y cuánta luz pierde.
Atmosfera.cubierto = 0.85
Atmosfera.colorCubierto = { 0.92, 0.95, 1.0 }
Atmosfera.oscurecerCubierto = 0.45

local CARPETA = 'batalla/dream/sombreadores/'

local function leer(nombre)
    return assert(love.filesystem.read(CARPETA .. nombre .. '.glsl'), 'falta ' .. nombre)
end

--- Sombreador con las piezas comunes delante (`piezas`, nombres de archivo).
function Atmosfera.sombreador(piezas, principal)
    local partes = { '#pragma language glsl3\n' }
    for _, nombre in ipairs(piezas) do
        partes[#partes + 1] = leer(nombre)
    end
    partes[#partes + 1] = leer(principal)
    return love.graphics.newShader(table.concat(partes, '\n'))
end

local pixel

--- `sombreador:send` solo si el uniform existe (el compilador quita los que no
-- se usan y LÖVE da error al enviarlos).
function Atmosfera.enviar(sombreador, nombre, valor)
    if sombreador:hasUniform(nombre) then
        sombreador:send(nombre, valor)
    end
end

local enviar = Atmosfera.enviar

--- Dibuja `sombreador` llenando `destino` (o su cara y nivel) de `ancho` x `alto`.
function Atmosfera.pasada(destino, sombreador, ancho, alto, cara, nivel)
    if sombreador:hasUniform('escalaMie') then
        sombreador:send('escalaMie', Atmosfera.escalaMie)
    end
    if not pixel then
        pixel = love.graphics.newImage(love.image.newImageData(1, 1, 'rgba8', string.rep('\255', 4)))
    end
    love.graphics.push('all')
    love.graphics.reset()
    if cara or nivel then
        love.graphics.setCanvas({ { destino, face = cara or 1, mipmap = nivel or 1 } })
    else
        love.graphics.setCanvas(destino)
    end
    love.graphics.setBlendMode('replace', 'premultiplied')
    love.graphics.setShader(sombreador)
    love.graphics.draw(pixel, 0, 0, 0, ancho, alto)
    love.graphics.pop()
end

local function lienzo(ancho, alto, formato)
    local c = love.graphics.newCanvas(ancho, alto, { format = formato or 'rgba16f', dpiscale = 1 })
    c:setFilter('linear', 'linear')
    c:setWrap('clamp', 'clamp')
    return c
end

--- La atmósfera con sus tablas fijas ya calculadas. `opciones.albedoSuelo`:
-- {r, g, b} lineal del suelo (para la dispersión múltiple).
function Atmosfera.nueva(opciones)
    opciones = opciones or {}
    local self = setmetatable({}, Atmosfera)
    self.albedoSuelo = opciones.albedoSuelo or { 0.3, 0.3, 0.3 }
    local comun = { 'atmosfera_comun' }
    local lectura = { 'atmosfera_comun', 'atmosfera_lectura' }
    self.sombreadores = {
        transmitancia = Atmosfera.sombreador(comun, 'atmosfera_transmitancia'),
        multiple = Atmosfera.sombreador(comun, 'atmosfera_multiple'),
        vista = Atmosfera.sombreador(comun, 'atmosfera_vista'),
        irradiancia = Atmosfera.sombreador(lectura, 'atmosfera_irradiancia'),
        cielo = Atmosfera.sombreador(lectura, 'atmosfera_cielo'),
        cara = Atmosfera.sombreador({ 'atmosfera_comun', 'atmosfera_lectura', 'cubo_comun' }, 'atmosfera_cara'),
    }
    self.transmitancia = lienzo(256, 64)
    self.multiple = lienzo(32, 32)
    self.vista = lienzo(192, 108)
    self.irradiancia = lienzo(1, 1)
    Atmosfera.pasada(self.transmitancia, self.sombreadores.transmitancia, 256, 64)
    local s = self.sombreadores.multiple
    enviar(s, 'transmitancia', self.transmitancia)
    enviar(s, 'albedoSuelo', self.albedoSuelo)
    Atmosfera.pasada(self.multiple, s, 32, 32)
    self.solDir = { 0, 1, 0 }
    self.luzSol = { 0, 0, 0 }
    self.luzLuna = { 0, 0, 0 }
    self.version = 0
    return self
end

local function radioOjo()
    return Atmosfera.radioSuelo + Atmosfera.alturaOjo
end

--- Densidades del medio a `h` km (las de atmosfera_comun.glsl): extinción r, g, b.
local function extincion(h)
    h = math.max(h, 0)
    local dr = math.exp(-h / 8)
    local dm = math.exp(-h / 1.2) * Atmosfera.escalaMie
    local oz = math.max(0, 1 - math.abs(h - 25) / 15)
    return 5.802e-3 * dr + 4.440e-3 * dm + 0.650e-3 * oz,
        13.558e-3 * dr + 4.440e-3 * dm + 1.881e-3 * oz,
        33.1e-3 * dr + 4.440e-3 * dm + 0.085e-3 * oz
end

--- Transmitancia de la atmósfera desde el ojo hacia una dirección de altura
-- `mu` (coseno del cenit), en la CPU como en el sombreador: 0 si va al suelo.
function Atmosfera.transmitancia(mu)
    local r = radioOjo()
    local rg, rt = Atmosfera.radioSuelo, Atmosfera.radioCima
    local sen = math.sqrt(math.max(0, 1 - mu * mu))
    -- ¿Toca el suelo? (rayo desde (0, r) en la dirección (sen, mu))
    local b = r * mu
    local disc = b * b - (r * r - rg * rg)
    if disc >= 0 and -b - math.sqrt(disc) > 0 then
        return 0, 0, 0
    end
    disc = b * b - (r * r - rt * rt)
    local largo = -b + math.sqrt(math.max(disc, 0))
    local pasos = 40
    local dt = largo / pasos
    local ar, ag, ab = 0, 0, 0
    for i = 0, pasos - 1 do
        local t = (i + 0.5) * dt
        local x, y = sen * t, r + mu * t
        local er, eg, eb = extincion(math.sqrt(x * x + y * y) - rg)
        ar, ag, ab = ar + er * dt, ag + eg * dt, ab + eb * dt
    end
    return math.exp(-ar), math.exp(-ag), math.exp(-ab)
end

--- Pone el sol (dirección hacia él, Y arriba) y las iluminancias en la cima
-- del sol y de la luna para el cielo ({r, g, b}). Rehace la vista y la
-- irradiancia si cambiaron; devuelve true en ese caso.
function Atmosfera:actualizar(solDir, luzSol, luzLuna)
    local d = self.solDir
    local cambio = (d[1] * solDir[1] + d[2] * solDir[2] + d[3] * solDir[3]) < math.cos(math.rad(0.25))
    for k = 1, 3 do
        local a, b = self.luzSol[k], luzSol[k]
        if math.abs(a - b) > 0.005 * math.max(a, b, 1e-3) then
            cambio = true
        end
        a, b = self.luzLuna[k], luzLuna[k]
        if math.abs(a - b) > 0.005 * math.max(a, b, 1e-3) then
            cambio = true
        end
    end
    if not cambio and self.version > 0 then
        return false
    end
    self.solDir = { solDir[1], solDir[2], solDir[3] }
    self.luzSol = { luzSol[1], luzSol[2], luzSol[3] }
    self.luzLuna = { luzLuna[1], luzLuna[2], luzLuna[3] }
    local s = self.sombreadores.vista
    enviar(s, 'transmitancia', self.transmitancia)
    enviar(s, 'multiple', self.multiple)
    enviar(s, 'radioOjo', radioOjo())
    enviar(s, 'muSol', solDir[2])
    enviar(s, 'luzSol', self.luzSol)
    enviar(s, 'luzLuna', self.luzLuna)
    Atmosfera.pasada(self.vista, s, 192, 108)
    s = self.sombreadores.irradiancia
    self:enviarLectura(s)
    Atmosfera.pasada(self.irradiancia, s, 1, 1)
    self.version = self.version + 1
    return true
end

--- Uniforms de la lectura del cielo (atmosfera_lectura.glsl).
function Atmosfera:enviarLectura(s)
    enviar(s, 'escalaMie', Atmosfera.escalaMie)
    enviar(s, 'vistaCielo', self.vista)
    enviar(s, 'solDir', self.solDir)
    enviar(s, 'radioOjo', radioOjo())
    enviar(s, 'cubierto', Atmosfera.cubierto)
    enviar(s, 'colorCubierto', Atmosfera.colorCubierto)
    enviar(s, 'oscurecerCubierto', Atmosfera.oscurecerCubierto)
end

--- Pinta la cara `cara` (1 a 6) del cubo `destino` de `lado` px con la luz
-- del cielo y del suelo (para batalla/dream/ibl.lua). `luzSuelo`: la
-- iluminancia directa que recibe el suelo ({r, g, b}); `refuerzo`: escala
-- de la luz del cielo (más de noche).
function Atmosfera:pintarCara(destino, cara, lado, luzSuelo, albedoSuelo, refuerzo)
    local s = self.sombreadores.cara
    self:enviarLectura(s)
    enviar(s, 'cara', cara - 1)
    enviar(s, 'irradianciaCielo', self.irradiancia)
    enviar(s, 'luzSuelo', luzSuelo)
    enviar(s, 'albedoSuelo', albedoSuelo)
    enviar(s, 'refuerzo', refuerzo or 1)
    Atmosfera.pasada(destino, s, lado, lado, cara, 1)
end

--- Dibuja el cielo en el cubo de 3Dream (dentro de `dream:setSky`), con el
-- disco del sol de iluminancia `brilloSol` (la de la cima) y las estrellas
-- con `fuerzaEstrellas` (cubo `estrellas`, giro `giro` mat3).
function Atmosfera:dibujar(dream, transformProj, brilloSol, estrellas, fuerzaEstrellas, giro)
    local s = self.sombreadores.cielo
    love.graphics.setShader(s)
    self:enviarLectura(s)
    enviar(s, 'transmitancia', self.transmitancia)
    enviar(s, 'transformProj', transformProj)
    local radio = Atmosfera.radioAngularSol
    local angulo = 2 * math.pi * (1 - math.cos(radio))
    local disco = brilloSol / angulo
    enviar(s, 'discoSol', { disco, disco, disco })
    enviar(s, 'cosRadioSol', math.cos(radio))
    enviar(s, 'estrellas', estrellas)
    enviar(s, 'fuerzaEstrellas', fuerzaEstrellas)
    enviar(s, 'giroEstrellas', giro)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(dream.cubeObject.meshes.Cube:getMesh())
end

return Atmosfera
