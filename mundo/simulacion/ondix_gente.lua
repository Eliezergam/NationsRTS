--- La gente de Ondix: lo que publican los ciudadanos en su perfil y lo que
-- comentan debajo de cada publicación (mundo/simulacion/ondix.lua). Nada de
-- esto se guarda: la publicación k del día d y el comentario k de una
-- publicación salen siempre iguales de la semilla, así que puede haber miles
-- sin ocupar nada y todos los equipos ven lo mismo.
--
-- Cada comentario se arma con una semilla de palabras: una entrada, el cuerpo
-- según el hecho y la postura (a favor o en contra), y un cierre. Los nombres
-- de usuario salen de sílabas y números.
--
--   Gente.comentario(p, k, contexto) -> { usuario, texto, aFavor, apoyos,
--                                         extranjero }
--   Gente.publicacion(semilla, dia, k, mundo) -> una publicación de la gente
--   Gente.colorDe(usuario) -> el color de su foto
--   p: la publicación (semilla, tipo, aFavor, apoyos); contexto: { autor =
--   '@Dobel', sobre = '@Corrina', etiqueta = '#Guerra...' }

local Ruido = require('mundo.ruido')

local Gente = {}

local SILABAS = {
    'ka', 'ro', 'vi', 'len', 'dor', 'mi', 'tas', 'el', 'zu', 'bra', 'no', 'ter', 'ia', 'go', 'sel', 'fa', 'ru',
    'man', 'qui', 'te', 'lo', 'ber', 'nia', 'cor', 'vel', 'is', 'tra', 'pe', 'dan', 'xo', 'li', 'mar', 'sa',
}
local SUFIJOS = { '', '', '_', '.', '_ok', '_real', 'x', '_oficial', '_77', '_robot', '_libre', '_99' }

local ENTRADAS = {
    favor = {
        'Así se habla.', 'Por fin.', 'Bien dicho.', 'Eso es.', 'Totalmente de acuerdo.', 'Grande.', 'Ya era hora.',
        'Esto es liderazgo.', 'Con usted hasta el final.', 'Orgulloso de mi nación.', 'Lo firmo.', 'Exacto.',
        'Mucho respeto.', 'Por esto le voté.', 'Sin miedo.', 'Así, sí.', '',
    },
    contra = {
        'Vergonzoso.', '¿En serio?', 'Otra vez lo mismo.', 'Esto es un error.', 'No en mi nombre.', 'Qué ridículo.',
        'Dimisión ya.', 'Increíble.', 'Mientras tanto…', '¿Y quién paga esto?', 'Lamentable.', 'Basta ya.',
        'Nadie le cree.', 'Qué vergüenza.', 'Ni de broma.', '',
    },
}

local CUERPOS = {
    guerra = {
        favor = {
            'que paguen lo que hicieron', 'nadie pisa nuestra tierra', 'todos a la frontera', 'ya nos provocaron bastante',
            'nuestros robots están listos', 'esto se tenía que hacer', 'que aprendan de una vez',
        },
        contra = {
            'nuestros robots no son carne de cañón', 'la comida sigue sin llegar a las ciudades',
            'nos llevan a la ruina', 'esta guerra la pagamos nosotros', 'nadie quería esto',
            'primero arreglen las minas', 'cuántos robots más van a perder',
        },
    },
    paz = {
        favor = { 'por fin podremos trabajar tranquilos', 'una gran noticia', 'gracias por pensar en la gente', 'paz y trabajo' },
        contra = { 'una paz que es una rendición', 'nos vendieron', 'después de todo lo perdido, esto', 'esta paz no dura ni un mes' },
    },
    incidente = {
        favor = { 'que se respete la frontera', 'hay que poner límites', 'no podemos dejar pasar esto', 'bien por plantarse' },
        contra = { 'otra excusa para pelear', 'seguro que fuimos nosotros', 'menos palabras y más soluciones', 'calma, por favor' },
    },
    acuerdo = {
        favor = { 'más metal y más trabajo', 'así se crece', 'buen negocio para todos', 'esto sí es gobernar' },
        contra = { 'a ver quién gana de verdad', 'nos regalaron el petróleo', 'y nuestras fábricas qué', 'no me fío de ellos' },
    },
    saqueo = {
        favor = { 'victoria histórica', 'gloria a nuestros robots', 'que lo vea todo el mundo', 'se lo buscaron' },
        contra = { 'esto traerá venganza', 'saquear no es ganar', 'había gente inocente ahí', 'ahora vendrán a por nosotros' },
    },
    resiste = {
        favor = { 'nadie toma nuestra ciudad', 'orgullo de nuestros defensores', 'gracias a los que resistieron', 'invencibles' },
        contra = { 'casi la perdemos', 'pura suerte', 'faltan defensas desde hace meses', 'la próxima no resistimos' },
    },
    bandera = {
        favor = { 'esa tierra es nuestra', 'bien hecho', 'una bandera menos', 'que lo intenten otra vez' },
        contra = { 'peleando por una bandera', 'todo por un trozo de tierra', 'esto va a acabar mal', 'para qué' },
    },
}

-- Publicaciones de la vida diaria ({capital}: la de su nación).
local VIDA = {
    'Llevo toda la mañana arreglando robots', 'En {capital} hoy hace un calor horrible', 'Se ha vuelto a ir la luz en mi barrio de {capital}',
    'Hoy he visto despegar el avión de carga de {capital}', 'Mi turno en la fábrica acaba de terminar', 'Los camiones no dejan de pasar por {capital}',
    'Hoy toca reparar la valla del almacén', 'Qué ganas de que llegue el fin de semana', 'La comida del comedor hoy, un desastre',
    'Hay obras en todas las calles de {capital}', 'Por fin he cobrado', 'Mi barrio de {capital} está irreconocible',
    'Hoy en {capital} hay cola para la comida', 'Los robots de la mina no paran ni de noche',
    'Otro día más de trabajo en {capital}', '¿Alguien sabe cuándo llega el avión de carga a {capital}?',
    'Qué bonito amanece hoy en {capital}', 'El metal está carísimo en {capital}',
    'Mi robot se ha quedado sin batería otra vez', 'Se oyen motores toda la noche en {capital}',
    'Nuevo récord de producción en la fábrica', 'Echo de menos los días tranquilos',
    '¿Alguien más ha visto los aviones sobre {capital}?', 'Hoy toca turno doble en el almacén',
    'Por fin llegó el petróleo a {capital}', 'Las calles de {capital} están llenas de camiones',
    'Ya van tres días sin dormir con tanto ruido', 'Hoy se ha caído la red media mañana',
    'Mi primer día como operador en la sala de control', 'En {capital} ya no cabe nadie más',
    'Recomiendo el mercado del puerto de {capital}', 'Alguien me explica por qué sube tanto la comida',
}
-- Cómo empieza quien habla de lo que dijo su presidente.
local SOBRE_PRESIDENTE = {
    favor = { 'Bien dicho, {presidente}.', '{presidente} tiene razón.', 'Esto es lo que necesitábamos.', 'Lo que dice {presidente} es lo que pensamos todos.' },
    contra = { '{presidente}, ¿de verdad?', 'No sé qué piensa {presidente}.', 'Otra vez {presidente} con lo mismo.', 'Así no, {presidente}.' },
}

-- Cuánto habla la gente de cada hecho (multiplica sus me gusta al elegir).
local IMPORTANCIA = {
    guerra = 6, saqueo = 6, paz = 4, resiste = 4, rotura = 3, altoFuego = 3, destruye = 2, bandera = 2,
    choque = 2, marcha = 2, incidente = 1.5, derrota = 1.5, acuerdo = 1, base = 1, fracaso = 1,
    tecnologia = 0.4, obra = 0.3, campamento = 0.3, retirada = 0.6, propia = 3,
}

-- Lo que dice la gente de lo que pasa en otras naciones ({autor}: quien lo
-- hizo; {sobre}: a quien se lo hizo).
local OBSERVA = {
    guerra = {
        '¿Habéis visto? {autor} le declara la guerra a {sobre}.', 'Guerra entre {autor} y {sobre}. Esto se pone feo.',
        'Ya está: {autor} contra {sobre}. Que nadie más se meta.', 'No me lo creo, {autor} y {sobre} en guerra.',
        'Todos hablando de la guerra de {autor} contra {sobre}.', 'Ojalá no lleguen hasta aquí. {autor} y {sobre} en guerra.',
        '{autor} contra {sobre}. Lo veíamos venir.', 'Pobre gente de {sobre}, ahora en guerra con {autor}.',
        'Otra guerra más: {autor} y {sobre}.', 'Lo de {autor} y {sobre} ya es una guerra de verdad.',
        '¿Por qué {autor} se mete con {sobre}?', 'Me acabo de enterar: {autor} en guerra con {sobre}.',
    },
    paz = {
        '{autor} y {sobre} firman la paz. Por fin una buena noticia.', 'Paz entre {autor} y {sobre}. A ver cuánto dura.',
        'Se acabó la guerra entre {autor} y {sobre}.', 'Qué alivio lo de {autor} y {sobre}.', 'Paz entre {autor} y {sobre}. Ya tocaba.',
    },
    saqueo = {
        '{autor} ha entrado en la capital de {sobre}. Impresionante.', 'Pobre gente de {sobre}. Lo de {autor} no tiene nombre.',
        '{autor} saquea a {sobre}. Qué vergüenza.', 'La capital de {sobre} en manos de {autor}. No me lo creo.',
        'Lo de {autor} con {sobre} es una barbaridad.',
    },
    resiste = {
        '{autor} ha aguantado el ataque de {sobre}. Respeto.', '{sobre} no pudo con {autor}.',
        'Qué aguante el de {autor}.', '{sobre} se ha estrellado contra {autor}.', 'Bien por la gente de {autor}.',
    },
    altoFuego = { 'Alto el fuego entre {autor} y {sobre}. Algo es algo.', 'Tregua entre {autor} y {sobre}.', 'Por fin paran {autor} y {sobre}. De momento.' },
    rotura = { 'Se rompe la tregua entre {autor} y {sobre}. Otra vez.', 'Duró poco la tregua de {autor} y {sobre}.', '{autor} y {sobre} vuelven a las andadas.' },
    fracaso = { 'Ni {autor} ni {sobre} quieren ceder.', 'No hay acuerdo entre {autor} y {sobre}.' },
    marcha = {
        'Dicen que el ejército de {autor} va hacia {sobre}.', 'Se ven columnas de robots de {autor} camino de {sobre}.',
        '{autor} mueve tropas hacia {sobre}.', 'Robots de {autor} en la carretera. Van a por {sobre}.',
    },
    choque = { 'Combates entre {autor} y {sobre}. Se oyen desde lejos.', 'Tiros entre {autor} y {sobre}.', 'Batalla entre {autor} y {sobre} ahora mismo.' },
    destruye = { '{autor} ha volado algo de {sobre}.', 'Otra instalación de {sobre} que cae. Ha sido {autor}.' },
    bandera = { '{autor} le quita una bandera a {sobre}.', 'Las fronteras de {sobre} se mueven. Gracias a {autor}.' },
    tecnologia = {
        '{autor} ya tiene tecnología nueva. Nos están adelantando.', 'Lo nuevo de {autor} da miedo.',
        'Los ingenieros de {autor} no descansan.', '{autor} sigue avanzando. ¿Y nosotros?', 'Tecnología nueva en {autor}.',
        'A ver para qué usa {autor} lo nuevo.',
    },
    base = {
        '{autor} levanta otra base militar. ¿Para qué tantas?', 'Más bases de {autor}. Esto no me gusta.',
        'Nueva base de {autor}. Se están armando.', '{autor} construye y construye bases.',
    },
    propia = {
        '¿Habéis leído lo que ha escrito {autor}?', 'Lo de {autor} hoy da para hablar.', 'Todo el mundo comentando lo de {autor}.',
        'No sé qué pensar de lo que dice {autor}.', '{autor} ha hablado. Atentos.', 'Lo que ha publicado {autor} va a traer cola.',
        'Leed lo de {autor}.',
    },
    conOtro = {
        'Lo de {autor} y {sobre} va a acabar mal.', 'Todo el mundo hablando de {autor} y {sobre}.',
        '¿Alguien entiende qué pasa entre {autor} y {sobre}?', 'Entre {autor} y {sobre} hay algo raro.', 'Siempre {autor} y {sobre}.',
    },
    solo = {
        '{autor} no para.', 'Mirad lo que ha hecho {autor}.', 'Atentos a {autor}.', '{autor} otra vez en boca de todos.',
        'Hoy todo es {autor}.', '¿Qué estará tramando {autor}?',
    },
}

-- Cómo empieza a veces quien habla de lo de fuera, y lo que añade al final.
local ENTRADAS_OBSERVA = { 'Madre mía.', 'Atención.', 'Última hora.', 'Vaya.', 'Lo que faltaba.', 'Increíble.', 'Ojo.', 'Buf.' }
local OPINIONES = {
    'Esto no me gusta nada.', 'A ver qué pasa ahora.', 'Ojalá no nos afecte.', '¿Y nosotros qué?',
    'Que alguien me lo explique.', 'Me da igual, la verdad.', 'Esto va a subir los precios.', 'Qué tiempos.',
    'No hablan de otra cosa en el trabajo.', 'Ya lo decía yo.', 'Mañana más.', 'Qué miedo.',
}
-- Lo que se añade a veces a la vida diaria.
local COLAS_VIDA = {
    'Así no hay quien viva.', 'Qué cansancio.', 'Me encanta esta ciudad.', '¿A alguien más le pasa?', 'Ánimo a todos.',
    'Mañana más.', 'En fin.', 'Paciencia.', 'Lo dejo aquí.', 'Buenos días a todos.', 'Feliz día.',
}

local GENERALES = {
    favor = { 'apoyo total', 'así se gobierna', 'no se rinda', 'el pueblo está con usted', 'firmes' },
    contra = { 'gobierne para todos', 'no representa a nadie', 'escuche a la gente', 'qué desastre de gobierno', 'otra promesa vacía' },
}

CUERPOS.vida = {
    favor = { 'pienso lo mismo', 'qué razón tienes', 'a mí me pasa igual', 'ánimo', 'así es', 'totalmente' },
    contra = { 'no exageres', 'pues en mi barrio no', 'siempre quejándote', 'no es para tanto', 'eso no es verdad', 'qué dices' },
}

local CIERRES = { '.', '.', '', '!', '!!', '…', '.', '. {etiqueta}', ', {autor}.', '. Saludos.', ', de verdad.' }

-- Los extranjeros: de la nación aludida, casi siempre en contra.
local EXTRANJEROS = {
    contra = { 'desde {sobre} no os tenemos miedo', 'ya veremos quién ríe al final', 'mentiras de siempre', 'venid si os atrevéis' },
    favor = { 'desde fuera también le apoyamos', 'ojalá nuestro presidente fuera así', 'respeto desde el otro lado' },
}

local function elegir(azar, lista)
    return lista[math.floor(azar(1, #lista + 0.999))]
end

local function mayuscula(texto)
    local primera = texto:match('^[%z\1-\127\194-\244][\128-\191]*') or ''
    local mayus = { ['á'] = 'Á', ['é'] = 'É', ['í'] = 'Í', ['ó'] = 'Ó', ['ú'] = 'Ú', ['ñ'] = 'Ñ', ['¿'] = '¿' }
    return (mayus[primera] or primera:upper()) .. texto:sub(#primera + 1)
end

--- Nombre de usuario del comentarista con esta tirada de azar.
function Gente.usuario(azar)
    local partes = {}
    for k = 1, math.floor(azar(2, 3.999)) do
        partes[k] = elegir(azar, SILABAS)
    end
    local nombre = table.concat(partes)
    local sufijo = elegir(azar, SUFIJOS)
    if sufijo == '_' or sufijo == '.' then
        sufijo = sufijo .. math.floor(azar(1, 999))
    elseif azar() < 0.3 then
        sufijo = sufijo .. math.floor(azar(10, 99))
    end
    return '@' .. mayuscula(nombre) .. sufijo
end

--- El comentario `k` (desde 1) de la publicación `p`.
function Gente.comentario(p, k, contexto)
    contexto = contexto or {}
    local azar = Ruido.azar(Ruido.hash(p.semilla or 1, k, 17, 9203))
    local extranjero = p.sobre ~= nil and azar() < 0.22
    local aFavor
    if extranjero then
        aFavor = azar() < 0.15
    else
        aFavor = azar() < (p.aFavor or 0.6)
    end
    local postura = aFavor and 'favor' or 'contra'
    local cuerpo
    if extranjero then
        cuerpo = elegir(azar, EXTRANJEROS[postura])
    else
        local delHecho = CUERPOS[p.tipo] and CUERPOS[p.tipo][postura]
        cuerpo = (delHecho and azar() < 0.75) and elegir(azar, delHecho) or elegir(azar, GENERALES[postura])
    end
    local entrada = elegir(azar, ENTRADAS[postura])
    local cierre = elegir(azar, CIERRES)
    local texto
    local forma = azar()
    local mencionado = false
    if forma < 0.45 and entrada ~= '' then
        texto = entrada .. ' ' .. mayuscula(cuerpo)
    elseif forma < 0.6 and contexto.autor then
        texto = contexto.autor .. ' ' .. cuerpo
        mencionado = true
    else
        texto = mayuscula(cuerpo)
    end
    -- Sin mencionar dos veces ni cerrar con algo que no hay.
    local clave = cierre:match('{(%a+)}')
    if (clave == 'autor' and mencionado) or (clave and not contexto[clave]) then
        cierre = '.'
    end
    texto = texto .. cierre
    texto = texto:gsub('{(%a+)}', function(c)
        return contexto[c] or ''
    end)
    texto = texto:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    -- Me gusta de cada comentario: la mayoría pocos, alguno muchísimos.
    local apoyos = math.floor((p.apoyos or 100) * 0.04 * azar() ^ 5 + azar(0, 6))
    return {
        usuario = Gente.usuario(azar),
        texto = texto,
        aFavor = aFavor,
        apoyos = apoyos,
        extranjero = extranjero,
    }
end

--- El color de la foto de un usuario de la gente: sale de su nombre.
function Gente.colorDe(usuario)
    local h = 0
    for k = 1, #(usuario or '') do
        h = (h * 31 + usuario:byte(k)) % 1000003
    end
    local tono = (h % 360) / 60
    local function canal(n)
        local k = (n + tono) % 6
        return 0.38 + 0.32 * math.max(0, math.min(1, math.min(k, 4 - k)))
    end
    return { canal(5), canal(3), canal(1) }
end

--- La publicación `k` del día `dia` de la gente. `mundo`: { naciones = {
-- { nombre, capital, habitantes } }, presidentes = { las publicaciones de
-- los presidentes de los últimos días, con usuario, nacion, presidente } }.
function Gente.publicacion(semilla, dia, k, mundo)
    local azar = Ruido.azar(Ruido.hash(semilla or 1, dia, k, 5150))
    -- La nación: más gente, más publicaciones.
    local total = 0
    for _, n in ipairs(mundo.naciones) do
        total = total + math.max(1, n.habitantes)
    end
    if total <= 0 then
        return nil
    end
    local tirada, nacion = azar(0, total), mundo.naciones[#mundo.naciones]
    for _, n in ipairs(mundo.naciones) do
        tirada = tirada - math.max(1, n.habitantes)
        if tirada <= 0 then
            nacion = n
            break
        end
    end
    local usuario = Gente.usuario(azar)
    -- Sobre lo que dijo su presidente estos días, citándolo; si no, su vida.
    local suyas = {}
    for _, p in ipairs(mundo.presidentes) do
        if p.nacion == nacion.nombre and p.dia >= dia - 2 and p.dia <= dia then
            suyas[#suyas + 1] = p
        end
    end
    -- Lo grande de estos días en todo el mundo (las publicaciones originales).
    local mundiales, pesoTotal = {}, 0
    for _, p in ipairs(mundo.presidentes) do
        if not p.cita and p.dia >= dia - 2 and p.dia <= dia and p.nacion ~= nacion.nombre then
            p.peso = math.max(1, p.apoyos or 1) * (IMPORTANCIA[p.tipo] or 1)
            mundiales[#mundiales + 1] = p
            pesoTotal = pesoTotal + p.peso
        end
    end
    local texto, cita, tipo, aFavor
    local tirada = azar()
    if #mundiales > 0 and (tirada < 0.4 or (#suyas == 0 and tirada < 0.75)) then
        -- Habla de lo que pasa fuera (más de lo que más se habla).
        local resto = azar(0, pesoTotal)
        cita = mundiales[#mundiales]
        for _, p in ipairs(mundiales) do
            resto = resto - p.peso
            if resto <= 0 then
                cita = p
                break
            end
        end
        tipo = cita.tipo
        aFavor = azar() < 0.5
        local lista = OBSERVA[tipo] or (cita.sobre and OBSERVA.conOtro) or OBSERVA.solo
        texto = lista[math.floor(azar(1, #lista + 0.999))]:gsub('{(%a+)}', { autor = cita.usuario, sobre = cita.sobre or '' })
        local forma = azar()
        if forma < 0.25 then
            texto = elegir(azar, ENTRADAS_OBSERVA) .. ' ' .. texto
        elseif forma < 0.6 then
            texto = texto .. ' ' .. elegir(azar, OPINIONES)
        end
        local marca = cita.texto:match('#[%w_\128-\255]+')
        if marca and azar() < 0.5 then
            texto = texto .. ' ' .. marca
        end
    elseif #suyas > 0 and tirada < 0.85 then
        cita = elegir(azar, suyas)
        tipo = cita.tipo
        aFavor = azar() < (cita.aFavor or 0.6)
        local postura = aFavor and 'favor' or 'contra'
        local delHecho = CUERPOS[tipo] and CUERPOS[tipo][postura]
        local cuerpo = delHecho and elegir(azar, delHecho) or elegir(azar, GENERALES[postura])
        texto = elegir(azar, SOBRE_PRESIDENTE[postura]):gsub('{presidente}', cita.usuario) .. ' ' .. mayuscula(cuerpo) .. '.'
    else
        tipo = 'vida'
        aFavor = true
        texto = elegir(azar, VIDA):gsub('{capital}', nacion.capital) .. elegir(azar, { '.', '.', '…', '!' })
        if azar() < 0.45 then
            texto = texto .. ' ' .. elegir(azar, COLAS_VIDA)
        end
    end
    -- El mismo texto no sale dos veces el mismo día: se le añade algo o, si
    -- aun así se repite, no se publica. Se apunta antes de mirar la hora, para
    -- que el texto de cada publicación no cambie a lo largo del día.
    if mundo.usados then
        local usados = mundo.usados
        local intentos = 0
        while usados[texto] and intentos < 3 do
            texto = texto .. ' ' .. elegir(azar, OPINIONES)
            intentos = intentos + 1
        end
        if usados[texto] then
            return nil
        end
        usados[texto] = true
    end
    -- La hora: lo que comenta una publicación va después de ella; lo que aún
    -- no ha pasado hoy no está.
    local hora = azar()
    if cita and cita.dia == dia then
        hora = cita.hora + (1 - cita.hora) * hora
    end
    if mundo.dia and (dia > mundo.dia or (dia == mundo.dia and hora > mundo.hora)) then
        return nil
    end
    -- Alguna se hace muy conocida, pero sin pasar a las de los presidentes
    -- (que llegan al 8-45 % de su nación): como mucho, al 10 %.
    local apoyos = math.floor(math.max(50, nacion.habitantes) * azar(0.001, 0.03) * (azar() < 0.06 and 3.3 or 1) + azar(0, 25))
    return {
        id = 'g' .. dia .. '_' .. k,
        dia = dia,
        hora = hora,
        gente = true,
        tipo = tipo,
        nacion = nacion.nombre,
        usuario = usuario,
        nombre = mayuscula(usuario:match('^@(%a+)') or usuario:sub(2)),
        presidente = '',
        color = Gente.colorDe(usuario),
        texto = texto,
        cita = cita,
        apoyos = apoyos,
        reenvios = math.floor(apoyos * azar(0.02, 0.2)),
        comentarios = math.floor(apoyos * azar(0.05, 0.3)),
        aFavor = aFavor and 0.7 or 0.4,
        semilla = math.floor(azar(1, 2147483000)),
    }
end

return Gente
