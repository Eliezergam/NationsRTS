-- Programa «Terminal»: una consola de texto como la de Linux, con su carpeta
-- actual, su historial (flechas arriba y abajo) y las órdenes de siempre
-- sobre los archivos del ordenador (almacen/pc/archivos.lua): ayuda, ls, cd,
-- pwd, cat, abrir, editar, mkdir, rm, clear, date, whoami, hostname, uname y
-- exit.

local Dibujo = require('almacen.pc.dibujo')
local Archivos = require('almacen.pc.archivos')
local Lua = require('almacen.pc.lua')
local ApiRobots = require('almacen.pc.api_robots')
local Depuracion = require('almacen.pc.depuracion')

local Terminal = {}

-- El programa de Lua que corre en cada terminal (no se guarda: al volver a
-- abrir el juego la terminal está libre). [estado] = programa.
local procesos = setmetatable({}, { __mode = 'k' })

Terminal.titulo = 'Terminal'
Terminal.orden = 2
Terminal.ancho, Terminal.alto = 860, 520
Terminal.maximoLineas = 400

function Terminal.nuevo(ordenador)
    local nombre = ordenador and ordenador.nombre or 'puesto'
    local estado = {
        nombre = nombre,
        carpeta = '/home/operador',
        lineas = {
            'Arranque de ' .. nombre .. ' completado.',
            'Conectado a la red del almacén. Escribe «ayuda» para ver las órdenes.',
            '',
        },
        escrito = '',
        historial = {},
    }
    return estado
end

local function indicador(estado)
    local carpeta = estado.carpeta:gsub('^/home/operador', '~')
    return 'operador@' .. estado.nombre .. ':' .. carpeta .. '$ '
end

local function escribir(estado, texto)
    for linea in (texto .. '\n'):gmatch('(.-)\n') do
        estado.lineas[#estado.lineas + 1] = linea
    end
    while #estado.lineas > Terminal.maximoLineas do
        table.remove(estado.lineas, 1)
    end
end

local function textoDe(c)
    if type(c) == 'table' then
        return tostring(c.texto or '')
    end
    return c ~= nil and tostring(c) or ''
end

local AYUDA = [[
Órdenes:
  ls [ruta]          lo que hay en una carpeta
  cd [ruta]          cambia de carpeta (~ es la tuya, .. la de arriba)
  pwd                la carpeta actual
  cat <archivo>      enseña lo que tiene un archivo
  abrir <archivo>    lo abre con su programa (hoja, editor, archivos)
  editar <archivo>   abre (o crea) un texto en el editor
  mkdir <carpeta>    crea una carpeta en tu carpeta personal
  rm <archivo>       borra algo de tu carpeta personal
  clear              limpia la pantalla
  date, whoami, hostname, uname
  exit               cierra la terminal

Programas (Lua, como en CC: Tweaked; Ctrl+T los corta):
  lua <archivo.lua>  corre un programa de este ordenador
  <archivo.lua>      lo mismo, si está en la carpeta actual o en ~/programas
  robot              los robots y qué hace cada uno
  robot <nombre> ejecutar <archivo.lua>   deja lo que ejecutaba y pasa a ese
                     (de ~/guiones o del juego: /red/almacen/guiones)
  robot <nombre> parar
  En los programas: robots.lista(), robots.estado(n), robots.trabajar(n),
  robots.parar(n), robots.ejecutar(n, archivo), robots.posicion(n),
  print, sleep. Cada guion de robot es un ejecutable: una especialización
  (onLoad, onUpdate, self = el robot); uno a la vez. Lee ~/guiones/LEEME.txt]]

local ordenes = {}

function ordenes.ayuda(estado)
    escribir(estado, AYUDA)
end
ordenes.help = ordenes.ayuda

function ordenes.ls(estado, ctx, ruta)
    local fs = ctx.ordenador.archivos
    local destino = Archivos.resolver(estado.carpeta, ruta)
    local nodo = fs:buscar(destino)
    if not nodo then
        escribir(estado, 'ls: no existe ' .. (ruta or destino))
    elseif not nodo.carpeta then
        escribir(estado, nodo.nombre)
    else
        local nombres = fs:contenidoDe(destino)
        escribir(estado, #nombres > 0 and table.concat(nombres, '   ') or '')
    end
end

function ordenes.cd(estado, ctx, ruta)
    local destino = Archivos.resolver(estado.carpeta, ruta or '~')
    local nodo = ctx.ordenador.archivos:buscar(destino)
    if not nodo then
        escribir(estado, 'cd: no existe ' .. ruta)
    elseif not nodo.carpeta then
        escribir(estado, 'cd: no es una carpeta: ' .. ruta)
    else
        estado.carpeta = destino
    end
end

function ordenes.pwd(estado)
    escribir(estado, estado.carpeta)
end

function ordenes.cat(estado, ctx, ruta)
    if not ruta then
        escribir(estado, 'cat: falta el archivo')
        return
    end
    local destino = Archivos.resolver(estado.carpeta, ruta)
    local nodo = ctx.ordenador.archivos:buscar(destino)
    if not nodo or nodo.carpeta then
        escribir(estado, 'cat: no es un archivo: ' .. ruta)
        return
    end
    local contenido = ctx.ordenador.archivos:leer(destino, ctx)
    if nodo.tipo == 'hoja' then
        for _, fila in ipairs(contenido.filas or {}) do
            local celdas = {}
            for j = 1, #fila do
                celdas[j] = textoDe(fila[j])
            end
            escribir(estado, table.concat(celdas, '\t'))
        end
    else
        for _, linea in ipairs(contenido or {}) do
            escribir(estado, linea)
        end
    end
end

function ordenes.abrir(estado, ctx, ruta)
    if not ruta then
        escribir(estado, 'abrir: falta el archivo')
        return
    end
    local fs = ctx.ordenador.archivos
    local destino = Archivos.resolver(estado.carpeta, ruta)
    local programa = fs:programaPara(destino)
    if not programa then
        escribir(estado, 'abrir: no existe ' .. ruta)
        return
    end
    local opciones = programa == 'archivos' and { ruta = destino } or { archivo = destino }
    ctx.ordenador:abrir(programa, nil, nil, nil, nil, opciones)
end
ordenes.open = ordenes.abrir
ordenes['xdg-open'] = ordenes.abrir

function ordenes.editar(estado, ctx, ruta)
    if not ruta then
        escribir(estado, 'editar: falta el archivo')
        return
    end
    local fs = ctx.ordenador.archivos
    local destino = Archivos.resolver(estado.carpeta, ruta)
    if not fs:buscar(destino) then
        local _, motivo = fs:crear(destino)
        if motivo then
            escribir(estado, 'editar: ' .. motivo)
            return
        end
    end
    ctx.ordenador:abrir('texto', nil, nil, nil, nil, { archivo = destino })
end
ordenes.nano = ordenes.editar

function ordenes.mkdir(estado, ctx, ruta)
    if not ruta then
        escribir(estado, 'mkdir: falta el nombre')
        return
    end
    local _, motivo = ctx.ordenador.archivos:crear(Archivos.resolver(estado.carpeta, ruta), true)
    if motivo then
        escribir(estado, 'mkdir: ' .. motivo)
    end
end

function ordenes.rm(estado, ctx, ruta)
    if not ruta then
        escribir(estado, 'rm: falta el archivo')
        return
    end
    local ok, motivo = ctx.ordenador.archivos:borrar(Archivos.resolver(estado.carpeta, ruta))
    if not ok then
        escribir(estado, 'rm: ' .. motivo)
    end
end

function ordenes.clear(estado)
    estado.lineas = {}
end
ordenes.limpiar = ordenes.clear

function ordenes.date(estado)
    escribir(estado, os.date('%d/%m/%Y %H:%M:%S'))
end

function ordenes.whoami(estado)
    escribir(estado, 'operador')
end

function ordenes.hostname(estado)
    escribir(estado, estado.nombre)
end

function ordenes.uname(estado)
    escribir(estado, 'Linux ' .. estado.nombre .. ' (sala de control del almacén)')
end

function ordenes.exit()
    return 'cerrar'
end
ordenes.salir = ordenes.exit

-- Corre el programa de Lua `ruta` en la terminal.
local function correr(estado, ctx, ruta)
    local fs = ctx.ordenador.archivos
    local nodo = fs:buscar(ruta)
    if not nodo or nodo.carpeta or nodo.tipo ~= 'texto' then
        escribir(estado, 'lua: no existe ' .. ruta)
        return
    end
    local codigo = table.concat(fs:leer(ruta) or {}, '\n')
    local api = { robots = ApiRobots.para(ctx.ordenador, estado.carpeta) }
    local origen = { puesto = ctx.ordenador.nombre, archivo = ruta:match('[^/]+$') }
    local programa, error = Lua.cargar(codigo, origen.archivo, api, function(texto, linea)
        escribir(estado, texto)
        Depuracion.apuntar(origen, texto, 'print', linea)
    end)
    if not programa then
        escribir(estado, error)
        Depuracion.apuntar(origen, error, 'error')
        return
    end
    programa.origen = origen
    procesos[estado] = programa
    Terminal.actualizar(estado, ctx, 0)
end

function ordenes.lua(estado, ctx, ruta)
    if not ruta then
        escribir(estado, 'lua: falta el archivo (lua programa.lua)')
        return
    end
    correr(estado, ctx, Archivos.resolver(estado.carpeta, ruta))
end

function ordenes.robot(estado, ctx, nombre, orden, archivo)
    if not nombre then
        for _, e in ipairs(ApiRobots.robots()) do
            local r = e.robot
            local modo = r:getModo()
            local que = modo == 'parado' and 'parado' or ('ejecuta ' .. tostring(r:getGuion()))
            escribir(estado, string.format('%-8s %-14s %s', e.nombre, que, r.getTarea and r:getTarea() or ''))
        end
        return
    end
    local r = ApiRobots.buscar(nombre)
    if not r then
        escribir(estado, 'robot: no hay ningún robot «' .. nombre .. '» (escribe «robot» para verlos)')
    elseif orden == 'trabajar' or orden == 'parar' then
        r:setOrden(orden)
        escribir(estado, nombre .. ': ' .. (orden == 'trabajar' and ('ejecuta ' .. tostring(r:getGuion())) or 'parado'))
    elseif (orden == 'ejecutar' or orden == 'guion') and archivo then
        local ok, error = ApiRobots.ejecutar(ctx.ordenador, nombre, Archivos.resolver(estado.carpeta, archivo))
        if ok then
            -- Su depuración en una ventanita, delante (para seguir escribiendo,
            -- clic en la terminal).
            require('almacen.pc.programas.depurador').abrirPara(ctx.ordenador, nombre)
        end
        escribir(estado, ok and (nombre .. ': ' .. archivo .. ' en marcha') or ('robot: ' .. tostring(error)))
    else
        escribir(estado, 'robot <nombre> ejecutar <archivo.lua> | parar')
    end
end

local function ejecutar(estado, ctx, linea)
    escribir(estado, indicador(estado) .. linea)
    local palabras = {}
    for p in linea:gmatch('%S+') do
        palabras[#palabras + 1] = p
    end
    if #palabras == 0 then
        return
    end
    estado.historial[#estado.historial + 1] = linea
    local orden = ordenes[palabras[1]]
    -- Un .lua por su nombre: de la carpeta actual o de ~/programas.
    if not orden and palabras[1]:match('%.lua$') then
        local fs = ctx.ordenador.archivos
        local aqui = Archivos.resolver(estado.carpeta, palabras[1])
        local programas = Archivos.resolver('/home/operador/programas', palabras[1])
        correr(estado, ctx, fs:buscar(aqui) and aqui or programas)
        return
    end
    if not orden then
        escribir(estado, palabras[1] .. ': orden no encontrada (escribe «ayuda»)')
        return
    end
    return orden(estado, ctx, palabras[2], palabras[3], palabras[4])
end

-- Entrada ---------------------------------------------------------------------------

--- Sigue el programa que corre (cada cuadro, con la terminal abierta).
function Terminal.actualizar(estado, ctx, dt)
    local p = procesos[estado]
    if not p then
        return
    end
    local fin, mensaje = p:paso(dt)
    if fin == 'error' then
        escribir(estado, mensaje == 'terminado' and 'Terminado.' or tostring(mensaje))
        if mensaje ~= 'terminado' then
            Depuracion.apuntar(p.origen or {}, tostring(mensaje), 'error')
        end
        procesos[estado] = nil
    elseif fin == 'fin' then
        procesos[estado] = nil
    end
end

function Terminal.texto(estado, ctx, t)
    if procesos[estado] then
        return
    end
    estado.escrito = estado.escrito .. t
    estado.paso = nil
end

function Terminal.tecla(estado, ctx, tecla)
    local control = love.keyboard.isDown('lctrl', 'rctrl')
    if procesos[estado] then
        -- Mientras corre un programa, Ctrl+T lo corta (como en CC).
        if tecla == 't' and control then
            procesos[estado]:terminar()
            Terminal.actualizar(estado, ctx, 0)
        end
        return
    end
    if tecla == 'return' or tecla == 'kpenter' then
        local linea = estado.escrito
        estado.escrito = ''
        estado.paso = nil
        return ejecutar(estado, ctx, linea)
    elseif tecla == 'backspace' then
        -- Quita el último carácter (UTF-8: hasta el inicio del último).
        local s = estado.escrito
        local corte = #s
        while corte > 0 and s:byte(corte) >= 0x80 and s:byte(corte) < 0xC0 do
            corte = corte - 1
        end
        estado.escrito = s:sub(1, math.max(0, corte - 1))
    elseif tecla == 'up' or tecla == 'down' then
        local h = estado.historial
        if #h == 0 then
            return
        end
        local paso = estado.paso or (#h + 1)
        paso = math.max(1, math.min(#h + 1, paso + (tecla == 'up' and -1 or 1)))
        estado.paso = paso
        estado.escrito = h[paso] or ''
    elseif tecla == 'l' and love.keyboard.isDown('lctrl', 'rctrl') then
        estado.lineas = {}
    end
end

-- Dibujo ---------------------------------------------------------------------------

function Terminal.dibujar(estado, ctx, w, h)
    local g = love.graphics
    estado.carpeta = estado.carpeta or '/home/operador'
    estado.historial = estado.historial or {}
    estado.nombre = estado.nombre or ctx.ordenador.nombre
    Dibujo.fondo(w, h, 0.02, 0.025, 0.03)
    local letra = Dibujo.letra('dato', 17)
    g.setFont(letra)
    local alto = letra:getHeight() + 4
    local caben = math.floor((h - 20) / alto)
    -- Las líneas largas se parten al ancho de la ventana.
    local visibles = {}
    for _, linea in ipairs(estado.lineas) do
        local _, partes = letra:getWrap(linea, w - 28)
        if #partes == 0 then
            partes = { '' }
        end
        for _, p in ipairs(partes) do
            visibles[#visibles + 1] = p
        end
    end
    local primera = math.max(1, #visibles + 2 - caben)
    local y = 12
    g.setColor(0.8, 0.86, 0.84)
    for k = primera, #visibles do
        g.print(visibles[k], 14, y)
        y = y + alto
    end
    local pide = procesos[estado] and '' or indicador(estado)
    g.setColor(Dibujo.verde)
    g.print(pide, 14, y)
    local x = 14 + letra:getWidth(pide)
    g.setColor(0.92, 0.95, 0.93)
    g.print(estado.escrito, x, y)
    x = x + letra:getWidth(estado.escrito)
    if math.floor((ctx.reloj or 0) * 2) % 2 == 0 then
        g.rectangle('fill', x + 1, y + 2, letra:getWidth('m'), alto - 6)
    end
end

--- Icono del programa (panel y escritorio), en un cuadro de s px.
function Terminal.icono(x, y, s)
    local g = love.graphics
    g.setColor(0.13, 0.14, 0.15)
    g.rectangle('fill', x, y, s, s, s * 0.18)
    g.setColor(Dibujo.verde)
    g.setLineWidth(math.max(1, s * 0.08))
    g.line(x + s * 0.22, y + s * 0.32, x + s * 0.42, y + s * 0.5, x + s * 0.22, y + s * 0.68)
    g.line(x + s * 0.5, y + s * 0.7, x + s * 0.78, y + s * 0.7)
    g.setLineWidth(1)
end

return Terminal
