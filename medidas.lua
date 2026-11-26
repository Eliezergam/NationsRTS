-- Sistema de medidas del juego (el dueño, 19-nov: «usamos un sistema de
-- medidas, para así yo decirle tal cosa de tantos metros; todo a escala real:
-- robots, vehículos, árboles, hierba, todo»).
--
-- Todo se mide en METROS reales. La batalla 3D dibuja a 10 px por metro
-- (`Medidas.px`); el terreno del mapa se lee ampliado `Medidas.escalaMundo`
-- veces para que las montañas, valles y distancias tengan su tamaño real.
--
-- Para cambiar el tamaño de algo, se cambia aquí su número en metros: el
-- código que lo dibuja lo lee de esta tabla. Cada línea dice de dónde sale
-- la cifra real.

local Medidas = {}

-- Escala de la batalla: px por metro (batalla/dream, robots, colocación).
Medidas.px = 10
-- El mapa del mundo, ampliado en la batalla 3D (batalla/terreno_escalado.lua).
Medidas.escalaMundo = 10

--- Metros -> px de la batalla.
function Medidas.aPx(metros)
    return metros * Medidas.px
end

--- px de la batalla -> metros.
function Medidas.aMetros(px)
    return px / Medidas.px
end

-- Alto (m) de cada cosa. Donde hay `variacion`, cada copia sale entre
-- alto * (1 - variacion) y alto * (1 + variacion).
Medidas.alto = {
    -- Hierba alta de pradera (el dueño, 19-nov: «de un metro»).
    hierba = 1.0,
    hierbaVariacion = 0.2,
    -- Árboles adultos: haya/roble de 15-25 m y abedul de 15-20 m (la media aquí;
    -- la colocación varía cada uno de 0,8 a 1,25 veces).
    arbolFrondoso = 16,
    abedul = 15,
    -- Arbustos del pack: de 1,3 a 2,4 m (su tamaño en el pack, ya real).
    -- Flores silvestres: unos 0,5 m.
    flor = 0.5,
}

-- Robots y vehículos de la batalla, por modelo (assets/batalla/robots/<modelo>.glb):
-- `alto` o `largo` es el que se quiere (m); `modelo`, lo que mide el .glb
-- (medido de sus piezas). El juego los dibuja a alto / modelo: cambiar `alto`
-- (o `largo`) cambia su tamaño. Soldado, lanzamisiles y conductor: el mismo
-- cuerpo de 1,85 m hasta lo alto de la cabeza, como una persona.
Medidas.robots = {
    soldado = { alto = 1.85, modelo = 1.85 },
    lanzamisiles = { alto = 1.85, modelo = 1.85 },
    conductor = { alto = 1.85, modelo = 1.85 },
    -- Camión de misiles: 14,0 m de largo (como un MAZ-543 con su carga).
    camionMisiles = { largo = 14.0, modelo = 14.0 },
    -- Avión de carga: 4 camiones de misiles y unos 24 robots en la bodega
    -- (tools/blender/avion_carga.py), medido con ellos dentro.
    avionCarga = { largo = 1, modelo = 1 },
}

--- Escala de dibujo de un modelo de robot o vehículo (1 si no está en la tabla).
function Medidas.escalaRobot(modelo)
    local r = Medidas.robots[modelo]
    if not r then
        return 1
    end
    return (r.alto or r.largo) / r.modelo
end

-- Medidas de los restos (tools/restos_campo.py; normas reales). Cambiarlas
-- aquí estira el modelo a lo que se pida:
-- contenedor ISO 668 1CC de 20 pies 6,058 x 2,438 x 2,591 m; bidón de 200 l
-- 0,585 m de diámetro y 0,88 m de alto; caja de madera 1,2 x 0,8 x 0,8 m.
Medidas.contenedor = { largo = 6.058, ancho = 2.438, alto = 2.591 }
Medidas.bidon = { diametro = 0.585, alto = 0.88 }
Medidas.caja = { largo = 1.2, ancho = 0.8, alto = 0.8 }

return Medidas
