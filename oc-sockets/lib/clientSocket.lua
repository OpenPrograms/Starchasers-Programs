local component = require('component')
local connection = require('connection')
local serialization = require('serialization')
local computer = require('computer')
local _packet = require('packet')

local clientSocket = {}

-- Basically wrapper for connection lol
function clientSocket.constructor(modem, destAddr, port)
  checkArg(1, modem, 'string')
  checkArg(2, destAddr, 'string')
  checkArg(3, port, 'number')

  local client = {}
  client.connection = {}

  function client.receiveBlocking(timeout)
    return client.connection.receiveBlocking(timeout)
  end

  function client.receive()
    return client.connection.receive()
  end

  function client.send(data)
    client.connection.send(data)
  end
  function client.close()
    client.connection.close()
  end
  function client.isOpen()
    return client.connection.active
  end

  function client.connect(timeout)
    local connectPacket = _packet.create(-1, _packet.type.CONNECT)
    component.proxy(modem).open(port)
    component.proxy(modem).send(destAddr, port,
            connectPacket.id,
            connectPacket.type,
            connectPacket.part_count,
            connectPacket.first_part_id,
            connectPacket.flags,
            connectPacket.data)
    client.connection = connection.constructor(modem, port, destAddr)
    if not timeout then
      timeout = 5
    end
    local startTime = computer.uptime()
    while not client.connection.active and computer.uptime() - startTime < timeout do
      os.sleep(0.1)
    end

    if client.connection.active then
      return true
    end

    client.close()
    return false
  end

  return client
end

return clientSocket