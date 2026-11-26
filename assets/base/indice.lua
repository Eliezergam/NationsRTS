-- Generado por tools/blender/kit_base.py: no editar a mano.
-- Kit del modo Base (diseno/modo-base.md). Unidades en px del juego
-- (1 m = 10 px), z arriba, y hacia el sur del mapa. Cada pieza es un
-- objeto de `archivo` con su pivote en el origen: z = 0 es el suelo del
-- recinto y x, y = 0 la esquina de menor i, j de su celda (o el nodo).
-- Paredes y portón corren a lo largo de +x con la cara exterior a -y;
-- en la arista `o` se giran para que +x apunte a +y.
-- ranura: suelo, arista, techo, nodo (pilar), estacion, fijo o accesorio.
-- celdas: { ancho, fondo } (una arista mide { 1, 0 } y el portón { 2, 0 }).
return {
    archivo = 'assets/base/kit_base.glb',
    -- Cargar antes: dream:loadMaterialLibrary(materiales).
    materiales = 'assets/base/materiales',
    celda = 40,
    alturaSuelo = 3,
    altoPiso = 45,
    libreInterior = 43.6,
    piezas = {
        cimiento = {
            objeto = 'cimiento',
            ranura = 'suelo',
            celdas = { 1, 1 },
            caja = { { 0, 0, 0 }, { 40, 40, 3 } },
            triangulos = 10,
            materiales = { 'baseHormigon' },
            descripcion = 'Losa de 4 x 4 m, 0,3 m',
            anclas = {
                esquinas = {
                    { 0, 0, 3 },
                    { 40, 0, 3 },
                    { 40, 40, 3 },
                    { 0, 40, 3 },
                },
                centro = {
                    { 20, 20, 3 },
                },
            },
        },
        pared = {
            objeto = 'pared',
            ranura = 'arista',
            celdas = { 1, 0 },
            caja = { { 0, -1, 3 }, { 40, 1, 48 } },
            triangulos = 14,
            materiales = { 'baseHormigon', 'baseChapa', 'baseAcero' },
            descripcion = 'Pared de 4 x 4,5 m',
            anclas = {
                extremos = {
                    { 0, 0, 3 },
                    { 40, 0, 3 },
                },
                cima = {
                    { 0, 0, 48 },
                    { 40, 0, 48 },
                },
                fuera = { 0, -1, 0 },
            },
        },
        pared_ventana = {
            objeto = 'pared_ventana',
            ranura = 'arista',
            celdas = { 1, 0 },
            caja = { { 0, -2.4, 3 }, { 40, 1, 48 } },
            triangulos = 72,
            materiales = { 'baseHormigon', 'baseChapa', 'baseAcero', 'baseVidrio' },
            descripcion = 'Pared con ventana de 1,6 x 1,2 m',
            anclas = {
                extremos = {
                    { 0, 0, 3 },
                    { 40, 0, 3 },
                },
                cima = {
                    { 0, 0, 48 },
                    { 40, 0, 48 },
                },
                fuera = { 0, -1, 0 },
            },
        },
        pared_puerta = {
            objeto = 'pared_puerta',
            ranura = 'arista',
            celdas = { 1, 0 },
            caja = { { 0, -6, 3 }, { 40, 1, 48 } },
            triangulos = 54,
            materiales = { 'baseHormigon', 'baseChapa', 'baseAcero', 'baseMadera' },
            descripcion = 'Pared con puerta de 1,2 x 2,4 m',
            anclas = {
                extremos = {
                    { 0, 0, 3 },
                    { 40, 0, 3 },
                },
                cima = {
                    { 0, 0, 48 },
                    { 40, 0, 48 },
                },
                fuera = { 0, -1, 0 },
            },
        },
        porton = {
            objeto = 'porton',
            ranura = 'arista',
            celdas = { 2, 0 },
            caja = { { 0, -2.2, 3 }, { 80, 2, 48 } },
            triangulos = 74,
            materiales = { 'baseHormigon', 'baseChapa', 'baseAcero', 'basePeligro' },
            descripcion = 'Portón de 8 m, hueco de 7 x 4,2 m',
            anclas = {
                extremos = {
                    { 0, 0, 3 },
                    { 80, 0, 3 },
                },
                cima = {
                    { 0, 0, 48 },
                    { 80, 0, 48 },
                },
                nodoSinPilar = {
                    { 40, 0, 0 },
                },
                hueco = {
                    { 5, 0, 3 },
                    { 75, 0, 45 },
                },
                fuera = { 0, -1, 0 },
            },
        },
        techo = {
            objeto = 'techo',
            ranura = 'techo',
            celdas = { 1, 1 },
            caja = { { 0, 0, 46.6 }, { 40, 40, 47.8 } },
            triangulos = 12,
            materiales = { 'baseHormigon' },
            descripcion = 'Techo plano de 4 x 4 m',
            anclas = {
                esquinas = {
                    { 0, 0, 47.8 },
                    { 40, 0, 47.8 },
                    { 40, 40, 47.8 },
                    { 0, 40, 47.8 },
                },
            },
        },
        pilar = {
            objeto = 'pilar',
            ranura = 'nodo',
            celdas = { 0, 0 },
            caja = { { -1.5, -1.5, 0 }, { 1.5, 1.5, 49 } },
            triangulos = 10,
            materiales = { 'baseAcero' },
            descripcion = 'Pilar de esquina (lo pone la vista)',
            anclas = {
                base = {
                    { 0, 0, 0 },
                },
                cima = {
                    { 0, 0, 49 },
                },
            },
        },
        foso = {
            objeto = 'foso',
            ranura = 'estacion',
            celdas = { 3, 2 },
            caja = { { 3, 3.5, 3 }, { 119, 76.5, 24.19 } },
            triangulos = 810,
            materiales = { 'AtlasSyntyBase' },
            descripcion = 'Foso de reparación',
            anclas = {
                esquinas = {
                    { 0, 0, 3 },
                    { 120, 0, 3 },
                    { 120, 80, 3 },
                    { 0, 80, 3 },
                },
                vehiculo = {
                    { 60, 40, 3 },
                },
            },
        },
        linea_montaje = {
            objeto = 'linea_montaje',
            ranura = 'estacion',
            celdas = { 4, 2 },
            caja = { { 2, 1.96, 3 }, { 158, 77.05, 39 } },
            triangulos = 1284,
            materiales = { 'AtlasSyntyBase' },
            descripcion = 'Línea de montaje',
            anclas = {
                esquinas = {
                    { 0, 0, 3 },
                    { 160, 0, 3 },
                    { 160, 80, 3 },
                    { 0, 80, 3 },
                },
                vehiculo = {
                    { 80, 40, 6.5 },
                },
                operario = {
                    { 12, 65, 3 },
                },
            },
        },
        mesa_reclutamiento = {
            objeto = 'mesa_reclutamiento',
            ranura = 'estacion',
            celdas = { 1, 1 },
            caja = { { 1.42, 2.84, 2.96 }, { 38.5, 35.5, 29 } },
            triangulos = 422,
            materiales = { 'AtlasSyntyBase' },
            descripcion = 'Mesa de reclutamiento',
            anclas = {
                esquinas = {
                    { 0, 0, 3 },
                    { 40, 0, 3 },
                    { 40, 40, 3 },
                    { 0, 40, 3 },
                },
                reclutador = {
                    { 20, 8, 3 },
                },
                recluta = {
                    { 20, 26, 3 },
                },
            },
        },
        enfermeria = {
            objeto = 'enfermeria',
            ranura = 'estacion',
            celdas = { 2, 1 },
            caja = { { 7.5, 2.5, 3 }, { 78, 37, 22.6 } },
            triangulos = 370,
            materiales = { 'AtlasSyntyBase' },
            descripcion = 'Enfermería',
            anclas = {
                esquinas = {
                    { 0, 0, 3 },
                    { 80, 0, 3 },
                    { 80, 40, 3 },
                    { 0, 40, 3 },
                },
                camas = {
                    { 12, 13.5, 9.2 },
                    { 36, 13.5, 9.2 },
                },
                sanitario = {
                    { 24, 29, 3 },
                },
            },
        },
        banco_municion = {
            objeto = 'banco_municion',
            ranura = 'estacion',
            celdas = { 2, 1 },
            caja = { { 5, 3.5, 3 }, { 77.76, 36.76, 24.15 } },
            triangulos = 1606,
            materiales = { 'AtlasSyntyBase' },
            descripcion = 'Banco de munición',
            anclas = {
                esquinas = {
                    { 0, 0, 3 },
                    { 80, 0, 3 },
                    { 80, 40, 3 },
                    { 0, 40, 3 },
                },
                operario = {
                    { 29, 18, 3 },
                },
            },
        },
        estanteria = {
            objeto = 'estanteria',
            ranura = 'estacion',
            celdas = { 1, 1 },
            caja = { { 1.5, 2.5, 3 }, { 38.5, 14.5, 33 } },
            triangulos = 236,
            materiales = { 'AtlasSyntyBase' },
            descripcion = 'Estantería de almacén',
            anclas = {
                esquinas = {
                    { 0, 0, 3 },
                    { 40, 0, 3 },
                    { 40, 40, 3 },
                    { 0, 40, 3 },
                },
                huecos = {
                    { 8, 8.5, 4.2 },
                    { 20, 8.5, 4.2 },
                    { 32, 8.5, 4.2 },
                    { 8, 8.5, 14 },
                    { 20, 8.5, 14 },
                    { 32, 8.5, 14 },
                    { 8, 8.5, 23.8 },
                    { 20, 8.5, 23.8 },
                    { 32, 8.5, 23.8 },
                },
            },
        },
        caja_fuerte = {
            objeto = 'caja_fuerte',
            ranura = 'estacion',
            celdas = { 1, 1 },
            caja = { { 3, 3, 3 }, { 38.94, 17.8, 24.5 } },
            triangulos = 380,
            materiales = { 'AtlasSyntyBase' },
            descripcion = 'Caja fuerte',
            anclas = {
                esquinas = {
                    { 0, 0, 3 },
                    { 40, 0, 3 },
                    { 40, 40, 3 },
                    { 0, 40, 3 },
                },
                frente = {
                    { 20, 22, 3 },
                },
            },
        },
        carga_caja = {
            objeto = 'carga_caja',
            ranura = 'accesorio',
            celdas = { 0, 0 },
            caja = { { -4.34, -4.34, 0 }, { 4.34, 4.34, 8.68 } },
            triangulos = 144,
            materiales = { 'AtlasSyntyBase' },
            descripcion = 'Caja para la estantería',
            anclas = {
                esquinas = {
                    { 0, 0, 3 },
                    { 0, 0, 3 },
                    { 0, 0, 3 },
                    { 0, 0, 3 },
                },
            },
        },
        carga_bidon = {
            objeto = 'carga_bidon',
            ranura = 'accesorio',
            celdas = { 0, 0 },
            caja = { { -5.61, -3.11, 0 }, { 6.6, 4, 8.82 } },
            triangulos = 64,
            materiales = { 'AtlasSyntyBase' },
            descripcion = 'Dos bidones para la estantería',
            anclas = {
                esquinas = {
                    { 0, 0, 3 },
                    { 0, 0, 3 },
                    { 0, 0, 3 },
                    { 0, 0, 3 },
                },
            },
        },
        centroMando = {
            objeto = 'centroMando',
            ranura = 'fijo',
            celdas = { 3, 3 },
            caja = { { -1.5, -1.5, 0 }, { 121.5, 154.62, 174.3 } },
            triangulos = 2042,
            materiales = { 'baseHormigon', 'baseChapa', 'baseAcero', 'baseVidrio', 'baseMadera', 'AtlasSyntyBase' },
            descripcion = 'Centro de mando: nave de 3 x 3 celdas, antena y mástil',
            anclas = {
                esquinas = {
                    { 0, 0, 3 },
                    { 120, 0, 3 },
                    { 120, 120, 3 },
                    { 0, 120, 3 },
                },
                puerta = {
                    { 60, 126, 0 },
                },
                mastil = {
                    { 12, 150, 90 },
                },
                antena = {
                    { 100, 20, 174.3 },
                },
            },
        },
        centroMandoBandera = {
            objeto = 'centroMandoBandera',
            ranura = 'accesorio',
            celdas = { 0, 0 },
            caja = { { 12.7, 149.9, 74 }, { 36.7, 150.1, 89 } },
            triangulos = 4,
            materiales = { 'AtlasSyntyBase' },
            descripcion = 'Tela de la bandera (material de la nación)',
            anclas = {
                mastil = {
                    { 12, 150, 90 },
                },
            },
        },
    },
}
