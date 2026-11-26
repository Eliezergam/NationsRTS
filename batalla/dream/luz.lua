-- Luz y cielo de la batalla según la hora del mundo (Valeria). El recorrido
-- del sol y de la luna, la luna, las estrellas y las nubes son los de la
-- extensión `sky` de 3DreamEngine (`sky:setDaytime(sol, hora)`); el cielo, el
-- color del sol, la luz del cielo y el color de la niebla salen de una
-- atmósfera física, como en Unreal (batalla/dream/atmosfera.lua, ibl.lua y
-- oclusion.lua; plan en batalla/dream/PLAN-RENDER-UE.md).
--
-- La hora sale del reloj de la simulación (`Simulacion:ahora()`: el día más la
-- fracción transcurrida). La vista solo la lee.
--
-- Correspondencia con la hora de la extensión (0 amanecer, 0,25 mediodía,
-- 0,5 puesta, 0,75 medianoche): el día del juego empieza al amanecer y la luz
-- de sol dura `Luz.parteDeSol` del día; el resto es noche, con la misma
-- velocidad repartida en la otra mitad de la vuelta. Con 0,62:
--   fracción 0      amanecer
--   fracción 0,155  media mañana
--   fracción 0,31   mediodía
--   fracción 0,56   atardecer (sol bajo y naranja)
--   fracción 0,62   puesta
--   fracción 0,81   medianoche (luna en lo alto y estrellas)
--
-- Lo que espera 3DreamEngine (leído en lib/3DreamEngine):
-- - `light.direction` apunta HACIA el sol, en ejes de Dream (Y arriba).
-- - El sol ilumina con `albedo / pi * color * brillo * cos`; la curva tonal
--   la pone batalla/dream/tono.lua (3Dream no tiene una).
-- - La luz ambiente es la del cielo capturado en un cubo (batalla/dream/ibl.lua):
--   irradiancia difusa, especular prefiltrado y, abajo, el suelo iluminado.
--   De noche se refuerza (`Luz.refuerzoNoche`) para que el campo no quede negro.

local dream = require('lib.3DreamEngine')
local Atmosfera = require('batalla.dream.atmosfera')
local IBL = require('batalla.dream.ibl')
local Oclusion = require('batalla.dream.oclusion')
local Rebote = require('batalla.dream.rebote')
local CieloHDRI = require('batalla.dream.cielo_hdri')
local Calidad = require('batalla.dream.calidad')
-- Exposición por la luz que llega (batalla/dream/tono.lua).
local Tono = require('batalla.dream.tono')

local Luz = {}

-- Nubes del ejemplo. El dueño pidió antes «sin nubes por ahora»: con false se
-- quitan sin tocar nada más.
Luz.nubes = true

Luz.parteDeSol = 0.62 -- fracción del día de juego con el sol sobre el horizonte
-- Iluminancia del sol en la cima de la atmósfera, en las unidades de la luz
-- de 3Dream (albedo / pi * color * brillo * coseno). Atraviesa la atmósfera
-- (batalla/dream/atmosfera.lua): a 50° de altura llega con ~0,85 de ella,
-- blanca, y al atardecer, más débil y naranja. El cielo pone lo que dé la
-- física (en Unreal, la sombra del suelo queda a 0,17 del suelo al sol).
Luz.brilloSol = 5.0
-- Luz directa de la luna sobre el campo (para jugar de noche) y la que ilumina
-- el cielo nocturno (mucho menor: si no, el cielo de noche saldría azul de día).
Luz.brilloLuna = 1.1
Luz.colorLuna = { 0.55, 0.68, 1.0 }
Luz.lunaCielo = 0.035
-- La luz difusa del cielo de noche se multiplica por esto (de día, 1); los
-- reflejos no, para que el agua de noche no brille como de día.
Luz.refuerzoNoche = 6
-- Albedo medio del campo (lineal): el suelo que ilumina desde abajo en la luz
-- del cielo y en la dispersión múltiple de la atmósfera.
Luz.albedoSuelo = { 0.14, 0.16, 0.08 }
-- Inclinación y giro del recorrido del sol (setSunOffset): a mediodía queda a
-- unos 60° de altura, sin la luz plana de un sol en el cénit.
Luz.inclinacionSol = 0.52
Luz.giroSol = 0.75
-- Bruma: empieza a `Luz.inicioNiebla` m del ojo (lib/3DreamEngine:
-- setFogStart) y su color es el del cielo justo encima del horizonte en cada
-- rumbo (la franja de batalla/dream/ibl.lua): lo lejano se funde con el cielo
-- de detrás, sin color de estilo. Solo muy a lo lejos (el dueño, 2026-10-01:
-- nada de imagen lavada): el campo de batalla entero (el límite tiene 1,2 km
-- de radio) queda dentro de los 2,5 km sin bruma, y de ahí al plano lejano de
-- la cámara (9 km) se cierra hasta fundirse con el cielo. A ras de suelo
-- (1 - e^(-densidad * (distancia - inicio) en unidades de 10 m)): 0 % hasta
-- 2,5 km, 25 % a 3 km, 58 % a 4 km, 82 % a 5,5 km y 97 % a 8,5 km.
-- Antes empezaba a 250 m con 0,0045 (15 % a 600 m, 43 % a 1,5 km): vista
-- desde arriba, el campo entero salía velado de blanco.
-- 17-nov, el dueño pidió lo contrario: «con más neblina se vería mejor…
-- hostil, apagado». Ahora empieza a 60 m: 33 % a 500 m, 58 % a 1 km y 85 %
-- a 2 km (antes: 2,5 km y 0,0058).
Luz.densidadNiebla = 0.009
Luz.inicioNiebla = 60
-- Sesgo de profundidad de la sombra del sol, en escala del de 3Dream
-- (lib/3DreamEngine: setShadowBias). El suyo está pensado para 1 unidad = 1 m;
-- aquí 1 unidad son 10 m y con él la sombra empezaba a ~1,3 m (segunda
-- cascada) o ~3,8 m (tercera) del objeto con el sol de la tarde: los tanques
-- casi no tenían sombra y la de los soldados salía despegada de los pies.
-- Con 0,15, en suelo llano: 2, 6 y 18 cm por cascada a mediodía; 7, 22 y
-- 66 cm con el sol a 30°. Va con la normal del vértice y con los mapas en
-- r32f (en r16f el paso de profundidad junto al suelo era de ~24 cm y salía
-- acné en arcos).
Luz.sesgoSombra = 0.15
-- Panorama HDRI (ruta de un .hdr) en vez de la atmósfera, para compararlos
-- (batalla/dream/cielo_hdri.lua); nil: la atmósfera.
Luz.panorama = nil
-- Con el AA temporal, marcar lo que se mueve por su cuenta (sin la marca,
-- los soldados que andan salen emborronados: batalla/dream/temporal.lua).
Luz.mascaraMovil = true
-- Lado de las caras del cubo de la luz del cielo (reflejos): 128 px.
Luz.ladoReflejo = 128

local cielo
local atmosfera
local panorama
local ibl
local oclusion
local estado = {
    estrellas = 0,
    solDir = { 0, 1, 0 },
    brilloSolCima = 0,
    capturada = -1,
}

--- Luna y nubes de la extensión sky, encima de la atmósfera. Las nubes, con
-- la luz que les llega del sol a través de la atmósfera y la del cielo.
local function dibujarLunaYNubes(transformProj, camTransform, sol)
    local vec3 = dream.vec3
    local right = vec3(camTransform[1], camTransform[2], camTransform[3]):normalize()
    local up = vec3(camTransform[5], camTransform[6], camTransform[7])
    local plano = dream.planeObject.meshes.Plane:getMesh()
    -- Luna (tamaño de NationsRTS, 2026-09-29: muy lejana).
    local size = 0.04
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode('alpha')
    local luna = cielo.shaders.moon
    love.graphics.setShader(luna)
    luna:send('transformProj', transformProj)
    luna:send('up', up * size)
    luna:send('right', right * size)
    luna:send('InstanceCenter', -sol.direction)
    luna:send('sun', { math.cos(cielo.day / 30 * math.pi * 2), math.sin(cielo.day / 30 * math.pi * 2), 0 })
    luna:send('normalTex', cielo.textures.moon_normal)
    plano:setTexture(cielo.textures.moon)
    love.graphics.draw(plano)
    if #cielo.clouds == 0 then
        return
    end
    local c = sol.color * (sol.brightness * 0.8 / math.pi * 1.2)
    local noche = 0.004 * (1 - math.min(1, sol.brightness))
    local nubes = cielo.shaders.clouds
    love.graphics.setShader(nubes)
    nubes:send('transformProj', transformProj)
    nubes:send('sunColor', {
        (c.x + noche) ^ (1 / 2.2),
        (c.y + noche) ^ (1 / 2.2),
        (c.z + noche * 1.2) ^ (1 / 2.2),
    })
    nubes:send('sunVec', sol.direction)
    local cubo = dream.cubeObject.meshes.Cube.mesh
    for _, nube in ipairs(cielo.clouds) do
        nubes:send('clouds', nube.texture)
        nubes:send(
            'cloudsTransform',
            dream.mat4.getRotateY((nube.roration or 0) + love.timer.getTime() * nube.rotationDelta):subm()
        )
        love.graphics.setColor(nube.color or { 1, 1, 1 })
        love.graphics.draw(cubo)
    end
end

--- El cielo que se ve (dentro de `dream:setSky`): la atmósfera con el disco
-- del sol y las estrellas, la luna y las nubes.
local function dibujarCielo(transformProj, camTransform)
    love.graphics.push('all')
    love.graphics.setBlendMode('replace', 'premultiplied')
    if panorama then
        panorama:dibujar(dream, transformProj)
        love.graphics.pop()
        return
    end
    atmosfera:dibujar(
        dream,
        transformProj,
        estado.brilloSolCima,
        cielo.textures.stars,
        estado.estrellas,
        dream.mat4.getRotateX(love.timer.getTime() * 0.0025):subm()
    )
    love.graphics.pop()
    love.graphics.push('all')
    dibujarLunaYNubes(transformProj, camTransform, estado.sol)
    love.graphics.pop()
end

--- Cielo, luz del cielo, bruma, oclusión y sombras del motor (antes de
-- `dream:init()`), según la calidad elegida (batalla/dream/calidad.lua) o la
-- tabla `calidad` con las mismas claves (el mapa de campaña pasa la suya:
-- campana/luz_campana.lua).
function Luz.configurarMotor(calidad)
    calidad = calidad or Calidad.actual()
    cielo = require('lib.3DreamEngine.extensions.sky')
    if not Luz.nubes then
        cielo:setClouds({})
    end
    cielo:setSunOffset(Luz.inclinacionSol, Luz.giroSol)
    cielo:setRainbow(0)
    atmosfera = Atmosfera.nueva({ albedoSuelo = Luz.albedoSuelo })
    panorama = Luz.panorama and CieloHDRI.nuevo(Luz.panorama) or nil
    ibl = IBL.nuevo({ lado = calidad.ladoCielo or Luz.ladoReflejo })
    Luz.ibl, Luz.atmosfera = ibl, atmosfera
    ibl:instalar(dream)
    dream:setSky(dibujarCielo)
    dream:setFogHeight(-2, 120)
    dream:setFogStart(Luz.inicioNiebla * 0.1)
    dream:setShadowBias(Luz.sesgoSombra)
    dream:setShadowFormat('r32f')
    -- Bordes (Fase 2 de PLAN-RENDER-UE.md): el AA temporal y el FXAA dibujan
    -- sin MSAA; 'msaa' deja el MSAA 4 de antes.
    local suavizado = calidad.suavizado or 'msaa'
    dream.canvases:setMSAA(suavizado == 'msaa' and 4 or 0)
    dream.canvases:setFXAA(suavizado == 'fxaa')
    Luz.suavizado = suavizado
    if calidad.oclusion then
        oclusion = Oclusion.nueva(dream, calidad.oclusion)
        Luz.oclusion = oclusion
        -- Luz rebotada de pantalla (Fase 2 de PLAN-RENDER-UE.md).
        if calidad.rebote then
            oclusion.rebote = Rebote.nuevo(dream, calidad.rebote, ibl.irradiancia, oclusion.uniforms)
        else
            dream:setBounce(false)
        end
    else
        oclusion = nil
        dream:setAO(false)
        dream:setAmbientSplit(false)
        dream:setBounce(false)
    end
    -- Con el AA temporal, un lienzo r8 marca lo que se mueve por su cuenta
    -- (lib/3DreamEngine: setMotionMask y `mesh.movil`; necesita la luz
    -- ambiente aparte, que va con la oclusión).
    dream:setMotionMask(Luz.mascaraMovil and suavizado == 'taa' and calidad.oclusion and true or false)
    -- Sin resplandor: su umbral (1,0 sobre el color con gamma) no lo pasaba
    -- casi nada (cambiaban menos de 50 píxeles de la imagen) y costaba
    -- ~0,4 ms por cuadro a 1920 x 1080. setBloom() lo apaga (el valor por
    -- defecto de 3Dream, setBloom(-1), lo deja encendido).
    dream:setBloom()
end

--- Sol y luna, cada uno con su sombra. La hora se pone con `Luz.actualizar`.
function Luz.nuevas()
    local sol = dream:newLight('sun')
    sol:setBrightness(Luz.brilloSol)
    sol:addNewShadow(2048)
    local luna = dream:newLight('sun')
    local c = Luz.colorLuna
    luna:setColor(c[1], c[2], c[3])
    luna:addNewShadow(2048)
    estado.sol = sol
    return sol, luna
end

--- Hora de la extensión sky para el día y la fracción del reloj del juego.
function Luz.horaCielo(dia, fraccion)
    local parte = Luz.parteDeSol
    local t
    if fraccion < parte then
        t = fraccion / parte * 0.5
    else
        t = 0.5 + (fraccion - parte) / (1 - parte) * 0.5
    end
    return dia + t
end

--- Sombras del sol y de la luna según la calidad (batalla/dream/calidad.lua):
-- tres cascadas con factor 3, centradas un radio de la primera por delante del
-- ojo (`Luz.centrarSombras`), así que la última llega a 10 radios de la
-- primera: `calidad.sombra` m. El lado de cada mapa, como mucho 2048 (con 4096
-- la sombra costaba el doble).
function Luz.configurarSombras(luces, calidad)
    for _, luz in ipairs(luces) do
        local sombra = luz.shadow
        if sombra then
            local resolucion = math.min(2048, calidad.resolucion)
            if sombra.resolution ~= resolucion then
                sombra:setResolution(resolucion)
                sombra.canvases = nil
            end
            sombra:setCascadeFactor(3)
            -- Unidades de 3Dream (10 m): radio de la primera cascada = sombra / 10.
            sombra:setCascadeDistance(calidad.sombra * 0.1 * 2 / 10)
            sombra:setLazy(calidad.perezosa)
            -- Se recoloca en cuanto cambia el centro (que ya va a saltos de texel).
            sombra:setRefreshStepSize(0.000001)
        end
    end
end

--- Centra las cascadas un radio de la primera por delante del ojo, en la
-- dirección de la mirada (`ojo` y `mira` en unidades de 3Dream). 3Dream las
-- centra en el ojo: a 30 m de altura la primera (13 m) no tocaba el suelo
-- visible y media sombra quedaba detrás de la cámara. El centro salta de
-- texel en texel de la cascada mayor (múltiplo de los de las otras dos) en los
-- ejes de la cámara de sombra (lib/3DreamEngine/jobs/sunShadow.lua: lookAt con
-- arriba = Y): así el borde de la sombra no tiembla al mover la cámara.
function Luz.centrarSombras(luces, ojo, mira)
    if not luces then
        return
    end
    local dx, dy, dz = mira.x - ojo.x, mira.y - ojo.y, mira.z - ojo.z
    local largo = math.sqrt(dx * dx + dy * dy + dz * dz)
    if largo < 1e-6 then
        return
    end
    dx, dy, dz = dx / largo, dy / largo, dz / largo
    for _, luz in ipairs(luces) do
        local sombra = luz.shadow
        if sombra then
            local radio = sombra.cascadeDistance / 2
            local cx, cy, cz = ojo.x + dx * radio, ojo.y + dy * radio, ojo.z + dz * radio
            local d = luz.direction
            local ex, ez = -d.z, d.x
            local le = math.sqrt(ex * ex + ez * ez)
            if le > 1e-6 then
                ex, ez = ex / le, ez / le
                local ux, uy, uz = d.y * ez, d.z * ex - d.x * ez, -d.y * ex
                local texel = 2 * radio * sombra.cascadeFactor ^ 2 / sombra.resolution
                local a = cx * ex + cz * ez
                local b = cx * ux + cy * uy + cz * uz
                local n = cx * d.x + cy * d.y + cz * d.z
                a = math.floor(a / texel + 0.5) * texel
                b = math.floor(b / texel + 0.5) * texel
                cx = ex * a + ux * b + d.x * n
                cy = uy * b + d.y * n
                cz = ez * a + uz * b + d.z * n
            end
            sombra:setCenter(dream.vec3(cx, cy, cz))
        end
    end
end

--- Pone la hora `hora` (día más fracción de la extensión, ver `horaCielo`):
-- sol, luna, cielo, luz del cielo y niebla. Devuelve las luces que iluminan.
function Luz.actualizar(sol, luna, hora, activas)
    cielo:setDaytime(sol, hora)
    estado.sol = sol
    local giro
    if panorama then
        -- El sol, donde está el del panorama, girado al rumbo del de la hora.
        local s = panorama.analisis.sol
        local d0 = sol.direction
        giro = math.atan2(d0.z, d0.x) - math.atan2(s[3], s[1])
        local g = panorama:solGirado(giro)
        sol.direction = dream.vec3(g[1], g[2], g[3])
    end
    local d = sol.direction
    local altura = d.y
    -- El sol atraviesa la atmósfera: su color es la transmitancia (blanco
    -- arriba, naranja junto al horizonte, nada por debajo).
    local tr, tg, tb = Atmosfera.transmitancia(altura)
    local paso = math.max(tr, tg, tb)
    sol:setColor(tr / math.max(paso, 1e-6), tg / math.max(paso, 1e-6), tb / math.max(paso, 1e-6))
    sol:setBrightness(Luz.brilloSol * paso)
    estado.brilloSolCima = Luz.brilloSol
    local noche = math.max(0, math.min(1, -altura * 6))
    luna.direction = -d
    luna:setBrightness(Luz.brilloLuna * noche)
    estado.estrellas = math.max(0, -math.sin((hora % 1) * math.pi * 2))

    -- Cielo y luz del cielo: se rehacen cuando el sol se ha movido.
    local cl = Luz.colorLuna
    local lunaCielo = Luz.brilloLuna * Luz.lunaCielo * noche
    local cambio = atmosfera:actualizar(
        { d.x, d.y, d.z },
        { Luz.brilloSol, Luz.brilloSol, Luz.brilloSol },
        { cl[1] * lunaCielo, cl[2] * lunaCielo, cl[3] * lunaCielo }
    )
    if panorama then
        cambio = not estado.giroPanorama or math.abs(estado.giroPanorama - giro) > math.rad(0.25)
        if cambio then
            estado.giroPanorama = giro
            panorama:ajustar(giro, Luz.brilloSol * paso)
        end
    end
    if cambio or ibl.capturas == 0 then
        local ks = Luz.brilloSol * math.max(altura, 0)
        local kl = Luz.brilloLuna * noche * math.max(-altura, 0)
        local luzSuelo = { tr * ks + cl[1] * kl, tg * ks + cl[2] * kl, tb * ks + cl[3] * kl }
        local refuerzo = 1 + (Luz.refuerzoNoche - 1) * math.max(0, math.min(1, 0.5 - altura * 4))
        ibl:capturar(function(cubo, cara, lado)
            if panorama then
                panorama:pintarCara(cubo, cara, lado, luzSuelo, Luz.albedoSuelo)
            else
                atmosfera:pintarCara(cubo, cara, lado, luzSuelo, Luz.albedoSuelo, 1)
            end
        end, refuerzo)
    end
    -- Exposición por la luz incidente: la directa sobre el suelo horizontal
    -- (en luminancia) y la del cielo (su lienzo de 1 x 1).
    local yl = 0.2126 * cl[1] + 0.7152 * cl[2] + 0.0722 * cl[3]
    Tono.luzCielo = panorama and panorama.irradiancia or atmosfera.irradiancia
    Tono.noche = noche
    Tono.luzDirecta = Luz.brilloSol * (0.2126 * tr + 0.7152 * tg + 0.0722 * tb) * math.max(altura, 0)
        + Luz.brilloLuna * noche * yl * math.max(-altura, 0)
    -- El color de la niebla lo da la franja del horizonte (ibl.horizonte).
    dream:setFog(Luz.densidadNiebla, dream.vec3(0.5, 0.6, 0.7), 0)
    if oclusion then
        if paso > 0 then
            oclusion:ponerLuz(d, 1)
        else
            oclusion:ponerLuz(luna.direction, noche)
        end
    end

    activas = activas or {}
    for indice = #activas, 1, -1 do
        activas[indice] = nil
    end
    if paso > 0 then
        activas[#activas + 1] = sol
    end
    if noche > 0 then
        activas[#activas + 1] = luna
    end
    return activas
end

return Luz
