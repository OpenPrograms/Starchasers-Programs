--Run on computer named test2

local clientLib = require('clientSocket')
local component = require('component')
local dns = require('dns')

local client = clientLib.constructor(component.modem.address, dns.getAddress('test1'),1337)
client.connect()
print('connected')
print(client.receive(10))
client.send('Yup')
client.close()
print('closed')