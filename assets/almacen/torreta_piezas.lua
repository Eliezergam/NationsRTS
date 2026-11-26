-- Piezas de la torreta (tools/blender/torreta.py): cada una con su pivote en
-- el origen de su malla; la matriz es su sitio respecto a la madre.
return {
    { nombre = 'base', padre = nil, malla = true, matriz = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } },
    { nombre = 'cabezal', padre = 'base', malla = true, matriz = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0.72, 0, 0, 0, 1 } },
    { nombre = 'canon', padre = 'cabezal', malla = true, matriz = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0.28, 0, 0, 0, 1 } },
}
