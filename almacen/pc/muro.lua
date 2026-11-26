-- El muro de pantallas de la sala de control (el dueño, 26-nov: «que desde
-- las PC se pueda elegir qué mostrar en la pantalla grande del frente»).
-- El muro son 6 pantallas en 3 x 2, en tres partes:
--
--   grande   las 4 de la izquierda (una sola imagen)
--   arriba   la de arriba a la derecha
--   abajo    la de abajo a la derecha
--
-- Cada parte enseña una fuente (el mapa, la nación, los misiles, los robots,
-- la depuración o la pantalla de un puesto) o el muro entero enseña una sola
-- fuente repartida por las 6 pantallas. Lo pinta almacen/sala.lua; lo cambian
-- el programa «Muro» de los ordenadores y los programas de Lua con la API
-- `muro`. Se guarda con los ordenadores.

local Muro = {}

Muro.zonas = {
    { clave = 'grande', titulo = 'Las 4 de la izquierda' },
    { clave = 'arriba', titulo = 'Arriba a la derecha' },
    { clave = 'abajo', titulo = 'Abajo a la derecha' },
}

Muro.fuentes = {
    { clave = 'mapa', titulo = 'Mapa de la capital' },
    { clave = 'nacion', titulo = 'Nación y recursos' },
    { clave = 'arsenal', titulo = 'Misiles del polvorín' },
    { clave = 'robots', titulo = 'Robots del almacén' },
    { clave = 'depuracion', titulo = 'Depuración (print de los robots)' },
}
for k = 1, 6 do
    Muro.fuentes[#Muro.fuentes + 1] = { clave = 'pc' .. k, titulo = 'Pantalla del puesto ' .. k }
end

-- Lo de cada parte en el muro entero (2304 x 872 px): x, y, ancho, alto.
Muro.ancho, Muro.alto = 2304, 872
Muro.partes = {
    grande = { 0, 0, 1536, 872 },
    arriba = { 1536, 0, 768, 436 },
    abajo = { 1536, 436, 768, 436 },
}

-- El estado (el de la partida: almacen.muro) lo pone la sala al cargarse.
Muro.estado = nil

function Muro.porDefecto()
    return { entero = false, grande = 'mapa', arriba = 'nacion', abajo = 'arsenal', todo = 'mapa' }
end

function Muro.esFuente(clave)
    for _, f in ipairs(Muro.fuentes) do
        if f.clave == clave then
            return true
        end
    end
    return false
end

function Muro.tituloDe(clave)
    for _, f in ipairs(Muro.fuentes) do
        if f.clave == clave then
            return f.titulo
        end
    end
    return tostring(clave)
end

--- Pone `fuente` en `zona` ('grande', 'arriba', 'abajo' o 'todo', el muro
-- entero). Devuelve true, o false y por qué no.
function Muro.poner(zona, fuente)
    local e = Muro.estado
    if not e then
        return false, 'el muro no está encendido'
    end
    if not Muro.esFuente(fuente) then
        return false, 'no hay ninguna fuente «' .. tostring(fuente) .. '»'
    end
    if zona == 'todo' then
        e.entero = true
        e.todo = fuente
    elseif Muro.partes[zona] then
        e.entero = false
        e[zona] = fuente
    else
        return false, 'no hay ninguna parte «' .. tostring(zona) .. '» (grande, arriba, abajo o todo)'
    end
    Muro.cambiado = true
    return true
end

--- Vuelve a enseñar cada parte por separado (con lo que tenía cada una).
function Muro.porPartes()
    if Muro.estado then
        Muro.estado.entero = false
        Muro.cambiado = true
    end
end

--- Lo que enseña `zona` ahora ('todo' si el muro entero enseña una sola).
function Muro.que(zona)
    local e = Muro.estado or Muro.porDefecto()
    if e.entero then
        return e.todo
    end
    return e[zona]
end

--- Si alguna parte enseña algo que cambia a cada momento (la pantalla de un
-- puesto o la depuración): la sala la pinta más a menudo.
function Muro.esVivo()
    local e = Muro.estado or Muro.porDefecto()
    local lista = e.entero and { e.todo } or { e.grande, e.arriba, e.abajo }
    for _, f in ipairs(lista) do
        if f == 'depuracion' or f == 'robots' or (f and f:match('^pc%d$')) then
            return true
        end
    end
    return false
end

--- La tabla `muro` para los programas de Lua de los ordenadores:
--   muro.fuentes()               { 'mapa', 'nacion', ... }
--   muro.mostrar(parte, fuente)  parte: 'grande', 'arriba', 'abajo' o 'todo'
--   muro.porPartes()             cada parte con lo suyo otra vez
--   muro.que(parte)              lo que enseña esa parte
function Muro.para()
    local api = {}
    function api.fuentes()
        local t = {}
        for k, f in ipairs(Muro.fuentes) do
            t[k] = f.clave
        end
        return t
    end
    function api.mostrar(zona, fuente)
        local bien, motivo = Muro.poner(zona, fuente)
        if not bien then
            error(motivo, 2)
        end
        return true
    end
    function api.porPartes()
        Muro.porPartes()
    end
    function api.que(zona)
        return Muro.que(zona)
    end
    return api
end

return Muro
