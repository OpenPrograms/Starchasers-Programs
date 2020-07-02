local event = require('event')
local computer = require('computer')
local dns = require('dns')
local _packet = require('packet')


--
TYPE_ARP = 0x01 --not used because arp uses own port
TYPE_ACK = 0x02
TYPE_DATA = 0x03


-- "hostname" => {address, time}
-- "address" => {hostname, time}
local sendTimerId
local expireTimerId
local hostname

local function receive(_, _, remoteAddress, port, _, type, msg)
  if port == dns.PORT_ARP then
    if type == _packet.type.TYPE_ARP_RESPONSE and msg then
      local now = computer.uptime()
      dns.hostsByName[msg] = { address = remoteAddress, time = now }
      dns.hostsByAddress[remoteAddress] = { hostname = msg, time = now }
    elseif type == _packet.type.TYPE_ARP_QUESTION and msg and msg == dns.hostname then
      dns._modem.send(remoteAddress, dns.PORT_ARP, _packet.type.TYPE_ARP_RESPONSE, dns.hostname)
    end
  end
end

----


dns._modem.open(dns.PORT_ARP)
dns.broadcastHostname()
event.listen('modem_message', receive)
sendTimerId = event.timer(60, dns.broadcastHostname, math.huge)
expireTimerId = event.timer(30, dns._removeExpired, math.huge)
