-- Hilo obrero: genera comarcas del mundo físico (`mundo/generador.lua`) en
-- segundo plano. Hay uno por núcleo menos el principal (`mundo/comarcas.lua`).
--
-- Lee pedidos del canal `mundo.pedidos` y deja cada comarca en
-- `mundo.hechos`. Un pedido es { mundo, semilla, cx, cy, obras } (o, con
-- `zona`, los datos de la nación { zx, zy } para la simulación). Con
-- `archivo`, la comarca se lee de la caché en disco si está y si no se guarda
-- ahí al generarla si `guardar` (`firma`: las obras con que se hizo). Con
-- `asegurar` (precarga), solo se comprueba que esté en el disco y, si no, se
-- genera y se guarda; la respuesta no lleva los datos. La
-- respuesta lleva el mismo `mundo` para que el mundo que la pidió la
-- reconozca (si entretanto se empezó otro, se tira). `{ salir = true }`
-- termina el hilo.

require('love.filesystem')
require('love.data')
require('love.timer')

local Generador = require('mundo.generador')

local pedidos = love.thread.getChannel('mundo.pedidos')
local hechos = love.thread.getChannel('mundo.hechos')

local contexto

--- La comarca del pedido: del disco si está (`archivo`, con la misma firma de
-- obras) y si no, generada y guardada para la próxima vez.
local function comarca(p)
    if p.archivo then
        local datos = love.filesystem.read('data', p.archivo)
        local r = datos and Generador.desempaquetar(datos, p.firma, p.semilla)
        if r then
            return r
        end
    end
    local r = Generador.comarca(contexto, p.cx, p.cy, p.obras)
    if p.archivo and p.guardar then
        local datos = Generador.empaquetar(r, p.firma)
        if pcall(love.filesystem.write, p.archivo, datos) then
            r.guardado = datos:getSize()
        end
        datos:release()
    end
    return r
end

while true do
    local p = pedidos:demand()
    if p.salir then
        break
    end
    if not contexto or contexto.semilla ~= p.semilla then
        contexto = Generador.contexto(p.semilla)
    end
    local inicio = love.timer.getTime()
    local ok, r
    if p.asegurar then
        -- Precarga: que la comarca quede en el disco (sin mandar sus datos).
        ok, r = pcall(function()
            local hecho = { asegurada = true, cx = p.cx, cy = p.cy }
            if love.filesystem.getInfo(p.archivo) then
                return hecho
            end
            local c = Generador.comarca(contexto, p.cx, p.cy, p.obras)
            if p.guardar then
                local datos = Generador.empaquetar(c, p.firma)
                if pcall(love.filesystem.write, p.archivo, datos) then
                    hecho.guardado = datos:getSize()
                end
                datos:release()
            end
            for _, campo in ipairs({ 'suelo', 'sueloLejos', 'plantas', 'plantasLejos' }) do
                if c[campo] then
                    c[campo]:release()
                end
            end
            hecho.generada = true
            return hecho
        end)
    elseif p.zona then
        ok, r = pcall(Generador.datosZona, contexto, p.zx, p.zy)
        r = ok and { mundo = p.mundo, zona = true, zx = p.zx, zy = p.zy, datos = r } or r
    else
        ok, r = pcall(comarca, p)
    end
    if ok then
        r.mundo = p.mundo
        r.firma = p.firma
        r.ms = (love.timer.getTime() - inicio) * 1000
        hechos:push(r)
    else
        hechos:push({ mundo = p.mundo, cx = p.cx, cy = p.cy, zona = p.zona, asegurada = p.asegurar, error = tostring(r) })
    end
end
