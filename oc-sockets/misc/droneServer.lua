local component = require('component')
local event = require('event')
local serverLib = require('serverSocket')

local arg = {...}
if not arg[1] or not arg[2] then
  print('Usage: droneServer droneScript port')
  return
end

local modem = component.modem
local BOOT_SERVER_PORT = 800
local BOOT_SERVER_RESPONSE_PORT = 801
local DEBUG_PORT = 802
local PACKET_MAX_PAYLOAD_SIZE = 6000
local bootScript = io.open('dronePhase2.lua'):read(100000)
local chunks = {}
for i = 1, math.ceil(#bootScript / PACKET_MAX_PAYLOAD_SIZE) do
  chunks[#chunks + 1] = bootScript:sub(PACKET_MAX_PAYLOAD_SIZE * (i - 1) + 1, PACKET_MAX_PAYLOAD_SIZE * i)
end

local function receive(_, localAddress, remoteAddress, event_port, _, message)
  if event_port == BOOT_SERVER_PORT then
    print('sending phase 2 boot script to ' .. remoteAddress)
    for k, v in pairs(chunks) do
      modem.send(remoteAddress, BOOT_SERVER_RESPONSE_PORT, #chunks, k, v)
    end
  elseif event_port == DEBUG_PORT then
    print(remoteAddress .. ' says ' .. message)
  end
end

modem.open(BOOT_SERVER_PORT)
modem.open(DEBUG_PORT)

event.listen('modem_message', receive)

local server = serverLib.constructor(component.modem.address, tonumber(arg[2]))
local clients = {}
local script = io.open(arg[1], 'r'):read(10000)

while true do
  local client = server.accept()
  if client then
    print('Phase 2 client accepted')
    client.send(script)
    table.insert(clients, client)
  end
  for k,v in pairs(clients) do
    local message = v.receive()
    if message then
      print(message)
    end
  end
  os.sleep(1)
end