-- Sitios llanos para ciudades y minas (el dueño, 20-nov: «la generación de
-- minas tiene que ser en lugares parejos, que quepa todo con naturalidad; si
-- hay montañas no se genera, se genera en lugares buenos; en el 2D y el 3D
-- lo mismo; lo mismo con las ciudades»).
--
-- Como los generadores de mundos con asentamientos (las aldeas y estructuras
-- de Minecraft miran la altura de la huella entera antes de colocarse; el PCG
-- de Unreal filtra los puntos por pendiente): no basta con que el centro sea
-- llano, se mide toda la huella del sitio (recinto y aeródromo) y, si cerca
-- no hay ninguna huella llana, el sitio no se genera.
--
-- La batalla 3D lee este mismo mapa ampliado 10 veces en horizontal y en
-- vertical (batalla/terreno_escalado.lua): 1 px del mapa = 1 m de la
-- batalla, también en altura, y las pendientes no cambian. Por eso lo que
-- aquí sale llano en el mapa 2D es igual de llano en la batalla, en el
-- mismo sitio.

local Llano = {}

-- Huellas (medio largo este-oeste, medio ancho norte-sur, en m = px del
-- mapa): el recinto con su aeródromo (batalla/sitios/plano.lua) y 60 m de
-- margen para los taludes.
Llano.huellaMina = { 460, 240 }
Llano.huellaCiudad = { 520, 560 }
-- Lo que se acepta: la pista se explana con pendiente de hasta el 1,5 %, y
-- lo que quede, en desmontes de pocos metros con su talud.
Llano.pendienteMaxima = 0.035 -- del plano que mejor se ajusta a la huella
Llano.residuoMaximo = 12 -- m: lo más que se sale el terreno de ese plano
Llano.alturaMinima = 6 -- m sobre el mar en toda la huella (ni playa ni agua)
Llano.alturaMaxima = 250 -- m: fuera de las mesetas de los macizos

--- Pendiente del plano que mejor se ajusta a la huella (hx, hy) alrededor
-- de (x, y), lo más que se aparta el terreno de él (m) y la altura mínima.
-- `n` muestras por eje (5 por defecto).
function Llano.medir(terreno, x, y, hx, hy, n)
    n = n or 5
    local sxx, syy, sxz, syz, sz, cuenta = 0, 0, 0, 0, 0, 0
    local muestras = {}
    local minimo, maximo = math.huge, -math.huge
    for j = -n, n do
        for i = -n, n do
            local u, v = i / n * hx, j / n * hy
            local z = terreno:base(x + u, y + v)
            muestras[#muestras + 1] = u
            muestras[#muestras + 1] = v
            muestras[#muestras + 1] = z
            sxx, syy = sxx + u * u, syy + v * v
            sxz, syz, sz = sxz + u * z, syz + v * z, sz + z
            cuenta = cuenta + 1
            minimo, maximo = math.min(minimo, z), math.max(maximo, z)
        end
    end
    local a, b, c = sxz / sxx, syz / syy, sz / cuenta
    local residuo = 0
    for k = 1, #muestras, 3 do
        local u, v, z = muestras[k], muestras[k + 1], muestras[k + 2]
        residuo = math.max(residuo, math.abs(z - (a * u + b * v + c)))
    end
    return math.sqrt(a * a + b * b), residuo, minimo, maximo
end

--- ¿Cabe el sitio con naturalidad en (x, y)? Y su nota (menos, mejor).
function Llano.apto(terreno, x, y, huella)
    local pendiente, residuo, minimo, maximo = Llano.medir(terreno, x, y, huella[1], huella[2])
    local bueno = pendiente <= Llano.pendienteMaxima
        and residuo <= Llano.residuoMaximo
        and minimo >= Llano.alturaMinima
        and maximo <= Llano.alturaMaxima
    return bueno, residuo + pendiente * 300
end

--- El sitio llano más cercano a (x, y) a menos de `alcance` m, en anillos
-- cada `paso` m (lo primero, lo más cercano: con varios aptos en el mismo
-- anillo, el de mejor nota). Nil si no hay ninguno: el sitio no se genera.
-- `valido(x, y)` opcional: descarta puntos (dentro de una ciudad...).
function Llano.buscar(terreno, x, y, huella, alcance, paso, valido)
    paso = paso or 300
    for r = 0, alcance, paso do
        local n = r == 0 and 1 or math.max(6, math.floor(2 * math.pi * r / paso))
        local mejor, bx, by = math.huge, nil, nil
        for k = 0, n - 1 do
            local a = k / n * 2 * math.pi
            local cx, cy = x + math.cos(a) * r, y + math.sin(a) * r
            if not valido or valido(cx, cy) then
                local bueno, nota = Llano.apto(terreno, cx, cy, huella)
                if bueno and nota < mejor then
                    mejor, bx, by = nota, cx, cy
                end
            end
        end
        if bx then
            return bx, by
        end
    end
    return nil
end

return Llano
