-- Línea de montaje de misiles (tools/blender/almacen_interior.py --glb):
-- puestos en orden, alturas de la grúa. Metros, ejes del almacén.
return {
    puestos = {
        { -69.000, -6.000 },
        { -57.500, -6.000 },
        { -57.500, 6.000 },
        { -69.000, 6.000 },
    },
    ejeZ = 1.150, -- alto del eje del misil en las cunas
    cuelga = 1.874, -- del punto de los cables al eje del misil colgado
    cableZ = 7.800, -- donde salen los cables del polipasto
    ejeEnCaja = 0.564, -- del suelo de la caja al eje del misil en sus cunas
    puenteX = { -73.000, -47.000 }, -- recorrido del puente
    mesaMenu = { -72.000, -9.550, 0.940 },
}
