local event = require('event')
local component = require('component')
local serialization = require('serialization')
local computer = require('computer')
local _packet = require('packet')

local config
if io.open('/etc/sockets_cfg.lua', 'r') then
  config = dofile('/etc/sockets_cfg.lua')
  PORT_ARP = config.arp_port
  PACKET_RETRY_TIME = config.packet_retry_time
  PACKET_RETRY_AMOUNT = config.packet_retry_amount
  PACKET_MAX_PAYLOAD_SIZE = config.max_packet_size - 128 -- 126 bytes of header size overhead + 2 bytes OC overhead
  MAX_ACTIVE_PACKETS = config.max_active_packets
else
  PORT_ARP = 1
  PACKET_RETRY_TIME = 4
  PACKET_RETRY_AMOUNT = 3
  PACKET_MAX_PAYLOAD_SIZE = 8192 - 128
  MAX_ACTIVE_PACKETS = 10
end


--ID	INT	8
--TYPE	INT	8
--PART COUNT	INT	8
--FIRST PART ID	INT	8
--DATA	BYTE[]	MAX-HEADER

--serialized header max size: 126 bytes

local connection = {}

--Creates socket
--@param networkCard address of network card to open connection on
--@param port connection port
--@param address target card address
--@return new socket
function connection.constructor(networkCard, port, address)
  checkArg(1, networkCard, "string")
  checkArg(2, port, "number")
  checkArg(3, address, "string")
  local socket = {}
  socket.cardAddress = networkCard
  socket.modem = component.proxy(networkCard)
  socket.port = port
  socket.targetCard = address
  ----------------------------
  socket.sendMeta = {} --id:number => {try:number, timerId: number}
  socket.sendQueue = {}
  socket.nextPacketId = 1 --used to construct packet
  socket.sendError = nil --if error occurs set it here and throw it when send() is executed
  socket.receiveQueue = {} --holds raw data
  socket.nextReceivedPacketId = 1
  socket.unorderedData = {} --id:number => {data:string, part_count:number} -- packets that came out of order
  socket.partialPackets = {} --first_part_id:number => {part_count:number, chunks:{data:serialized_string}} -- packets that came in parts
  socket.active = false

  function socket.createRetryTimer(packet)
    return function()
      --resend packet if meta != null
      --throw exception after 3rd try
      if socket.sendMeta[packet.id] then
        if socket.sendMeta[packet.id].try > PACKET_RETRY_AMOUNT then
          socket.sendError = 'Failed to deliver packet (no response)'
          socket.active = false
          event.ignore('modem_message', socket.receiveEvent)
        end
        socket.sendRaw(packet)
        socket.sendMeta[packet.id].try = socket.sendMeta[packet.id].try + 1
      end
    end
  end

  function socket._sendInitializeMeta(packet)
    socket.sendMeta[packet.id] = {
      try = 1,
      timerId = event.timer(PACKET_RETRY_TIME,
              socket.createRetryTimer(packet), PACKET_RETRY_AMOUNT + 1)
    }
    socket.sendRaw(packet)
  end

  function socket.send(data)
    if socket.sendError then
      error(socket.sendError)
    end

    local serializedData = serialization.serialize(data)
    local chunks = {}
    for i = 1, math.ceil(#serializedData / PACKET_MAX_PAYLOAD_SIZE) do
      chunks[#chunks + 1] = serializedData:sub(PACKET_MAX_PAYLOAD_SIZE * (i - 1) + 1, PACKET_MAX_PAYLOAD_SIZE * i)
    end

    local firstId = socket.nextPacketId
    for _, v in ipairs(chunks) do
      local packet = _packet.create(socket.nextPacketId, _packet.type.TYPE_DATA, v, #chunks, firstId)

      socket.nextPacketId = socket.nextPacketId + 1

      if #socket.sendMeta >= MAX_ACTIVE_PACKETS then
        table.insert(socket.sendMeta, packet)
      else
        socket._sendInitializeMeta(packet)
      end
    end
  end

  function socket.sendRaw(packet)
    socket.modem.send(socket.targetCard, socket.port, serialization.serialize(packet))
  end

  function socket.sendACK(id)
    local packet = _packet.create(id, _packet.type.TYPE_ACK)
    socket.modem.send(socket.targetCard, socket.port, serialization.serialize(packet))
  end

  function socket.receive()
    if #socket.receiveQueue == 0 then
      return nil
    end
    local message = table.remove(socket.receiveQueue, 1)
    return serialization.unserialize(message)
  end

  function socket.receiveBlocking(timeout)
    local startTime = computer.uptime()
    if not timeout then
      timeout = math.huge
    end
    while true do
      if #socket.receiveQueue > 0 then
        local message = table.remove(socket.receiveQueue, 1)
        return serialization.unserialize(message)
      end
      if computer.uptime() - startTime > timeout then
        return nil
      end
      os.sleep(0.1)
    end
  end
  --
  function socket._acceptUnorderedPacket(packetId, partCount, data)
    socket.unorderedData[packetId] = {
      part_count = partCount,
      data = data
    }
  end

  socket._processPartialDataPacket = function(packet)
    if not socket.partialPackets[packet.first_part_id] then
      --create partial entry
      socket.partialPackets[packet.first_part_id] = {}
      socket.partialPackets[packet.first_part_id].part_count = packet.part_count
      socket.partialPackets[packet.first_part_id].chunks = {}
    end

    --insert part of data
    socket.partialPackets[packet.first_part_id].chunks[packet.id - packet.first_part_id + 1] = packet.data

    if socket.partialPackets[packet.first_part_id].part_count == #socket.partialPackets[packet.first_part_id].chunks then
      --put parts together
      socket._acceptUnorderedPacket(packet.first_part_id,
              socket.partialPackets[packet.first_part_id].part_count,
              table.concat(socket.partialPackets[packet.first_part_id].chunks))
      socket.partialPackets[packet.first_part_id] = nil
    end
  end

  function socket._receiveDataPacket(packet)
    socket.sendACK(packet.id)
    if packet.part_count > 1 then
      socket._processPartialDataPacket(packet)
    elseif packet.id == socket.nextReceivedPacketId then
      table.insert(socket.receiveQueue, packet.data)
      socket.nextReceivedPacketId = socket.nextReceivedPacketId + 1
    elseif packet.id > socket.nextReceivedPacketId then
      socket._acceptUnorderedPacket(packet.id, 1, packet.data)
    end
    --check unorderedData with nextReceivedPacketId
    while socket.unorderedData[socket.nextReceivedPacketId] do
      local theId = socket.nextReceivedPacketId
      table.insert(socket.receiveQueue, socket.unorderedData[theId].data)
      socket.nextReceivedPacketId = socket.nextReceivedPacketId + socket.unorderedData[theId].part_count
      socket.unorderedData[theId] = nil
    end
  end

  function socket._processAck(packet)
    event.cancel(socket.sendMeta[packet.id].timerId)
    socket.sendMeta[packet.id] = nil
    if #socket.sendQueue > 0 then
      socket._sendInitializeMeta(table.remove(socket.sendQueue, 1))
    end
  end

  function socket.receiveEvent(_, localAddress, remoteAddress, event_port, _, packet)
    if localAddress == socket.cardAddress and
            remoteAddress == socket.targetCard and
            event_port == socket.port then
      packet = serialization.unserialize(packet)
      if packet.type == _packet.type.TYPE_DATA then
        socket._receiveDataPacket(packet)
      elseif packet.type == _packet.type.TYPE_ACK then
        socket._processAck(packet)
      elseif packet.type == _packet.type.TYPE_DISCONNECT then
        socket.close()
      elseif packet.type == _packet.type.TYPE_CONNECT then
        socket.active = true
      end
    end
  end
  event.listen('modem_message', socket.receiveEvent)

  socket.close = function()
    local packet = _packet.create(-1, _packet.type.TYPE_DISCONNECT)
    socket.modem.send(socket.targetCard, socket.port, serialization.serialize(packet))

    event.ignore('modem_message', socket.receiveEvent)
    socket.active = false
  end

  return socket
end

--Sending/receiving

return connection