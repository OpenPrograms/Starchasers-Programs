local event = require('event')
local component = require('component')
local serialization = require('serialization')
local computer = require('computer')

local config
if io.open('/etc/sockets_cfg.lua', 'r') then
  config = dofile('/etc/sockets_cfg.lua')
  PORT_ARP = config.arp_port
  PACKET_RETRY_TIME = config.packet_retry_time
  PACKET_RETRY_AMOUNT = config.packet_retry_amount
else
  PORT_ARP = 1
  PACKET_RETRY_TIME = 4
  PACKET_RETRY_AMOUNT = 3
end


--ID	INT	8
--TYPE	INT	8
--PART COUNT	INT	8
--FIRST PART ID	INT	8
--DATA	BYTE[]	MAX-HEADER

TYPE_ARP = 0x01 --not used because arp uses own port
TYPE_ACK = 0x02
TYPE_DATA = 0x03

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
  socket.nextPacketId = 1 --used to construct packet
  socket.sendError = nil --if error occurs set it here and throw it when send() is executed
  socket.receiveQueue = {} --holds raw data
  socket.nextReceivedPacketId = 1
  socket.unorderedData = {} --id:number => {data:string, part_count:number} -- packets that came out of order
  socket.partialPackets = {} --first_part_id:number => {part_count:number, chunks:{data:serialized_string}} -- packets that came in parts
  socket.active = true

  socket.createRetryTimer = function(packet)
    return function()
      --resend packet if meta != null
      --throw exception after 3rd try
      if socket.sendMeta[packet.id] then
        if socket.sendMeta[packet.id].try > PACKET_RETRY_AMOUNT then
          socket.sendError = 'Failed to deliver packet (no response)'
        end
        socket.modem.send(socket.targetCard, socket.port, serialization.serialize(packet))
        socket.sendMeta[packet.id].try = socket.sendMeta[packet.id].try + 1
      end
    end
  end

  socket.send = function(data)
    if socket.sendError then
      error(socket.sendError)
    end

    local serializedData = serialization.serialize(data)
    local chunks = {}
    for i = 1, math.ceil(#serializedData / 8000) do
      chunks[#chunks + 1] = data:sub(8000 * (i - 1) + 1, 8000 * i)
    end

    local firstId = socket.nextPacketId
    for _, v in ipairs(chunks) do
      local packet = {}
      packet.id = socket.nextPacketId
      packet.type = TYPE_DATA
      packet.part_count = #chunks
      packet.first_part_id = firstId
      packet.data = v

      socket.sendMeta[packet.id] = {}
      socket.sendMeta[packet.id].try = 1
      socket.sendMeta[packet.id].timerId = event.timer(PACKET_RETRY_TIME,
              socket.createRetryTimer(packet), PACKET_RETRY_AMOUNT + 1)

      socket.nextPacketId = socket.nextPacketId + 1

      socket.modem.send(socket.targetCard, socket.port, serialization.serialize(packet))
    end
  end

  socket.sendACK = function(id)
    local packet = {}
    packet.id = id
    packet.type = TYPE_ACK
    packet.part_count = 1
    packet.first_part_id = id

    socket.modem.send(socket.targetCard, socket.port, serialization.serialize(packet))
  end

  socket.receive = function(timeout)
    local startTime = computer.uptime()
    if not timeout then
      timeout = math.huge
    end
    while true do
      if #socket.receiveQueue > 0 then
        return table.remove(socket.receiveQueue, 1)
      end
      if computer.uptime() - startTime > timeout then
        return nil
      end
      os.sleep(0.1)
    end
  end
  --
  socket.receiveEvent = function(_, localAddress, remoteAddress, event_port, _, packet)
    if localAddress == socket.cardAddress and
            remoteAddress == socket.targetCard and
            event_port == socket.port then
      packet = serialization.unserialize(packet)
      if packet.type == TYPE_DATA then
        socket.sendACK(packet.id)
        if packet.part_count > 1 then
          if not socket.partialPackets[packet.first_part_id] then
            --create partial entry
            socket.partialPackets[packet.first_part_id] = {}
            socket.partialPackets[packet.first_part_id].part_count = packet.part_count
          end
          if not socket.partialPackets[packet.first_part_id].chunks then
            socket.partialPackets[packet.first_part_id].chunks = {}
          end
          socket.partialPackets[packet.first_part_id].chunks[packet.id - packet.first_part_id + 1] = packet.data --insert part of data
          if socket.partialPackets[packet.first_part_id].part_count == #socket.partialPackets[packet.first_part_id].chunks then
            --put parts together
            socket.unorderedData[packet.first_part_id] = {}
            socket.unorderedData[packet.first_part_id].part_count = socket.partialPackets[packet.first_part_id].part_count
            socket.unorderedData[packet.first_part_id].data = table.concat(socket.partialPackets[packet.first_part_id].chunks)
            socket.partialPackets[packet.first_part_id] = nil
          end
        elseif packet.id == socket.nextReceivedPacketId then
          table.insert(socket.receiveQueue, packet.data)
          socket.nextReceivedPacketId = socket.nextReceivedPacketId + 1
        elseif packet.id > socket.nextReceivedPacketId then
          socket.unorderedData[packet.id] = {}
          socket.unorderedData[packet.id].part_count = 1
          socket.unorderedData[packet.id].data = serialization.unserialize(packet.data)
        end
        --check unorderedData with nextReceivedPacketId
        while socket.unorderedData[socket.nextReceivedPacketId] do
          local theId = socket.nextReceivedPacketId
          table.insert(socket.receiveQueue, socket.unorderedData[theId].data)
          socket.nextReceivedPacketId = socket.nextReceivedPacketId + socket.unorderedData[theId].part_count
          socket.unorderedData[theId] = nil
        end
      end
      if packet.type == TYPE_ACK then
        event.cancel(socket.sendMeta[packet.id].timerId)
        socket.sendMeta[packet.id] = nil
      end
      if packet.type == TYPE_DISCONNECT then
        socket.close()
      end
    end
  end
  event.listen('modem_message', socket.receiveEvent)

  socket.close = function()
    local packet = {}
    packet.id = -1
    packet.type = TYPE_DISCONNECT
    packet.first_part_id = -1
    packet.part_count = 1
    socket.modem.send(socket.targetCard, socket.port, serialization.serialize(packet))

    event.ignore('modem_message', socket.receiveEvent)
    socket.active = false
  end

  return socket
end

--Sending/receiving

return connection