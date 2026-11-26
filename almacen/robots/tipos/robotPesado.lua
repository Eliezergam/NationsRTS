-- El robot grande del almacén: humanoide de 3,6 m sobre orugas, con dos
-- brazos hidráulicos y garras para los contenedores de misil, los misiles y
-- los bidones de petróleo (tools/blender/robot_pesado.py). Trabaja en la
-- fábrica de misiles: lleva las cajas de misil de las mesas de encajado al
-- polvorín y les trae cajas vacías (encajado.lua).
return {
    modelo = 'robot_pesado',
    ancho = 2.75, -- m de lado a lado (orugas)
    alto = 3.6,
    ajustes = {
        -- Los ojos del robot pequeño a 2,8 (los del pequeño, a 0,95).
        mirada = { escalaOjo = 2.8 / 0.95 },
        lidar = {
            -- Todo el almacén (nave de 42 m, 17-nov) y el patio: va a todas partes.
            limites = { -75.5, -42.5, 64.5, 32.5 }, -- con el muelle de misiles
            -- A la altura de las orugas, del pecho y de la cabeza.
            capas = { 0.4, 1.6, 2.9 },
            alcance = 16,
        },
        conduccion = {
            -- 3,2 t sobre orugas: despacio y sin brusquedades.
            velocidadMaxima = 0.9,
            velocidadSinCarga = 1.2,
            aceleracion = 0.45,
            aceleracionSinCarga = 0.6,
            giroMaximo = 0.45,
            aceleracionGiro = 0.5,
            giroEnSitio = 0.2,
            llegada = 0.06,
            cerca = 0.5,
            balanceo = 0,
            agacharDesde = 99,
            -- Del centro al frente de las orugas (1,6 m) y algo más; el
            -- pasillo del parachoques es el del chasis (lo que va delante de
            -- las orugas lo coge la garra).
            parachoques = 1.75,
            anchoParachoques = 2.0,
            anchoFrenar = 2.0,
            capaParachoques = 0.4,
        },
    },
    'lidar',
    'conduccion',
    'orugas',
    'mirada',
    'siglas',
    'sombra', -- sombra de contacto (en pausa: solo oculta la placa)
    'brazosPesado',
    'cintura',
    'encajado',
}
