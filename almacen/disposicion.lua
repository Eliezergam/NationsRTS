-- Dónde quedó cada caja del almacén (el dueño, 26-nov: «cuando entro al
-- almacén todo se reinicia»). El almacén es un reflejo vivo de lo que tiene
-- la nación: la simulación manda (cuánto metal, dinero... hay) y aquí solo se
-- guarda dónde está cada caja que lo representa, para que al volver esté
-- todo como se dejó.
--
-- Al salir (EscenaAlmacen:cerrar) se apuntan las cajas que están en un
-- rack o en una mesa del patio: tipo, cantidad y hueco. Las que van en las
-- manos de un robot o en el depósito del misil no se apuntan: al volver
-- llegan otra vez al patio (lo que hay se cuenta igual).
--
-- Al entrar (EscenaAlmacen:llenarDescarga) se vuelven a poner y solo llega
-- al patio la diferencia con lo que la nación tiene ahora. Si ahora tiene
-- menos (lo gastó mientras tanto), se quitan cajas de los racks hasta que
-- cuadre (más adelante: los robots las sacarán al muelle).
--
-- Se guarda en la memoria de la partida (el objeto Almacen de la nación) y
-- en `almacen_disposicion.lua` de la carpeta del juego, con la semilla y la
-- nación: al cargar la misma partida sigue igual. No es parte de la
-- simulación (no cambia nada del juego en línea).

local Disposicion = {}

Disposicion.archivo = 'almacen_disposicion.lua'

local function serializar(v, sangria)
    sangria = sangria or ''
    if type(v) == 'table' then
        local partes = { '{\n' }
        local otra = sangria .. '    '
        for k, x in pairs(v) do
            local clave = type(k) == 'number' and ('[' .. k .. ']') or ('[' .. string.format('%q', k) .. ']')
            partes[#partes + 1] = otra .. clave .. ' = ' .. serializar(x, otra) .. ',\n'
        end
        partes[#partes + 1] = sangria .. '}'
        return table.concat(partes)
    elseif type(v) == 'string' then
        return string.format('%q', v)
    else
        return tostring(v)
    end
end

--- Dónde está el mueble `mueble` en la escena: { 'rack', fila, indice } o
-- { 'mesa', indice }, o nil si no es un rack ni una mesa del patio.
local function lugarDe(escena, mueble)
    for nombre, fila in pairs(escena.filas) do
        for k, rack in ipairs(fila) do
            if rack == mueble then
                return { 'rack', nombre, k }
            end
        end
    end
    for k, mesa in ipairs(escena.mesasDescarga) do
        if mesa == mueble then
            return { 'mesa', k }
        end
    end
    return nil
end

local function muebleDe(escena, lugar)
    if lugar[1] == 'rack' then
        local fila = escena.filas[lugar[2]]
        return fila and fila[lugar[3]]
    elseif lugar[1] == 'mesa' then
        return escena.mesasDescarga[lugar[2]]
    end
end

--- Foto de las cajas de suministros de la escena que están en un hueco.
function Disposicion.tomar(escena, objetos, tipos)
    local esSuministro = {}
    for _, t in ipairs(tipos) do
        esSuministro[t] = true
    end
    local cajas = {}
    for _, o in ipairs(objetos) do
        local tipo = o:getTipo()
        local mueble, numero = o:getApoyadoEn()
        if esSuministro[tipo] and mueble and not o:getLlevadoPor() then
            local lugar = lugarDe(escena, mueble)
            if lugar then
                lugar[#lugar + 1] = numero
                cajas[#cajas + 1] = { tipo = tipo, cantidad = o.cantidad or 0, lugar = lugar }
            end
        end
    end
    -- En orden fijo (la lista de objetos puede cambiar de orden).
    table.sort(cajas, function(a, b)
        local la, lb = table.concat(a.lugar, '/'), table.concat(b.lugar, '/')
        return la < lb
    end)
    return cajas
end

--- Guarda la foto `cajas` para la partida y nación de `almacen`.
function Disposicion.guardar(almacen, semilla, cajas)
    almacen.disposicion = cajas
    local datos = { semilla = semilla, nacion = almacen:getNacion(), cajas = cajas }
    love.filesystem.write(Disposicion.archivo, 'return ' .. serializar(datos) .. '\n')
end

--- La última foto de `almacen` (la de la memoria; si no hay, la del
-- archivo si es de la misma partida y nación), o una lista vacía.
function Disposicion.leer(almacen, semilla)
    if almacen.disposicion then
        return almacen.disposicion
    end
    if not love.filesystem.getInfo(Disposicion.archivo) then
        return {}
    end
    local bien, datos = pcall(function()
        return love.filesystem.load(Disposicion.archivo)()
    end)
    if bien and type(datos) == 'table' and datos.semilla == semilla and datos.nacion == almacen:getNacion() then
        return datos.cajas or {}
    end
    return {}
end

--- Pone en su hueco las cajas de la foto. `crear(tipo, hueco)` crea el
-- objeto. Devuelve los objetos puestos (los huecos ya ocupados o que ya no
-- existen se saltan).
function Disposicion.poner(escena, cajas, crear)
    local puestos = {}
    for _, c in ipairs(cajas) do
        local mueble = muebleDe(escena, c.lugar)
        local numero = c.lugar[#c.lugar]
        local hueco = mueble and mueble:getHueco(numero)
        if hueco and not hueco.ocupado then
            local o = crear(c.tipo, hueco)
            o:setApoyar(mueble, numero)
            o.cantidad = c.cantidad
            puestos[#puestos + 1] = o
        end
    end
    return puestos
end

return Disposicion
