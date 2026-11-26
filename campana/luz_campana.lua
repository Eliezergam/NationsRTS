-- Luz del mapa de campaña (Valeria): la misma de la batalla 3D
-- (batalla/dream/luz.lua: atmósfera física, luz del cielo por imagen, sol con
-- sombras en cascada; batalla/dream/tono.lua: curva fílmica de Unreal), con
-- las medidas pasadas a la escala del mapa.
--
-- La batalla usa 1 unidad = 10 m y el mapa 1 unidad = 1 km (campana/mapa3d.lua),
-- y la cámara del mapa va de 3 a 700 km (campana/camara.lua). Lo que depende
-- de la escala se ajusta aquí y cada cuadro según la distancia de la cámara:
-- - Bruma: no empieza hasta `inicioNiebla` distancias de la cámara más allá
--   del ojo (todo lo que rodea al punto mirado queda nítido) y se cierra hasta
--   fundirse con el cielo del horizonte, sin capa por alturas.
-- - Sombras del sol: tres cascadas centradas en el punto mirado; la primera
--   cubre `radioSombra` distancias de la cámara y la última nueve veces más.
--   Son estáticas: se rehacen solo al cruzar un salto de zoom o de posición.
--   La profundidad de sus cámaras (`shadow.depthRange`, lib/3DreamEngine:
--   jobs/sunShadow.lua) crece con la última cascada para que quepa el relieve.
-- - Sin GTAO, luz rebotada ni sombras de contacto: miden metros alrededor de
--   cada píxel y a esta escala no aportan nada.
-- - Bordes con el AA temporal de la batalla (batalla/dream/temporal.lua) y su
--   afilado suave, como la calidad alta: con el MSAA 4 de antes, la vista
--   general iba a 61 FPS y la costa a 75; con el AA temporal, a ~130 y ~180
--   (el MSAA de 3Dream multiplica cada lienzo de la escena).
-- La hora es fija (`fraccion`): media tarde, con el sol al oeste-suroeste a
-- 41° de altura (dirección hacia el sol 0,69 oeste, 0,66 arriba, 0,30 sur),
-- de lado respecto a la cámara que mira al norte, para que el relieve se lea.
-- Con el sol al sur (detrás de la cámara) el relieve salía plano.

local dream = require('lib.3DreamEngine')
local Luz = require('batalla.dream.luz')
local Tono = require('batalla.dream.tono')
local Temporal = require('batalla.dream.temporal')
local Escalado = require('batalla.dream.escalado')

local LuzCampana = {}
LuzCampana.__index = LuzCampana

-- Fracción del día de juego (batalla/dream/luz.lua: 0 amanecer, 0,31 mediodía).
LuzCampana.fraccion = 0.45
-- Recorrido del sol: altura a mediodía y rumbo (cielo:setSunOffset).
LuzCampana.inclinacionSol = 0.52
LuzCampana.giroSol = 1.68
-- Bruma: empieza a `inicioNiebla` x distancia de la cámara (más `inicioMinimo`
-- km) y llega a la mitad `mitadNiebla` x distancia después.
LuzCampana.inicioNiebla = 1.6
LuzCampana.inicioMinimo = 40
LuzCampana.mitadNiebla = 2.5
-- Radio de la primera cascada de sombra, en distancias de la cámara.
LuzCampana.radioSombra = 0.6
LuzCampana.pasoZoom = 1.15
LuzCampana.pasoCentro = 0.25
LuzCampana.resolucionSombra = 2048
-- Sesgo de la sombra (lib/3DreamEngine: setShadowBias), en el espacio de
-- profundidad de la cámara de sombra; crece con su profundidad, es decir,
-- con la distancia de la cámara, como el tamaño del texel. Con 0,6 y 1,2
-- quedaban rayas de acné en las laderas rasantes al sol; con 3, a 40 km de
-- distancia, la sombra se despega como mucho ~0,9 km (las de las montañas
-- miden varios km).
LuzCampana.sesgoSombra = 3

LuzCampana.calidad = {
    resolucion = 2048,
    perezosa = false,
    ao = false,
    oclusion = false,
    ladoCielo = 128,
    rebote = false,
    suavizado = 'taa',
    afilado = 0.3,
    escalaRender = 0.77, -- FSR 1 «Ultra Quality», como la calidad alta de la batalla
}

--- Cielo, luz del cielo y sombras del motor (antes de `dream:init()`).
function LuzCampana.configurarMotor()
    Luz.configurarMotor(LuzCampana.calidad)
    local cielo = require('lib.3DreamEngine.extensions.sky')
    cielo:setSunOffset(LuzCampana.inclinacionSol, LuzCampana.giroSol)
    dream:setFogHeight()
    dream:setShadowBias(LuzCampana.sesgoSombra)
end

--- Sol y luna con sus sombras y la curva tonal (después de `dream:init()`).
function LuzCampana.nueva()
    local self = setmetatable({}, LuzCampana)
    self.sol, self.luna = Luz.nuevas()
    self.luces = { self.sol, self.luna }
    self.activas = {}
    self.tono = Tono.nuevo()
    if Luz.suavizado == 'taa' then
        self.temporal = Temporal.nuevo()
        Tono.afilado = LuzCampana.calidad.afilado
    else
        Tono.afilado = 0
    end
    for _, luz in ipairs(self.luces) do
        local sombra = luz.shadow
        sombra:setResolution(LuzCampana.resolucionSombra)
        sombra:setCascadeFactor(3)
        sombra:setLazy(false)
        -- El mapa y el sol no se mueven: el mapa de sombra solo se rehace
        -- cuando cambian el centro o el radio de las cascadas.
        sombra:setStatic(true)
        sombra:setRefreshStepSize(0.000001)
    end
    return self
end

--- Hora, cielo, bruma y sombras para la cámara del mapa (campana/camara.lua).
function LuzCampana:actualizar(camara)
    local hora = Luz.horaCielo(0, LuzCampana.fraccion)
    Luz.actualizar(self.sol, self.luna, hora, self.activas)
    local distancia = camara.distancia
    -- 1 - e^(-densidad * tramo) = 0,5 a `mitadNiebla` distancias del inicio.
    local densidad = math.log(2) / (LuzCampana.mitadNiebla * distancia)
    dream:setFog(densidad, dream.vec3(0.5, 0.6, 0.7), 0)
    dream:setFogStart(LuzCampana.inicioNiebla * distancia + LuzCampana.inicioMinimo)
    -- Radio a saltos de `pasoZoom` y centro a saltos de `pasoCentro` radios:
    -- con el mapa y el sol quietos, las sombras solo se rehacen al cruzar un
    -- salto (`shadow.static`), no en cada cuadro.
    local nivel = math.floor(math.log(distancia) / math.log(LuzCampana.pasoZoom) + 0.5)
    local radio = LuzCampana.radioSombra * LuzCampana.pasoZoom ^ nivel
    for _, luz in ipairs(self.luces) do
        local sombra = luz.shadow
        sombra:setCascadeDistance(radio * 2)
        -- La última cascada (9 radios) y lo más alto del relieve, a cada lado.
        sombra.depthRange = 2 * (radio * 9 + 40)
    end
    local paso = radio * LuzCampana.pasoCentro
    local centroX = math.floor(camara.x / paso + 0.5) * paso
    local centroZ = math.floor(camara.z / paso + 0.5) * paso
    -- Luz.centrarSombras pone el centro un radio por delante del «ojo» (y lo
    -- ajusta al texel): se le da un ojo un radio por debajo del centro.
    Luz.centrarSombras(self.luces, dream.vec3(centroX, -radio, centroZ), dream.vec3(centroX, 0, centroZ))
end

--- Añade las luces que iluminan (entre `dream:prepare()` y `present`).
function LuzCampana:anadirLuces()
    for _, luz in ipairs(self.activas) do
        dream:addLight(luz)
    end
end

--- `dream:present()` con el AA temporal y a través de la curva tonal; a
-- menos resolución y subido con FSR 1, como la batalla
-- (batalla/dream/escalado.lua).
function LuzCampana:presentar()
    local escala = Escalado.escala(LuzCampana.calidad)
    local ancho, alto = Escalado.ajustar(dream, escala)
    local escalado = escala < 1 and Escalado.compartido()
    local entrada = escalado and escalado:entrada(ancho, alto)
    if escalado then
        Tono.afilado = 0
    end
    self.tono:empezar(ancho, alto)
    local temporal = self.temporal
    local imagen
    if temporal then
        temporal:prepararCuadro(dream.camera)
    end
    dream:present()
    if temporal then
        imagen = temporal:resolver(self.tono.lienzo, dream.canvases, dream.camera)
        temporal:quitar(dream.camera)
        dream.camera:applyProjectionTransform(dream.canvases)
    end
    self.tono:terminar(imagen, entrada)
    if escalado then
        escalado:subir(self.tono.anterior)
        love.graphics.setCanvas(self.tono.anterior)
    end
end

return LuzCampana
