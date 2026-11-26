-- Pantalla de inicio (login) de Nations RTS: el diseño de Camila
-- (assets/ui/login/previews/login_completo.jpg), copiado de la referencia de
-- El dueño (assets/ui/login/fuente/referencia.jpg). El fondo se mueve un poco
-- con el ratón, el brillo del logo late despacio y el panel entra con un
-- fundido (interfaz/vida.lua).
--
-- Lo que hace cada cosa (decisiones del dueño, 2026-10-01):
--   «Invitado»          entra a jugar sin conexión (partida nueva);
--   «ENTRAR» y Enter    iniciar sesión: por ahora, «Próximamente»;
--   «¿Olvidaste…?», «Soporte» y «Crear cuenta»: «Próximamente»;
--   los dos campos se escriben (Tab pasa de uno a otro, el ojo enseña la
--   contraseña) y «Recordarme» se marca;
--   Esc pregunta antes de salir del juego (interfaz/dialogoSalir.lua, que
--   abre el juego).
--
-- Todo está medido en el lienzo del diseño, 1920 x 1080
-- (assets/ui/login/indice.lua), y se escala entero con la pantalla, sin
-- estirar nada: el panel lleva un mapa dentro y conserva su proporción.
--
-- Los textos están todos en `TEXTOS`, para traducirlos.

local Tema = require('interfaz.tema')
local Vida = require('interfaz.vida')
local Nueve = require('interfaz.nueve')
local CampoTexto = require('interfaz.campoTexto')
local FondoLogin = require('interfaz.fondoLogin')
local Indice = require('assets.ui.login.indice')

local TEXTOS = {
    titulo = 'ENTRAR AL MANDO',
    lema = 'LIDERA TU ALIANZA. FORJA EL MAÑANA.',
    usuario = 'ID de comandante / correo',
    clave = 'Contraseña',
    recordar = 'Recordarme',
    olvido = '¿Olvidaste la contraseña?',
    entrar = 'ENTRAR',
    o = 'O',
    invitado = 'Invitado',
    soporte = 'Soporte',
    crearCuenta = 'Crear cuenta',
    proximamente = 'Próximamente',
    proximamenteDetalle = 'Por ahora, entra como invitado.',
}

local Login = {}
Login.__index = Login
Login.TEXTOS = TEXTOS

-- Lienzo del diseño.
local ANCHO = 1920
local ALTO = 1080

-- Colores del diseño (indice.lua y el script de Camila, tools/login_piezas.py).
local function hex(texto)
    local r, g, b = texto:match('#(%x%x)(%x%x)(%x%x)')
    return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

local COLORES = {
    texto = hex(Indice.disposicion.colores.texto),
    marcador = hex(Indice.disposicion.colores.marcador),
    textoBoton = hex(Indice.disposicion.colores.textoBoton),
    casilla = hex(Indice.disposicion.colores.casilla),
    lema = { 210 / 255, 214 / 255, 220 / 255 },
    dorado = hex('#f2c14e'),
}

-- Fuentes del diseño: tipo de Tema y tamaño (em) a 1080p.
local FUENTES = {
    titulo = { 'condensada', 46 },
    lema = { 'semi', 19 },
    campo = { 'semi', 22 },
    pequena = { 'semi', 20 },
    boton = { 'condensada', 44 },
    avisoTitulo = { 'condensada', 26 },
    avisoDetalle = { 'semi', 19 },
}

-- Espaciado entre letras (px de diseño).
local ESPACIADO = { titulo = 2, lema = 3, boton = 3 }

-- Cajas (x, y, ancho, alto) del diseño.
local D = Indice.disposicion
local CAJAS = {
    usuario = { D.campoUsuario[1], D.campoUsuario[2], 568, 73 },
    clave = { D.campoClave[1], D.campoClave[2], 568, 73 },
    -- Cuerpo del botón dorado, sin su resplandor.
    entrar = { 1210, 655, 614, 99 },
    invitado = { D.botonInvitado[1], D.botonInvitado[2], 283, 73 },
    soporte = { D.botonSoporte[1], D.botonSoporte[2], 283, 73 },
    ojo = { 1726, 492, 60, 58 },
}

-- Texto de los campos: empieza tras el icono y acaba antes del borde (o del ojo).
local TEXTO_CAMPO = {
    izquierda = 1303,
    derecha = { usuario = 1774, clave = 1722 },
    centro = { usuario = 418, clave = 521 },
}

local DURACION_AVISO = 3.2
local PERIODO_LOGO = 4.5 -- segundos de un latido del brillo del logo

--- Pantalla nueva. Carga sus imágenes enseguida; las capas del fondo van en un
-- hilo, salvo con `capturando` (aquí mismo, para que la foto salga con ellas).
-- `fondo` (opcional) es el FondoLogin que comparte con la pantalla de carga.
function Login.nuevo(capturando, fondo)
    local login = setmetatable({}, Login)
    login.fondo = fondo or FondoLogin.nuevo()
    login.fondo:cargarCapas(capturando)
    login.imagenes = {}
    login.cortes = {}
    login.usuario = CampoTexto.nuevo({ maximo = 64 })
    login.clave = CampoTexto.nuevo({ oculto = true, maximo = 64 })
    login.foco = nil -- 'usuario', 'clave' o nil
    login.recordar = false
    login.pulsando = nil -- elemento pulsado (se activa al soltar encima)
    login.aviso = nil -- { inicio } del «Próximamente»
    login.tecleo = 0
    login.repeticionAntes = love.keyboard.hasKeyRepeat()
    love.keyboard.setKeyRepeat(true)
    login:cargarImagenes()
    return login
end

local function nuevaImagen(ruta)
    local img = love.graphics.newImage(ruta, { mipmaps = true })
    img:setFilter('linear', 'linear')
    img:setMipmapFilter('linear')
    return img
end

function Login:cargarImagenes()
    local piezas = Indice.piezas
    local img = self.imagenes
    img.logo = nuevaImagen(Indice.logo.archivo)
    img.logo2x = nuevaImagen(Indice.logo.archivo2x)
    img.logoEfecto = nuevaImagen(Indice.logo.efecto)
    for nombre, pieza in pairs(piezas) do
        img[nombre] = nuevaImagen(pieza.archivo)
        if pieza.nueve then
            self.cortes[nombre] = Nueve.nuevo(img[nombre], pieza.nueve)
        end
    end
    self.iconos = {}
    for nombre, icono in pairs(Indice.iconos) do
        self.iconos[nombre] = nuevaImagen(icono.archivo)
    end
end

--- Deja el teclado como estaba (al salir de la pantalla).
function Login:cerrar()
    love.keyboard.setKeyRepeat(self.repeticionAntes)
    self.fondo:soltarCapas()
end

-- Medidas --------------------------------------------------------------------------------------------

--- Escala y origen del lienzo del diseño en la pantalla: entero y centrado,
-- sin deformar.
function Login:medir()
    local w, h = love.graphics.getDimensions()
    local s = math.min(w / ANCHO, h / ALTO)
    self.s = s
    self.ox = math.floor((w - ANCHO * s) / 2 + 0.5)
    self.oy = math.floor((h - ALTO * s) / 2 + 0.5)
end

--- Punto del diseño en la pantalla.
function Login:p(x, y)
    return math.floor(self.ox + x * self.s + 0.5), math.floor(self.oy + y * self.s + 0.5)
end

--- Caja del diseño en la pantalla.
function Login:caja(c)
    local x, y = self:p(c[1], c[2])
    local x2, y2 = self:p(c[1] + c[3], c[2] + c[4])
    return x, y, x2 - x, y2 - y
end

--- Fuente de un estilo de `FUENTES` a la escala de la pantalla. Usa la caché
-- de Tema: su tamaño es diseño × escala de Tema × Tema.TEXTO, así que se le
-- pide el que da el tamaño del diseño a la escala del login.
function Login:fuente(estilo)
    local f = FUENTES[estilo]
    local base = f[2] * self.s / (Tema.escala() * Tema.TEXTO)
    return Tema.fuenteExacta(f[1], base, 10)
end

--- `y` de un texto que tiene su centro vertical (entre ascendente y
-- descendente, como el ancla «m» del diseño) en `centro`.
local function arribaDe(fuente, centro)
    return math.floor(centro - (fuente:getAscent() - fuente:getDescent()) / 2 + 0.5)
end

local function color(c, alfa)
    love.graphics.setColor(c[1], c[2], c[3], alfa or 1)
end

--- Imagen del diseño en (x, y) del lienzo, a la escala de la pantalla, con
-- alfa y escala extra opcionales.
function Login:imagen(img, x, y, alfa, escala)
    local px, py = self:p(x, y)
    local k = self.s * (escala or 1)
    love.graphics.setColor(1, 1, 1, alfa or 1)
    love.graphics.draw(img, px, py, 0, k, k)
end

-- Estado del ratón --------------------------------------------------------------------------------

--- Zonas que se pueden pulsar, en píxeles de pantalla (las de los enlaces
-- dependen del ancho de su texto).
function Login:zonas()
    local z = {}
    for nombre, c in pairs(CAJAS) do
        z[nombre] = { self:caja(c) }
    end
    local pequena = self:fuente('pequena')
    local campo = self:fuente('campo')
    -- «Recordarme»: la casilla y su texto.
    local cx, cy = self:p(D.casilla[1], D.casilla[2] - 4)
    local finRecordar = self:p(1267 + 8, 0) + campo:getWidth(TEXTOS.recordar)
    z.recordar = { cx, cy, finRecordar - cx, math.floor(33 * self.s) }
    -- «¿Olvidaste la contraseña?»: alineado a la derecha en 1790.
    local ox, oy = self:p(1790, 593)
    local anchoOlvido = pequena:getWidth(TEXTOS.olvido)
    z.olvido = { ox - anchoOlvido - 4, oy - math.floor(16 * self.s), anchoOlvido + 8, math.floor(32 * self.s) }
    -- «Crear cuenta»: del icono a la flecha.
    local ix, iy = self:p(D.iconoCrearCuenta[1] - 6, 926)
    local tx = self:p(1440, 0)
    local fin = tx + pequena:getWidth(TEXTOS.crearCuenta) + math.floor(36 * self.s)
    z.crearCuenta = { ix, iy, fin - ix, math.floor(36 * self.s) }
    return z
end

--- Elemento bajo (x, y), o nil.
function Login:bajo(x, y)
    local zonas = self:zonas()
    -- El ojo está dentro del campo de la contraseña: va antes.
    if Tema.dentro(x, y, zonas.ojo[1], zonas.ojo[2], zonas.ojo[3], zonas.ojo[4]) then
        return 'ojo'
    end
    for nombre, c in pairs(zonas) do
        if Tema.dentro(x, y, c[1], c[2], c[3], c[4]) then
            return nombre
        end
    end
    return nil
end

--- ¿Está el ratón sobre `nombre`? (En las capturas, lo que diga `encimaFijo`.)
function Login:encima(nombre)
    if self.encimaFijo then
        return self.encimaFijo == nombre
    end
    if Vida.quieta then
        return false
    end
    return self:bajo(love.mouse.getPosition()) == nombre
end

--- ¿Se está pulsando `nombre`?
function Login:pulsado(nombre)
    return self.pulsando == nombre and self:encima(nombre) and love.mouse.isDown(1)
end

-- Acciones --------------------------------------------------------------------------------------------

--- Sale el aviso de «Próximamente».
function Login:proximamente()
    self.aviso = { inicio = love.timer.getTime() }
end

--- Hace lo de `nombre`. Devuelve 'invitado' si el juego tiene que hacer algo.
function Login:activar(nombre)
    if nombre == 'invitado' then
        return 'invitado'
    elseif nombre == 'entrar' or nombre == 'olvido' or nombre == 'soporte' or nombre == 'crearCuenta' then
        self:proximamente()
    elseif nombre == 'recordar' then
        self.recordar = not self.recordar
    elseif nombre == 'ojo' then
        self.clave.mostrar = not self.clave.mostrar
    end
    return nil
end

--- Pone el cursor del campo donde se pulsó.
function Login:cursorEn(nombre, x)
    local campo = self[nombre]
    local fuente = self:fuente('campo')
    local inicio = self:p(TEXTO_CAMPO.izquierda, 0) - (self.desplazado and self.desplazado[nombre] or 0)
    campo.cursor = 0
    local largo = campo:largo()
    for n = 1, largo do
        campo.cursor = n
        local ancho = fuente:getWidth(campo:visibleAntesDelCursor())
        if inicio + ancho > x then
            local anterior = n - 1
            campo.cursor = anterior
            local anchoAntes = fuente:getWidth(campo:visibleAntesDelCursor())
            if x - (inicio + anchoAntes) > inicio + ancho - x then
                campo.cursor = n
            end
            return
        end
    end
    campo.cursor = largo
end

function Login:pulsar(x, y, boton)
    if boton ~= 1 then
        return nil
    end
    self:medir()
    local nombre = self:bajo(x, y)
    self.pulsando = nombre
    if nombre == 'usuario' or nombre == 'clave' then
        self.foco = nombre
        self.tecleo = love.timer.getTime()
        self:cursorEn(nombre, x)
    elseif nombre ~= 'ojo' then
        self.foco = nil
    end
    return nil
end

function Login:soltar(x, y, boton)
    if boton ~= 1 then
        return nil
    end
    self:medir()
    local nombre = self:bajo(x, y)
    local pulsado = self.pulsando
    self.pulsando = nil
    if nombre and nombre == pulsado and nombre ~= 'usuario' and nombre ~= 'clave' then
        return self:activar(nombre)
    end
    return nil
end

function Login:texto(texto)
    if not self.foco then
        self.foco = 'usuario'
        self.usuario:alFinal()
    end
    self[self.foco]:escribir(texto)
    self.tecleo = love.timer.getTime()
end

--- Tecla. Devuelve 'preguntarSalir' con Esc: el juego abre la pregunta
-- (interfaz/dialogoSalir.lua).
function Login:tecla(tecla)
    if tecla == 'escape' then
        self.pulsando = nil
        return 'preguntarSalir'
    end
    if tecla == 'tab' then
        local atras = love.keyboard.isDown('lshift', 'rshift')
        if self.foco == 'usuario' then
            self.foco = 'clave'
        elseif self.foco == 'clave' then
            self.foco = 'usuario'
        else
            self.foco = atras and 'clave' or 'usuario'
        end
        self[self.foco]:alFinal()
        self.tecleo = love.timer.getTime()
        return nil
    end
    if tecla == 'return' or tecla == 'kpenter' then
        self:proximamente()
        return nil
    end
    if self.foco and self[self.foco]:tecla(tecla) then
        self.tecleo = love.timer.getTime()
    end
    return nil
end

function Login:actualizar()
    self.fondo:actualizar()
    if self.aviso and not Vida.quieta and love.timer.getTime() - self.aviso.inicio > DURACION_AVISO then
        self.aviso = nil
    end
end

-- Dibujo ------------------------------------------------------------------------------------------------

function Login:dibujarLogo()
    local logo = Indice.logo
    -- El brillo late despacio alrededor de su opacidad del diseño.
    local latido = 1
    if not Vida.quieta then
        local t = love.timer.getTime() * 2 * math.pi / PERIODO_LOGO
        latido = 0.82 + 0.18 * (0.5 + 0.5 * math.sin(t))
        latido = latido / 0.91
    end
    self:imagen(self.imagenes.logoEfecto, 0, 0, logo.efectoOpacidad * latido)
    if self.s > 1 then
        self:imagen(self.imagenes.logo2x, 50, 35, 1, 0.5)
    else
        self:imagen(self.imagenes.logo, 50, 35)
    end
end

--- Un texto con espaciado entre letras, anclado a la izquierda (o al
-- centro, con `centrado`) y centrado en vertical en `y` (del diseño).
function Login:textoEspaciado(estilo, texto, x, y, c, centrado)
    local fuente = self:fuente(estilo)
    local espacio = (ESPACIADO[estilo] or 0) * self.s
    local px, py = self:p(x, y)
    if centrado then
        px = math.floor(px - Tema.anchoEspaciado(texto, fuente, espacio) / 2 + 0.5)
    end
    color(c)
    Tema.espaciado(texto, px, arribaDe(fuente, py), fuente, espacio)
end

--- Un texto normal centrado en vertical en `y` (del diseño); `ancla`
-- 'izquierda', 'derecha' o 'centro'. Devuelve su x y su ancho en pantalla.
function Login:texto1(estilo, texto, x, y, c, ancla, alfa)
    local fuente = self:fuente(estilo)
    local px, py = self:p(x, y)
    local ancho = fuente:getWidth(texto)
    if ancla == 'derecha' then
        px = px - ancho
    elseif ancla == 'centro' then
        px = math.floor(px - ancho / 2 + 0.5)
    end
    love.graphics.setFont(fuente)
    color(c, alfa)
    love.graphics.print(texto, px, arribaDe(fuente, py))
    return px, ancho
end

--- Subraya un enlace de pantalla (x, ancho) a la altura `y` del diseño.
function Login:subrayar(x, ancho, y, c)
    local _, py = self:p(0, y)
    local grueso = math.max(1, math.floor(self.s + 0.5))
    color(c)
    love.graphics.rectangle('fill', x, py, ancho, grueso)
end

--- Un campo de texto con su icono, lo escrito (o el marcador) y el cursor.
function Login:dibujarCampo(nombre, icono, xIcono, yIcono, marcador)
    local g = love.graphics
    local c = CAJAS[nombre]
    local x, y, w, h = self:caja(c)
    local campo = self[nombre]
    local enfocado = self.foco == nombre
    local encima = self:encima(nombre)
    g.setColor(1, 1, 1, 1)
    self.cortes.campo:dibujar(x, y, w, h, self.s)
    -- Borde: más claro con el ratón encima y dorado con el foco.
    local luz = Vida.suave('login:borde:' .. nombre, enfocado and 1 or (encima and 0.45 or 0), 14)
    if luz > 0.01 then
        local grueso = math.max(1, math.floor(1.5 * self.s + 0.5))
        g.setLineWidth(grueso)
        color(enfocado and COLORES.dorado or COLORES.texto, (enfocado and 0.85 or 0.35) * math.min(1, luz))
        g.rectangle('line', x + grueso / 2, y + grueso / 2, w - grueso, h - grueso)
        g.setLineWidth(1)
    end
    self:imagen(self.iconos[icono], xIcono, yIcono, enfocado and 1 or 0.9)
    -- Lo escrito, con su recorte y desplazado para que se vea el cursor.
    local fuente = self:fuente('campo')
    local izquierda = self:p(TEXTO_CAMPO.izquierda, 0)
    local derecha = self:p(TEXTO_CAMPO.derecha[nombre], 0)
    local _, cy = self:p(0, TEXTO_CAMPO.centro[nombre])
    local ty = math.floor(cy - (fuente:getAscent() - fuente:getDescent()) / 2 + 0.5)
    local visible = campo:textoVisible()
    local cursorX = fuente:getWidth(campo:visibleAntesDelCursor())
    self.desplazado = self.desplazado or {}
    local desplazado = math.max(0, cursorX - (derecha - izquierda) + 2)
    self.desplazado[nombre] = desplazado
    local sx, sy, sw, sh = g.getScissor()
    g.intersectScissor(izquierda, y, derecha - izquierda, h)
    g.setFont(fuente)
    if visible == '' then
        color(COLORES.marcador)
        g.print(marcador, izquierda, ty)
    else
        color(COLORES.texto)
        g.print(visible, izquierda - desplazado, ty)
    end
    if enfocado then
        local parpadeo = Vida.quieta or (love.timer.getTime() - self.tecleo) % 1.06 < 0.53
        if parpadeo then
            local alto = math.floor(fuente:getHeight() * 0.62)
            local grueso = math.max(1, math.floor(1.5 * self.s + 0.5))
            color(COLORES.dorado)
            g.rectangle('fill', izquierda - desplazado + cursorX, math.floor(cy - alto / 2), grueso, alto)
        end
    end
    if sx then
        g.setScissor(sx, sy, sw, sh)
    else
        g.setScissor()
    end
end

function Login:dibujarCasilla()
    local g = love.graphics
    local encima = self:encima('recordar')
    self:imagen(self.imagenes.casilla, D.casilla[1], D.casilla[2])
    local x, y = self:p(D.casilla[1], D.casilla[2])
    local lado = math.floor(25 * self.s + 0.5)
    if encima then
        color(COLORES.casilla, 0.18)
        g.rectangle('fill', x, y, lado, lado)
    end
    if self.recordar then
        local grueso = math.max(2, 3 * self.s)
        g.setLineWidth(grueso)
        g.setLineJoin('miter')
        color(COLORES.casilla)
        g.line(x + lado * 0.24, y + lado * 0.52, x + lado * 0.43, y + lado * 0.72, x + lado * 0.78, y + lado * 0.3)
        g.setLineWidth(1)
    end
    local claro = Tema.mezcla(COLORES.texto, COLORES.dorado, encima and 0.5 or 0)
    self:texto1('campo', TEXTOS.recordar, 1267, 594, claro)
end

function Login:dibujarEntrar()
    local g = love.graphics
    local encima = self:encima('entrar')
    local crece, hunde = Vida.boton('login:entrar', encima, self:pulsado('entrar'))
    -- Centro del cuerpo del botón: crece un poco con el ratón y se hunde al pulsar.
    local cx, cy = self:p(1517, 704)
    local escala = 1 + 0.012 * crece - 0.025 * hunde
    g.push()
    g.translate(cx, cy)
    g.scale(escala)
    g.translate(-cx, -cy)
    local oscuro = 1 - 0.14 * hunde
    local x, y = self:p(D.botonPrincipal[1], D.botonPrincipal[2])
    local k = self.s
    g.setColor(oscuro, oscuro, oscuro, 1)
    g.draw(self.imagenes.botonPrincipal, x, y, 0, k, k)
    if crece > 0.01 then
        local modo, alfaModo = g.getBlendMode()
        g.setBlendMode('add')
        g.setColor(1, 0.85, 0.5, 0.16 * crece)
        g.draw(self.imagenes.botonPrincipal, x, y, 0, k, k)
        g.setBlendMode(modo, alfaModo)
    end
    self:textoEspaciado('boton', TEXTOS.entrar, 1517, 704, COLORES.textoBoton, true)
    -- La flecha doble se adelanta un poco con el ratón.
    self:imagen(self.iconos.flechaDoble, D.iconoFlechaDoble[1] + 6 * crece, D.iconoFlechaDoble[2])
    g.pop()
end

--- Botón oscuro con icono y texto.
function Login:dibujarSecundario(nombre, icono, xIcono, yIcono, texto, xTexto, yTexto)
    local g = love.graphics
    local x, y, w, h = self:caja(CAJAS[nombre])
    local crece, hunde = Vida.boton('login:' .. nombre, self:encima(nombre), self:pulsado(nombre))
    local baja = math.floor(2 * self.s * hunde + 0.5)
    g.setColor(1, 1, 1, 1)
    self.cortes.botonSecundario:dibujar(x, y + baja, w, h, self.s)
    if crece > 0.01 then
        color(COLORES.texto, 0.05 * crece)
        g.rectangle('fill', x, y + baja, w, h)
        color(COLORES.dorado, 0.55 * crece)
        g.rectangle('line', x + 0.5, y + baja + 0.5, w - 1, h - 1)
    end
    local diseno = baja / self.s
    self:imagen(self.iconos[icono], xIcono, yIcono + diseno)
    local claro = Tema.mezcla(COLORES.texto, COLORES.dorado, 0.35 * crece)
    self:texto1('campo', texto, xTexto, yTexto + diseno, claro)
end

function Login:dibujarSeparador()
    local g = love.graphics
    local img = self.imagenes.separador
    for _, tramo in ipairs({ D.separadorIzquierda, D.separadorDerecha }) do
        local x, y = self:p(tramo[1], tramo[2])
        local fin = self:p(tramo[1] + tramo[3], 0)
        g.setColor(1, 1, 1, 1)
        g.draw(img, x, y, 0, fin - x, self.s)
    end
    self:texto1('campo', TEXTOS.o, 1516, 787, COLORES.texto, 'centro')
end

function Login:dibujarEnlaces()
    -- «¿Olvidaste la contraseña?», a la derecha.
    local mezcla = Vida.suave('login:olvido', self:encima('olvido') and 1 or 0, 14)
    local c = Tema.mezcla(COLORES.texto, COLORES.dorado, mezcla)
    local x, ancho = self:texto1('pequena', TEXTOS.olvido, 1790, 593, c, 'derecha')
    self:subrayar(x, ancho, 605, c)
    -- «Crear cuenta», con su icono y la flecha.
    mezcla = Vida.suave('login:crear', self:encima('crearCuenta') and 1 or 0, 14)
    c = Tema.mezcla(COLORES.texto, COLORES.dorado, mezcla)
    self:imagen(self.iconos.crearCuenta, D.iconoCrearCuenta[1], D.iconoCrearCuenta[2])
    x, ancho = self:texto1('pequena', TEXTOS.crearCuenta, 1440, 943, c)
    self:subrayar(x, ancho, 955, c)
    local fx = (x + ancho - self.ox) / self.s + 16 + 3 * mezcla
    love.graphics.setColor(c[1], c[2], c[3], 1)
    local px, py = self:p(fx, 937)
    love.graphics.draw(self.iconos.flecha, px, py, 0, self.s, self.s)
end

function Login:dibujarPanel()
    local img = self.imagenes
    Vida.entrar('login:panel', 0, math.floor(24 * self.s))
    self:imagen(img.panelSombra, D.panelSombra[1], D.panelSombra[2], 77 / 255)
    self:imagen(img.panel, D.panel[1], D.panel[2])
    self:imagen(img.emblemaPanel, D.emblemaPanel[1], D.emblemaPanel[2])
    self:textoEspaciado('titulo', TEXTOS.titulo, 1208, 276, COLORES.texto)
    self:textoEspaciado('lema', TEXTOS.lema, 1208, 324, COLORES.lema)
    self:dibujarCampo('usuario', 'correo', D.iconoCorreo[1], D.iconoCorreo[2], TEXTOS.usuario)
    self:dibujarCampo('clave', 'candado', D.iconoCandado[1], D.iconoCandado[2], TEXTOS.clave)
    -- El ojo: más claro con el ratón encima y dorado con la contraseña a la vista.
    local luzOjo = Vida.suave('login:ojo', self:encima('ojo') and 1 or 0, 14)
    local ojo = self.clave.mostrar and COLORES.dorado or { 1, 1, 1 }
    local ox, oy = self:p(D.iconoOjo[1], D.iconoOjo[2])
    love.graphics.setColor(ojo[1], ojo[2], ojo[3], 0.82 + 0.18 * luzOjo)
    love.graphics.draw(self.iconos.ojo, ox, oy, 0, self.s, self.s)
    self:dibujarCasilla()
    self:dibujarEntrar()
    self:dibujarSeparador()
    self:dibujarSecundario('invitado', 'invitado', D.iconoInvitado[1], D.iconoInvitado[2], TEXTOS.invitado, 1334, 860)
    self:dibujarSecundario('soporte', 'soporte', D.iconoSoporte[1], D.iconoSoporte[2], TEXTOS.soporte, 1648, 858)
    self:dibujarEnlaces()
    Vida.fin()
end

--- «Próximamente», bajo el panel: entra y sale con un fundido.
function Login:dibujarAviso()
    if not self.aviso then
        return
    end
    local g = love.graphics
    local alfa = 1
    if not Vida.quieta then
        local edad = love.timer.getTime() - self.aviso.inicio
        alfa = math.min(1, edad / 0.18, (DURACION_AVISO - edad) / 0.4)
        alfa = math.max(0, alfa)
    end
    local titulo = self:fuente('avisoTitulo')
    local detalle = self:fuente('avisoDetalle')
    local espacio = math.floor(14 * self.s)
    local relleno = math.floor(22 * self.s)
    local ancho = titulo:getWidth(TEXTOS.proximamente) + espacio + detalle:getWidth(TEXTOS.proximamenteDetalle)
    local w = ancho + relleno * 2
    local h = math.floor(48 * self.s)
    local cx, cy = self:p(1517, 1040)
    local x = math.floor(cx - w / 2)
    -- Que no se salga por la derecha de la pantalla.
    x = math.min(x, g.getWidth() - w - math.floor(8 * self.s))
    local y = math.floor(cy - h / 2) - math.floor(6 * self.s * (1 - alfa))
    g.setColor(1, 1, 1, alfa)
    self.cortes.botonSecundario:dibujar(x, y, w, h, self.s)
    color(COLORES.dorado, alfa)
    g.rectangle('fill', x, y, math.max(2, math.floor(4 * self.s)), h)
    local centro = y + h / 2
    g.setFont(titulo)
    color(COLORES.dorado, alfa)
    g.print(TEXTOS.proximamente, x + relleno, arribaDe(titulo, centro))
    g.setFont(detalle)
    color(COLORES.texto, alfa)
    local dx = x + relleno + titulo:getWidth(TEXTOS.proximamente) + espacio
    g.print(TEXTOS.proximamenteDetalle, dx, arribaDe(detalle, centro))
end

function Login:dibujar()
    Tema.actualizar()
    self:medir()
    self.fondo:dibujar(true)
    self:dibujarLogo()
    self:dibujarPanel()
    self:dibujarAviso()
    love.graphics.setColor(1, 1, 1, 1)
end

return Login
