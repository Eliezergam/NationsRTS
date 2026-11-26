-- Órdenes de movimiento sobre NV, sin lógica de entrada: el juego (o
-- `runtime/units.lua`) decide cuándo hay clic derecho; aquí solo se crea la
-- orden y se entrega a la navegación de grupos.
--
--   local Commands = require('runtime.nv.commands')
--   local commands = Commands.CommandSystem.new(manager, Group.GroupNavigation.new(manager))
--   local order = commands:moveUnits(agents, x, y)      -- MoveCommand
--   order.requestedDestination                          -- { x, y } pedido
--   order.navigationDestinations['TankNavigation']      -- { x, y } proyectado por red
--   order.groups                                        -- los grupos de la petición
--   order.strategies['TankNavigation']                  -- 'small' | 'medium' | 'massive' (ver group.lua)
--   commands:update(dt)
--
-- `moveUnits(agents, x, y, { strategy = 'massive' })` fuerza una estrategia;
-- sin ella la elige `GroupNavigationRequest` por tamaño del grupo con los
-- umbrales de `manager.options.strategy`.

local NvUtil = require('runtime.nv.util')
local Group = require('runtime.nv.group')

local Commands = {}

local MoveCommand = NvUtil.class('MoveCommand')
Commands.MoveCommand = MoveCommand

function MoveCommand:init(x, y)
    self.kind = 'move'
    self.requestedDestination = { x = x, y = y }
    self.navigationDestinations = {} -- tag → { x=, y= }
    self.strategies = {} -- tag → 'small' | 'medium' | 'massive'
    self.groups = {}
    self.request = nil
    self.failed = {}
end

--- Rellena la orden con la petición de grupo ya resuelta.
function MoveCommand:attach(request)
    self.request = request
    self.groups = request.groups
    self.failed = request.failed
    for _, group in ipairs(request.groups) do
        local nd = group.navigationDestination
        if nd then
            self.navigationDestinations[group.tag] = { x = nd.x, y = nd.y }
        end
        self.strategies[group.tag] = group.strategy
    end
    return self
end

function MoveCommand:arrived(fraction)
    if not self.request then
        return true
    end
    return self.request:arrived(fraction)
end

local CommandSystem = NvUtil.class('CommandSystem')
Commands.CommandSystem = CommandSystem

function CommandSystem:init(manager, group)
    self.manager = manager
    self.group = group or Group.GroupNavigation.new(manager)
    self.last = nil
end

--- Orden de mover para `agents` (lista de `NavigationAgent`). `opts`
-- (`spacing`, `arrivedFraction`, `strategy`, `formation`...) pasan a la
-- navegación de grupos.
function CommandSystem:moveUnits(agents, x, y, opts)
    local order = MoveCommand.new(x, y)
    order:attach(self.group:moveGroup(agents, x, y, opts))
    self.last = order
    return order
end

function CommandSystem:update(dt)
    self.group:update(dt)
end

function CommandSystem:activeRequests()
    return self.group:activeRequests()
end

return Commands
