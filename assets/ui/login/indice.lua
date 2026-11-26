-- Piezas de la pantalla de login (diseño encargado por el dueño, sin texto).
-- Generado por tools/login_piezas.py: no editar a mano.
--
-- ancho, alto: px a 1080p (a 1440p escalar por 4/3).
-- nueve = { izq, der, arr, aba }: márgenes 9-slice; sin nueve, tamaño fijo.
-- contenido = { izq, der, arr, aba }: relleno interior para el texto.
-- disposicion: posición de cada pieza y caja de cada texto en el diseño
-- original a 1920 x 1080 (esquina superior izquierda, px).
-- Los textos se escriben en el juego con Barlow (assets/fuentes).
local carpeta = "assets/ui/login/"

return {
    carpeta = carpeta,
    logo = {
        archivo = carpeta .. "logo_nations.png",
        archivo2x = carpeta .. "logo_nations@2x.png",
        ancho = 927,
        alto = 301,
        efecto = carpeta .. "logo_nations_efecto.png",
        -- El efecto (1198 x 508) va en (0, 0) al 71 % y el logo en (50, 35).
        efectoOpacidad = 0.71,
    },
    fondo = {
        archivo = carpeta .. "fondo/fondo_login_1920.jpg",
        archivo1440 = carpeta .. "fondo/fondo_login_2560.jpg",
        -- Capas de paralaje a 2816 x 1584 (10 % de margen sobre 2560 x 1440):
        -- el encuadre del fondo es su recorte central.
        capas = {
            carpeta .. "fondo/capa_fondo.jpg",
            carpeta .. "fondo/capa_base.png",
            carpeta .. "fondo/capa_primerPlano.png",
        },
        margenCapas = 0.1,
    },
    piezas = {
        panel = {
            -- Capa «Panel» del PSD, sin emblema. Lleva un mapa del mundo arriba: mejor a su tamaño (715 x 910).
            archivo = carpeta .. "piezas/panel.png",
            ancho = 715,
            alto = 910,
            nueve = { 64, 64, 64, 64 },
            contenido = { 55, 55, 60, 60 },
        },
        panelSombra = {
            -- Sombra negra difusa detrás del panel; en el diseño, en (906, 0) al 30 % de opacidad.
            archivo = carpeta .. "piezas/panel_sombra.png",
            ancho = 1009,
            alto = 1080,
        },
        emblemaPanel = {
            -- Nuestro escudo en acero tenue; en el diseño, en (1228, 133).
            archivo = carpeta .. "piezas/emblema_panel.png",
            ancho = 208,
            alto = 204,
        },
        campo = {
            -- Campo de texto: relleno #101419 y borde gris claro al 50 %. El texto empieza en x = 81 tras el icono.
            archivo = carpeta .. "piezas/campo.png",
            ancho = 568,
            alto = 73,
            nueve = { 4, 4, 4, 4 },
            contenido = { 80, 16, 8, 8 },
        },
        botonPrincipal = {
            -- Botón dorado con su resplandor (24 px de margen alrededor del cuerpo de 614 x 99).
            archivo = carpeta .. "piezas/boton_principal.png",
            ancho = 660,
            alto = 143,
            nueve = { 40, 40, 36, 36 },
            contenido = { 36, 36, 26, 26 },
        },
        botonSecundario = {
            -- Botón oscuro (Invitado, Soporte): el mismo estilo que el campo.
            archivo = carpeta .. "piezas/boton_secundario.png",
            ancho = 283,
            alto = 73,
            nueve = { 4, 4, 4, 4 },
            contenido = { 12, 12, 8, 8 },
        },
        casilla = {
            -- Casilla sin marcar, borde naranja #ff9d00.
            archivo = carpeta .. "piezas/casilla.png",
            ancho = 25,
            alto = 25,
        },
        separador = {
            -- Raya del «O»: 1 x 5 px (2 px grises #737373), estirar a lo ancho.
            archivo = carpeta .. "piezas/separador.png",
            ancho = 1,
            alto = 5,
            nueve = { 0, 0, 0, 0 },
        },
    },
    iconos = {
        correo = { archivo = carpeta .. "piezas/icono_correo.png", ancho = 36, alto = 23 },
        candado = { archivo = carpeta .. "piezas/icono_candado.png", ancho = 24, alto = 32 },
        ojo = { archivo = carpeta .. "piezas/icono_ojo.png", ancho = 31, alto = 20 },
        invitado = { archivo = carpeta .. "piezas/icono_invitado.png", ancho = 45, alto = 31 },
        soporte = { archivo = carpeta .. "piezas/icono_soporte.png", ancho = 37, alto = 34 },
        crearCuenta = { archivo = carpeta .. "piezas/icono_crear_cuenta.png", ancho = 26, alto = 27 },
        flechaDoble = { archivo = carpeta .. "piezas/icono_flecha_doble.png", ancho = 39, alto = 27 },
        flecha = { archivo = carpeta .. "piezas/icono_flecha.png", ancho = 10, alto = 15 },
    },
    disposicion = {
        panel = { 1153, 93 },
        panelSombra = { 906, 0 },
        emblemaPanel = { 1228, 133 },
        campoUsuario = { 1222, 380 },
        campoClave = { 1222, 484 },
        casilla = { 1222, 581 },
        -- El PNG del botón lleva 23 px de resplandor: su cuerpo empieza en (1210, 655).
        botonPrincipal = { 1187, 633 },
        separadorIzquierda = { 1210, 784, 276 },
        separadorDerecha = { 1546, 784, 277 },
        botonInvitado = { 1222, 822 },
        botonSoporte = { 1522, 822 },
        iconoCorreo = { 1246, 406 },
        iconoCandado = { 1253, 505 },
        iconoOjo = { 1740, 512 },
        iconoFlechaDoble = { 1749, 691 },
        iconoInvitado = { 1268, 844 },
        iconoSoporte = { 1594, 842 },
        iconoCrearCuenta = { 1401, 930 },
        iconoFlecha = { 1603, 937 },
        -- Cajas de texto { x, y, ancho, alto } del diseño (alto = mayúsculas).
        textos = {
            titulo = { 1208, 262, 477, 29 },
            lema = { 1208, 317, 510, 14 },
            usuario = { 1303, 409, 224, 18 },
            clave = { 1303, 513, 98, 16 },
            recordar = { 1267, 584, 159, 18 },
            olvido = { 1614, 583, 176, 21 },
            entrar = { 1444, 689, 146, 30 },
            o = { 1500, 778, 31, 17 },
            invitado = { 1334, 851, 127, 23 },
            soporte = { 1648, 847, 87, 23 },
            crearCuenta = { 1440, 935, 147, 18 },
        },
        colores = {
            texto = "#eef0f2",
            marcador = "#969ca4",
            textoBoton = "#18140e",
            casilla = "#ff9d00",
            relleno = "#101419",
        },
    },
}
