local component = require('component')
local connection = require('connection')
local serialization = require('serialization')
local computer = require('computer')

local clientSocket = {}

TYPE_ARP = 0x01 --not used because arp uses own port
TYPE_ACK = 0x02
TYPE_DATA = 0x03
TYPE_CONNECT = 0x04 --send this to server to receive port for connection
TYPE_DISCONNECT = 0x05 --send to close connection

-- Basically wrapper for connection lol
function clientSocket.constructor(modem, destAddr, port)
  checkArg(1, modem, 'string')
  checkArg(2, destAddr, 'string')
  checkArg(3, port, 'number')

  local client = {}
  client.connection = {}

  function client.receive(timeout)
    return client.connection.receive(timeout)
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
    local connectPacket = {}
    connectPacket.id = -1
    connectPacket.type = TYPE_CONNECT
    connectPacket.part_count = 1
    connectPacket.first_part_id = -1
    component.proxy(modem).open(port)
    component.proxy(modem).send(destAddr, port, serialization.serialize(connectPacket))
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