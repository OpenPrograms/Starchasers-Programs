--Run on computer named test1

local serverLib = require('serverSocket')
local component = require('component')

local server = serverLib.constructor(component.modem.address, 1337)
local clientSocket = server.accept()
print('Client accepted')

clientSocket.send('U there?')
print(clientSocket.receive(10))
clientSocket.close()
server.close()
print('closed')