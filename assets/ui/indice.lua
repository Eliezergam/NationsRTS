-- Kit gráfico de la interfaz militar de Nations RTS (estilo Warpath original).
-- Generado por tools/generar_ui_militar.py: no editar a mano, volver a generar.
--
-- USO
--   Indice.carpeta          : prefijo de todas las rutas ("assets/ui/").
--   Indice.paleta[color][estado] : color hex; estados normal, resaltado,
--                             pulsado y desactivado.
--   Indice.piezas[nombre]   : ancho, alto (px a 1080p; a 720p escalar por 2/3),
--                             archivos[estado] (ruta por estado),
--                             nueve = { izq, der, arr, aba } márgenes 9-slice
--                               (si falta, la pieza es de tamaño fijo),
--                             contenido = { izq, der, arr, aba } relleno interior
--                               donde poner texto o hijos,
--                             anclas = { nombre = { x, y, ref } }: x, y en px
--                               desde la esquina de ref (por defecto arriba a
--                               la izquierda; "arriba_der" mide hacia dentro
--                               desde la esquina derecha, así que x negativo
--                               sale del borde).
--   Indice.iconos[nombre]   : archivos["64"] y archivos["32"]; blancos sobre
--                             transparente. Se tiñen con setColor.
--
-- 9-slice: cortar la imagen con nueve; las esquinas se dibujan sin estirar y
-- los lados y el centro se estiran. Con arr = 0 y aba = 0 son tres trozos
-- horizontales (barras); con izq = 0 y der = 0, tres verticales.
--
-- Estados de botones: normal, resaltado (ratón encima), pulsado y
-- desactivado. Fichas: normal, resaltada y activa. Pestañas: inactiva y
-- activa. Filas: normal, hover y seleccionada.

local Indice = {}

Indice.carpeta = "assets/ui/"

Indice.paleta = {
    hormigon = {
        normal = "#9fa2a6",
        resaltado = "#aeb1b4",
        pulsado = "#7c7e81",
        desactivado = "#77797b",
    },
    hormigon_oscuro = {
        normal = "#8a8d91",
        resaltado = "#9d9fa3",
        pulsado = "#6c6e71",
        desactivado = "#696b6d",
    },
    placa_clara = {
        normal = "#dfe0e2",
        resaltado = "#e4e5e7",
        pulsado = "#aeafb0",
        desactivado = "#a0a1a3",
    },
    celda_opcion = {
        normal = "#dfdfdf",
        resaltado = "#e4e4e4",
        pulsado = "#aeaeae",
        desactivado = "#9fa0a2",
    },
    tarjeta_gris = {
        normal = "#cecfca",
        resaltado = "#d6d7d2",
        pulsado = "#a1a19e",
        desactivado = "#939596",
    },
    fila_gris = {
        normal = "#b9bab5",
        resaltado = "#c4c5c1",
        pulsado = "#90918d",
        desactivado = "#868788",
    },
    linea_gris = {
        normal = "#8c8e90",
        resaltado = "#9ea0a2",
        pulsado = "#6d6f70",
        desactivado = "#6a6c6d",
    },
    borde_negro = {
        normal = "#1c1c1d",
        resaltado = "#404041",
        pulsado = "#161617",
        desactivado = "#202223",
    },
    marino = {
        normal = "#2a2f3d",
        resaltado = "#4c505c",
        pulsado = "#212530",
        desactivado = "#2d2f33",
    },
    marino_hondo = {
        normal = "#1a1e29",
        resaltado = "#3f424b",
        pulsado = "#141720",
        desactivado = "#222427",
    },
    oliva = {
        normal = "#38402b",
        resaltado = "#585f4d",
        pulsado = "#2c3222",
        desactivado = "#323432",
    },
    oliva_hondo = {
        normal = "#292d18",
        resaltado = "#4b4f3d",
        pulsado = "#202313",
        desactivado = "#272927",
    },
    oliva_negro = {
        normal = "#1e1f17",
        resaltado = "#42433c",
        pulsado = "#171812",
        desactivado = "#212222",
    },
    oliva_claro = {
        normal = "#55603f",
        resaltado = "#70795e",
        pulsado = "#424b31",
        desactivado = "#434743",
    },
    caqui = {
        normal = "#b9b9ae",
        resaltado = "#c4c4bb",
        pulsado = "#909088",
        desactivado = "#848685",
    },
    metal = {
        normal = "#3b3b3b",
        resaltado = "#5a5a5a",
        pulsado = "#2e2e2e",
        desactivado = "#343637",
    },
    metal_hondo = {
        normal = "#242424",
        resaltado = "#474747",
        pulsado = "#1c1c1c",
        desactivado = "#252728",
    },
    metal_claro = {
        normal = "#acadb0",
        resaltado = "#b9babd",
        pulsado = "#868789",
        desactivado = "#7f8082",
    },
    dorado = {
        normal = "#e7b534",
        resaltado = "#ebc154",
        pulsado = "#b48d29",
        desactivado = "#7f7865",
    },
    dorado_claro = {
        normal = "#fed860",
        resaltado = "#fede79",
        pulsado = "#c6a84b",
        desactivado = "#938e7c",
    },
    dorado_oscuro = {
        normal = "#8d6c4d",
        resaltado = "#9f8469",
        pulsado = "#6e543c",
        desactivado = "#5a5652",
    },
    rojo_aviso = {
        normal = "#c53535",
        resaltado = "#ce5555",
        pulsado = "#9a2929",
        desactivado = "#5f494b",
    },
    verde_energia = {
        normal = "#84c144",
        resaltado = "#98cb62",
        pulsado = "#679735",
        desactivado = "#636f5c",
    },
    verde_oscuro = {
        normal = "#5e7f41",
        resaltado = "#78935f",
        pulsado = "#496333",
        desactivado = "#4c534a",
    },
    verde_nombre = {
        normal = "#4b9044",
        resaltado = "#68a262",
        pulsado = "#3a7035",
        desactivado = "#49554a",
    },
    texto_negro = {
        normal = "#000000",
        resaltado = "#292929",
        pulsado = "#000000",
        desactivado = "#0e0f11",
    },
    texto_gris = {
        normal = "#5e5e5e",
        resaltado = "#787878",
        pulsado = "#494949",
        desactivado = "#4b4c4e",
    },
    texto_claro = {
        normal = "#f2f2ee",
        resaltado = "#f4f4f1",
        pulsado = "#bdbdba",
        desactivado = "#abacad",
    },
    texto_tenue = {
        normal = "#b9b9ae",
        resaltado = "#c4c4bb",
        pulsado = "#909088",
        desactivado = "#848685",
    },
    texto_dorado = {
        normal = "#e7b534",
        resaltado = "#ebc154",
        pulsado = "#b48d29",
        desactivado = "#7f7865",
    },
    texto_sobre_dorado = {
        normal = "#1c1608",
        resaltado = "#403b30",
        pulsado = "#161106",
        desactivado = "#1c1c1c",
    },
}

Indice.tipografia = {
    familia = "Barlow Condensed / Barlow Semi Condensed",
    licencia = "SIL OFL 1.1 (assets/fuentes/OFL-Barlow.txt)",
    archivos = {
        titulo = "assets/fuentes/BarlowCondensed-SemiBold.ttf",
        subtitulo = "assets/fuentes/BarlowCondensed-SemiBold.ttf",
        cuerpo = "assets/fuentes/BarlowSemiCondensed-Medium.ttf",
        cuerpo_negrita = "assets/fuentes/BarlowSemiCondensed-SemiBold.ttf",
        rotulo = "assets/fuentes/BarlowCondensed-Medium.ttf",
    },
    nota = "Sans condensada de trazo militar, legible a tamaños pequeños.",
    tamanos = {
        rotulo = 13,
        cuerpo = 15,
        titulo_ventana = 22,
        cifra_grande = 28,
    },
}

Indice.piezas = {
    panel_acero = {
        descripcion = "Panel del HUD: verde oliva/caqui oscuro translúcido (88 %), esquinas de 6 px, filete claro fino. Texto blanco.",
        ancho = 96,
        alto = 96,
        nueve = {
            izq = 20,
            der = 20,
            arr = 20,
            aba = 20,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 8,
            aba = 8,
        },
        archivos = {
            normal = "paneles/panel_acero.png",
        },
    },
    panel_acero_cabecera = {
        descripcion = "Ventana del HUD: oliva translúcido con franja de cabecera de 44 px más oscura (título blanco, cerrar).",
        ancho = 96,
        alto = 112,
        nueve = {
            izq = 20,
            der = 20,
            arr = 48,
            aba = 20,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 50,
            aba = 8,
        },
        anclas = {
            logo = {
                x = 0,
                y = 0,
            },
            cerrar = {
                x = -4,
                y = 6,
                ref = "arriba_der",
            },
        },
        archivos = {
            normal = "paneles/panel_acero_cabecera.png",
        },
    },
    panel_contenido = {
        descripcion = "Área clara (#dfdfdf) con doble borde negro biselado, como los botones de opciones. Texto NEGRO encima.",
        ancho = 64,
        alto = 64,
        nueve = {
            izq = 10,
            der = 10,
            arr = 10,
            aba = 10,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 8,
            aba = 8,
        },
        archivos = {
            normal = "paneles/panel_contenido.png",
        },
    },
    celda_contenido = {
        descripcion = "Celda plana gris casi blanco (#dfe0e2) sin marco: rejilla de estadísticas. Texto negro.",
        ancho = 32,
        alto = 32,
        nueve = {
            izq = 4,
            der = 4,
            arr = 4,
            aba = 4,
        },
        contenido = {
            izq = 4,
            der = 4,
            arr = 4,
            aba = 4,
        },
        archivos = {
            normal = "paneles/celda_contenido.png",
        },
    },
    placa_dato = {
        descripcion = "Placa de dato clara (perfil: \"Nv. 27 / Nv. del Centro de mando\"): título negro grande (#000000) y subtítulo gris (#5e5e5e).",
        ancho = 64,
        alto = 64,
        nueve = {
            izq = 6,
            der = 6,
            arr = 6,
            aba = 6,
        },
        contenido = {
            izq = 16,
            der = 12,
            arr = 10,
            aba = 12,
        },
        archivos = {
            normal = "paneles/placa_dato.png",
        },
    },
    tarjeta_perfil = {
        descripcion = "Tarjeta de perfil: marco azul marino muy oscuro (#2a2f3d, el único azul del kit) con interior gris claro. Texto negro dentro.",
        ancho = 96,
        alto = 96,
        nueve = {
            izq = 24,
            der = 24,
            arr = 24,
            aba = 24,
        },
        contenido = {
            izq = 12,
            der = 12,
            arr = 12,
            aba = 12,
        },
        archivos = {
            normal = "paneles/tarjeta_perfil.png",
        },
    },
    panel_tooltip = {
        descripcion = "Ficha clara translúcida sobre el mapa (\"Centro de mando nv. 27\"): filas con fila_clara, texto negro.",
        ancho = 64,
        alto = 64,
        nueve = {
            izq = 8,
            der = 8,
            arr = 8,
            aba = 8,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 8,
            aba = 8,
        },
        archivos = {
            normal = "paneles/panel_tooltip.png",
        },
    },
    chip_oscuro = {
        descripcion = "Placa oliva translúcida de esquinas suaves: nivel, moneda, contadores del HUD.",
        ancho = 64,
        alto = 32,
        nueve = {
            izq = 12,
            der = 12,
            arr = 10,
            aba = 10,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 4,
            aba = 4,
        },
        archivos = {
            normal = "paneles/chip_oscuro.png",
        },
    },
    pastilla_recurso = {
        descripcion = "Pastilla de recurso de la cabecera del mapa: paralelogramo oliva translúcido con extremos inclinados. Icono a la izquierda, cifra blanca con contorno (dorada si es el oro).",
        ancho = 96,
        alto = 32,
        nueve = {
            izq = 16,
            der = 16,
            arr = 0,
            aba = 0,
        },
        contenido = {
            izq = 14,
            der = 14,
            arr = 3,
            aba = 3,
        },
        anclas = {
            icono = {
                x = 16,
                y = 16,
            },
        },
        archivos = {
            normal = "paneles/pastilla_recurso.png",
        },
    },
    rotulo = {
        descripcion = "Rótulo oliva translúcido para nombres sobre el mapa (texto blanco con contorno).",
        ancho = 32,
        alto = 32,
        nueve = {
            izq = 6,
            der = 6,
            arr = 6,
            aba = 6,
        },
        contenido = {
            izq = 6,
            der = 6,
            arr = 3,
            aba = 3,
        },
        archivos = {
            normal = "paneles/rotulo.png",
        },
    },
    cabecera = {
        descripcion = "Franja de cabecera oliva que se estira solo a lo ancho (3 trozos horizontales).",
        ancho = 96,
        alto = 44,
        nueve = {
            izq = 8,
            der = 8,
            arr = 0,
            aba = 0,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 0,
            aba = 2,
        },
        archivos = {
            normal = "paneles/cabecera.png",
        },
    },
    cabecera_logo = {
        descripcion = "Ranura de logotipo negra con marca dorada, a la izquierda de la cabecera; el título empieza en x = 68.",
        ancho = 64,
        alto = 44,
        anclas = {
            icono = {
                x = 28,
                y = 22,
            },
        },
        archivos = {
            normal = "paneles/cabecera_logo.png",
        },
    },
    separador = {
        descripcion = "Filete horizontal (oscuro y caqui tenue) para separar filas en paneles oliva.",
        ancho = 32,
        alto = 2,
        nueve = {
            izq = 4,
            der = 4,
            arr = 0,
            aba = 0,
        },
        archivos = {
            normal = "paneles/separador.png",
        },
    },
    ranura_vacia = {
        descripcion = "Hueco gris claro con borde punteado para elementos sin asignar (icono \"+\" encima).",
        ancho = 64,
        alto = 64,
        nueve = {
            izq = 8,
            der = 8,
            arr = 8,
            aba = 8,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 8,
            aba = 8,
        },
        archivos = {
            normal = "paneles/ranura_vacia.png",
        },
    },
    fondo_hormigon = {
        descripcion = "Textura de hormigón gris (#9fa2a6) de 256 px sin costuras, con losas de 128 px: fondo de las pantallas de menú (repetir en mosaico).",
        ancho = 256,
        alto = 256,
        archivos = {
            normal = "paneles/fondo_hormigon.png",
        },
    },
    boton_dorado = {
        descripcion = "Botón dorado (acción principal): oro con borde negro. Texto oscuro. Cuatro estados del mismo tamaño.",
        ancho = 96,
        alto = 40,
        nueve = {
            izq = 12,
            der = 12,
            arr = 12,
            aba = 12,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 4,
            aba = 4,
        },
        archivos = {
            normal = "botones/boton_dorado_normal.png",
            resaltado = "botones/boton_dorado_resaltado.png",
            pulsado = "botones/boton_dorado_pulsado.png",
            desactivado = "botones/boton_dorado_desactivado.png",
        },
    },
    boton_gris = {
        descripcion = "Botón claro de menú: gris casi blanco con DOBLE borde negro, como los de Opciones. Texto negro. Cuatro estados del mismo tamaño.",
        ancho = 96,
        alto = 36,
        nueve = {
            izq = 10,
            der = 10,
            arr = 10,
            aba = 10,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 4,
            aba = 4,
        },
        archivos = {
            normal = "botones/boton_gris_normal.png",
            resaltado = "botones/boton_gris_resaltado.png",
            pulsado = "botones/boton_gris_pulsado.png",
            desactivado = "botones/boton_gris_desactivado.png",
        },
    },
    boton_oscuro = {
        descripcion = "Botón de metal gris oscuro con borde claro (cuadrados del HUD). Texto e iconos blancos. Cuatro estados del mismo tamaño.",
        ancho = 96,
        alto = 36,
        nueve = {
            izq = 10,
            der = 10,
            arr = 10,
            aba = 10,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 4,
            aba = 4,
        },
        archivos = {
            normal = "botones/boton_oscuro_normal.png",
            resaltado = "botones/boton_oscuro_resaltado.png",
            pulsado = "botones/boton_oscuro_pulsado.png",
            desactivado = "botones/boton_oscuro_desactivado.png",
        },
    },
    boton_mas = {
        descripcion = "Botón cuadrado dorado con \"+\" ya dibujado (oro, energía, ranuras). Tamaño fijo 40x40.",
        ancho = 40,
        alto = 40,
        anclas = {
            centro = {
                x = 20,
                y = 20,
            },
        },
        archivos = {
            normal = "botones/boton_mas_normal.png",
            resaltado = "botones/boton_mas_resaltado.png",
            pulsado = "botones/boton_mas_pulsado.png",
            desactivado = "botones/boton_mas_desactivado.png",
        },
    },
    hexagono_icono = {
        descripcion = "Hexágono de metal gris (72x80, vértice arriba) para iconos del HUD, menú radial y accesos del perfil. Estados: normal, resaltado, pulsado, desactivado y activo (crema con aro dorado: icono oscuro). Icono blanco de 32-36 px en el centro, rótulo blanco con contorno debajo, insignia roja arriba a la derecha.",
        ancho = 72,
        alto = 80,
        anclas = {
            icono = {
                x = 36,
                y = 40,
            },
            texto = {
                x = 36,
                y = 88,
            },
            insignia = {
                x = -8,
                y = 6,
                ref = "arriba_der",
            },
        },
        archivos = {
            normal = "botones/hexagono_icono_normal.png",
            resaltado = "botones/hexagono_icono_resaltado.png",
            pulsado = "botones/hexagono_icono_pulsado.png",
            desactivado = "botones/hexagono_icono_desactivado.png",
            activo = "botones/hexagono_icono_activo.png",
        },
    },
    ficha_icono = {
        descripcion = "Ficha cuadrada de metal gris oscuro con borde claro (botones cuadrados del HUD): icono blanco arriba, rótulo abajo, insignia roja. Activa: aro dorado sobre oliva.",
        ancho = 72,
        alto = 72,
        nueve = {
            izq = 12,
            der = 12,
            arr = 12,
            aba = 12,
        },
        contenido = {
            izq = 6,
            der = 6,
            arr = 6,
            aba = 6,
        },
        anclas = {
            icono = {
                x = 36,
                y = 26,
            },
            texto = {
                x = 36,
                y = 60,
            },
            insignia = {
                x = -4,
                y = 4,
                ref = "arriba_der",
            },
        },
        archivos = {
            normal = "botones/ficha_icono_normal.png",
            resaltada = "botones/ficha_icono_resaltada.png",
            activa = "botones/ficha_icono_activa.png",
        },
    },
    insignia_roja = {
        descripcion = "Insignia redonda roja (#c53535) con aro blanco, 24 px; el número (blanco, negrita) en el centro.",
        ancho = 24,
        alto = 24,
        anclas = {
            centro = {
                x = 12,
                y = 12,
            },
        },
        archivos = {
            normal = "botones/insignia_roja.png",
        },
    },
    insignia_nuevo = {
        descripcion = "Pastilla roja para \"Nuevo\" y avisos de texto corto (blanco, negrita).",
        ancho = 44,
        alto = 20,
        nueve = {
            izq = 10,
            der = 10,
            arr = 0,
            aba = 0,
        },
        contenido = {
            izq = 6,
            der = 6,
            arr = 2,
            aba = 2,
        },
        archivos = {
            normal = "botones/insignia_nuevo.png",
        },
    },
    pestana = {
        descripcion = "Pestaña de metal gris (inactiva) u oliva con filete dorado abajo (activa). Texto blanco / dorado.",
        ancho = 96,
        alto = 36,
        nueve = {
            izq = 12,
            der = 12,
            arr = 12,
            aba = 6,
        },
        contenido = {
            izq = 10,
            der = 10,
            arr = 4,
            aba = 6,
        },
        archivos = {
            inactiva = "botones/pestana_inactiva.png",
            activa = "botones/pestana_activa.png",
        },
    },
    boton_cerrar = {
        descripcion = "Botón cuadrado de metal con aspa blanca ya dibujada, para la esquina de la cabecera.",
        ancho = 32,
        alto = 32,
        anclas = {
            centro = {
                x = 16,
                y = 16,
            },
        },
        archivos = {
            normal = "botones/boton_cerrar_normal.png",
            resaltado = "botones/boton_cerrar_resaltado.png",
            pulsado = "botones/boton_cerrar_pulsado.png",
            desactivado = "botones/boton_cerrar_desactivado.png",
        },
    },
    barra_fondo = {
        descripcion = "Canal oliva casi negro con marco gris claro fino; el relleno va dentro del margen \"contenido\" (2 px).",
        ancho = 64,
        alto = 14,
        nueve = {
            izq = 5,
            der = 5,
            arr = 0,
            aba = 0,
        },
        contenido = {
            izq = 2,
            der = 2,
            arr = 2,
            aba = 2,
        },
        archivos = {
            normal = "barras/barra_fondo.png",
        },
    },
    barra_relleno_estadistica = {
        descripcion = "Estadística: blanco caqui (Ataque, Defensa...).",
        ancho = 64,
        alto = 10,
        nueve = {
            izq = 4,
            der = 4,
            arr = 0,
            aba = 0,
        },
        archivos = {
            normal = "barras/barra_relleno_estadistica.png",
        },
    },
    barra_relleno_recurso = {
        descripcion = "Recurso: dorado (capacidad de almacén, producción).",
        ancho = 64,
        alto = 10,
        nueve = {
            izq = 4,
            der = 4,
            arr = 0,
            aba = 0,
        },
        archivos = {
            normal = "barras/barra_relleno_recurso.png",
        },
    },
    barra_relleno_experiencia = {
        descripcion = "Experiencia y nivel: verde caqui claro.",
        ancho = 64,
        alto = 10,
        nueve = {
            izq = 4,
            der = 4,
            arr = 0,
            aba = 0,
        },
        archivos = {
            normal = "barras/barra_relleno_experiencia.png",
        },
    },
    barra_relleno_peligro = {
        descripcion = "Peligro: rojo (vida baja, alerta).",
        ancho = 64,
        alto = 10,
        nueve = {
            izq = 4,
            der = 4,
            arr = 0,
            aba = 0,
        },
        archivos = {
            normal = "barras/barra_relleno_peligro.png",
        },
    },
    barra_relleno_energia = {
        descripcion = "Energía: verde lima (#84c144) con galones. Para que los galones no se deformen, estirar en múltiplos de 16 px.",
        ancho = 64,
        alto = 10,
        nueve = {
            izq = 8,
            der = 8,
            arr = 0,
            aba = 0,
        },
        archivos = {
            normal = "barras/barra_relleno_energia.png",
        },
    },
    deslizador_carril = {
        descripcion = "Carril vacío del deslizador (gris claro, borde negro).",
        ancho = 64,
        alto = 8,
        nueve = {
            izq = 4,
            der = 4,
            arr = 0,
            aba = 0,
        },
        archivos = {
            normal = "barras/deslizador_carril.png",
        },
    },
    deslizador_lleno = {
        descripcion = "Tramo lleno del deslizador (verde lima), hasta el centro del pomo.",
        ancho = 64,
        alto = 8,
        nueve = {
            izq = 4,
            der = 4,
            arr = 0,
            aba = 0,
        },
        archivos = {
            normal = "barras/deslizador_lleno.png",
        },
    },
    deslizador_pomo = {
        descripcion = "Pomo redondo del deslizador; centrarlo sobre el valor.",
        ancho = 20,
        alto = 20,
        anclas = {
            centro = {
                x = 10,
                y = 10,
            },
        },
        archivos = {
            normal = "barras/deslizador_pomo_normal.png",
            resaltado = "barras/deslizador_pomo_resaltado.png",
            pulsado = "barras/deslizador_pomo_pulsado.png",
            desactivado = "barras/deslizador_pomo_desactivado.png",
        },
    },
    interruptor = {
        descripcion = "Interruptor de 44x22 (encendido en verde). Estados: apagado, encendido y sus dos versiones desactivadas.",
        ancho = 44,
        alto = 22,
        anclas = {
            centro = {
                x = 22,
                y = 11,
            },
        },
        archivos = {
            apagado = "barras/interruptor_apagado.png",
            encendido = "barras/interruptor_encendido.png",
            desactivado_apagado = "barras/interruptor_desactivado_apagado.png",
            desactivado_encendido = "barras/interruptor_desactivado_encendido.png",
        },
    },
    fila_clara = {
        descripcion = "Fila de lista clara (normal, hover, seleccionada). Clara: texto negro; la seleccionada (oliva + barra dorada) lleva texto blanco. Oscura: oliva translúcido, texto blanco. Icono a la izquierda, texto a 34 px.",
        ancho = 64,
        alto = 28,
        nueve = {
            izq = 4,
            der = 4,
            arr = 4,
            aba = 4,
        },
        contenido = {
            izq = 12,
            der = 8,
            arr = 2,
            aba = 2,
        },
        archivos = {
            normal = "listas/fila_clara_normal.png",
            hover = "listas/fila_clara_hover.png",
            seleccionada = "listas/fila_clara_seleccionada.png",
        },
    },
    fila_oscura = {
        descripcion = "Fila de lista oscura (normal, hover, seleccionada). Clara: texto negro; la seleccionada (oliva + barra dorada) lleva texto blanco. Oscura: oliva translúcido, texto blanco. Icono a la izquierda, texto a 34 px.",
        ancho = 64,
        alto = 28,
        nueve = {
            izq = 4,
            der = 4,
            arr = 4,
            aba = 4,
        },
        contenido = {
            izq = 12,
            der = 8,
            arr = 2,
            aba = 2,
        },
        archivos = {
            normal = "listas/fila_oscura_normal.png",
            hover = "listas/fila_oscura_hover.png",
            seleccionada = "listas/fila_oscura_seleccionada.png",
        },
    },
    fila_opcion = {
        descripcion = "Botón ancho de la pantalla de Opciones: gris casi blanco (#dfdfdf) con DOBLE borde negro biselado, icono NEGRO a la izquierda (centro en x = 32) y texto negro condensado a x = 60. Cuatro estados. Insignia \"Nuevo\" arriba a la derecha.",
        ancho = 96,
        alto = 56,
        nueve = {
            izq = 12,
            der = 12,
            arr = 12,
            aba = 12,
        },
        contenido = {
            izq = 60,
            der = 14,
            arr = 6,
            aba = 6,
        },
        anclas = {
            icono = {
                x = 32,
                y = 28,
            },
            insignia = {
                x = -6,
                y = -8,
                ref = "arriba_der",
            },
        },
        archivos = {
            normal = "listas/fila_opcion_normal.png",
            resaltado = "listas/fila_opcion_resaltado.png",
            pulsado = "listas/fila_opcion_pulsado.png",
            desactivado = "listas/fila_opcion_desactivado.png",
        },
    },
    campo = {
        descripcion = "Campo de texto claro con doble borde negro. Cuatro estados. Texto negro.",
        ancho = 96,
        alto = 26,
        nueve = {
            izq = 6,
            der = 6,
            arr = 6,
            aba = 6,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 2,
            aba = 2,
        },
        archivos = {
            normal = "listas/campo_normal.png",
            resaltado = "listas/campo_resaltado.png",
            pulsado = "listas/campo_pulsado.png",
            desactivado = "listas/campo_desactivado.png",
        },
    },
    desplegable = {
        descripcion = "Desplegable claro con doble borde negro y triángulo a la derecha. Cuatro estados. Texto negro.",
        ancho = 96,
        alto = 26,
        nueve = {
            izq = 6,
            der = 24,
            arr = 6,
            aba = 6,
        },
        contenido = {
            izq = 8,
            der = 26,
            arr = 2,
            aba = 2,
        },
        archivos = {
            normal = "listas/desplegable_normal.png",
            resaltado = "listas/desplegable_resaltado.png",
            pulsado = "listas/desplegable_pulsado.png",
            desactivado = "listas/desplegable_desactivado.png",
        },
    },
    tarjeta_unidad = {
        descripcion = "Marco de tarjeta de unidad: oliva con filete gris claro (activa: dorado), como las tarjetas de tropa de Warpath.",
        ancho = 64,
        alto = 64,
        nueve = {
            izq = 6,
            der = 6,
            arr = 6,
            aba = 6,
        },
        contenido = {
            izq = 3,
            der = 3,
            arr = 3,
            aba = 3,
        },
        anclas = {
            insignia_nivel = {
                x = -6,
                y = 6,
                ref = "arriba_der",
            },
        },
        archivos = {
            normal = "listas/tarjeta_unidad_normal.png",
            resaltada = "listas/tarjeta_unidad_resaltada.png",
            activa = "listas/tarjeta_unidad_activa.png",
        },
    },
    tarjeta_evento = {
        descripcion = "Marco de tarjeta de evento/aviso (columna derecha del mapa): filete negro + borde gris claro con el centro TRANSPARENTE. Dibujar debajo la imagen o un fondo oliva, y encima el título (blanco con contorno). Estados: normal, resaltada, activa (dorado). Insignia roja arriba a la derecha.",
        ancho = 96,
        alto = 48,
        nueve = {
            izq = 6,
            der = 6,
            arr = 6,
            aba = 6,
        },
        contenido = {
            izq = 5,
            der = 5,
            arr = 5,
            aba = 5,
        },
        anclas = {
            insignia = {
                x = -4,
                y = -6,
                ref = "arriba_der",
            },
        },
        archivos = {
            normal = "listas/tarjeta_evento_normal.png",
            resaltada = "listas/tarjeta_evento_resaltada.png",
            activa = "listas/tarjeta_evento_activa.png",
        },
    },
    chapa_nacion = {
        descripcion = "Chapa redonda de nación (80x80): anillo dorado y oliva con hueco central TRANSPARENTE de 54 px de diámetro. Dibujar dentro la bandera o el escudo recortado en círculo (radio 27). Sirve de avatar en el perfil.",
        ancho = 80,
        alto = 80,
        anclas = {
            centro = {
                x = 40,
                y = 40,
            },
            insignia = {
                x = -4,
                y = 4,
                ref = "arriba_der",
            },
        },
        archivos = {
            normal = "listas/chapa_nacion.png",
        },
    },
    contador = {
        descripcion = "Pastilla oliva oscura con el contador de una categoría.",
        ancho = 40,
        alto = 20,
        nueve = {
            izq = 10,
            der = 10,
            arr = 0,
            aba = 0,
        },
        contenido = {
            izq = 6,
            der = 6,
            arr = 2,
            aba = 2,
        },
        archivos = {
            normal = "listas/contador.png",
        },
    },
    selector_cantidad = {
        descripcion = "Selector de cantidad \"-  1  +\": botones cuadrados de 40 px con el signo ya dibujado y campo oscuro central (texto blanco, cifra centrada; rango de clic: los 40 px de cada extremo). Estados: normal, menos_pulsado, mas_pulsado, desactivado.",
        ancho = 160,
        alto = 40,
        nueve = {
            izq = 42,
            der = 42,
            arr = 6,
            aba = 6,
        },
        contenido = {
            izq = 44,
            der = 44,
            arr = 4,
            aba = 4,
        },
        anclas = {
            menos = {
                x = 20,
                y = 20,
            },
            mas = {
                x = -20,
                y = 20,
                ref = "arriba_der",
            },
        },
        archivos = {
            normal = "listas/selector_cantidad_normal.png",
            menos_pulsado = "listas/selector_cantidad_menos_pulsado.png",
            mas_pulsado = "listas/selector_cantidad_mas_pulsado.png",
            desactivado = "listas/selector_cantidad_desactivado.png",
        },
    },
    fila_datos = {
        descripcion = "Fila de la tabla de datos de dos columnas (Tipo / Arma principal / Costo...): franja oliva translúcida con filete. Estados normal y alterna (más clara, para filas pares). Etiqueta gris claro a la izquierda del 50 % y valor blanco a la derecha; una fila por par, dos pares por fila si la tabla lleva cuatro columnas.",
        ancho = 96,
        alto = 24,
        nueve = {
            izq = 4,
            der = 4,
            arr = 4,
            aba = 4,
        },
        contenido = {
            izq = 8,
            der = 8,
            arr = 2,
            aba = 2,
        },
        archivos = {
            normal = "listas/fila_datos_normal.png",
            alterna = "listas/fila_datos_alterna.png",
        },
    },
    barra_estadistica_fondo = {
        descripcion = "Canal de la barra de estadística del Arsenal (12 px) con marcas al 25, 50 y 75 %. Poner debajo el relleno barra_estadistica_relleno; a la derecha, el valor en texto blanco (y su unidad).",
        ancho = 96,
        alto = 12,
        nueve = {
            izq = 5,
            der = 5,
            arr = 0,
            aba = 0,
        },
        contenido = {
            izq = 2,
            der = 2,
            arr = 2,
            aba = 2,
        },
        archivos = {
            normal = "barras/barra_estadistica_fondo.png",
        },
    },
    barra_estadistica_relleno = {
        descripcion = "Relleno azul acero claro de la barra de estadística (como el concepto del Arsenal). Ancho = valor / máximo del canal menos 4 px; dentro del margen \"contenido\" del fondo.",
        ancho = 64,
        alto = 8,
        nueve = {
            izq = 3,
            der = 3,
            arr = 0,
            aba = 0,
        },
        archivos = {
            normal = "barras/barra_estadistica_relleno.png",
        },
    },
    franja_miniaturas = {
        descripcion = "Fondo oscuro de la franja de miniaturas bajo la imagen de detalle. Las flechas (boton_franja_*) van en los extremos; las miniaturas (miniatura_marco) en el área \"contenido\".",
        ancho = 320,
        alto = 72,
        nueve = {
            izq = 6,
            der = 6,
            arr = 6,
            aba = 6,
        },
        contenido = {
            izq = 34,
            der = 34,
            arr = 5,
            aba = 5,
        },
        anclas = {
            flecha_izquierda = {
                x = 15,
                y = 36,
            },
            flecha_derecha = {
                x = -15,
                y = 36,
                ref = "arriba_der",
            },
        },
        archivos = {
            normal = "listas/franja_miniaturas.png",
        },
    },
    boton_franja_izquierda = {
        descripcion = "Flecha de la franja de miniaturas (izquierda), 26x56 con el chevron dibujado. Cuatro estados.",
        ancho = 26,
        alto = 56,
        anclas = {
            centro = {
                x = 13.0,
                y = 28.0,
            },
        },
        archivos = {
            normal = "botones/boton_franja_izquierda_normal.png",
            resaltado = "botones/boton_franja_izquierda_resaltado.png",
            pulsado = "botones/boton_franja_izquierda_pulsado.png",
            desactivado = "botones/boton_franja_izquierda_desactivado.png",
        },
    },
    boton_franja_derecha = {
        descripcion = "Flecha de la franja de miniaturas (derecha), 26x56 con el chevron dibujado. Cuatro estados.",
        ancho = 26,
        alto = 56,
        anclas = {
            centro = {
                x = 13.0,
                y = 28.0,
            },
        },
        archivos = {
            normal = "botones/boton_franja_derecha_normal.png",
            resaltado = "botones/boton_franja_derecha_resaltado.png",
            pulsado = "botones/boton_franja_derecha_pulsado.png",
            desactivado = "botones/boton_franja_derecha_desactivado.png",
        },
    },
    miniatura_marco = {
        descripcion = "Marco de una miniatura de la franja (centro TRANSPARENTE: dibujar debajo la imagen). Estados: normal (gris) y activa (dorado).",
        ancho = 64,
        alto = 48,
        nueve = {
            izq = 4,
            der = 4,
            arr = 4,
            aba = 4,
        },
        contenido = {
            izq = 3,
            der = 3,
            arr = 3,
            aba = 3,
        },
        archivos = {
            normal = "listas/miniatura_marco_normal.png",
            activa = "listas/miniatura_marco_activa.png",
        },
    },
    tarjeta_doctrina = {
        descripcion = "Tarjeta de Doctrina (esquina inferior izquierda del Arsenal): marco fino con la parte superior TRANSPARENTE (poner debajo una imagen de fondo) y franja inferior oscura de 46 px con filete dorado y chevron dorado a la derecha. Sobre la franja: emblema hexagonal a la izquierda, título blanco en mayúsculas y lema gris debajo. Estados: normal y resaltada.",
        ancho = 300,
        alto = 100,
        nueve = {
            izq = 8,
            der = 34,
            arr = 8,
            aba = 54,
        },
        contenido = {
            izq = 8,
            der = 34,
            arr = 8,
            aba = 6,
        },
        anclas = {
            chevron = {
                x = -22,
                y = 76.0,
                ref = "arriba_der",
            },
            texto = {
                x = 66,
                y = 64,
            },
            emblema = {
                x = 8,
                y = 58,
            },
        },
        archivos = {
            normal = "listas/tarjeta_doctrina_normal.png",
            resaltada = "listas/tarjeta_doctrina_resaltada.png",
        },
    },
}

Indice.iconos = {
    metal = {
        grupo = "recursos",
        descripcion = "Planchas de metal",
        archivos = {
            ["64"] = "iconos/metal_64.png",
            ["32"] = "iconos/metal_32.png",
        },
    },
    petroleo = {
        grupo = "recursos",
        descripcion = "Gota de petróleo",
        archivos = {
            ["64"] = "iconos/petroleo_64.png",
            ["32"] = "iconos/petroleo_32.png",
        },
    },
    comida = {
        grupo = "recursos",
        descripcion = "Espiga",
        archivos = {
            ["64"] = "iconos/comida_64.png",
            ["32"] = "iconos/comida_32.png",
        },
    },
    dinero = {
        grupo = "recursos",
        descripcion = "Moneda con símbolo de dinero (el oro es dinero: mismo icono)",
        archivos = {
            ["64"] = "iconos/dinero_64.png",
            ["32"] = "iconos/dinero_32.png",
        },
    },
    soldado = {
        grupo = "unidades",
        descripcion = "Soldado con casco",
        archivos = {
            ["64"] = "iconos/soldado_64.png",
            ["32"] = "iconos/soldado_32.png",
        },
    },
    tanque = {
        grupo = "unidades",
        descripcion = "Tanque",
        archivos = {
            ["64"] = "iconos/tanque_64.png",
            ["32"] = "iconos/tanque_32.png",
        },
    },
    lanzacohetes = {
        grupo = "unidades",
        descripcion = "Camión lanzacohetes",
        archivos = {
            ["64"] = "iconos/lanzacohetes_64.png",
            ["32"] = "iconos/lanzacohetes_32.png",
        },
    },
    atacar = {
        grupo = "ordenes",
        descripcion = "Espadas cruzadas",
        archivos = {
            ["64"] = "iconos/atacar_64.png",
            ["32"] = "iconos/atacar_32.png",
        },
    },
    defender = {
        grupo = "ordenes",
        descripcion = "Escudo con galones",
        archivos = {
            ["64"] = "iconos/defender_64.png",
            ["32"] = "iconos/defender_32.png",
        },
    },
    recolectar = {
        grupo = "ordenes",
        descripcion = "Pico",
        archivos = {
            ["64"] = "iconos/recolectar_64.png",
            ["32"] = "iconos/recolectar_32.png",
        },
    },
    retirar = {
        grupo = "ordenes",
        descripcion = "Flecha en U",
        archivos = {
            ["64"] = "iconos/retirar_64.png",
            ["32"] = "iconos/retirar_32.png",
        },
    },
    mover = {
        grupo = "ordenes",
        descripcion = "Cuatro flechas",
        archivos = {
            ["64"] = "iconos/mover_64.png",
            ["32"] = "iconos/mover_32.png",
        },
    },
    bandera = {
        grupo = "ordenes",
        descripcion = "Bandera",
        archivos = {
            ["64"] = "iconos/bandera_64.png",
            ["32"] = "iconos/bandera_32.png",
        },
    },
    reparar = {
        grupo = "ordenes",
        descripcion = "Llave inglesa",
        archivos = {
            ["64"] = "iconos/reparar_64.png",
            ["32"] = "iconos/reparar_32.png",
        },
    },
    refuerzo = {
        grupo = "ordenes",
        descripcion = "Galones hacia arriba con más",
        archivos = {
            ["64"] = "iconos/refuerzo_64.png",
            ["32"] = "iconos/refuerzo_32.png",
        },
    },
    construir = {
        grupo = "navegacion",
        descripcion = "Martillo",
        archivos = {
            ["64"] = "iconos/construir_64.png",
            ["32"] = "iconos/construir_32.png",
        },
    },
    investigar = {
        grupo = "navegacion",
        descripcion = "Matraz",
        archivos = {
            ["64"] = "iconos/investigar_64.png",
            ["32"] = "iconos/investigar_32.png",
        },
    },
    misiones = {
        grupo = "navegacion",
        descripcion = "Portapapeles",
        archivos = {
            ["64"] = "iconos/misiones_64.png",
            ["32"] = "iconos/misiones_32.png",
        },
    },
    eventos = {
        grupo = "navegacion",
        descripcion = "Caja de regalo",
        archivos = {
            ["64"] = "iconos/eventos_64.png",
            ["32"] = "iconos/eventos_32.png",
        },
    },
    correo = {
        grupo = "navegacion",
        descripcion = "Sobre",
        archivos = {
            ["64"] = "iconos/correo_64.png",
            ["32"] = "iconos/correo_32.png",
        },
    },
    ejercito = {
        grupo = "navegacion",
        descripcion = "Estrella con galones de rango",
        archivos = {
            ["64"] = "iconos/ejercito_64.png",
            ["32"] = "iconos/ejercito_32.png",
        },
    },
    unidades = {
        grupo = "navegacion",
        descripcion = "Vehículo blindado",
        archivos = {
            ["64"] = "iconos/unidades_64.png",
            ["32"] = "iconos/unidades_32.png",
        },
    },
    suministros = {
        grupo = "navegacion",
        descripcion = "Caja de suministros",
        archivos = {
            ["64"] = "iconos/suministros_64.png",
            ["32"] = "iconos/suministros_32.png",
        },
    },
    alianza = {
        grupo = "navegacion",
        descripcion = "Tres personas",
        archivos = {
            ["64"] = "iconos/alianza_64.png",
            ["32"] = "iconos/alianza_32.png",
        },
    },
    oficiales = {
        grupo = "navegacion",
        descripcion = "Gorra de oficial",
        archivos = {
            ["64"] = "iconos/oficiales_64.png",
            ["32"] = "iconos/oficiales_32.png",
        },
    },
    mundo = {
        grupo = "navegacion",
        descripcion = "Globo terráqueo",
        archivos = {
            ["64"] = "iconos/mundo_64.png",
            ["32"] = "iconos/mundo_32.png",
        },
    },
    ajustes = {
        grupo = "navegacion",
        descripcion = "Engranaje",
        archivos = {
            ["64"] = "iconos/ajustes_64.png",
            ["32"] = "iconos/ajustes_32.png",
        },
    },
    guardar = {
        grupo = "navegacion",
        descripcion = "Disquete",
        archivos = {
            ["64"] = "iconos/guardar_64.png",
            ["32"] = "iconos/guardar_32.png",
        },
    },
    perfil = {
        grupo = "navegacion",
        descripcion = "Busto con galón de rango",
        archivos = {
            ["64"] = "iconos/perfil_64.png",
            ["32"] = "iconos/perfil_32.png",
        },
    },
    batallas = {
        grupo = "navegacion",
        descripcion = "Mira telescópica",
        archivos = {
            ["64"] = "iconos/batallas_64.png",
            ["32"] = "iconos/batallas_32.png",
        },
    },
    noticias = {
        grupo = "navegacion",
        descripcion = "Periódico",
        archivos = {
            ["64"] = "iconos/noticias_64.png",
            ["32"] = "iconos/noticias_32.png",
        },
    },
    busqueda = {
        grupo = "navegacion",
        descripcion = "Lupa",
        archivos = {
            ["64"] = "iconos/busqueda_64.png",
            ["32"] = "iconos/busqueda_32.png",
        },
    },
    cerrar = {
        grupo = "navegacion",
        descripcion = "Aspa",
        archivos = {
            ["64"] = "iconos/cerrar_64.png",
            ["32"] = "iconos/cerrar_32.png",
        },
    },
    mas = {
        grupo = "navegacion",
        descripcion = "Más",
        archivos = {
            ["64"] = "iconos/mas_64.png",
            ["32"] = "iconos/mas_32.png",
        },
    },
    flecha_arriba = {
        grupo = "navegacion",
        descripcion = "Flecha arriba",
        archivos = {
            ["64"] = "iconos/flecha_arriba_64.png",
            ["32"] = "iconos/flecha_arriba_32.png",
        },
    },
    flecha_abajo = {
        grupo = "navegacion",
        descripcion = "Flecha abajo",
        archivos = {
            ["64"] = "iconos/flecha_abajo_64.png",
            ["32"] = "iconos/flecha_abajo_32.png",
        },
    },
    flecha_izquierda = {
        grupo = "navegacion",
        descripcion = "Flecha izquierda",
        archivos = {
            ["64"] = "iconos/flecha_izquierda_64.png",
            ["32"] = "iconos/flecha_izquierda_32.png",
        },
    },
    flecha_derecha = {
        grupo = "navegacion",
        descripcion = "Flecha derecha",
        archivos = {
            ["64"] = "iconos/flecha_derecha_64.png",
            ["32"] = "iconos/flecha_derecha_32.png",
        },
    },
    cat_artilleria = {
        grupo = "categorias",
        descripcion = "Obús de artillería",
        archivos = {
            ["64"] = "iconos/cat_artilleria_64.png",
            ["32"] = "iconos/cat_artilleria_32.png",
        },
    },
    cat_misiles = {
        grupo = "categorias",
        descripcion = "Misil en diagonal",
        archivos = {
            ["64"] = "iconos/cat_misiles_64.png",
            ["32"] = "iconos/cat_misiles_32.png",
        },
    },
    cat_defensa_aerea = {
        grupo = "categorias",
        descripcion = "Mira con avión en el centro",
        archivos = {
            ["64"] = "iconos/cat_defensa_aerea_64.png",
            ["32"] = "iconos/cat_defensa_aerea_32.png",
        },
    },
    cat_aviacion = {
        grupo = "categorias",
        descripcion = "Avión de caza",
        archivos = {
            ["64"] = "iconos/cat_aviacion_64.png",
            ["32"] = "iconos/cat_aviacion_32.png",
        },
    },
    cat_helicopteros = {
        grupo = "categorias",
        descripcion = "Helicóptero",
        archivos = {
            ["64"] = "iconos/cat_helicopteros_64.png",
            ["32"] = "iconos/cat_helicopteros_32.png",
        },
    },
    cat_drones = {
        grupo = "categorias",
        descripcion = "Dron de cuatro rotores",
        archivos = {
            ["64"] = "iconos/cat_drones_64.png",
            ["32"] = "iconos/cat_drones_32.png",
        },
    },
    cat_marina = {
        grupo = "categorias",
        descripcion = "Buque sobre olas",
        archivos = {
            ["64"] = "iconos/cat_marina_64.png",
            ["32"] = "iconos/cat_marina_32.png",
        },
    },
    cat_logistica = {
        grupo = "categorias",
        descripcion = "Camión de carga",
        archivos = {
            ["64"] = "iconos/cat_logistica_64.png",
            ["32"] = "iconos/cat_logistica_32.png",
        },
    },
    cat_ingenieria = {
        grupo = "categorias",
        descripcion = "Casco de obra",
        archivos = {
            ["64"] = "iconos/cat_ingenieria_64.png",
            ["32"] = "iconos/cat_ingenieria_32.png",
        },
    },
    cat_mando = {
        grupo = "categorias",
        descripcion = "Ojo con estrella (mando e inteligencia)",
        archivos = {
            ["64"] = "iconos/cat_mando_64.png",
            ["32"] = "iconos/cat_mando_32.png",
        },
    },
    cat_defensa_estrategica = {
        grupo = "categorias",
        descripcion = "Escudo con misil interceptor",
        archivos = {
            ["64"] = "iconos/cat_defensa_estrategica_64.png",
            ["32"] = "iconos/cat_defensa_estrategica_32.png",
        },
    },
    filtro = {
        grupo = "categorias",
        descripcion = "Embudo de filtro",
        archivos = {
            ["64"] = "iconos/filtro_64.png",
            ["32"] = "iconos/filtro_32.png",
        },
    },
    alerta = {
        grupo = "estados",
        descripcion = "Triángulo de alerta",
        archivos = {
            ["64"] = "iconos/alerta_64.png",
            ["32"] = "iconos/alerta_32.png",
        },
    },
    energia = {
        grupo = "estados",
        descripcion = "Rayo",
        archivos = {
            ["64"] = "iconos/energia_64.png",
            ["32"] = "iconos/energia_32.png",
        },
    },
    poder = {
        grupo = "estados",
        descripcion = "Estrella en hexágono",
        archivos = {
            ["64"] = "iconos/poder_64.png",
            ["32"] = "iconos/poder_32.png",
        },
    },
    nivel = {
        grupo = "estados",
        descripcion = "Flecha de subida de nivel",
        archivos = {
            ["64"] = "iconos/nivel_64.png",
            ["32"] = "iconos/nivel_32.png",
        },
    },
    vida = {
        grupo = "estados",
        descripcion = "Corazón",
        archivos = {
            ["64"] = "iconos/vida_64.png",
            ["32"] = "iconos/vida_32.png",
        },
    },
    escudo = {
        grupo = "estados",
        descripcion = "Escudo con escudo",
        archivos = {
            ["64"] = "iconos/escudo_64.png",
            ["32"] = "iconos/escudo_32.png",
        },
    },
}

-- Iconos a color propio (no se tiñen): archivos["64"] y archivos["32"].
Indice.iconosColor = {
    metal = {
        grupo = "recursos",
        descripcion = "Lingotes de acero azul-gris",
        archivos = {
            ["64"] = "iconos_color/metal_64.png",
            ["32"] = "iconos_color/metal_32.png",
        },
    },
    petroleo = {
        grupo = "recursos",
        descripcion = "Gota de petróleo oscura con brillo",
        archivos = {
            ["64"] = "iconos_color/petroleo_64.png",
            ["32"] = "iconos_color/petroleo_32.png",
        },
    },
    comida = {
        grupo = "recursos",
        descripcion = "Espiga dorada",
        archivos = {
            ["64"] = "iconos_color/comida_64.png",
            ["32"] = "iconos_color/comida_32.png",
        },
    },
    dinero = {
        grupo = "recursos",
        descripcion = "Fajo de billetes verde (el oro es dinero: mismo icono)",
        archivos = {
            ["64"] = "iconos_color/dinero_64.png",
            ["32"] = "iconos_color/dinero_32.png",
        },
    },
    poder = {
        grupo = "recursos",
        descripcion = "Escudo con estrella dorada",
        archivos = {
            ["64"] = "iconos_color/poder_64.png",
            ["32"] = "iconos_color/poder_32.png",
        },
    },
}

-- Renders del Arsenal (miniatura 200x120, detalle 520x230), hechos con
-- tools/blender/render_arsenal.py y tools/componer_arsenal.py.
Indice.arsenal = {
    soldado = {
        miniatura = "arsenal/soldado_miniatura.png",
        detalle = "arsenal/soldado_detalle.png",
    },
}

return Indice
