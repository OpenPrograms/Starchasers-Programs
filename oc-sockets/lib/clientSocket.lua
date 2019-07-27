local component = require('component')
local connection = require('connection')
local serialization = require('serialization')

local clientSocket = {}

TYPE_ARP = 0x01 --not used because arp uses own port
TYPE_ACK = 0x02
TYPE_DATA = 0x03
TYPE_CONNECT = 0x04 --send this to server to receive port for connection
TYPE_DISCONNECT = 0x05 --send to close connection

-- Basically wrapper for connection lol
clientSocket.constructor = function(modem, destAddr, port)
  checkArg(1, modem, 'string')
  checkArg(2, destAddr, 'string')
  checkArg(3, port, 'number')

  local client = {}
  client.connection = {}

  client.receive = function(timeout)
    return client.connection.receive(timeout)
  end
  client.send = function(data)
    client.connection.send(data)
  end
  client.close = function()
    client.connection.close()
  end
  client.isOpen = function()
    return client.connection.active
  end
  client.connect = function()
    local connectPacket = {}
    connectPacket.id = -1
    connectPacket.type = TYPE_CONNECT
    connectPacket.part_count = 1
    connectPacket.first_part_id = -1
    component.proxy(modem).open(port)
    component.proxy(modem).send(destAddr, port, serialization.serialize(connectPacket))
    client.connection = connection.constructor(modem, port, destAddr)
  end

  return client
end

return clientSocket