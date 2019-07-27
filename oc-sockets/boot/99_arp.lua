local event = require('event')
local computer = require('computer')
local component = require('component')
local modem = component.modem;
local dns = require('dns')

if not io.open('/etc/sockets_cfg.lua') == nil then
    local config = dofile('/etc/sockets_cfg.lua')
    PORT_ARP = config.arp_port
else
    PORT_ARP = 1
end


--
TYPE_ARP = 0x01 --not used because arp uses own port
TYPE_ACK = 0x02
TYPE_DATA = 0x03


-- "hostname" => {address, time}
-- "address" => {hostname, time}
local sendTimerId
local expireTimerId
local hostname

local function receive(_, _, remoteAddress, port, _, msg)
    if port == 1 then
        local now = computer.uptime()
        dns.hostsByName[msg] = { address = remoteAddress, time = now }
        dns.hostsByAddress[remoteAddress] = { hostname = msg, time = now }
    end
end

local function send()
    modem.broadcast(PORT_ARP, hostname)
end

local function expire()
    local now = computer.uptime()
    for k, v in pairs(dns.hostsByName) do
        if v.time < now - 10 then
            dns.hostsByName[k] = nil
            dns.hostsByAddress[v.address] = nil
        end
    end
end

----
local file = io.open("/etc/hostname")
if file then
    hostname = file:read("*l")
    file:close()
end

if hostname == nil or hostname == '' then
    print("Hostname not set\n")
    return
end
modem.open(1)
send()
event.listen('modem_message', receive)
sendTimerId = event.timer(10, send, math.huge)
expireTimerId = event.timer(15, expire, math.huge)

