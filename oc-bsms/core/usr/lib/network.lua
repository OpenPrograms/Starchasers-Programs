local serialization = require("serialization")
local event = require("event")
---@type Queue
local queue = require("queue")

local connectionManager = {
    connections = {}
}

---@param connection connection
function connectionManager.addConnection(connection)
    local modemaddr = connection.modem.address
    local port = connection.clientPort
    local remoteaddr = connection.address
    if connectionManager.getConnectionList(modemaddr, port)[remoteaddr] == nil then
        connectionManager.getConnectionList(modemaddr, port)[remoteaddr] = connection
        return true
    else
        return false
    end
end

---@param modemAddr string
function connectionManager.getPortList(modemAddr)
    if connectionManager.connections[modemAddr] == nil then
        connectionManager.connections[modemAddr] = {}
    end
    return connectionManager.connections[modemAddr]
end

---@param modemAddr string
function connectionManager.getConnectionList(modemAddr, port)
    if connectionManager.getPortList(modemAddr) == nil then
        connectionManager.getPortList(modemAddr)[port] = {}
    end
    return connectionManager.getPortList(modemAddr)[port]
end

---@param modemAddr string
---@param port number
---@param remoteAddr string
---@return connection
function connectionManager.getConnection(modemAddr, port, remoteAddr)
    local portList = connectionManager.getPortList(modemAddr)
    if portList == nil then
        return nil
    end
    local connectionList = portList[port]
    if connectionList == nil then
        return nil
    end
    return connectionList[remoteAddr]
end

---@class network
---@field protected headerSize number
local network = {
    portStart = 6000,
    headerSize = 8 + 8 + 1 + 6 + 2,
    connections = connectionManager,
    attempts = 20
}

---@class connectionState
local connectionState = {
    NEW = 0,
    ACCEPTED = 1,
    CLOSED = 2
}

local messageType = {
    HANDSHAKE = 0,
    ACCEPTED = 1,
    ACK = 2,
    MESSAGE = 3
}

---@class connection
---@field protected modem modem
---@field protected address string
---@field protected port number
---@field protected clientPort number
---@field protected maxPacketSize number
---@field protected packetParts table
---@field protected packetBuff Queue
---@field protected connectionState connectionState
local connection = {
}

function connection.new(modem, address, port, clientPort)
    local newConnection = {
        modem = modem,
        address = address, -- remote address
        port = port, -- remote port
        clientPort = clientPort, -- local port
        packetId = 0,
        packetBuff = queue.new(),
        packetParts = {},
        connectionState = connectionState.NEW
    }
    setmetatable(newConnection, connection)
end

function connection:send(message)
    ---@type string
    messageS = serialization.serialize(message)
    if (#messageS > messageMaxSize) then
        messageS:sub(1, messageMaxSize) --part
        messageS = messageS:sub(messageMaxSize + 1, #messageS)
    end

end

function connection:receive()

end

function connection:receive()

end

function connection:receiveRaw(id, part, type, message)
    if type == messageType.ACCEPTED then
        self.connectionState = connectionState.ACCEPTED
    elseif type == messageType.ACK then
        

    if type == messageType.MESSAGE then
        self.modem.send(self.address, self.port, id, messageType.ACK, nil)
        if self.packetParts[id] == nil then
            self.packetParts[id] = message
        end
        if not part then
            local fullMessage = ""
            for i, p in pairs(self.packetParts) do
                fullMessage = fullMessage .. p.message
            end
            finalMessage = serialization.unserialize(fullMessage)
            self.packetBuff:Add(finalMessage)
        end
    end
end

function connection:state()

end

function connection:close()
    network.connections.getConnectionList(self.modem.address, self.clientPort)
end

---@param modem modem
local function findFreePort(modem)
    local port = network.portStart
    while modem.isOpen(port) do
        port = port + 1
    end
    return port
end

---@param clientPort number
local function createHandshake(clientPort)
    return 0, false, messageType.HANDSHAKE, clientPort
end

---@param id number
local function createHandshake(id)
    return 0, false, messageType.ACK, id
end

---@param connection connection
local function waitForAccept(connection)
    local i = 1
    while connection.state() ~= connectionState.ACCEPTED do
        if i > network.attempts then
            return false
        end
        os.sleep(0.1)
        i = i + 1
    end
    return true
end

---@param modem modem modem
---@param address string remote address
---@param port
---@return connection
function network.openClientSocket(modem, address, port)
    local clientPort = findFreePort(modem)
    modem.open(clientPort)
    local conn = connection.new()
    network.connections.addConnection(conn)
    modem.send(address, port, createHandshake(clientPort))
    if waitForAccept(conn) then
        return conn
    end
    conn:close()
    return nil
end

---@param modem modem modem
---@param port
---@return connection
function network.openServerSocket(modem, port)

end

function network.init()
    event.listen("modem_message", function(modemAddr, from, port, dist, id, part, type, message)
        local conn = network.connections.getConnection(modemAddr, port, from)
        if conn ~= nil then
            conn:receiveRaw(id, part, type, message)
        end
    end)
end

function network.stop()

end


--[[
------
socket = network.openServerSocket(modem, 45)
connection = socket.accept()
connection.send()
connection.receive()
connection.close()

----
connection = network.openClientSocket(modem, "serveraddres", 45)
connection.send()
connection.receive()
connection.close()
--]]
return network