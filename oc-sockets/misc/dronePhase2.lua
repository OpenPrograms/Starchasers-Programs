local PACKET_RETRY_AMOUNT = 3
local PACKET_MAX_PAYLOAD_SIZE = 8000
local MAX_ACTIVE_PACKETS = 10
local PACKET_RETRY_TIME = 4
local KEEP_ALIVE_INTERVAL = 20
local uptime = computer.uptime
local MODEM_MESSAGE = 'modem_message'

local event = {
  listeners = {},
  timers = {},
  nextTimerId = 1
}

local env = {
  modem = component.proxy(component.list('modem')()),
  event = event,
}

local function debug(string)
  env.modem.broadcast(802, string)
end

function env.sleep(time)
  local startTime = uptime()
  while uptime() - startTime < time do
    event._process(time, startTime)
  end
end

function event._process(time, startTime)
  for k, v in pairs(event.timers) do
    if v.lastCall + v.interval < uptime() then
      v.callback()
      v.times = v.times - 1
      v.lastCall = uptime()
      if v.times == 0 then
        event.timers[k] = nil
      end
    end
  end
  local pulledEvent = { computer.pullSignal(math.max(0, time - (uptime() - startTime))) }
  local listeners = event.listeners[pulledEvent[1]]
  if not listeners then
    return
  end
  for k, v in pairs(listeners) do
    k(table.unpack(pulledEvent))
  end
end

function event.ignore(type, callback)
  if not event.listeners[type] then
    event.listeners[type] = {}
  end
  event.listeners[type][callback] = nil
end

function event.listen(type, callback)
  if not event.listeners[type] then
    event.listeners[type] = {}
  end

  event.listeners[type][callback] = true
end

function event.timer(interval, callback, times)
  event.timers[event.nextTimerId] = {
    lastCall = uptime(),
    interval = interval,
    callback = callback,
    times = times
  }
  event.nextTimerId = event.nextTimerId + 1
  return event.nextTimerId - 1
end

function event.cancel(timerId)
  event.timers[timerId] = nil
end

local _packet = {
  t = {
    AQ = 0x01, --TYPE_ARP_QUESTION
    AR = 0x02, --TYPE_ARP_RESPONSE
    ACK = 0x03, --TYPE_ACK
    D = 0x04, --TYPE_DATA
    C = 0x05, --TYPE_CONNECT
    DC = 0x06, --TYPE_DISCONNECT
    K = 0x07 --TYPE_KEEP_ALIVE
  }
}

---_packet.create
function _packet.c(id, type, data, flags, partCount, firstPartId)
  partCount = partCount or 1
  firstPartId = firstPartId or id
  data = data or ''
  flags = flags or 0
  return {
    i = id,
    t = type,
    pc = partCount,
    fi = firstPartId,
    fl = flags,
    d = data
  }
end

local dns = {
  hostsByName = {},
  PORT_ARP = 1,
  _modem = env.modem
}
env.dns = dns

function dns.askHostname(hostname, timeout)
  timeout = timeout or 2
  dns._modem.broadcast(dns.PORT_ARP, _packet.t.AQ, hostname)

  local startTime = uptime()
  while not dns.hostsByName[hostname] and uptime() - startTime < timeout do
    env.sleep(0.1)
  end
end

function dns.getAddress(hostname, shouldAsk)
  shouldAsk = shouldAsk or true
  if not dns.hostsByName[hostname] and shouldAsk then
    dns.askHostname(hostname)
  end
  return dns.hostsByName[hostname].address
end

function dns.enable()
  dns._modem.open(dns.PORT_ARP)
  event.listen(MODEM_MESSAGE, dns._rc)
  dns.expireTimerId = event.timer(15, dns._re)
end

function dns.disable()
  dns._modem.close(dns.PORT_ARP)
  event.cancel(dns.expireTimerId)
  event.ignore(MODEM_MESSAGE, dns._rc)
end

---dns._removeExpired()
function dns._re()
  local now = uptime()
  for k, v in pairs(dns.hostsByName) do
    if v.time < now - 10 then
      dns.hostsByName[k] = nil
    end
  end
end

---dns._receive(...)
function dns._rc(_, _, remoteAddress, port, _, type, msg)
  if port == dns.PORT_ARP then
    if type == _packet.t.AR and msg then
      local now = uptime()
      dns.hostsByName[msg] = { address = remoteAddress, time = now }
    end
  end
end

local connection = {}
env.connection = connection

function connection.constructor(port, address)
  local socket = {}
  socket.modem = env.modem
  socket.cardAddress = env.modem.address
  socket.port = port
  socket.targetCard = address

  socket.sendMeta = {}
  socket.sendQ = {}
  socket.nextPacketId = 1
  socket.sendE = nil --sendError
  socket.receiveQueue = {}
  socket.nextReceivedPacketId = 1
  socket.unorderedData = {}
  socket.partialPackets = {}
  socket.active = false
  socket.lka = uptime()

  function socket.createRetryTimer(packet)
    return function()
      --resend packet if meta != null
      --throw exception after 3rd try
      if socket.sendMeta[packet.i] then
        if socket.sendMeta[packet.i].try > PACKET_RETRY_AMOUNT then
          socket.sendE = 'e2'
          socket.active = false
          event.ignore(MODEM_MESSAGE, socket.receiveEvent)
        end
        socket.sendRaw(packet)
        socket.sendMeta[packet.i].try = socket.sendMeta[packet.i].try + 1
      end
    end
  end

  ---socket._sendInitializeMeta(packet)
  function socket._sim(packet)
    socket.sendMeta[packet.i] = {
      try = 1,
      timerId = event.timer(PACKET_RETRY_TIME,
              socket.createRetryTimer(packet), PACKET_RETRY_AMOUNT + 1)
    }
    socket.sendRaw(packet)
  end

  function socket.send(data)
    if type(data) ~= 'string' then
      socket.error = 'e1'
    end

    if socket.sendE then
      error(socket.sendE)
    end

    local serializedData = data
    local flag = 0
    local chunks = {}
    for i = 1, math.ceil(#serializedData / PACKET_MAX_PAYLOAD_SIZE) do
      chunks[#chunks + 1] = serializedData:sub(PACKET_MAX_PAYLOAD_SIZE * (i - 1) + 1, PACKET_MAX_PAYLOAD_SIZE * i)
    end

    local firstId = socket.nextPacketId
    for _, v in ipairs(chunks) do
      local packet = _packet.c(socket.nextPacketId, _packet.t.D, v, flag, #chunks, firstId)

      socket.nextPacketId = socket.nextPacketId + 1

      if #socket.sendMeta >= MAX_ACTIVE_PACKETS then
        table.insert(socket.sendMeta, packet)
      else
        socket._sim(packet)
      end
    end
  end

  function socket.sendRaw(packet)
    socket.modem.send(socket.targetCard,
            socket.port,
            packet.i, --id
            packet.t, --type
            packet.pc, --partCount
            packet.fi, --firstPartId
            packet.fl, --flags
            packet.d)--data
  end

  function socket.sendACK(id)
    socket.sendRaw(_packet.c(id, _packet.t.ACK))
  end

  function socket.receive()
    if #socket.receiveQueue == 0 then
      return nil
    end
    local message = table.remove(socket.receiveQueue, 1)
    return message
  end

  ---socket.acceptUnorderedPacket
  function socket._aup(packetId, partCount, data)
    socket.unorderedData[packetId] = {
      part_count = partCount,
      data = data
    }
  end

  ---socket._processPartialDataPacket
  function socket._ppdp(packet)
    if not socket.partialPackets[packet.fi] then
      --create partial entry
      socket.partialPackets[packet.fi] = {}
      socket.partialPackets[packet.fi].part_count = packet.pc
      socket.partialPackets[packet.fi].ch = {}
    end

    --insert part of data
    socket.partialPackets[packet.fi].ch[packet.i - packet.fi + 1] = packet.d

    if socket.partialPackets[packet.fi].part_count == #socket.partialPackets[packet.fi].ch then
      --put parts together
      local unserializedData = table.concat(socket.partialPackets[packet.fi].ch)
      socket._aup(packet.fi,
              socket.partialPackets[packet.fi].part_count,
              unserializedData)
      socket.partialPackets[packet.fi] = nil
    end
  end

  ---socket.receiveDataPacket()
  function socket._rdp(packet)
    if packet.flags == 1 then
      error('e1')
    end
    socket.sendACK(packet.i)
    if packet.pc > 1 then
      socket._ppdp(packet)
    elseif packet.i == socket.nextReceivedPacketId then
      table.insert(socket.receiveQueue, packet.d)
      socket.nextReceivedPacketId = socket.nextReceivedPacketId + 1
    elseif packet.i > socket.nextReceivedPacketId then
      socket._aup(packet.i, 1, packet.d)
    end
    --check unorderedData with nextReceivedPacketId
    while socket.unorderedData[socket.nextReceivedPacketId] do
      local theId = socket.nextReceivedPacketId
      table.insert(socket.receiveQueue, socket.unorderedData[theId].data)
      socket.nextReceivedPacketId = socket.nextReceivedPacketId + socket.unorderedData[theId].part_count
      socket.unorderedData[theId] = nil
    end
  end

  ---socket.processAck()
  function socket._pack(packet)
    if not socket.sendMeta[packet.i] then
      return
    end
    event.cancel(socket.sendMeta[packet.i].timerId)
    socket.sendMeta[packet.i] = nil
    if #socket.sendQ > 0 then
      socket._sim(table.remove(socket.sendQ, 1))
    end
  end

  ---socket._keepAlive()
  function socket._ka()
    if uptime() - socket.lka > 3 * KEEP_ALIVE_INTERVAL then
      socket.close()
    end
    socket.sendRaw(_packet.c(-1, _packet.t.K))
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
      local packet = _packet.c(packetId, packetType, packetData, packetFlags, packetPartCount, packetFirstPartId)
      if packet.t == _packet.t.D then
        socket._rdp(packet)
      elseif packet.t == _packet.t.ACK then
        socket._pack(packet)
      elseif packet.t == _packet.t.DC then
        socket.close()
      elseif packet.t == _packet.t.C then
        socket.active = true
      elseif packet.t == _packet.t.K then
        socket.lka = uptime()
      end
    end
  end

  function socket.close()
    socket.sendRaw(_packet.c(-1, _packet.t.DC))

    event.ignore(MODEM_MESSAGE, socket.receiveEvent)
    if socket.kai then
      event.cancel(socket.kai)
      socket.kai = nil
    end
    socket.active = false
  end

  --function socket.connect(timeout)
  env.modem.open(socket.port)
  event.listen(MODEM_MESSAGE, socket.receiveEvent)
  socket.sendRaw(_packet.c(-1, _packet.t.C))
  if not timeout then
    timeout = 5
  end
  local startTime = uptime()
  while not socket.active and uptime() - startTime < timeout do
    env.sleep(0.1)
  end

  if socket.active then
    socket.lka = uptime() --last keepAlive
    socket.kai = event.timer(KEEP_ALIVE_INTERVAL, socket._ka, math.huge) --keepAlive timer id
    return socket
    --return true
  end

  socket.close()
  return nil
  --return false
  --end

  --return socket
end

local function safeRun(fun, socket, err)
  local res = pcall(fun, env)
  if not res then
    socket.send(err)
    return false
  end
  return true
end

local socket
local result
local program
debug('Phase 2 started')
dns.enable()
local address = dns.getAddress('droneServer')
dns.disable()
local function loop()
  if (not socket or not socket.active) then
    socket = connection.constructor(2137, address)
    if not socket then
      debug('Phase 2: no connection')
      env.sleep(10)
      return
    end
  end
  result = socket.receive()
  if result then
    local compiled = load(result)
    if not compiled then
      socket.send('parse error')
      return
    end

    if program then
      safeRun(program.dispose, socket, 'dispose error')
    end

    local r1, r2 = pcall(compiled, env)
    if not r1 or not r2 then
      socket.send('load error')
      return
    end
    program = r2
    if not safeRun(program.setup, socket, 'setup error') then
      program = nil
    end
  end

  if program and not safeRun(program.loop, socket, 'loop error') then
    program = nil
    return
  end
end


while true do
  loop()
  env.sleep(1)
end