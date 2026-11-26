-- Objetos del almacén que maneja el robot y sus muebles
-- (tools/blender/objetos_almacen.py --glb). Metros, ejes del objeto:
-- +x hacia donde mira el robot al cogerlo (el frente en -x), z arriba,
-- origen en el suelo bajo el centro.
--   puntos: puntos de agarre { nombre, x, y, z, eje de cierre, grosor, mano }
--           mano: 'izq', 'der' o 'cualquiera'; las dos manos si hay dos.
--   huecos: sitios de apoyo { x, y, z } (el objeto se pone con su origen ahí
--           y mirando como el mueble).
--   cajas:  cajas de colisión { x0, y0, z0, x1, y1, z1 }.
return {
    cajaRobot = {
        nombre = 'caja de plástico', movible = true, peso = 6,
        tamano = { 0.300, 0.400, 0.240 },
        puntos = {
            { 'orejetaIzq', -0.100, 0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'izq' },
            { 'orejetaDer', -0.100, -0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'der' },
        },
        cajas = { { -0.150, -0.241, 0.000, 0.150, 0.241, 0.246 } },
    },
    cajaMunicion = {
        nombre = 'caja de munición', movible = true, peso = 9,
        tamano = { 0.280, 0.140, 0.180 },
        puntos = {
            { 'asa', 0, 0, 0.225, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'cualquiera' },
        },
        cajas = { { -0.156, -0.075, 0.000, 0.140, 0.075, 0.235 } },
    },
    mesaRecepcion = {
        nombre = 'mesa de recepción', movible = false,
        tamano = { 0.700, 1.500, 0.900 },
        huecos = {
            { -0.200, -0.450, 0.900 },
            { -0.200, 0.000, 0.900 },
            { -0.200, 0.450, 0.900 },
        },
        cajas = {
            { -0.350, -0.750, 0.820, 0.350, 0.750, 0.900 },
            { -0.125, -0.750, 0.000, 0.350, -0.675, 0.900 },
            { -0.125, 0.675, 0.000, 0.350, 0.750, 0.900 },
            { -0.125, -0.750, 0.150, 0.350, 0.750, 0.170 },
        },
    },
    estanteriaRobot = {
        nombre = 'estantería', movible = false,
        tamano = { 0.500, 1.960, 1.950 },
        huecos = {
            { -0.100, -0.620, 0.850 },
            { -0.100, 0.000, 0.850 },
            { -0.100, 0.620, 0.850 },
            { -0.100, -0.620, 1.300 },
            { -0.100, 0.000, 1.300 },
            { -0.100, 0.620, 1.300 },
        },
        cajas = {
            { -0.250, -0.980, 0.730, 0.250, 0.980, 0.850 },
            { -0.250, -0.980, 1.180, 0.250, 0.980, 1.300 },
            { -0.250, -0.980, 1.630, 0.250, 0.980, 1.750 },
            { 0.170, -0.980, 0.000, 0.460, 0.980, 1.950 },
        },
    },
    pacaDinero = {
        nombre = 'paca de dinero', movible = true, peso = 8, recurso = 'dinero', cantidad = 200,
        tamano = { 0.300, 0.400, 0.240 },
        puntos = {
            { 'orejetaIzq', -0.100, 0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'izq' },
            { 'orejetaDer', -0.100, -0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'der' },
        },
        cajas = { { -0.150, -0.241, 0.000, 0.150, 0.241, 0.246 } },
    },
    cajaComida = {
        nombre = 'caja de comida', movible = true, peso = 9, recurso = 'comida', cantidad = 20,
        tamano = { 0.300, 0.400, 0.240 },
        puntos = {
            { 'orejetaIzq', -0.100, 0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'izq' },
            { 'orejetaDer', -0.100, -0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'der' },
        },
        cajas = { { -0.150, -0.241, 0.000, 0.150, 0.241, 0.246 } },
    },
    cajaObuses = {
        nombre = 'caja de obuses', movible = true, peso = 18, recurso = 'obuses', cantidad = 100,
        tamano = { 0.300, 0.400, 0.240 },
        puntos = {
            { 'orejetaIzq', -0.100, 0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'izq' },
            { 'orejetaDer', -0.100, -0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'der' },
        },
        cajas = { { -0.150, -0.241, 0.000, 0.150, 0.241, 0.246 } },
    },
    cajaMetal = {
        nombre = 'caja de metal', movible = true, peso = 20, recurso = 'metal', cantidad = 10,
        tamano = { 0.300, 0.400, 0.240 },
        puntos = {
            { 'orejetaIzq', -0.100, 0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'izq' },
            { 'orejetaDer', -0.100, -0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'der' },
        },
        cajas = { { -0.150, -0.241, 0.000, 0.150, 0.241, 0.246 } },
    },
    bidonPetroleo = {
        nombre = 'bidón de petróleo', movible = true, peso = 180, recurso = 'petroleo', cantidad = 50,
        tamano = { 0.580, 0.580, 0.880 },
        puntos = {
            { 'cuerpo', 0.000, 0.000, 0.528, eje = { 0, 1, 0 }, grosor = 0.580, mano = 'garra', redondo = true },
        },
        cajas = {
            { -0.290, -0.290, 0.000, 0.290, 0.290, 0.900 },
        },
    },
    rackRobot = {
        nombre = 'rack', movible = false,
        tamano = { 0.500, 5.400, 1.950 },
        huecos = {
            { -0.100, -2.170, 0.850 },
            { -0.100, -1.550, 0.850 },
            { -0.100, -0.930, 0.850 },
            { -0.100, -0.310, 0.850 },
            { -0.100, 0.310, 0.850 },
            { -0.100, 0.930, 0.850 },
            { -0.100, 1.550, 0.850 },
            { -0.100, 2.170, 0.850 },
            { -0.100, -2.170, 1.300 },
            { -0.100, -1.550, 1.300 },
            { -0.100, -0.930, 1.300 },
            { -0.100, -0.310, 1.300 },
            { -0.100, 0.310, 1.300 },
            { -0.100, 0.930, 1.300 },
            { -0.100, 1.550, 1.300 },
            { -0.100, 2.170, 1.300 },
        },
        cajas = {
            { -0.250, -2.700, 0.730, 0.250, 2.700, 0.850 },
            { -0.250, -2.700, 1.180, 0.250, 2.700, 1.300 },
            { -0.250, -2.700, 1.630, 0.250, 2.700, 1.750 },
            { 0.170, -2.700, 0.000, 0.470, 2.700, 1.950 },
        },
    },
    cajaCaudales = {
        nombre = 'caja de dinero', movible = true, peso = 4, recurso = 'dinero', cantidad = 0, recipiente = true,
        tamano = { 0.300, 0.400, 0.200 },
        puntos = {
            { 'orejetaIzq', -0.100, 0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'izq' },
            { 'orejetaDer', -0.100, -0.235, 0.140, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'der' },
        },
        cajas = { { -0.150, -0.241, 0.000, 0.150, 0.241, 0.212 } },
    },
    garrafaPetroleo = {
        nombre = 'garrafa de petróleo', movible = true, peso = 9, recurso = 'petroleo', cantidad = 0, capacidad = 10, recipiente = true,
        tamano = { 0.280, 0.140, 0.330 },
        puntos = {
            { 'asa', 0, 0, 0.370, eje = { 0, 1, 0 }, grosor = 0.012, mano = 'cualquiera' },
        },
        cajas = { { -0.140, -0.070, 0.000, 0.140, 0.070, 0.380 } },
    },
    depositoMisil = {
        nombre = 'depósito del misil', movible = false,
        tamano = { 0.700, 4.800, 2.000 },
        zonas = { dinero = { 1, 2 }, metal = { 3, 4 }, petroleo = { 5, 6 } },
        huecos = {
            { -0.200, 1.980, 0.900 },
            { -0.200, 1.220, 0.900 },
            { -0.200, 0.380, 0.900 },
            { -0.200, -0.380, 0.900 },
            { -0.200, -1.220, 0.900 },
            { -0.200, -1.980, 0.900 },
        },
        cajas = {
            { -0.350, -2.400, 0.780, 0.350, 2.400, 0.900 },
            { -0.270, -2.400, 0.000, -0.190, 2.400, 0.900 },
            { 0.250, -2.400, 0.000, 0.350, 2.400, 2.030 },
        },
    },
}
