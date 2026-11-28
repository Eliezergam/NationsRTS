--- Ondix: la red social del mundo del juego (el dueño, 26-nov). Cada
-- presidente tiene su perfil y publica por lo que pasa en la partida. Nunca
-- contestan debajo de la publicación de otro: cada uno publica en su perfil
-- citando lo que dijo el otro y mencionándolo. Debajo comenta la gente, a
-- favor y en contra (los comentarios se generan al leerlos, desde la semilla:
-- mundo/ondix/gente.lua). Se lee en el navegador de los PC (ondix.red).
--
-- Un hecho (`Simulacion:hecho(tipo, a, b)`: a es quien lo hace, b a quien se
-- lo hacen) dispara:
--   1. la publicación de `a` (siempre en los hechos grandes);
--   2. la de `b`, que cita la de `a` y lo menciona (más probable cuanto más
--      agresivo es su presidente);
--   3. hasta dos aliados de cada lado que también la citan.
-- El presidente del jugador habla solo hasta que el jugador publique por su
-- cuenta (orden 'publicarOndix'); desde entonces solo publica lo que escribe
-- él, y los demás presidentes le contestan citándolo.
--
-- Alcance: los me gusta, reenvíos y comentarios salen de la población de la
-- nación (miles en una nación grande) y crecen los primeros días hasta su
-- total (`Ondix.alcanceEn`). `aFavor` (0 a 1): la parte de la gente que lo
-- apoya, según el hecho y el carácter de quien publica.
--
-- Todo con el azar de la partida (Ruido.hash con la semilla y un contador):
-- la misma partida da las mismas publicaciones en cualquier equipo.
--
-- Estado: e.ondix = { publicaciones = { { id, dia, autor, texto, tipo, sobre,
-- cita, apoyos, reenvios, comentarios, aFavor, semilla } } (la más nueva
-- primero), siguiente }.

local Ruido = require('mundo.ruido')

local Simulacion -- se pone en instalar

local Ondix = {}

Ondix.maximo = 200 -- publicaciones que se guardan

-- Frases por hecho, papel y tono. {otro}: el @ de la otra nación; {yo}: el
-- nombre de la propia; {tema}: la etiqueta del hecho.
local FRASES = {
    guerra = {
        autor = {
            agresivo = {
                '{otro} se lo ha buscado. Desde hoy estamos en guerra. No habrá piedad. {tema}',
                'Se acabó la paciencia con {otro}. Nuestros robots ya están en marcha. {tema}',
                'Hoy {yo} declara la guerra a {otro}. Que tiemblen. {tema}',
            },
            burlon = {
                '{otro} pidió atención y hoy la tiene: guerra. Ya nos lo agradecerán. {tema}',
                'Nota para {otro}: a partir de hoy, guerra. Preparad las excusas. {tema}',
            },
            diplomatico = {
                'Con pesar, {yo} entra en guerra con {otro}. Agotamos todas las vías. {tema}',
                'No queríamos llegar aquí, pero {otro} no nos deja otra opción. {tema}',
            },
            orgulloso = {
                '{yo} no se deja pisar. Guerra contra {otro}. {tema}',
                'Defenderemos lo nuestro. Desde hoy, guerra con {otro}. {tema}',
            },
        },
        respuesta = {
            agresivo = { 'Que vengan. Los esperamos en la frontera.', 'Gran error. Lo vais a pagar caro.' },
            burlon = { '¿Eso es todo? Llevamos semanas esperándolo.', 'Qué valientes. A ver cuánto duran.' },
            diplomatico = { 'Lamentamos esta decisión. Nuestras puertas siguen abiertas a la paz.', 'Pedimos calma. Aún hay tiempo para hablar.' },
            orgulloso = { 'Ningún robot nuestro dará un paso atrás.', 'Nos defenderemos hasta el último tornillo.' },
        },
        aliadoAutor = { 'Todo nuestro apoyo a {amigo}. {tema}', 'Con {amigo}, hasta el final.' },
        aliadoOtro = { '{amigo} no está sola. {tema}', 'Quien ataca a {amigo} nos ataca a todos.' },
    },
    paz = {
        autor = {
            agresivo = { 'Firmamos la paz con {otro}. Que no se repita. {tema}' },
            burlon = { 'Paz con {otro}. Ya se les habían acabado los robots, de todas formas. {tema}' },
            diplomatico = { 'Hoy es un buen día: paz con {otro}. Gracias a todos. {tema}' },
            orgulloso = { 'Paz con {otro}, con la cabeza alta. {tema}' },
        },
        respuesta = {
            agresivo = { 'Paz, por ahora.' },
            burlon = { 'Paz, sí. Tomad nota de quién la pidió.' },
            diplomatico = { 'Nos alegra cerrar este capítulo.' },
            orgulloso = { 'Firmamos sin rendirnos.' },
        },
        aliadoAutor = { 'Celebramos la paz entre {amigo} y {otro}.' },
        aliadoOtro = { 'Una buena noticia para {amigo}.' },
    },
    incidente = {
        autor = {
            agresivo = { 'Otro incidente en la frontera con {otro}. Estamos perdiendo la paciencia. {tema}' },
            burlon = { '{otro} vuelve a perderse en nuestra frontera. ¿Necesitan un mapa? {tema}' },
            diplomatico = { 'Pedimos explicaciones a {otro} por lo ocurrido en la frontera. {tema}' },
            orgulloso = { 'Nadie cruza nuestra frontera sin permiso. {otro}, quedáis avisados. {tema}' },
        },
        respuesta = {
            agresivo = { 'Fueron ellos los que provocaron.' },
            burlon = { 'Qué sensibles.' },
            diplomatico = { 'Investigaremos lo ocurrido.' },
            orgulloso = { 'Estábamos en nuestra tierra.' },
        },
        aliadoAutor = { 'Inaceptable lo de la frontera de {amigo}.' },
        aliadoOtro = { 'Apoyamos la versión de {amigo}.' },
    },
    acuerdo = {
        autor = {
            agresivo = { 'Acuerdo comercial con {otro}. Más metal para lo que viene. {tema}' },
            burlon = { 'Hemos hecho negocios con {otro}. Han salido ganando… casi tanto como nosotros. {tema}' },
            diplomatico = { 'Firmamos un acuerdo comercial con {otro}. El comercio nos une. {tema}' },
            orgulloso = { 'Acuerdo con {otro}: {yo} sigue creciendo. {tema}' },
        },
        respuesta = {
            agresivo = { 'Que se cumpla.' },
            burlon = { 'Ya veremos quién sale ganando.' },
            diplomatico = { 'Un placer trabajar juntos.' },
            orgulloso = { 'Un acuerdo justo.' },
        },
        aliadoAutor = { 'Buen negocio de {amigo}.' },
        aliadoOtro = { 'Bien hecho, {amigo}.' },
    },
    saqueo = {
        autor = {
            agresivo = { 'Hemos entrado en la capital de {otro}. Esto es lo que pasa cuando nos provocan. {tema}' },
            burlon = { 'Visita a la capital de {otro}. Nos llevamos un recuerdo. Bastantes, en realidad. {tema}' },
            diplomatico = { 'Nuestros robots han tomado la capital de {otro}. Pedimos que se rindan. {tema}' },
            orgulloso = { 'La capital de {otro} ha caído. {yo} vence. {tema}' },
        },
        respuesta = {
            agresivo = { 'Esto no acaba aquí. Volveremos.', 'Lo pagaréis.' },
            burlon = { 'Disfrutadlo mientras dure.' },
            diplomatico = { 'Pedimos un alto el fuego inmediato.' },
            orgulloso = { 'Nos levantaremos. Siempre lo hacemos.' },
        },
        aliadoAutor = { 'Gran victoria de {amigo}. {tema}' },
        aliadoOtro = { 'Fuerza, {amigo}. Estamos con vosotros.' },
    },
    resiste = {
        autor = {
            agresivo = { '{otro} lo ha intentado y ha fallado. Nuestra ciudad sigue en pie. {tema}' },
            burlon = { '{otro} vino a por nuestra ciudad y se fue sin ella. Otra vez será. {tema}' },
            diplomatico = { 'Hemos resistido el ataque de {otro}. Gracias a nuestros robots. {tema}' },
            orgulloso = { 'Nadie toma una ciudad de {yo}. {otro}, ya lo sabéis. {tema}' },
        },
        respuesta = {
            agresivo = { 'Solo era el primer intento.' },
            burlon = { 'Era un ensayo.' },
            diplomatico = { 'Reorganizamos nuestras fuerzas.' },
            orgulloso = { 'Volveremos más fuertes.' },
        },
        aliadoAutor = { 'Bien resistido, {amigo}.' },
        aliadoOtro = { 'Ánimo, {amigo}.' },
    },
    bandera = {
        autor = {
            agresivo = { 'Hemos arrancado la bandera de {otro}. Esa tierra es nuestra. {tema}' },
            burlon = { 'A {otro} se le ha caído una bandera. No hace falta que la busquen. {tema}' },
            diplomatico = { 'Recuperamos tierra que {otro} había ocupado. {tema}' },
            orgulloso = { 'Una bandera menos de {otro} en nuestro camino. {tema}' },
        },
        respuesta = {
            agresivo = { 'Plantaremos dos por cada una que arranquéis.' },
            burlon = { 'Teníamos más.' },
            diplomatico = { 'Protestamos por esta agresión.' },
            orgulloso = { 'Esa tierra seguirá siendo nuestra.' },
        },
        aliadoAutor = { 'Bien hecho, {amigo}.' },
        aliadoOtro = { 'Inaceptable, {amigo} tiene todo nuestro apoyo.' },
    },
    altoFuego = {
        autor = {
            agresivo = { 'Alto el fuego con {otro}. Solo una pausa. {tema}' },
            burlon = { '{otro} pidió un respiro y se lo damos. Somos así de generosos. {tema}' },
            diplomatico = { 'Acordamos un alto el fuego con {otro}. Un primer paso. {tema}' },
            orgulloso = { 'Alto el fuego con {otro}, sin ceder nada. {tema}' },
        },
        respuesta = {
            agresivo = { 'Que no se confíen.' }, burlon = { 'Ya veremos cuánto dura.' },
            diplomatico = { 'Respetaremos el acuerdo.' }, orgulloso = { 'Lo aceptamos con dignidad.' },
        },
        aliadoAutor = { 'Bien por {amigo}. Que dure.' }, aliadoOtro = { 'Ojalá sea el fin, {amigo}.' },
    },
    fracaso = {
        autor = {
            agresivo = { 'Hablar con {otro} es perder el tiempo. {tema}' },
            burlon = { 'Intentamos hablar con {otro}. Ellos no saben. {tema}' },
            diplomatico = { 'No hubo acuerdo con {otro}. Seguiremos intentándolo. {tema}' },
            orgulloso = { 'No firmaremos lo que pide {otro}. {tema}' },
        },
        respuesta = {
            agresivo = { 'Ellos se lo pierden.' }, burlon = { 'Qué sorpresa.' },
            diplomatico = { 'La puerta sigue abierta.' }, orgulloso = { 'No aceptaremos imposiciones.' },
        },
        aliadoAutor = { 'Con {amigo}, pase lo que pase.' }, aliadoOtro = { '{amigo} hizo lo que pudo.' },
    },
    rotura = {
        autor = {
            agresivo = { '{otro} rompió el alto el fuego. Ahora sí, sin contemplaciones. {tema}' },
            burlon = { 'Duró poco la paciencia con {otro}. Como su palabra. {tema}' },
            diplomatico = { 'Lamentamos que el alto el fuego con {otro} se haya roto. {tema}' },
            orgulloso = { 'Se acabó la tregua con {otro}. {yo} vuelve al frente. {tema}' },
        },
        respuesta = {
            agresivo = { 'Estábamos esperando.' }, burlon = { 'Como si no lo supiéramos.' },
            diplomatico = { 'No fuimos nosotros.' }, orgulloso = { 'Que la historia juzgue.' },
        },
        aliadoAutor = { '{amigo} tiene nuestro apoyo.' }, aliadoOtro = { 'Fuerza, {amigo}.' },
    },
    marcha = {
        autor = {
            agresivo = { 'Nuestro ejército ya va a por {otro}. {tema}', 'En marcha. {otro}, preparaos. {tema}', '{otro}, ya vamos. {tema}', 'Nuestro ejército avanza hacia {otro}. Sin pausa. {tema}' },
            burlon = { 'Vamos de visita a casa de {otro}. Sin avisar. {tema}', '{otro}, poned la mesa, que llegamos. {tema}', 'Excursión de robots hacia {otro}. {tema}' },
            diplomatico = { 'Movemos tropas hacia {otro} para proteger lo nuestro. {tema}', 'Nuestras tropas se mueven para proteger lo nuestro de {otro}. {tema}', 'Avanzamos hacia {otro}. No buscamos esto, pero no huimos. {tema}' },
            orgulloso = { 'Nuestros robots marchan contra {otro}. {tema}', '{yo} marcha contra {otro}. {tema}', 'Nuestros robots van a por {otro}. {tema}' },
        },
        respuesta = {
            agresivo = { 'Os estamos esperando.' }, burlon = { 'Traed repuestos.' },
            diplomatico = { 'Pedimos que se detengan.' }, orgulloso = { 'No pasarán.' },
        },
        aliadoAutor = { 'Adelante, {amigo}.' }, aliadoOtro = { 'Cuidado, {amigo}. Estamos atentos.' },
    },
    choque = {
        autor = {
            agresivo = { 'Ya estamos peleando con {otro}. No retrocedemos. {tema}', 'Combate abierto con {otro}. Vamos a ganar. {tema}' },
            burlon = { '{otro} se ha cruzado en nuestro camino. Mala idea. {tema}', '{otro} quería pelea. Ya la tiene. {tema}' },
            diplomatico = { 'Combates con {otro}. Pedimos que acaben pronto. {tema}', 'Nuestros robots se defienden de {otro}. {tema}' },
            orgulloso = { 'Nuestro ejército se enfrenta a {otro}. {tema}', 'Nuestro ejército lucha contra {otro} con honor. {tema}' },
        },
        respuesta = {
            agresivo = { 'Vais a caer.' }, burlon = { 'Esto va a ser rápido.' },
            diplomatico = { 'Nos defendemos.' }, orgulloso = { 'Resistiremos.' },
        },
        aliadoAutor = { 'Ánimo, {amigo}.' }, aliadoOtro = { 'Aguanta, {amigo}.' },
    },
    asedio = {
        autor = {
            agresivo = { 'Atacamos la bandera de {otro}. Caerá en días. {tema}' },
            burlon = { 'A la bandera de {otro} le queda poco. Como a {otro}. {tema}' },
            diplomatico = { 'Recuperamos posiciones frente a {otro}. {tema}' },
            orgulloso = { 'La bandera de {otro} no aguantará. {tema}' },
        },
        respuesta = {
            agresivo = { 'Esa bandera no se toca.' }, burlon = { 'Suerte con eso.' },
            diplomatico = { 'Pedimos que cesen.' }, orgulloso = { 'La defenderemos.' },
        },
        aliadoAutor = { 'Bien, {amigo}.' }, aliadoOtro = { 'Aguanta, {amigo}.' },
    },
    destruye = {
        autor = {
            agresivo = { 'Hemos destruido una instalación de {otro}. Seguiremos. {tema}' },
            burlon = { '{otro} tenía algo ahí. Tenía. {tema}' },
            diplomatico = { 'Hemos neutralizado una amenaza de {otro}. {tema}' },
            orgulloso = { 'Otra instalación de {otro} que cae. {tema}' },
        },
        respuesta = {
            agresivo = { 'Lo vais a pagar.' }, burlon = { 'La teníamos de adorno.' },
            diplomatico = { 'Condenamos este ataque.' }, orgulloso = { 'La reconstruiremos.' },
        },
        aliadoAutor = { 'Bien, {amigo}.' }, aliadoOtro = { 'Indignante lo que le hacen a {amigo}.' },
    },
    derrota = {
        autor = {
            agresivo = { 'Hemos perdido un ejército. Volveremos el doble de fuertes. {tema}', 'Hoy caímos. Mañana caen ellos. {tema}' },
            burlon = { 'Hoy no ha sido nuestro día. Mañana será el suyo. {tema}', 'Mal día. Ya nos tocará reír a nosotros. {tema}' },
            diplomatico = { 'Honor a los robots que cayeron hoy. {tema}', 'Lamentamos la pérdida de nuestro ejército. {tema}' },
            orgulloso = { 'Caímos de pie. {yo} no se rinde. {tema}', 'Perdimos un ejército, no el orgullo. {tema}' },
        },
    },
    retirada = {
        autor = {
            agresivo = { 'Retirada táctica. Esto no ha acabado. {tema}', 'Volvemos a cargar. Esto no se olvida. {tema}' },
            burlon = { 'Volvemos a casa a por más munición. Ya volveremos. {tema}', 'Media vuelta. Ya volveremos con más ganas. {tema}' },
            diplomatico = { 'Retiramos a nuestros robots para salvarlos. {tema}', 'Retiramos a nuestros robots. Primero, su seguridad. {tema}' },
            orgulloso = { 'Nos retiramos con orden y con la cabeza alta. {tema}', 'Una retirada no es una derrota. {tema}' },
        },
    },
    tecnologia = {
        autor = {
            agresivo = { '{yo} desarrolla {cosa}. Que tomen nota. {tema}', 'Ya tenemos {cosa}. Que se preparen. {tema}', '{cosa}. Un motivo más para no meterse con {yo}. {tema}' },
            burlon = { 'Ya tenemos {cosa}. Los demás, aún buscando las instrucciones. {tema}', '{cosa}, listo. ¿Alguien más? ¿No? Vale. {tema}', 'Estrenamos {cosa}. Los demás, mirando. {tema}' },
            diplomatico = { 'Orgullosos de nuestros ingenieros: {cosa}. {tema}', '{cosa}: un avance para todos en {yo}. {tema}', 'Seguimos invirtiendo en ciencia: {cosa}. {tema}' },
            orgulloso = { '{cosa}: {yo} sigue avanzando. {tema}', '{yo} lo ha vuelto a hacer: {cosa}. {tema}', 'Nuestros ingenieros, los mejores: {cosa}. {tema}' },
        },
    },
    base = {
        autor = {
            agresivo = { 'Empezamos una base militar. Para quien la necesite saber. {tema}', 'Una base más. Que tomen nota. {tema}', 'Nueva base militar de {yo}. Para quien se atreva. {tema}' },
            burlon = { 'Una base nueva. Por si acaso, ya sabéis. {tema}', 'Otra base. Coleccionamos. {tema}', 'Base nueva. Que no cunda el pánico. Bueno, un poco. {tema}' },
            diplomatico = { 'Levantamos una base para defender nuestra tierra. {tema}', 'Una base para la defensa, nunca para atacar. {tema}', 'Reforzamos la defensa de nuestra tierra. {tema}' },
            orgulloso = { '{yo} levanta una base militar. {tema}', '{yo} se defiende: nueva base militar. {tema}', 'Más fuerte cada día. Nueva base. {tema}' },
        },
    },
    obra = {
        autor = {
            agresivo = { 'Hemos terminado {cosa}. Seguimos creciendo. {tema}', 'Ya funciona {cosa}. Esto no para. {tema}', 'Acabamos {cosa}. A por lo siguiente. {tema}' },
            burlon = { 'Terminamos {cosa}. Y a tiempo, que es lo raro. {tema}', 'Ya tenemos {cosa}. Sin retrasos, no como otros. {tema}', 'Hoy estrenamos {cosa}. Sin cortar cinta, que sale cara. {tema}' },
            diplomatico = { 'Inauguramos {cosa}. Gracias a todos los que trabajaron. {tema}', 'Hemos acabado {cosa}, al servicio de todos. {tema}', 'Ya está en marcha {cosa}. Gracias a nuestros trabajadores. {tema}' },
            orgulloso = { 'Así trabaja {yo}: hemos terminado {cosa}. {tema}', '{yo} construye: ya funciona {cosa}. {tema}', 'Hemos levantado {cosa}. Así crece una nación. {tema}' },
        },
    },
    campamento = {
        autor = {
            agresivo = { 'Salimos a plantar un campamento. Esa tierra será nuestra. {tema}', 'Más tierra para {yo}. Nuevo campamento en marcha. {tema}', 'Plantamos un campamento. Que nadie se acerque. {tema}' },
            burlon = { 'Nos vamos de acampada. Con robots. {tema}', 'Campamento nuevo. Esta vez con mejores tiendas. {tema}', 'Otro campamento. Nos gusta el aire libre. {tema}' },
            diplomatico = { 'Nuevo campamento en camino para traer recursos a casa. {tema}', 'Un campamento más para traer recursos a nuestra gente. {tema}', 'Salimos a abrir un campamento. Trabajo para todos. {tema}' },
            orgulloso = { '{yo} se expande: nuevo campamento en camino. {tema}', 'Nuestras fronteras crecen. Nuevo campamento. {tema}', 'Otro campamento de {yo}. Seguimos. {tema}' },
        },
    },
}

-- Cuánto se habla de cada hecho: la probabilidad de que publique quien lo
-- hace (los grandes, siempre) y si contestan el aludido y los aliados.
local INTERES = {
    guerra = { autor = 1, otros = true }, paz = { autor = 1, otros = true }, saqueo = { autor = 1, otros = true },
    resiste = { autor = 0.9, otros = true }, altoFuego = { autor = 0.9, otros = true },
    rotura = { autor = 0.9, otros = true }, fracaso = { autor = 0.6, otros = true },
    incidente = { autor = 0.7, otros = true }, acuerdo = { autor = 0.7, otros = true },
    bandera = { autor = 0.7, otros = true }, destruye = { autor = 0.7, otros = true },
    asedio = { autor = 0.35, otros = false },
    marcha = { autor = 0.3, otros = false }, choque = { autor = 0.3, otros = false },
    derrota = { autor = 0.6 }, retirada = { autor = 0.3 }, tecnologia = { autor = 0.35 },
    base = { autor = 0.5 }, obra = { autor = 0.3 }, campamento = { autor = 0.25 },
}

-- Hechos que siempre publica quien los hace (los demás, a veces).
local GRANDES = { guerra = true, paz = true, saqueo = true }

local function estadoOndix(e)
    e.ondix = e.ondix or { publicaciones = {}, siguiente = 1 }
    return e.ondix
end

--- El tono de un presidente según su carácter.
function Ondix.tono(n)
    local g = n.gobernante or {}
    local agresividad, prudencia = g.agresividad or 0.5, g.prudencia or 0.5
    if agresividad > 0.55 and prudencia < 0.4 then
        return 'burlon'
    elseif agresividad > 0.65 then
        return 'agresivo'
    elseif prudencia > 0.65 then
        return 'diplomatico'
    end
    return 'orgulloso'
end

--- El nombre del orden (la alianza) `orden` de una nación.
function Ondix.nombreOrden(sim, orden)
    local o = Simulacion.ordenes and Simulacion.ordenes[orden]
    return o and o.nombre or tostring(orden)
end

--- El @ de una nación: el nombre de su capital, sin espacios.
function Ondix.usuario(sim, nid)
    local e = sim.estado
    local n = e.naciones[nid]
    local capital = n and e.ciudades[n.capital]
    local nombre = capital and capital.nombre or (n and n.nombre) or '?'
    return '@' .. nombre:gsub('%s+', '')
end

local function etiqueta(sim, tipo, a, b)
    local e = sim.estado
    local function corto(nid)
        local n = e.naciones[nid]
        local c = n and e.ciudades[n.capital]
        return (c and c.nombre or '?'):gsub('%s+', '')
    end
    if tipo == 'guerra' then
        return '#Guerra' .. corto(a) .. corto(b)
    elseif tipo == 'paz' then
        return '#Paz' .. corto(a) .. corto(b)
    elseif tipo == 'saqueo' then
        return '#CaeLaCapital'
    elseif tipo == 'resiste' then
        return '#' .. corto(a) .. 'Resiste'
    elseif tipo == 'bandera' then
        return '#Frontera' .. corto(b)
    elseif tipo == 'incidente' then
        return '#Frontera' .. corto(a) .. corto(b)
    elseif tipo == 'acuerdo' then
        return '#Comercio'
    elseif tipo == 'altoFuego' or tipo == 'fracaso' or tipo == 'rotura' then
        return '#Tregua' .. corto(a) .. corto(b)
    elseif b and (tipo == 'marcha' or tipo == 'choque' or tipo == 'asedio' or tipo == 'destruye') then
        return '#Frente' .. corto(b)
    elseif tipo == 'tecnologia' then
        return '#Tecnologia' .. corto(a)
    end
    return '#' .. corto(a)
end

-- Cómo empieza la publicación de quien cita a otro: lo menciona.
local MENCIONES = { '{otro} ', 'Leo a {otro}. ', 'Para {otro}: ', 'A {otro} le digo una cosa: ', 'Ojo con lo que dice {otro}. ' }

-- Parte de la gente que apoya una publicación según el hecho y el papel de
-- quien publica (antes del carácter y del azar).
local A_FAVOR = {
    guerra = { autor = 0.58, respuesta = 0.72, aliadoAutor = 0.55, aliadoOtro = 0.68 },
    paz = { autor = 0.8, respuesta = 0.74, aliadoAutor = 0.78, aliadoOtro = 0.78 },
    propia = { autor = 0.6, respuesta = 0.55, aliadoAutor = 0.65, aliadoOtro = 0.6 },
    incidente = { autor = 0.66, respuesta = 0.6, aliadoAutor = 0.6, aliadoOtro = 0.6 },
    acuerdo = { autor = 0.8, respuesta = 0.76, aliadoAutor = 0.7, aliadoOtro = 0.7 },
    saqueo = { autor = 0.86, respuesta = 0.7, aliadoAutor = 0.66, aliadoOtro = 0.72 },
    resiste = { autor = 0.9, respuesta = 0.48, aliadoAutor = 0.8, aliadoOtro = 0.6 },
    bandera = { autor = 0.76, respuesta = 0.66, aliadoAutor = 0.62, aliadoOtro = 0.66 },
}

--- Habitantes de la nación `nid` (todas sus ciudades).
local function habitantes(sim, nid)
    local e = sim.estado
    local total = 0
    for _, c in ipairs(sim:ciudadesDe(nid)) do
        local ciudad = type(c) == 'table' and c or e.ciudades[c]
        total = total + (ciudad and ciudad.poblacion or 0)
    end
    return total
end
Ondix.habitantes = habitantes

local function publicar(sim, azar, autor, texto, tipo, sobre, cita, papel)
    local e = sim.estado
    local o = estadoOndix(e)
    local n = e.naciones[autor]
    local g = n and n.gobernante or {}
    -- Alcance: de la población; los hechos grandes llegan a más gente.
    local gente = math.max(300, habitantes(sim, autor))
    local fuerza = (GRANDES[tipo] and 1.6 or 1) * (papel == 'autor' and 1 or 0.7)
    local apoyos = math.floor(gente * azar(0.08, 0.45) * fuerza * (0.7 + 0.6 * (g.agresividad or 0.5)))
    -- Los agresivos dividen más; los prudentes, menos.
    local base = (A_FAVOR[tipo] or {})[papel] or 0.6
    local aFavor = base + 0.12 * ((g.prudencia or 0.5) - (g.agresividad or 0.5)) + azar(-0.12, 0.12)
    local p = {
        id = o.siguiente,
        dia = e.dia,
        hora = (e.paso or 0) / Simulacion.pasosDia, -- del día: 0 al empezar, casi 1 al acabar
        autor = autor,
        texto = texto,
        tipo = tipo,
        sobre = sobre,
        cita = cita,
        apoyos = apoyos,
        reenvios = math.floor(apoyos * azar(0.06, 0.3)),
        comentarios = math.floor(apoyos * azar(0.08, 0.35)),
        aFavor = math.max(0.08, math.min(0.97, aFavor)),
        semilla = math.floor(azar(1, 2147483000)),
    }
    o.siguiente = o.siguiente + 1
    table.insert(o.publicaciones, 1, p)
    while #o.publicaciones > Ondix.maximo do
        table.remove(o.publicaciones)
    end
    return p
end

--- Lo que lleva una publicación `p` el día `dia`: crece los primeros días
-- hasta su total (como una publicación de verdad).
function Ondix.alcanceEn(p, dia)
    local f = 1 - math.exp(-((dia or p.dia) - p.dia + 0.35) / 1.4)
    f = math.max(0.25, math.min(1, f))
    return math.floor(p.apoyos * f), math.floor(p.reenvios * f), math.floor(p.comentarios * f)
end

local function rellenar(plantilla, valores)
    return (plantilla:gsub('{(%a+)}', function(clave)
        return valores[clave] or ''
    end))
end

local function elegir(azar, lista)
    return lista[math.floor(azar(1, #lista + 0.999))]
end

--- Las naciones del mismo orden que `nid` (sus aliados), en orden fijo.
local function aliados(sim, nid, sin)
    local e = sim.estado
    local n = e.naciones[nid]
    local lista = {}
    for id, otra in pairs(e.naciones) do
        if id ~= nid and id ~= sin and otra.orden == n.orden and not otra.jugador and #sim:ciudadesDe(id) > 0 then
            lista[#lista + 1] = id
        end
    end
    table.sort(lista, function(x, y)
        return tostring(x) < tostring(y)
    end)
    return lista
end

--- Un hecho de la partida: `a` lo hace, `b` lo recibe (nil si es solo de
-- `a`); `cosa`: lo que se nombra (una tecnología, una instalación). Todas las
-- naciones publican, también la del jugador (su presidente habla solo hasta
-- que el jugador publique por su cuenta).
function Ondix.hecho(sim, tipo, a, b, cosa)
    local e = sim.estado
    local frases = FRASES[tipo]
    local interes = INTERES[tipo] or { autor = 0.5 }
    local na, nb = e.naciones[a], b and e.naciones[b]
    if not frases or not na or (b and not nb) or na.ondixPropio then
        return
    end
    local o = estadoOndix(e)
    local azar = Ruido.azar(Ruido.hash(e.semilla or 1, e.dia or 0, o.siguiente, 4021))
    local tema = etiqueta(sim, tipo, a, b)
    if azar() >= interes.autor then
        return
    end
    -- Una frase distinta de la última que usó para este tipo de hecho.
    o.ultimas = o.ultimas or {}
    local lista = frases.autor[Ondix.tono(na)]
    local clave = tipo .. ':' .. tostring(a)
    local plantilla = elegir(azar, lista)
    for _ = 1, 6 do
        if plantilla ~= o.ultimas[clave] then
            break
        end
        plantilla = elegir(azar, lista)
    end
    o.ultimas[clave] = plantilla
    local texto = rellenar(plantilla, {
        otro = b and Ondix.usuario(sim, b) or '',
        yo = na.nombre,
        tema = tema,
        cosa = cosa or '',
    })
    texto = texto:gsub('^%l', string.upper)
    local principal = publicar(sim, azar, a, texto, tipo, b, nil, 'autor')
    if not (b and interes.otros and frases.respuesta) or nb.ondixPropio then
        return
    end
    -- El aludido publica en su perfil citando la de `a`.
    local agresividadB = nb.gobernante and nb.gobernante.agresividad or 0.5
    if azar() < 0.45 + 0.5 * agresividadB then
        local respuesta = rellenar(elegir(azar, MENCIONES), { otro = Ondix.usuario(sim, a) })
            .. elegir(azar, frases.respuesta[Ondix.tono(nb)])
        publicar(sim, azar, b, respuesta, tipo, a, principal.id, 'respuesta')
    end
    -- Aliados de cada lado.
    local function sumar(lado, frasesAliado, amigo, otro)
        local puestos = 0
        for _, id in ipairs(aliados(sim, lado, otro)) do
            if puestos >= 2 then
                break
            end
            if azar() < 0.35 then
                local textoAliado = rellenar(elegir(azar, frasesAliado), {
                    amigo = Ondix.usuario(sim, amigo),
                    otro = Ondix.usuario(sim, otro),
                    tema = tema,
                })
                publicar(sim, azar, id, textoAliado, tipo, otro, principal.id, lado == a and 'aliadoAutor' or 'aliadoOtro')
                puestos = puestos + 1
            end
        end
    end
    sumar(a, frases.aliadoAutor, a, b)
    sumar(b, frases.aliadoOtro, b, a)
end

-- Lo que publican los presidentes citando lo que escribe el jugador: no
-- contestan al texto, sino según cómo están con su nación (Ondix.trato). La
-- frase es una de su carácter y, a veces, otra del trato detrás: así salen
-- muchas combinaciones, y nadie repite la última que dijo.
local CONTESTAN = {
    guerra = {
        agresivo = {
            'Escribe lo que quieras. En el frente hablamos nosotros.', 'Mucho texto para alguien que va perdiendo.',
            'Nos vemos en el campo de batalla.', 'Cada palabra suya nos da más ganas de seguir.',
            'Que venga a decirlo delante de nuestros robots.', 'Menos publicar y más rendirse.',
            'Nuestros lanzamisiles ya tienen su respuesta.', 'Hablar no le va a salvar.',
        },
        burlon = {
            'Qué bien escribe para estar en guerra con nosotros.', 'Seguro que sus robots leen esto con miedo.',
            'Le dejo aquí su frase para la historia. La de los perdedores.', 'Se nota que tiene tiempo libre.',
            '¿Esto lo ha escrito antes o después de perder su última batalla?', 'Sus soldados piden munición y él publica.',
            'Gran estrategia: escribir en Ondix.', 'Lo imprimiremos para tirarlo desde un avión.',
        },
        diplomatico = {
            'Mientras haya guerra, las palabras sobran. Que pare primero.', 'Seguimos dispuestos a hablar, no a escuchar esto.',
            'Esto no ayuda a terminar la guerra.', 'La paz se firma, no se publica.',
            'Si quiere hablar, la mesa está puesta. Esto no es hablar.', 'Lamentamos el tono. Seguimos defendiéndonos.',
            'Cada día de guerra cuesta vidas. También las suyas.', 'Pedimos responsabilidad, no publicaciones.',
        },
        orgulloso = {
            'Nuestra nación no se rinde ante palabras.', 'Que lo diga cuando gane una batalla.',
            'Nada de lo que escriba cambia quién defiende su tierra.', 'Hemos resistido cosas peores.',
            'Nuestro pueblo no se asusta.', 'La historia la escriben los que aguantan.',
            'Ni un paso atrás.', 'Nuestra bandera sigue en pie.',
        },
    },
    tregua = {
        agresivo = {
            'La tregua no es amistad. Que no se confunda.', 'Seguimos atentos. Un paso en falso y se acaba.',
            'Que hable menos y cumpla el alto el fuego.', 'Nuestros robots siguen en su sitio.',
            'Un alto el fuego se rompe muy fácil.', 'No bajamos la guardia.',
        },
        burlon = {
            'Qué tranquilo se le ve desde que no disparamos.', 'Disfrute de la tregua mientras dure.',
            'Valiente desde detrás del alto el fuego.', 'Habla mucho para alguien que pidió un respiro.',
            'La tregua le sienta bien. Al teclado, sobre todo.', 'Aprovecha para escribir, que luego no habrá tiempo.',
        },
        diplomatico = {
            'Respetamos el alto el fuego. Esperamos lo mismo.', 'Ojalá esta tregua lleve a una paz de verdad.',
            'Cada día sin combates es un paso.', 'Mejor hablar que disparar. Sigamos así.',
            'Pedimos calma a las dos partes.', 'La tregua es una oportunidad. No la perdamos.',
        },
        orgulloso = {
            'Aceptamos la tregua, no lecciones.', 'Que nadie lea la tregua como debilidad.',
            'Paramos porque quisimos.', 'Nuestra nación cumple su palabra.',
            'La tregua no cambia nada de lo que somos.', 'Seguimos firmes, con o sin alto el fuego.',
        },
    },
    tension = {
        agresivo = {
            'No olvidamos lo que ha hecho.', 'Que tenga cuidado con lo que dice.', 'Nadie le tiene miedo.',
            'Está jugando con fuego.', 'Lo estamos mirando muy de cerca.', 'No nos provoque.',
        },
        burlon = {
            'Mira quién habla.', 'Otra vez con lo mismo.', 'Esto hay que enmarcarlo.',
            'Qué sorpresa, otra ocurrencia.', 'Siempre tan oportuno.', 'Gracias por el entretenimiento del día.',
        },
        diplomatico = {
            'Tomamos nota, sin compartirlo.', 'Así no se arreglan las cosas entre nuestras naciones.',
            'Le pedimos más prudencia.', 'Hay mejores formas de decir las cosas.',
            'Preferimos los canales oficiales.', 'No ayuda a calmar las cosas.',
        },
        orgulloso = {
            'No aceptamos lecciones.', 'Nuestra nación sabe lo que hace.', 'No nos impresiona.',
            'No necesitamos su opinión.', 'Cada uno en su casa.', 'Que mire primero lo suyo.',
        },
    },
    aliado = {
        agresivo = {
            'Así se habla.', 'Con vosotros, siempre.', 'Totalmente de acuerdo.',
            'Quien se meta con vosotros se mete con nosotros.', 'Eso es tener carácter.', 'Firmes, como siempre.',
        },
        burlon = {
            'Ni una coma que quitar.', 'Lo has dicho mejor que yo.', 'Alguien tenía que decirlo.',
            'Ya están temblando por ahí.', 'Esto va directo a enmarcar.', 'Y luego dicen que nosotros exageramos.',
        },
        diplomatico = {
            'Compartimos cada palabra.', 'Un mensaje necesario. Contad con nosotros.', 'Estamos a vuestro lado.',
            'Gran mensaje de un gran aliado.', 'Así se construye la confianza.', 'Seguiremos trabajando juntos.',
        },
        orgulloso = {
            'Juntos somos más fuertes.', 'Bien dicho, amigos.', 'Orgullosos de nuestra alianza.',
            'Nuestras naciones van de la mano.', 'Así hablan los nuestros.', 'Un orden, una voz.',
        },
    },
    neutral = {
        agresivo = { 'Ya veremos si cumple.', 'Palabras. Queremos hechos.', 'Que lo demuestre.', 'No nos fiamos de nadie.', 'Lo tendremos en cuenta.' },
        burlon = { 'Interesante. O no.', 'Lo leo con palomitas.', 'Qué día más entretenido.', 'Apuntado en la lista de cosas raras.', 'Sin comentarios. Bueno, este.' },
        diplomatico = { 'Seguimos con atención lo que dice.', 'Tomamos nota.', 'Respetamos todas las opiniones.', 'Ojalá se hable más y se dispare menos.', 'Escuchamos a todos.' },
        orgulloso = { 'Nosotros a lo nuestro.', 'Cada nación sabe lo que hace.', 'Nuestra nación no necesita opinar de todo.', 'Seguimos con nuestro camino.', 'Lo nuestro habla por nosotros.' },
    },
}

-- Cómo empieza, mencionándolo, según el trato.
local MENCIONES_TRATO = {
    guerra = { '{otro} ', 'Leo a {otro}. ', 'Para {otro}: ', 'A {otro} le digo una cosa: ', 'Ojo con lo que dice {otro}. ' },
    tregua = { '{otro} ', 'Leo a {otro}. ', 'Para {otro}: ', 'Sobre lo que dice {otro}: ' },
    tension = { '{otro} ', 'Leo a {otro}. ', 'Para {otro}: ', 'Ojo con lo que dice {otro}. ', 'A {otro} le digo una cosa: ' },
    aliado = { '{otro} ', 'Leo a {otro}. ', 'Para {otro}: ', 'Gracias, {otro}. ', 'Bien, {otro}. ' },
    neutral = { '{otro} ', 'Leo a {otro}. ', 'Sobre lo que dice {otro}: ' },
}

-- Una segunda frase que a veces va detrás, según el trato.
local REMATES = {
    guerra = { 'Esto no acaba aquí.', 'El frente dirá la última palabra.', 'Que lo sepa todo el mundo.', 'Seguimos.', 'Hasta el final.', 'Nuestro pueblo está con nosotros.' },
    tregua = { 'La tregua sigue, de momento.', 'Estamos atentos.', 'Que dure.', 'Lo vigilamos.', 'El tiempo dirá.' },
    tension = { 'Lo apuntamos.', 'No lo olvidaremos.', 'Tome nota.', 'Así nos va.', 'Que cada uno saque sus conclusiones.' },
    aliado = { 'Juntos.', 'Un abrazo a vuestro pueblo.', 'Adelante.', 'Así se habla.' },
    neutral = { 'Ni más ni menos.', 'Eso es todo.', 'Seguiremos atentos.', 'Ya veremos.' },
}

--- Cómo está la nación `a` con `b`: 'guerra', 'tregua' (alto el fuego),
-- 'aliado' (mismo orden o buena relación), 'tension' (mala) o 'neutral'.
function Ondix.trato(sim, a, b)
    local g = sim:guerraEntre(a, b)
    if g then
        return g.fase == 'calma' and 'tregua' or 'guerra'
    end
    local na, nb = sim.estado.naciones[a], sim.estado.naciones[b]
    local relacion = sim:relacion(a, b)
    if na.orden == nb.orden or relacion > 30 then
        return 'aliado'
    elseif relacion < -30 then
        return 'tension'
    end
    return 'neutral'
end

--- Recorta un texto a `limite` letras (UTF-8) y sin saltos de línea.
local function recortar(texto, limite)
    texto = tostring(texto or ''):gsub('[\r\n\t]+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    local partes, n = {}, 0
    for letra in texto:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        n = n + 1
        if n > limite then
            break
        end
        partes[n] = letra
    end
    return table.concat(partes)
end

--- El jugador publica `texto` desde el perfil de su presidente; `cita`: el id
-- de una publicación que cita (o nil). Los mencionados con @ y a veces otros
-- presidentes le contestan en su perfil, citándolo.
function Ondix.propia(sim, nid, texto, citaId)
    local e = sim.estado
    local n = e.naciones[nid]
    texto = recortar(texto, Ondix.letras)
    if not n or texto == '' then
        return false, 'vacio'
    end
    local o = estadoOndix(e)
    local citada
    for _, p in ipairs(o.publicaciones) do
        if citaId and p.id == citaId then
            citada = p
        end
    end
    local azar = Ruido.azar(Ruido.hash(e.semilla or 1, e.dia or 0, o.siguiente, 4022))
    n.ondixPropio = true
    local principal = publicar(sim, azar, nid, texto, 'propia', citada and citada.autor, citada and citada.id, 'autor')
    -- Quién publica citándolo: los que menciona o cita casi siempre; los que
    -- están en guerra con él a menudo; aliados y los demás, a veces. Como
    -- mucho tres; cada uno según cómo está con su nación.
    local PROBABILIDAD = { guerra = 0.45, tregua = 0.25, tension = 0.15, aliado = 0.2, neutral = 0.04 }
    local contestan = 0
    local candidatos = {}
    for _, id in ipairs(Simulacion.ordenadas(e.naciones)) do
        local otra = e.naciones[id]
        if id ~= nid and not otra.jugador and #sim:ciudadesDe(id) > 0 then
            local aludido = texto:lower():find(Ondix.usuario(sim, id):lower(), 1, true) or (citada and citada.autor == id)
            -- Primero los aludidos; los demás en orden al azar (fijo por la semilla).
            candidatos[#candidatos + 1] = { id = id, aludido = aludido and true or false, orden = azar() }
        end
    end
    table.sort(candidatos, function(x, y)
        if x.aludido ~= y.aludido then
            return x.aludido
        end
        return x.orden < y.orden
    end)
    for _, candidato in ipairs(candidatos) do
        local id, aludido = candidato.id, candidato.aludido
        local otra = e.naciones[id]
        if contestan < 3 then
            local trato = Ondix.trato(sim, id, nid)
            local g = otra.gobernante or {}
            local prob = aludido and (0.55 + 0.4 * (g.agresividad or 0.5)) or PROBABILIDAD[trato]
            if azar() < prob then
                -- Una frase distinta de la última que dijo este presidente.
                o.ultimas = o.ultimas or {}
                local lista = CONTESTAN[trato][Ondix.tono(otra)]
                local cuerpo = elegir(azar, lista)
                for _ = 1, 6 do
                    if cuerpo ~= o.ultimas[id] then
                        break
                    end
                    cuerpo = elegir(azar, lista)
                end
                o.ultimas[id] = cuerpo
                if azar() < 0.4 then
                    local remate = elegir(azar, REMATES[trato])
                    if not cuerpo:find(remate, 1, true) then
                        cuerpo = cuerpo .. ' ' .. remate
                    end
                end
                local frase = rellenar(elegir(azar, MENCIONES_TRATO[trato]), { otro = Ondix.usuario(sim, nid) }) .. cuerpo
                publicar(sim, azar, id, frase, 'propia', nid, principal.id, trato == 'aliado' and 'aliadoAutor' or 'respuesta')
                contestan = contestan + 1
            end
        end
    end
    return true, principal.id
end

-- Letras como mucho en una publicación del jugador.
Ondix.letras = 280

local Publicas = {}

function Publicas:publicarOndix(nid, texto, cita)
    return Ondix.propia(self, nid, texto, tonumber(cita))
end

function Publicas:hecho(tipo, a, b, cosa)
    Ondix.hecho(self, tipo, a, b, cosa)
end

--- Las últimas `cuantas` publicaciones (la más nueva primero).
function Publicas:publicacionesOndix(cuantas)
    local lista = estadoOndix(self.estado).publicaciones
    local copia = {}
    for k = 1, math.min(cuantas or #lista, #lista) do
        copia[k] = lista[k]
    end
    return copia
end

function Ondix.instalar(clase)
    Simulacion = clase
    for nombre, f in pairs(Publicas) do
        clase[nombre] = f
    end
    clase.Ondix = Ondix
end

return Ondix
