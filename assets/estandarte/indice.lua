-- Estandarte colgante y kit de escudos de nación.
-- Generado por tools/generar_estandarte.py: no editar a mano, volver a generar.
--
-- ESTANDARTE. Cada pose tiene dos hojas del mismo tamaño y origen:
--   base  : asta, travesaño, remate, borlas, ribete, contorno y sombra en el
--           suelo. Se dibuja tal cual (setColor(1, 1, 1)).
--   color : solo la tela del paño, en gris ya sombreado. Se dibuja encima de
--           la base teñida con el color de la nación (como las hojas _color
--           de mundo/modelos.lua). Donde el travesaño o las espadas tapan el
--           paño, la capa _color ya es transparente.
-- Orden: base, color, y el escudo encima (ver «escudo» en cada pose).
--
-- ancla: píxel del lienzo donde el asta toca el suelo. Se dibuja con
--   love.graphics.draw(img, sx, sy, 0, s, s, ancla.x, ancla.y)
--   donde (sx, sy) es el punto del ejército en pantalla.
-- Tamaños en píxeles de la hoja 1x; la hoja _x2 mide el doble en todo
-- (ancla, escudo) y se usa en pantallas grandes con escala 0,5 o a tamaño doble.
--
-- Mirar a la izquierda: el paño ondea hacia la izquierda (el ejército va a la
-- derecha). Si va a la izquierda, dibujar base y color con escala x = -s (el
-- ancla es la misma). El escudo NO se refleja: se dibuja sin espejo en
-- x = ancla.x - (escudo.x - ancla.x), es decir, reflejando solo su centro.
--
-- Retirada: el diseño pide el estandarte «más pálido». Teñir la capa color con
-- el color de la nación mezclado un 40 % hacia el gris pergamino tenue
-- (0.73, 0.66, 0.52) y dibujar el escudo con alfa 0.85.

local Indice = {}

Indice.carpeta = "assets/estandarte/"

Indice.estandarte = {
    ancho = 64,
    alto = 72,
    -- Alto visible del estandarte (del remate al suelo), sin las espadas.
    altoVisible = 56,
    ancla = { x = 38, y = 66 },
    -- Etiqueta (líder y poder): centrada en ancla.x, justo debajo del suelo.
    etiqueta = { x = 38, y = 69 },
    poses = {
        marcha = {
            base = "estandarte_marcha.png",
            color = "estandarte_marcha_color.png",
            base2x = "estandarte_marcha_x2.png",
            color2x = "estandarte_marcha_color_x2.png",
            -- Centro del escudo en la hoja 1x y escala a la que se dibuja el
            -- escudo 1x (16x18) en esa hoja. giro (radianes) es la inclinación
            -- medida de la tela en ese punto: es opcional; el montaje de
            -- comprobación dibuja el escudo sin girar y se lee bien.
            escudo = { x = 36.0, y = 29.8, giro = 0.000, escala = 1 },
        },
        combate = {
            base = "estandarte_combate.png",
            color = "estandarte_combate_color.png",
            base2x = "estandarte_combate_x2.png",
            color2x = "estandarte_combate_color_x2.png",
            -- Centro del escudo en la hoja 1x y escala a la que se dibuja el
            -- escudo 1x (16x18) en esa hoja. giro (radianes) es la inclinación
            -- medida de la tela en ese punto: es opcional; el montaje de
            -- comprobación dibuja el escudo sin girar y se lee bien.
            escudo = { x = 34.4, y = 29.2, giro = 0.102, escala = 1 },
        },
        retirada = {
            base = "estandarte_retirada.png",
            color = "estandarte_retirada_color.png",
            base2x = "estandarte_retirada_x2.png",
            color2x = "estandarte_retirada_color_x2.png",
            -- Centro del escudo en la hoja 1x y escala a la que se dibuja el
            -- escudo 1x (16x18) en esa hoja. giro (radianes) es la inclinación
            -- medida de la tela en ese punto: es opcional; el montaje de
            -- comprobación dibuja el escudo sin girar y se lee bien.
            escudo = { x = 27.5, y = 29.8, giro = -0.256, escala = 1 },
        },
    },
}

-- ESCUDOS. Lienzo de 16x18 en 1x (versiones _x2 y _x4 al doble y al
-- cuádruple; la _x4 sirve para paneles). Todo es blanco o gris: se tiñe
-- con setColor. Se dibujan en este orden, todas en el mismo origen:
--   1. forma      teñida con el esmalte del campo
--   2. particion  (opcional) teñida con el segundo esmalte; hay un archivo
--                 por forma porque ya viene recortada a su silueta
--   3. carga      (opcional) teñida con el esmalte de la carga; lienzo de
--                 11x11 en 1x, su esquina va en forma.carga (x, y)
--   4. relieve    sin teñir (contorno, luz y sombra)
-- El centro del escudo es el centro del lienzo: (8, 9) en 1x.
-- Regla de contraste: si el campo es metal, la carga es color, y al revés.

Indice.escudo = {
    ancho = 16,
    alto = 18,
    centro = { x = 8, y = 9 },
    ladoCarga = 11,
    sufijos = { [1] = "", [2] = "_x2", [4] = "_x4" },
}

-- Cada forma: silueta, relieve y esquina de la carga (1x).
Indice.formas = {
    { nombre = "clasico", descripcion = "Escudo de punta clásico",
      forma = "escudos/forma_clasico.png", relieve = "escudos/relieve_clasico.png",
      carga = { x = 2, y = 2 } },
    { nombre = "redondo", descripcion = "Escudo de base redonda",
      forma = "escudos/forma_redondo.png", relieve = "escudos/relieve_redondo.png",
      carga = { x = 2, y = 3 } },
    { nombre = "frances", descripcion = "Escudo cuadrado con punta corta",
      forma = "escudos/forma_frances.png", relieve = "escudos/relieve_frances.png",
      carga = { x = 2, y = 3 } },
    { nombre = "ovalo", descripcion = "Óvalo",
      forma = "escudos/forma_ovalo.png", relieve = "escudos/relieve_ovalo.png",
      carga = { x = 2, y = 4 } },
    { nombre = "insignia", descripcion = "Insignia militar de chaflanes",
      forma = "escudos/forma_insignia.png", relieve = "escudos/relieve_insignia.png",
      carga = { x = 2, y = 3 } },
    { nombre = "cuadrilongo", descripcion = "Cuadrilongo de esquinas redondas",
      forma = "escudos/forma_cuadrilongo.png", relieve = "escudos/relieve_cuadrilongo.png",
      carga = { x = 2, y = 4 } },
}

-- Particiones: archivo = "escudos/particion_<forma>_<nombre>.png".
-- "ninguna" (campo liso) no tiene archivo. cargaSobre dice qué hay bajo la
-- carga: "campo" (primer esmalte), "pieza" (segundo) o "linea" (los dos).
Indice.particiones = {
    { nombre = "ninguna", descripcion = "Campo liso", cargaSobre = "campo" },
    { nombre = "partido", descripcion = "Partido: mitad derecha", cargaSobre = "linea" },
    { nombre = "cortado", descripcion = "Cortado: mitad de abajo", cargaSobre = "linea" },
    { nombre = "tronchado", descripcion = "Tronchado: triángulo de abajo a la izquierda", cargaSobre = "linea" },
    { nombre = "tajado", descripcion = "Tajado: triángulo de abajo a la derecha", cargaSobre = "linea" },
    { nombre = "cuartelado", descripcion = "Cuartelado: cuartos 2 y 3", cargaSobre = "linea" },
    { nombre = "jefe", descripcion = "Jefe: franja de arriba", cargaSobre = "campo" },
    { nombre = "faja", descripcion = "Faja: franja horizontal al centro", cargaSobre = "pieza" },
    { nombre = "palo", descripcion = "Palo: franja vertical al centro", cargaSobre = "pieza" },
    { nombre = "banda", descripcion = "Banda: diagonal de arriba a la izquierda", cargaSobre = "pieza" },
    { nombre = "barra", descripcion = "Barra: diagonal de arriba a la derecha", cargaSobre = "pieza" },
    { nombre = "cabrio", descripcion = "Cabrio: ángulo abierto hacia abajo", cargaSobre = "pieza" },
    { nombre = "aspa", descripcion = "Aspa: dos diagonales cruzadas", cargaSobre = "pieza" },
    { nombre = "cruz", descripcion = "Cruz", cargaSobre = "pieza" },
    { nombre = "bordura", descripcion = "Bordura: borde interior", cargaSobre = "campo" },
}

function Indice.archivoParticion(forma, particion, escala)
    if particion == "ninguna" then
        return nil
    end
    local sufijo = Indice.escudo.sufijos[escala or 1]
    return "escudos/particion_" .. forma .. "_" .. particion .. sufijo .. ".png"
end

-- Cargas: figuras ficticias, ninguna copia un escudo real.
Indice.cargas = {
    { nombre = "estrella", descripcion = "Estrella de cinco puntas", archivo = "escudos/carga_estrella.png" },
    { nombre = "torre", descripcion = "Torre almenada", archivo = "escudos/carga_torre.png" },
    { nombre = "ancla", descripcion = "Ancla", archivo = "escudos/carga_ancla.png" },
    { nombre = "espiga", descripcion = "Espiga de trigo", archivo = "escudos/carga_espiga.png" },
    { nombre = "rayo", descripcion = "Rayo", archivo = "escudos/carga_rayo.png" },
    { nombre = "ave", descripcion = "Ave en vuelo", archivo = "escudos/carga_ave.png" },
    { nombre = "llave", descripcion = "Llave", archivo = "escudos/carga_llave.png" },
    { nombre = "sol", descripcion = "Sol", archivo = "escudos/carga_sol.png" },
    { nombre = "engranaje", descripcion = "Engranaje", archivo = "escudos/carga_engranaje.png" },
    { nombre = "montana", descripcion = "Montaña", archivo = "escudos/carga_montana.png" },
    { nombre = "pino", descripcion = "Pino", archivo = "escudos/carga_pino.png" },
    { nombre = "espada", descripcion = "Espada en palo", archivo = "escudos/carga_espada.png" },
}

-- Añade el sufijo de escala a un archivo 1x: ("escudos/forma_ovalo.png", 2)
-- -> "escudos/forma_ovalo_x2.png".
function Indice.conEscala(archivo, escala)
    local sufijo = Indice.escudo.sufijos[escala or 1]
    return (archivo:gsub("%.png$", sufijo .. ".png"))
end

-- Esmaltes sugeridos (RGB 0..1). El juego puede usar otros; conviene que
-- el campo o la partición lleve el color de la nación.
Indice.esmaltes = {
    metales = {
        oro = { 0.85, 0.70, 0.36 },
        plata = { 0.90, 0.88, 0.82 },
    },
    colores = {
        gules = { 0.62, 0.18, 0.14 },
        azur = { 0.18, 0.30, 0.56 },
        sinople = { 0.22, 0.42, 0.22 },
        sable = { 0.14, 0.12, 0.11 },
        purpura = { 0.40, 0.22, 0.44 },
    },
}

-- Combinación de referencia por semilla (entero). Determinista y sin
-- love.math, para que el mismo país tenga el mismo escudo en todas partes.
-- Devuelve { forma, particion, carga, campo, segundo, figura }, donde campo,
-- segundo y figura son nombres de esmalte ("oro", "gules"...). No incluye el
-- color de la nación: el juego decide si lo usa como campo.
function Indice.combinar(semilla)
    local estado = math.floor(math.abs(semilla)) % 2147483647
    if estado == 0 then
        estado = 1
    end
    local function siguiente(n)
        estado = (estado * 48271) % 2147483647
        return math.floor(estado / 2147483647 * n) + 1
    end
    for _ = 1, 3 do
        siguiente(2) -- mezcla la semilla antes de elegir
    end
    local metales = { "oro", "plata" }
    local colores = { "gules", "azur", "sinople", "sable", "purpura" }
    local forma = Indice.formas[siguiente(#Indice.formas)].nombre
    local particion = Indice.particiones[siguiente(#Indice.particiones)].nombre
    local carga = Indice.cargas[siguiente(#Indice.cargas)].nombre
    local campoEsMetal = siguiente(2) == 1
    local campo, segundo, figura
    -- Contraste: metal sobre color y color sobre metal, mirando qué queda
    -- debajo de la carga (cargaSobre de la partición).
    local sobre = "campo"
    for _, p in ipairs(Indice.particiones) do
        if p.nombre == particion then
            sobre = p.cargaSobre
        end
    end
    local function otro(lista, distinto)
        local i = siguiente(#lista)
        if lista[i] == distinto then
            i = i % #lista + 1
        end
        return lista[i]
    end
    if campoEsMetal then
        campo = metales[siguiente(#metales)]
        segundo = colores[siguiente(#colores)]
    else
        campo = colores[siguiente(#colores)]
        segundo = metales[siguiente(#metales)]
    end
    if sobre == "campo" then
        -- sobre metal va color y al revés; distinto del segundo
        figura = otro(campoEsMetal and colores or metales, segundo)
    else
        -- sobre la línea o la pieza (toca los dos esmaltes): en campo de metal,
        -- sable (o gules si el segundo ya es sable); en campo de color, el
        -- metal que no está en el escudo
        if campoEsMetal then
            figura = segundo == "sable" and "gules" or "sable"
        else
            figura = metales[segundo == "oro" and 2 or 1]
        end
    end
    return {
        forma = forma,
        particion = particion,
        carga = carga,
        campo = campo,
        segundo = segundo,
        figura = figura,
    }
end

return Indice
