local component = require('component')
local serverLib = require('serverSocket')

local server = serverLib.constructor(component.modem.address, 2137)
local clients = {}
local script = io.open('dronePhase3.lua', 'r'):read(10000)

while true do
  local client = server.accept()
  if client then
    print('client accepted')
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