BOOT_SERVER_PORT = 800
BOOT_SERVER_RESPONSE_PORT = 801
DEBUG_PORT = 802
local modem = component.proxy(component.list('modem')())
local SCRIPT_RECEIVE_MAX_TIME = 5
local BOOT_REQUEST_INTERVAL = 10
local scriptParts = {}

local firstPartReceived = computer.uptime()
local lastRequestTime = -10

function debug(string)
  modem.broadcast(DEBUG_PORT, string)
end

local function loop()
  if computer.uptime() - lastRequestTime > BOOT_REQUEST_INTERVAL then
    modem.broadcast(BOOT_SERVER_PORT, 'boot_me')
    lastRequestTime = computer.uptime()
  end
  local pulledEvent = { computer.pullSignal(10) }
  if not pulledEvent then
    return
  end
  if pulledEvent[1] == 'modem_message' and pulledEvent[4] == BOOT_SERVER_RESPONSE_PORT then
    if computer.uptime() - firstPartReceived > SCRIPT_RECEIVE_MAX_TIME and #scriptParts > 0 then
      debug('Phase 1: Previous transfer took >5s. Discarding partial boot script')
      scriptParts = {}
      firstPartReceived = computer.uptime()
    end
    local partCount = pulledEvent[6]
    local partNumber = pulledEvent[7]
    local part = pulledEvent[8]
    scriptParts[partNumber] = part

    if partCount == #scriptParts then
      local loaded, err = load(table.concat(scriptParts))
      scriptParts = {}
      if not loaded then
        debug('Phase 1: Boot script parse error: ' .. err)
        return
      end

      local res, err = pcall(loaded)
      if not res then
        debug('Phase1: Boot script run error' .. err)
      end
    end
  end
end

debug('Phase 1 starting')
modem.open(BOOT_SERVER_RESPONSE_PORT)

while true do
  loop()
end