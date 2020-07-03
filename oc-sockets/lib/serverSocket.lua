local connection = require('connection')
local component = require('component')
local event = require('event')
local serialization = require('serialization')
local _packet = require('packet')

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
function serverSocket.constructor(modem, port)
  checkArg(1, modem, 'string')
  checkArg(2, port, 'number')
  local server = {}
  server.port = port
  server.modemAddress = modem
  server.modem = component.proxy(modem)
  server.activeConnections = {} -- address:string => connection
  server.connectionRequests = {} -- src_address:string

  function server.packetEvent(_, localAddress, remoteAddress, event_port, _, id, type)
    if event_port == server.port and localAddress == server.modemAddress then
      if type == _packet.type.CONNECT then
        table.insert(server.connectionRequests, remoteAddress)
      end
    end
  end

  --Waits for incoming connection and returns socket
  function server.accept()
    if #server.connectionRequests == 0 then
      return nil
    end

    local address = table.remove(server.connectionRequests, 1)
    local socket =  connection.constructor(server.modemAddress, server.port, address)
    local responsePacket = _packet.create(-1, _packet.type.CONNECT)
    socket.sendRaw(responsePacket)
    socket.active = true
    return socket
  end

  function server.acceptBlocking()
    while #server.connectionRequests == 0 do
      os.sleep(0.05)
    end
    local address = table.remove(server.connectionRequests, 1)
    local socket =  connection.constructor(server.modemAddress, server.port, address)
    local responsePacket = _packet.create(-1, _packet.type.CONNECT)
    socket.sendRaw(responsePacket)
    socket.active = true
    return socket
  end

  function server.close()
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