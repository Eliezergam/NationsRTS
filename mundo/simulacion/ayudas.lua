--- Ayudas compartidas de la simulación: orden fijo, distancias y pequeñas piezas de grupos.
--
-- Las usan `mundo/simulacion.lua` y los módulos que se parten de ella
-- (`guardado`, `recoleccion`...). Son funciones puras sobre tablas planas, sin
-- estado propio y sin LÖVE; lo que necesita la clase lo recibe por `self`.

local Ayudas = {}

--- Claves de `t` en orden fijo: primero los números y después los textos,
-- cada grupo de menor a mayor. Se ordena cada grupo por separado con el
-- orden propio de Lua (sin función de comparación), que es mucho más rápido.
function Ayudas.ordenadas(t)
    local numeros, textos = {}, {}
    for k in pairs(t) do
        if type(k) == 'number' then
            numeros[#numeros + 1] = k
        else
            textos[#textos + 1] = k
        end
    end
    table.sort(numeros)
    table.sort(textos)
    for _, k in ipairs(textos) do
        numeros[#numeros + 1] = k
    end
    return numeros
end

local ordenadas = Ayudas.ordenadas

--- Largo de (dx, dy). Con multiplicación y no con `^ 2`: LuaJIT calcula `x ^ 2`
-- a veces como `x * x` (código compilado) y a veces con `pow` (interpretado), y
-- pueden diferir en la última cifra. `x * x` y `math.sqrt` dan el mismo
-- resultado exacto en cualquier máquina, y la simulación debe ser determinista.
function Ayudas.hipotenusa(dx, dy)
    return math.sqrt(dx * dx + dy * dy)
end

local hipotenusa = Ayudas.hipotenusa

--- Distancia entre dos cosas con `x` e `y`.
function Ayudas.distancia(a, b)
    return hipotenusa(a.x - b.x, a.y - b.y)
end

--- Valores de `tabla` en el orden de sus claves (`ordenadas`).
function Ayudas.lista(tabla)
    local out = {}
    for _, k in ipairs(ordenadas(tabla)) do
        out[#out + 1] = tabla[k]
    end
    return out
end

--- Conteo de tropas a cero: { soldados, lanzacohetes }.
function Ayudas.tropasVacias()
    return { soldados = 0, lanzacohetes = 0 }
end

--- ¿Es una ciudad? (las instalaciones tienen `tipo`).
function Ayudas.esCiudad(sitio)
    return sitio.tipo == nil
end

--- Pone al líder `l` al mando del grupo `g` en el estado `e`.
function Ayudas.ponerAlMando(e, g, l)
    g.lider = l.id
    l.estado = 'campo'
    l.ejercito = g.id
    l.desde = e.dia
end

--- Carga de un grupo (0 si no lleva): los grupos de entrega llevan su carga
-- en una tabla, los recolectores en un número.
function Ayudas.cargaDe(g)
    return type(g.carga) == 'number' and g.carga or 0
end

--- Suma una victoria o una derrota (`campo`) al líder del grupo, si lo tiene.
function Ayudas.anotar(self, g, campo)
    local l = g.lider and self.estado.lideres[g.lider]
    if l then
        l[campo] = l[campo] + 1
    end
end

-- Tipos de tropa de un grupo, en el orden en que se reparte el daño y se paga.
Ayudas.TROPAS = { 'lanzacohetes', 'soldados' }

-- Los dos bandos de una batalla.
Ayudas.LADOS = { 'atacante', 'defensor' }

Ayudas.OTRO_LADO = { atacante = 'defensor', defensor = 'atacante' }

local TROPAS = Ayudas.TROPAS

--- Naciones de un bando (las de sus grupos y la del sitio), como conjunto.
function Ayudas.nacionesBando(self, b, lado)
    local out = {}
    for _, g in ipairs(self:gruposBando(b, lado)) do
        out[g.nacion] = true
    end
    if lado == 'defensor' then
        local s = self:sitioBando(b)
        if s then
            out[s.nacion] = true
        end
    end
    return out
end

--- Sanos de un bando por tipo de tropa: { soldados, lanzacohetes }
-- de sus grupos (y del sitio, si `conSitio`).
function Ayudas.sanosBando(self, b, lado, conSitio)
    local out = Ayudas.tropasVacias()
    for _, g in ipairs(self:gruposBando(b, lado)) do
        for _, tropa in ipairs(TROPAS) do
            out[tropa] = out[tropa] + (g[tropa] or 0)
        end
    end
    local s = conSitio and lado == 'defensor' and self:sitioBando(b)
    if s then
        for _, tropa in ipairs(TROPAS) do
            out[tropa] = out[tropa] + (s[tropa] or 0)
        end
    end
    return out
end

function Ayudas.claveGuerra(a, b)
    if a < b then
        return a .. '|' .. b
    end
    return b .. '|' .. a
end

function Ayudas.cambiarRelacion(self, a, b, cuanto)
    local na, nb = self.estado.naciones[a], self.estado.naciones[b]
    if not (na and nb) then
        return
    end
    local valor = math.max(-100, math.min(100, self:relacion(a, b) + cuanto))
    na.relaciones[b], nb.relaciones[a] = valor, valor
end

--- ¿Tiene `nid` algún grupo con esa misión (y esa obra) en camino?
function Ayudas.grupoEnCamino(self, nid, mision, tipo)
    for _, g in ipairs(self:gruposDe(nid)) do
        if g.mision == mision and (not tipo or (g.construye and g.construye.tipo == tipo)) then
            return true
        end
    end
    return false
end

--- Da a `g` lo que necesita para combatir si aún no lo tiene (vida, umbral de retirada, heridos).
-- `self` es la simulación.
function Ayudas.prepararCombate(self, g)
    g.lanzacohetes = g.lanzacohetes or 0
    g.vidaMax = g.vidaMax or self.vidaGrupo(g)
    g.umbral = g.umbral or self:umbralRetirada(g.nacion)
    g.heridos = g.heridos or Ayudas.tropasVacias()
    g.resto = g.resto or Ayudas.tropasVacias()
end

--- Reparte el entero `total` en proporción a `pesos` (lista de números ≥ 0)
-- por restos mayores: cada uno recibe la parte entera de su proporción y lo
-- que sobra va, de uno en uno, a los de mayor fracción (a igual fracción, al
-- de menor índice). Con `topes` (lista), nadie pasa del suyo. Devuelve la
-- lista de enteros, que suma min(total, Σ topes) (0 si los pesos suman 0).
function Ayudas.repartirRestos(pesos, total, topes)
    local n = #pesos
    local suma = 0
    for i = 1, n do
        suma = suma + pesos[i]
    end
    local out = {}
    for i = 1, n do
        out[i] = 0
    end
    if suma <= 0 or total <= 0 then
        return out
    end
    if topes then
        local maximo = 0
        for i = 1, n do
            maximo = maximo + topes[i]
        end
        total = math.min(total, maximo)
    end
    local puesto = 0
    local restos = {}
    for i = 1, n do
        local x = pesos[i] * total / suma
        local b = math.floor(x)
        if topes then
            b = math.min(b, topes[i])
        end
        out[i] = b
        puesto = puesto + b
        restos[#restos + 1] = { i = i, r = x - b }
    end
    table.sort(restos, function(a, b)
        if a.r ~= b.r then
            return a.r > b.r
        end
        return a.i < b.i
    end)
    -- Dos vueltas bastan: en la primera cada uno recibe como mucho uno, y lo
    -- que quede (por los topes) lo toman en la segunda los que aún caben.
    local k = 1
    while puesto < total and k <= #restos * 2 do
        local i = restos[(k - 1) % #restos + 1].i
        if not topes or out[i] < topes[i] then
            out[i] = out[i] + 1
            puesto = puesto + 1
        end
        k = k + 1
    end
    return out
end

-- Las celdas negativas también dan una clave positiva.
local DESPLAZA = 1048576 -- 2^20

--- Clave numérica única de la celda (cx, cy), para mapas celda -> dato.
function Ayudas.claveCelda(cx, cy)
    return (cx + DESPLAZA) * 2097152 + cy + DESPLAZA
end

--- Los cuatro vecinos de una celda (los que comparten un lado).
Ayudas.VECINOS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

return Ayudas
