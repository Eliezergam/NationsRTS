-- El robot soldado: dos piernas con una rueda en cada pie, metralleta de tres
-- cañones en el brazo derecho y garra de tres dedos en el izquierdo
-- (tools/blender/robot_soldado.py). Lo común a todas las escenas; cada una
-- puede heredarlo (`base = 'soldado'` en su tipo) y añadir lo suyo.
--
-- Se conduce como una base diferencial (conduccion.lua), las piernas se
-- ajustan solas como las de Ascento (piernasSoldado.lua) y se le ve vivo
-- (vida.lua: oídos que giran y parpadeo).
return {
    modelo = 'assets/batalla/robots/soldado',
    ancho = 0.5,
    alto = 1.6,
    ajustes = {
        conduccion = {
            radioRueda = 0.15,
            viaRuedas = 0.35,
            velocidadSinCarga = 3.5,
            aceleracionSinCarga = 2.0,
            giroMaximo = 1.6,
            aceleracionGiro = 3.0,
            agacharDesde = 1.2,
        },
    },
    'conduccion',
    'piernasSoldado',
    'vida',
    -- Le pueden dar: retrocede y se tuerce donde le dan (impactos.lua).
    'impactos',
}
