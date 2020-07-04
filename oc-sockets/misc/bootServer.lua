local component = require('component')
local event = require('event')

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
    print('sending boot script to ' .. remoteAddress)
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

while true do
  os.sleep(5)
end