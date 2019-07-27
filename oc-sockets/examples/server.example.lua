--Run on computer named test1

local serverLib = require('serverSocket')
local component = require('component')

local server = serverLib.constructor(component.modem.address, 1337)
local socket = server.accept()

socket.send('U there?')
print(socket.receive(10))
socket.close()