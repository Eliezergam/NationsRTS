-- Visor del mapa de campaña en 3D (campana/mapa3d.lua).
--
-- Se abre con campana/visor/abrir.py, que monta el juego con este main.lua.
-- Sin argumentos: ventana con WASD o flechas para moverse, Q y E para girar,
-- la rueda para acercar y el botón central para girar e inclinar.
-- Con `--captura <archivo> <x,z,distancia,rumbo[,inclinación]> ...` guarda
-- una imagen por vista (rumbo y ajuste de la inclinación en grados; varias
-- vistas se numeran) y se cierra. `--tam 1920x1080` fija el tamaño y
-- `--medir 300` mide los FPS de cada vista.

local dream = require('lib.3DreamEngine')
local Mapa3D = require('campana.mapa3d')
local Camara = require('campana.camara')
local LuzCampana = require('campana.luz_campana')
local Visibilidad = require('batalla.dream.visibilidad')
local Escalado = require('batalla.dream.escalado')

local estado = {}

local function configurarMotor()
    -- La luz de la batalla 3D a la escala del mapa (campana/luz_campana.lua).
    LuzCampana.configurarMotor()
    dream:init()
    dream.camera:setFov(40)
    -- El recorte de la batalla (planos normalizados): el de 3Dream quitaba
    -- trozos del relieve que aún se veían (huecos con el cielo de debajo).
    Visibilidad.instalar(dream.camera)
    estado.luz = LuzCampana.nueva()
end

local function dibujarEscena()
    -- Los lienzos a la escala del escalado (los sube LuzCampana:presentar).
    Escalado.ajustar(dream, Escalado.escala(LuzCampana.calidad))
    estado.camara:aplicar(dream)
    estado.mapa:actualizar(estado.camara, estado.vistas ~= nil)
    estado.luz:actualizar(estado.camara)
    dream:prepare()
    estado.luz:anadirLuces()
    estado.mapa:dibujar()
    estado.luz:presentar()
end

local function leerVista(texto)
    local valores = {}
    for numero in texto:gmatch('[^,]+') do
        table.insert(valores, tonumber(numero))
    end
    return valores
end

--- `--tam 1920x1080`: tamaño de la ventana (o de la imagen sin pantalla).
local function leerOpciones(argumentos)
    for indice, valor in ipairs(argumentos) do
        if valor == '--captura' then
            estado.archivo = argumentos[indice + 1]
            estado.vistas = {}
            for k = indice + 2, #argumentos do
                if argumentos[k]:sub(1, 2) == '--' then
                    break
                end
                table.insert(estado.vistas, leerVista(argumentos[k]))
            end
        elseif valor == '--tam' then
            local ancho, alto = argumentos[indice + 1]:match('(%d+)x(%d+)')
            estado.tam = { tonumber(ancho), tonumber(alto) }
        elseif valor == '--medir' then
            estado.medir = tonumber(argumentos[indice + 1])
        end
    end
end

function love.load(argumentos)
    leerOpciones(argumentos)
    if estado.tam then
        love.window.setMode(estado.tam[1], estado.tam[2], { msaa = 4, depth = 24, vsync = 0, resizable = true })
    end
    configurarMotor()
    local inicio = love.timer.getTime()
    estado.mapa = Mapa3D.nuevo(dream)
    print(string.format('MAPA cargado en %.2f s', love.timer.getTime() - inicio))
    estado.camara = Camara.nueva(estado.mapa, 0, 0, 450, 0)
end

function love.update(dt)
    if not estado.vistas then
        estado.camara:actualizar(dt)
    end
    dream:update()
end

local function guardar(archivo)
    love.graphics.captureScreenshot(function(imagen)
        local salida = assert(io.open(archivo, 'wb'))
        salida:write(imagen:encode('png'):getString())
        salida:close()
        print('CAPTURA', archivo)
    end)
end

--- FPS medios y del 1 % peor de los tiempos de cuadro medidos en una vista.
local function informarMedida(numero, tiempos)
    table.sort(tiempos)
    local suma = 0
    for _, tiempo in ipairs(tiempos) do
        suma = suma + tiempo
    end
    local peores = math.max(1, math.floor(#tiempos * 0.01))
    local sumaPeores = 0
    for indice = #tiempos - peores + 1, #tiempos do
        sumaPeores = sumaPeores + tiempos[indice]
    end
    print(
        string.format(
            'MEDIDA vista %d: %.1f FPS medios, %.1f FPS el 1 %% peor (%d cuadros)',
            numero,
            #tiempos / suma,
            peores / sumaPeores,
            #tiempos
        )
    )
end

--- Modo captura: cada vista se dibuja unos cuadros (y, con `--medir N`, N
-- más midiendo el tiempo de cada uno) y se guarda.
local function dibujarCaptura()
    -- El AA temporal necesita unos cuadros quietos para juntar su historia.
    local preparacion = 40
    local porVista = preparacion + 1 + (estado.medir or 0)
    estado.cuadro = (estado.cuadro or 0) + 1
    local numero = math.floor((estado.cuadro - 1) / porVista) + 1
    local paso = (estado.cuadro - 1) % porVista + 1
    local ahora = love.timer.getTime()
    -- Sin el intervalo del cuadro de la captura (codificar el PNG).
    if estado.medir and paso > preparacion + 1 and estado.ultimo then
        table.insert(estado.tiempos, ahora - estado.ultimo)
    end
    estado.ultimo = ahora
    if paso == 1 then
        if estado.tiempos and #estado.tiempos > 0 then
            informarMedida(numero - 1, estado.tiempos)
        end
        estado.tiempos = {}
    end
    local vista = estado.vistas[numero]
    if not vista then
        love.event.quit()
        return
    end
    local camara = estado.camara
    camara.x, camara.z, camara.distancia = vista[1], vista[2], vista[3]
    camara.rumbo = math.rad(vista[4] or 0)
    camara.ajusteInclinacion = math.rad(vista[5] or 0)
    dibujarEscena()
    if paso == preparacion then
        local archivo = estado.archivo
        if #estado.vistas > 1 then
            archivo = archivo:gsub('%.png$', '') .. '_' .. numero .. '.png'
        end
        guardar(archivo)
    end
end

function love.draw()
    if estado.vistas then
        dibujarCaptura()
        return
    end
    dibujarEscena()
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.print(
        string.format(
            'WASD mover · Q/E girar · rueda acercar · botón central girar/inclinar   %d FPS   distancia %.0f km',
            love.timer.getFPS(),
            estado.camara.distancia
        ),
        12,
        10
    )
end

function love.wheelmoved(_, dy)
    estado.camara:acercar(dy)
end

function love.mousemoved(_, _, dx, dy)
    if love.mouse.isDown(3) then
        estado.camara:girar(dx * 0.006, -dy * 0.004)
    end
end

function love.keypressed(tecla)
    if tecla == 'escape' then
        love.event.quit()
    elseif tecla == 'f11' then
        love.window.setFullscreen(not love.window.getFullscreen())
    end
end

function love.resize()
    dream:resize()
end
