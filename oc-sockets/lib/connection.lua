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
  KEEP_ALIVE_INTERVAL = config.keep_alive_interval
else
  PORT_ARP = 1
  PACKET_RETRY_TIME = 4
  PACKET_RETRY_AMOUNT = 3
  PACKET_MAX_PAYLOAD_SIZE = 8192 - 128
  MAX_ACTIVE_PACKETS = 10
  KEEP_ALIVE_INTERVAL = 20
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
  socket.lastKeepAlive = computer.uptime()
  socket.keepAliveTimer = nil

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
    local isString = type(data) == 'string'

    local serializedData = data
    local flag = 0
    if not isString then
      serializedData = serialization.serialize(serializedData)
      flag = 1
    end
    local chunks = {}
    for i = 1, math.ceil(#serializedData / PACKET_MAX_PAYLOAD_SIZE) do
      chunks[#chunks + 1] = serializedData:sub(PACKET_MAX_PAYLOAD_SIZE * (i - 1) + 1, PACKET_MAX_PAYLOAD_SIZE * i)
    end

    local firstId = socket.nextPacketId
    for _, v in ipairs(chunks) do
      local packet = _packet.create(socket.nextPacketId, _packet.type.DATA, v, flag, #chunks, firstId)

      socket.nextPacketId = socket.nextPacketId + 1

      if #socket.sendMeta >= MAX_ACTIVE_PACKETS then
        table.insert(socket.sendMeta, packet)
      else
        socket._sendInitializeMeta(packet)
      end
    end
  end

  function socket.sendRaw(packet)
    socket.modem.send(socket.targetCard,
            socket.port,
            packet.id,
            packet.type,
            packet.part_count,
            packet.first_part_id,
            packet.flags,
            packet.data)
  end

  function socket.sendACK(id)
    local packet = _packet.create(id, _packet.type.ACK)
    socket.sendRaw(packet)
  end

  function socket.receive()
    if #socket.receiveQueue == 0 then
      return nil
    end
    local message = table.remove(socket.receiveQueue, 1)
    return message
  end

  function socket.receiveBlocking(timeout)
    local startTime = computer.uptime()
    if not timeout then
      timeout = math.huge
    end
    while true do
      if #socket.receiveQueue > 0 then
        return table.remove(socket.receiveQueue, 1)
      end
      if computer.uptime() - startTime > timeout or not socket.active then
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
      local unserializedData = table.concat(socket.partialPackets[packet.first_part_id].chunks)
      if packet.flags == 1 then
        unserializedData = serialization.unserialize(unserializedData)
      end
      socket._acceptUnorderedPacket(packet.first_part_id,
              socket.partialPackets[packet.first_part_id].part_count,
              unserializedData)
      socket.partialPackets[packet.first_part_id] = nil
    end
  end

  function socket._receiveDataPacket(packet)
    socket.sendACK(packet.id)
    if packet.part_count > 1 then
      socket._processPartialDataPacket(packet)
    elseif packet.id == socket.nextReceivedPacketId then
      if packet.flags == 1 then
        table.insert(socket.receiveQueue, serialization.unserialize(packet.data))
      else
        table.insert(socket.receiveQueue, packet.data)
      end

      socket.nextReceivedPacketId = socket.nextReceivedPacketId + 1
    elseif packet.id > socket.nextReceivedPacketId then
      if packet.flags == 1 then
        socket._acceptUnorderedPacket(packet.id, 1, serialization.unserialize(packet.data))
      else
        socket._acceptUnorderedPacket(packet.id, 1, packet.data)
      end
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

  function socket._keepAlive()
    if computer.uptime() - socket.lastKeepAlive > 3 * KEEP_ALIVE_INTERVAL then
      socket.close()
    end
    socket.sendRaw(_packet.create(-1, _packet.type.KEEP_ALIVE))
  end

  function socket.receiveEvent(_, localAddress, remoteAddress, event_port, _,
                               packetId,
                               packetType,
                               packetPartCount,
                               packetFirstPartId,
                               packetFlags,
                               packetData)
    if localAddress == socket.cardAddress and
            remoteAddress == socket.targetCard and
            event_port == socket.port then
      local packet = _packet.create(packetId, packetType, packetData, packetFlags, packetPartCount, packetFirstPartId)
      if packet.type == _packet.type.DATA then
        socket._receiveDataPacket(packet)
      elseif packet.type == _packet.type.ACK then
        socket._processAck(packet)
      elseif packet.type == _packet.type.DISCONNECT then
        socket.close()
      elseif packet.type == _packet.type.CONNECT then
        socket.active = true
      elseif packet.type == _packet.type.KEEP_ALIVE then
        socket.lastKeepAlive = computer.uptime()
      end
    end
  end

  event.listen('modem_message', socket.receiveEvent)
  socket.keepAliveTimer = event.timer(KEEP_ALIVE_INTERVAL, socket._keepAlive, math.huge)

  socket.close = function()
    local packet = _packet.create(-1, _packet.type.DISCONNECT)
    socket.sendRaw(packet)

    event.ignore('modem_message', socket.receiveEvent)
    if socket.keepAliveTimer then
      event.cancel(socket.keepAliveTimer)
      socket.keepAliveTimer = nil
    end
    socket.active = false
  end

  return socket
end

--Sending/receiving

return connection