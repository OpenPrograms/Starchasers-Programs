local connection = require('connection')
local component = require('component')
local event = require('event')
local serialization = require('serialization')

TYPE_ARP = 0x01 --not used because arp uses own port
TYPE_ACK = 0x02
TYPE_DATA = 0x03
TYPE_CONNECT = 0x04 --send this to server to receive port for connection
TYPE_DISCONNECT = 0x05

local serverSocket = {}

--Creates server and starts listening on given port
--@param modem address of modem to start listening on]
--@param port
--@return server instance
serverSocket.constructor = function(modem, port)
  checkArg(1, modem, 'string')
  checkArg(2, port, 'number')
  local server = {}
  server.port = port
  server.modemAddress = modem
  server.modem = component.proxy(modem)
  server.activeConnections = {} -- address:string => connection
  server.connectionRequests = {} -- src_address:string

  server.packetEvent = function(_, localAddress, remoteAddress, event_port, _, packet)
    if event_port == server.port and localAddress == server.modemAddress then
      packet = serialization.unserialize(packet)
      if packet.type == TYPE_CONNECT then
        table.insert(server.connectionRequests, remoteAddress)
      end
    end
  end

  --Waits for incoming connection and returns socket
  server.accept = function()
    while #server.connectionRequests == 0 do
      os.sleep(0.05)
    end
    local address = table.remove(server.connectionRequests, 1)
    local socket =  connection.constructor(server.modemAddress, server.port, address)
    local responsePacket = {}
    responsePacket.id = -1
    responsePacket.type = TYPE_CONNECT
    responsePacket.part_count = 1
    responsePacket.first_part_id = -1
    socket.sendRaw(responsePacket)
    return socket
  end

  server.close = function()
    server.modem.close(server.port)
    event.ignore('modem_message', server.packetEvent)
    for socket in pairs(server.activeConnections) do
      socket.close()
    end
  end
  --
  event.listen('modem_message', server.packetEvent)

  if not server.modem.open(server.port) then
    error('port already in use')
  end

  return server
end

return serverSocket