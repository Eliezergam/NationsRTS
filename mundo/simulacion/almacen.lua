--- Almacén: el sitio aparte (otro mapa, solo se ve por dentro) donde una
-- nación guarda sus misiles contados (diseno/almacen.md). Prototipo del
-- arsenal de la compañía: lo que no está aquí no se puede disparar.
--
-- Estado guardado: `e.almacenes[nación] = { misiles }`. Se crea al pedirlo
-- por primera vez, con `MISILES_INICIALES`.
--
-- Contrato con la vista (y con los scripts, por almacen/almacen.lua):
--   sim:almacenDeMisiles(nid) -> la tabla guardada { misiles }.
--   sim:capacidadDeMisiles() -> huecos de misiles del polvorín (60).
--   ejecutar({ tipo = 'misilesAlmacen', nacion, misiles }) pone los misiles
--     (recortados a 0..capacidad). Devuelve los que quedan.
--   ejecutar({ tipo = 'sumarMisilesAlmacen', nacion, cantidad }) suma
--     (negativo: saca). Devuelve los que de verdad entraron o salieron.
--   ejecutar({ tipo = 'pagarAlmacen', nacion, coste = { dinero, metal,
--     petroleo } }) paga lo que gasta la fábrica de misiles del almacén (un
--     misil). Devuelve true, o false y el motivo.
--
-- Módulo de `mundo/simulacion.lua`: `AlmacenSim.instalar(Simulacion)`. Solo
-- datos y sin LÖVE.

local AlmacenSim = {}

-- Contenedores del polvorín del modelo (tools/blender/almacen_interior.py:
-- 10 columnas x 3 alturas x 2 lados).
AlmacenSim.CAPACIDAD_MISILES = 60
-- Con lo que empieza cada nación: ninguno, todos se fabrican en el almacén
-- (decisión del dueño, 2026-11-17).
AlmacenSim.MISILES_INICIALES = 0

local function recortar(n)
    n = math.floor(tonumber(n) or 0)
    return math.max(0, math.min(AlmacenSim.CAPACIDAD_MISILES, n))
end

--- Almacén guardado de la nación `nid` (se crea si no existía); nil si la
-- nación no existe.
function AlmacenSim:almacenDeMisiles(nid)
    if not self.estado.naciones[nid] then
        return nil
    end
    local almacenes = self.estado.almacenes
    local a = almacenes[nid]
    if not a then
        a = { misiles = AlmacenSim.MISILES_INICIALES }
        almacenes[nid] = a
    end
    return a
end

function AlmacenSim:capacidadDeMisiles()
    return AlmacenSim.CAPACIDAD_MISILES
end

--- Pone `misiles` en el almacén de `nid`. Devuelve los que quedan, o false
-- y el motivo.
function AlmacenSim:ponerMisilesAlmacen(nid, misiles)
    local a = self:almacenDeMisiles(nid)
    if not a then
        return false, 'nacion'
    end
    a.misiles = recortar(misiles)
    self.cambios = (self.cambios or 0) + 1
    return a.misiles
end

--- Suma `cantidad` misiles (negativo: los saca). Devuelve los que de verdad
-- cambiaron (con signo), o false y el motivo.
function AlmacenSim:sumarMisilesAlmacen(nid, cantidad)
    local a = self:almacenDeMisiles(nid)
    if not a then
        return false, 'nacion'
    end
    local antes = a.misiles
    a.misiles = recortar(antes + (tonumber(cantidad) or 0))
    self.cambios = (self.cambios or 0) + 1
    return a.misiles - antes
end

--- Paga `coste` ({ dinero, metal, petroleo }) de la nación `nid`: lo que
-- gasta la fábrica de misiles del almacén por cada misil.
function AlmacenSim:pagarAlmacen(nid, coste)
    local n = self.estado.naciones[nid]
    if not n then
        return false, 'nacion'
    end
    local limpio = {}
    for _, recurso in ipairs({ 'dinero', 'metal', 'petroleo' }) do
        limpio[recurso] = math.max(0, tonumber(coste and coste[recurso]) or 0)
    end
    if not self.pagar(n, limpio) then
        return false, 'noAlcanza'
    end
    self.cambios = (self.cambios or 0) + 1
    return true
end

function AlmacenSim.instalar(clase)
    -- Ojo: `Simulacion:almacen` es otra cosa (el tope de recursos de cada
    -- nación, economía): estos nombres no lo pisan.
    clase.almacenDeMisiles = AlmacenSim.almacenDeMisiles
    clase.capacidadDeMisiles = AlmacenSim.capacidadDeMisiles
    clase.ponerMisilesAlmacen = AlmacenSim.ponerMisilesAlmacen
    clase.sumarMisilesAlmacen = AlmacenSim.sumarMisilesAlmacen
    clase.pagarAlmacen = AlmacenSim.pagarAlmacen
    clase.AlmacenSim = AlmacenSim
end

return AlmacenSim
