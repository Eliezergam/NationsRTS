-- Calidad del dibujo de la batalla: baja, media o alta (por defecto alta).
-- Se elige con `--calidad <baja|media|alta>` al arrancar el juego. Los valores
-- son los de la prueba de estrés de Camila (batalla/pruebas_estilo/estres.lua),
-- con la sombra limitada a 2048 (lo que más rinde, según su medida).
--
-- Distancias en metros:
--   pinoCompleto   pino con todas sus ramas
--   pinoSimple     pino con menos ramas; más allá, impostor horneado
--   impostor       hasta dónde se ven los impostores de pino
--   arboles        detalle 0 y 1 de los demás árboles (roble, abedul...)
--   matas          matas de hierba y flores (dos detalles)
--   rocas          rocas pequeñas (las grandes llegan más lejos)
--   arbustos       arbustos
--   sombra         hasta dónde proyectan sombra la vegetación y las rocas;
--                  es también el alcance de las tres cascadas del sol, medido
--                  desde el ojo (van centradas por delante: batalla/dream/luz.lua)
--   resolucion     lado del mapa de cada cascada
--   perezosa       3Dream rehace una cascada por cuadro en vez de las tres
--   sombraDetallada  los pinos completos proyectan su sombra completa
--   ao             oclusión ambiental (solo cambia al arrancar)
--   oclusion       GTAO solo en la luz del cielo y sombras de contacto
--                  (batalla/dream/oclusion.lua: 'media' sin contacto, 'alta'
--                  con ellas; false, nada)
--   ladoCielo      px de cada cara del cubo de la luz del cielo (ibl.lua)
--   suavizado      bordes: 'fxaa' (barato), 'taa' (AA temporal,
--                  batalla/dream/temporal.lua) o 'msaa' (MSAA 4, el de antes);
--                  solo cambia al arrancar
--   afilado        afilado suave tras el AA temporal (batalla/dream/tono.lua)
--   escalaRender   parte de la resolución de la pantalla a la que se dibuja
--                  la escena 3D; FSR 1 la sube con nitidez (escalado.lua).
--                  1 = sin escalado
--   rebote         luz rebotada de pantalla (batalla/dream/rebote.lua):
--                  'media', 'alta' o false; necesita `oclusion`
--   nitidezMip     sesgo negativo de los mipmaps del suelo y los materiales
--                  con el AA temporal (batalla/dream/texturas_pbr.lua)
--   materiales     materiales de cerca (Fase 3 de PLAN-RENDER-UE.md): `altura`
--                  (mezcla por altura en el suelo), `detalle` (normales de
--                  detalle en el suelo, la roca del terreno y las rocas),
--                  `pom` (parallax del suelo), `translucidez` (la luz pasa
--                  por las hojas y la hierba al contraluz) y `viento` (las
--                  hojas y la hierba se mecen); solo cambia al arrancar

local Calidad = {}

Calidad.niveles = {
    baja = {
        pinoCompleto = 40,
        pinoSimple = 150,
        impostor = 1400,
        arboles = { 120, 400 },
        matas = 60,
        rocas = 100,
        arbustos = 60,
        sombra = 45,
        resolucion = 1024,
        perezosa = true,
        sombraDetallada = false,
        ao = false,
        oclusion = false,
        ladoCielo = 64,
        rebote = false,
        escalaRender = 0.67,
        suavizado = 'fxaa',
        afilado = 0,
        materiales = {},
    },
    media = {
        pinoCompleto = 60,
        pinoSimple = 220,
        impostor = 1800,
        arboles = { 160, 500 },
        matas = 100,
        rocas = 120,
        arbustos = 100,
        sombra = 70,
        resolucion = 2048,
        perezosa = true,
        sombraDetallada = false,
        ao = true,
        oclusion = 'media',
        ladoCielo = 128,
        rebote = 'media',
        escalaRender = 0.67,
        suavizado = 'taa',
        afilado = 0,
        nitidezMip = 1,
        materiales = { altura = true, detalle = true, translucidez = true, viento = true },
    },
    alta = {
        pinoCompleto = 90,
        pinoSimple = 300,
        impostor = 2200,
        -- Los árboles de antes no usan impostor: el detalle intermedio llega
        -- al horizonte (límite de la cámara, ~2000 m) y los lejanos no se dibujan.
        -- Evita que se vean como bolas verdes low-poly mezcladas con los pinos.
        arboles = { 200, 2000 },
        matas = 150,
        rocas = 150,
        arbustos = 150,
        -- 200 m como la referencia de Unreal (antes 120: los tanques del
        -- encuadre normal, a más de 120 m, no tenían sombra).
        sombra = 200,
        resolucion = 2048,
        perezosa = false,
        sombraDetallada = true,
        ao = true,
        oclusion = 'alta',
        ladoCielo = 128,
        rebote = 'alta',
        escalaRender = 0.77,
        suavizado = 'taa',
        afilado = 0.3,
        nitidezMip = 1,
        materiales = { altura = true, detalle = true, pom = true, translucidez = true, viento = true },
    },
}

Calidad.nombre = 'alta'

--- Elige la calidad por su nombre; devuelve false si no existe.
function Calidad.elegir(nombre)
    if not Calidad.niveles[nombre] then
        return false
    end
    Calidad.nombre = nombre
    return true
end

--- Valores de la calidad elegida.
function Calidad.actual()
    return Calidad.niveles[Calidad.nombre]
end

return Calidad
