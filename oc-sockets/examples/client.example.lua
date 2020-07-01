--Run on computer named test2

local clientLib = require('clientSocket')
local component = require('component')
local dns = require('dns')

local client = clientLib.constructor(component.modem.address, dns.getAddress('cmp1'),1337)
if not client.connect() then
  print('unable to connect')
  return
end
print('connected')
print(client.receive(10))
client.send('Yup')
client.close()