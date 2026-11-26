-- Ficha: el panel pequeño de un ejército al hacer clic en su estandarte
-- (diseno/ejercitos-en-el-mapa.md, §3.1.5). A la izquierda, junto a la columna
-- de iconos y bajo la barra superior: escudo y nación, líder y carácter, poder, estado y composición
-- (del ejército propio; de los ajenos, solo con informe de exploradores:
-- si no, «desconocida» y poder «Desconocido · Explorar»).
--
-- Los recolectores (diseno/recoleccion-y-batallas.md) muestran además su
-- recurso, su carga y lo que sacan al día.
--
-- Lo propio lleva también su munición (diseno/economia.md, 3.6): cuánta de
-- cada una y los días de batalla que le quedan (en ámbar por debajo de
-- `umbralAbasto`, en rojo sin nada). Un convoy de munición dice lo que lleva.
--
-- Solo lee `sim:fichaGrupo`. Los botones los pone main.lua (ir a la batalla,
-- retirar, redirigir, atacar); `pulsar` devuelve su acción.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Estandartes = require('mundo.estandartes')
local Inteligencia = require('interfaz.inteligencia')
local Simulacion = require('mundo.simulacion')

local Ficha = {}
Ficha.__index = Ficha

function Ficha.nuevo()
    local self = setmetatable({}, Ficha)
    self.zonas = {}
    self.rect = nil
    return self
end

local NOMBRE_CARGA = { metal = 'metal', petroleo = 'petróleo', comida = 'comida', oro = 'oro' }
local MUNICIONES = {
    { clave = 'balas', nombre = 'Balas', tropa = 'soldados' },
    { clave = 'misiles', nombre = 'Misiles', tropa = 'lanzacohetes' },
}

--- Días con coma y un decimal («2,5 días»).
local function textoDias(dias)
    local cifra = math.abs(dias - math.floor(dias + 0.5)) < 0.05 and tostring(math.floor(dias + 0.5))
        or (string.format('%.1f', dias):gsub('%.', ','))
    return cifra .. (cifra == '1' and ' día' or ' días')
end

--- Qué hace el grupo, en pocas palabras.
local function estado(sim, gr, pose)
    local objetivo = sim:sitio(gr.objetivo)
    local nombre = objetivo and objetivo.nombre or 'su objetivo'
    if not objetivo and sim.estado.depositos[gr.objetivo] then
        nombre = 'una mina'
    end
    local b = gr.batalla and sim:estadoBatalla(gr.batalla)
    local carga = NOMBRE_CARGA[gr.tipoCarga] or ''
    if pose == 'retirada' then
        return 'En retirada', 'amarillo'
    elseif b then
        return 'Batalla en ' .. b.nombre, 'rojoTexto'
    elseif pose == 'combate' then
        return 'Combate en ' .. nombre, 'rojoTexto'
    elseif gr.mision == 'recolectar' and gr.fase == 'ida' then
        return 'Va a recolectar ' .. carga, 'textoHud'
    elseif gr.mision == 'recolectar' and gr.fase == 'recolectando' then
        return 'Recolecta ' .. carga, 'verde'
    elseif gr.mision == 'recolectar' then
        return 'Vuelve con la carga', 'textoHudTenue'
    elseif gr.mision == 'apoyo' then
        return 'Va a ayudar en una batalla', 'amarillo'
    elseif gr.mision == 'atacar' then
        return 'En marcha hacia ' .. nombre, 'textoHud'
    elseif gr.mision == 'abasto' then
        return 'Lleva munición a su ejército', 'amarillo'
    elseif gr.remolque then
        return 'Remolca vehículos averiados al taller', 'textoHudTenue'
    elseif gr.mision == 'regreso' then
        return 'Vuelve a casa', 'textoHudTenue'
    elseif gr.mision == 'mover' then
        local llego = (gr.recorrido or 0) >= (gr.largo or 0)
        return llego and 'En posición' or 'En marcha', 'textoHud'
    end
    return 'Convoy', 'textoHudTenue'
end

--- Dibuja el panel del grupo `gid` visto por la nación `mira` (nil: todo).
-- `botones` (opcional) = { { texto, tipo, accion, activo }, ... }, uno bajo
-- otro, y `aviso` (opcional) una línea en ámbar sobre ellos. Si el grupo ya
-- no existe, no dibuja nada y devuelve false.
function Ficha:dibujar(sim, gid, mira, semillaMundo, arriba, botones, aviso)
    -- Gris caqui claro con texto negro, como los demás paneles del mapa.
    Tema.modoClaro = true
    local ok, resultado = pcall(self.dibujarClara, self, sim, gid, mira, semillaMundo, arriba, botones, aviso)
    Tema.modoClaro = false
    if not ok then
        error(resultado, 0)
    end
    return resultado
end

function Ficha:dibujarClara(sim, gid, mira, semillaMundo, arriba, botones, aviso)
    local g = love.graphics
    self.zonas = {}
    self.rect = nil
    local gr = sim.estado.grupos[gid]
    local ficha = gr and Inteligencia.ficha(sim, gid, mira)
    if not ficha then
        return false
    end
    local texto = Acero.fuente('cuerpo')
    local negrita = Acero.fuente('cifra', 18)
    local pequena = Acero.fuente('etiqueta')
    local ancho = Tema.px(Tema.compacta() and 340 or 400)
    local escudoLado = Tema.px(56)
    local x, y = Tema.px(112), arriba
    local lineas = {}
    local function linea(etiqueta, valor, color)
        lineas[#lineas + 1] = { etiqueta = etiqueta, valor = valor, color = color }
    end
    local pose = Estandartes.pose(gr)
    local queHace, colorEstado = estado(sim, gr, pose)
    if ficha.lider then
        linea('Carácter', ficha.lider.caracter)
        linea('Victorias', string.format('%d · derrotas %d', ficha.lider.victorias, ficha.lider.derrotas))
    end
    local recolector = Estandartes.esRecolector(ficha)
    if ficha.capacidad then
        local lleva = Estandartes.cifraCarga(ficha.carga) .. ' / ' .. Estandartes.cifraCarga(ficha.capacidad)
        linea('Carga de ' .. (NOMBRE_CARGA[ficha.tipoCarga] or '?'), lleva, 'amarillo')
        local d = gr.yacimiento and sim.estado.depositos[gr.yacimiento]
        if d and gr.mision == 'recolectar' and (mira == nil or mira == gr.nacion) then
            local ritmo = sim:ritmoRecoleccion(gr, d)
            linea('Recolecta al día', (string.format('%.2f', ritmo):gsub('%.', ',')))
        end
    end
    local c = ficha.composicion
    if c then
        -- Lo propio (lleva munición en la ficha) dice también sus modelos:
        -- «3 · 2 K2, 1 T-55» (diseno/catalogo-armamento.md).
        local function conModelos(tipo, cuantos)
            local cifra = Tema.numero(cuantos)
            if not ficha.municion or cuantos <= 0 then
                return cifra
            end
            local partes = {}
            for _, d in ipairs(Simulacion.desglose(gr, tipo)) do
                partes[#partes + 1] = Tema.numero(d.cantidad) .. ' ' .. Simulacion.nombreModelo(d.modelo)
            end
            return #partes > 0 and (cifra .. ' · ' .. table.concat(partes, ', ')) or cifra
        end
        linea('Lanzacohetes', conModelos('lanzacohetes', c.lanzacohetes))
        linea('Soldados', Tema.numero(c.soldados))
        local heridos = c.heridos.soldados + c.heridos.lanzacohetes
        if heridos > 0 then
            linea('Heridos', Tema.numero(heridos), 'amarillo')
        end
        if ficha.informeDia then
            linea('Informe', Inteligencia.hace(sim, ficha.informeDia), 'textoHudTenue')
        end
    else
        linea('Composición', 'desconocida', 'textoHudTenue')
    end
    -- Munición (solo lo propio: la ficha la trae solo para su dueño).
    local m = ficha.municion
    if m and gr.mision == 'abasto' then
        for _, t in ipairs(MUNICIONES) do
            if m[t.clave] > 0 then
                linea('Lleva ' .. t.nombre:lower(), Tema.numero(m[t.clave]), 'amarillo')
            end
        end
    elseif m and c then
        local umbral = Simulacion.produccion.umbralAbasto
        for _, t in ipairs(MUNICIONES) do
            if (c[t.tropa] or 0) > 0 then
                local dias = m.dias[t.clave]
                local color = (m[t.clave] <= 0 and 'rojoTexto') or (dias < umbral and 'amarillo') or nil
                linea(t.nombre, Tema.numero(m[t.clave]) .. ' · ' .. textoDias(dias), color)
            end
        end
    end
    -- Las alturas salen del tamaño real de las letras (el texto puede ir más
    -- grande que los paneles, `Tema.TEXTO`), para que nada se pise.
    local altoFila = math.max(Tema.px(28), math.max(texto:getHeight(), negrita:getHeight()) + Tema.px(10))
    botones = botones or {}
    local altoBoton = Tema.px(40)
    local relleno = Tema.px(12)
    local cabecera = Tema.px(50)
    local pie = Tema.px(8)
    local grandePoder = Acero.fuente('cifraGrande', 32)
    local altoPoder = ficha.ejercito and math.max(Tema.px(44), grandePoder:getHeight() + Tema.px(8)) or 0
    -- Bloque bajo el nombre: el nombre de la nación y el estado (hasta dos líneas).
    local anchoEstado = ancho - relleno * 2 - escudoLado - Tema.px(14)
    local _, partesPrevias = texto:getWrap(queHace, anchoEstado)
    local lineasEstado = math.max(1, math.min(2, #partesPrevias))
    local altoBloque = math.max(escudoLado, pequena:getHeight() + Tema.px(6) + lineasEstado * texto:getHeight())
    local alto = cabecera + relleno + altoBloque + Tema.px(8)
    alto = alto + altoPoder + #lineas * altoFila + pie
    if aviso then
        local _, partes = texto:getWrap(aviso, ancho - relleno * 2 - Tema.px(16))
        alto = alto + Tema.px(8) + #partes * texto:getHeight()
    end
    if #botones > 0 then
        alto = alto + Tema.px(8) + #botones * (altoBoton + Tema.px(6)) - Tema.px(6)
    end
    self.rect = { x = x, y = y, w = ancho, h = alto }
    local nombre = ficha.lider and ficha.lider.etiqueta
        or (ficha.ejercito and 'Ejército' or (recolector and 'Recolectores' or 'Convoy'))
    if gr.mision == 'abasto' then
        nombre = 'Convoy de munición'
    elseif gr.remolque then
        nombre = 'Remolque'
    end
    local _, _, _, _, cierre = Acero.panel(x, y, ancho, alto, { titulo = nombre, cerrar = true })
    if cierre then
        self.zonas[#self.zonas + 1] = { x = cierre.x, y = cierre.y, w = cierre.w, h = cierre.h, accion = 'cerrar' }
    end
    local cx = x + relleno + Tema.px(4)
    local cw = x + ancho - relleno - Tema.px(4) - cx
    local cy = y + cabecera + relleno
    -- Escudo del ejército (hoja _x4) con la nación y lo que hace.
    local hoja = 4
    local s = escudoLado / (18 * hoja)
    Estandartes.dibujarEscudo(
        Estandartes.escudoDe(semillaMundo, ficha.nacion),
        cx + escudoLado * 0.45,
        cy + escudoLado / 2,
        hoja,
        s
    )
    local tx = cx + escudoLado + Tema.px(10)
    local tw = x + ancho - relleno - Tema.px(4) - tx
    g.setFont(pequena)
    -- El color del país aclarado, para que se lea sobre el acero.
    -- El color del país se oscurece sobre el gris claro, para que se lea.
    if Tema.modoClaro then
        Tema.color(Tema.mezcla(ficha.color, Tema.colores.tinta, 0.7))
    else
        Tema.color(Tema.mezcla(ficha.color, Tema.colores.textoHud, 0.55))
    end
    g.print(Tema.cortar(pequena, (ficha.nombreNacion or ''):upper(), tw), tx, cy + Tema.px(2))
    g.setFont(texto)
    Tema.color(colorEstado)
    local _, partesEstado = texto:getWrap(queHace, tw)
    for k = 1, math.min(2, #partesEstado) do
        local parte = partesEstado[k]
        if k == 2 and #partesEstado > 2 then
            parte = Tema.cortar(texto, table.concat(partesEstado, ' ', 2), tw)
        end
        g.print(parte, tx, cy + pequena:getHeight() + Tema.px(6) + (k - 1) * texto:getHeight())
    end
    cy = cy + altoBloque + Tema.px(8)
    -- Poder: la cifra grande del ejército.
    if ficha.ejercito then
        local grande = Acero.fuente('cifraGrande', 32)
        g.setFont(pequena)
        Tema.color('textoHudTenue')
        g.print('PODER', cx, cy + Tema.px(14))
        g.setFont(grande)
        Tema.color('amarillo')
        if ficha.poderOculto then
            -- Ajeno sin informe (interfaz/inteligencia.lua): no se sabe.
            local medio = Acero.fuente('cifra', 20)
            g.setFont(medio)
            Tema.color('textoHudTenue')
            local desconocido = Inteligencia.textoDesconocido
            g.print(
                desconocido,
                cx + cw - medio:getWidth(desconocido),
                cy + math.floor((altoPoder - medio:getHeight()) / 2)
            )
        else
            local poder = Tema.numero(ficha.poderRedondeado)
            g.print(poder, cx + cw - grande:getWidth(poder), cy + math.floor((altoPoder - grande:getHeight()) / 2))
        end
        cy = cy + altoPoder
    end
    for _, l in ipairs(lineas) do
        -- El valor deja sitio a la etiqueta (los modelos pueden ser largos).
        local valor = Tema.cortar(negrita, l.valor, cw - math.min(texto:getWidth(l.etiqueta), cw * 0.4) - Tema.px(8))
        g.setFont(texto)
        Tema.color('textoHudTenue')
        g.print(
            Tema.cortar(texto, l.etiqueta, cw - negrita:getWidth(valor) - Tema.px(8)),
            cx,
            cy + math.floor((altoFila - texto:getHeight()) / 2)
        )
        g.setFont(negrita)
        Tema.color(l.color or 'textoHud')
        g.print(valor, cx + cw - negrita:getWidth(valor), cy + math.floor((altoFila - negrita:getHeight()) / 2))
        Tema.color('lineaOliva')
        g.rectangle('fill', cx, cy + altoFila - 1, cw, 1)
        cy = cy + altoFila
    end
    if aviso then
        cy = cy + Tema.px(8)
        g.setFont(texto)
        Tema.color('amarillo')
        local _, partes = texto:getWrap(aviso, cw)
        g.printf(aviso, cx, cy, cw, 'left')
        cy = cy + #partes * texto:getHeight()
    end
    if #botones > 0 then
        cy = cy + Tema.px(8)
        for _, b in ipairs(botones) do
            Tema.boton(b, cx, cy, cw, altoBoton)
            if b.activo ~= false then
                self.zonas[#self.zonas + 1] = { x = cx, y = cy, w = cw, h = altoBoton, accion = b.accion }
            end
            cy = cy + altoBoton + Tema.px(6)
        end
    end
    return true
end

--- Clic: nil si cayó fuera; si no, 'cerrar', la acción del botón o 'nada'.
function Ficha:pulsar(x, y)
    local r = self.rect
    if not (r and Tema.dentro(x, y, r.x, r.y, r.w, r.h)) then
        return nil
    end
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            return z.accion
        end
    end
    return 'nada'
end

return Ficha
