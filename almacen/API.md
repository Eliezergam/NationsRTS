# API del almacén

Lo que puedes usar desde cualquier script (un lanzamisiles, un camión, un
evento…). Se escribe igual que la de los vehículos
(`batalla/vehiculos/API.md`): **`get...` devuelve algo** y no cambia nada;
**`set...` cambia algo** y no devuelve nada. Todas con `:`.

`Almacen` es global, como `GestorVehiculos`: no hace falta `require`.

```lua
local almacen = Almacen.getDelJugador()
if almacen and almacen:getMisiles() == 0 then
    -- sin misiles en el almacén: no se dispara
end
almacen:setSacarMisiles(4) -- un camión se lleva 4
```

## Encontrar un almacén

| Función | Devuelve |
|---|---|
| `Almacen.getDelJugador()` | el almacén de tu nación (nil si solo se mira el mundo) |
| `Almacen.getDeNacion(nacion)` | el de esa nación (nil si no existe) |

Devuelven siempre el mismo objeto para la misma nación: se pueden comparar
con `==`.

## Leer

| Función | Devuelve |
|---|---|
| `almacen:getNacion()` | la nación dueña |
| `almacen:getMisiles()` | misiles guardados ahora |
| `almacen:getCapacidad()` | huecos del polvorín (60) |
| `almacen:getHuecosLibres()` | capacidad menos misiles |
| `almacen:getEstaVacio()` | `true` si no queda ninguno |
| `almacen:getEstaLleno()` | `true` si no cabe ninguno más |
| `almacen:getPartida()` | los datos de la nación ahora: `{ nacion, capital, habitantes, poder, nivel, dia, anio, ciudades, recursos, noticias }`; `recursos` son 4 `{ tipo, nombre, cantidad, tope, estado }` (metal, petróleo, comida, dinero), con las cifras de la barra de arriba |

## Cambiar

| Función | Qué hace |
|---|---|
| `almacen:setMisiles(n)` | pone `n` misiles (entre 0 y la capacidad) |
| `almacen:setAgregarMisiles(n)` | mete `n` (hasta llenar) |
| `almacen:setSacarMisiles(n)` | saca `n` (hasta vaciar) |

Cada cambio va a la simulación como una orden (como las del jugador): se
guarda con la partida y lo ve el almacén en 3D al momento (contador y
contenedores).
