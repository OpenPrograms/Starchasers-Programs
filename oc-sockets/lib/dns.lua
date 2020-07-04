local component = require('component')
local packet = require('packet')
local computer = require('computer')

local dns = {}

local file = io.open("/etc/hostname")
if file then
  dns.hostname = file:read("*l")
  file:close()
end

if dns.hostname == nil or dns.hostname == '' then
  dns.hostname = component.computer.address
end

if not io.open('/etc/sockets_cfg.lua') == nil then
  local config = dofile('/etc/sockets_cfg.lua')
  dns.PORT_ARP = config.arp_port
else
  dns.PORT_ARP = 1
end

dns._modem = component.modem;
dns.hostsByName = {} --hostname:string -> {address:string, time:number}
dns.hostsByAddress = {} --address:string -> {hostname:string, time:number}



function dns.getAddress(hostname, shouldAsk)
  shouldAsk = shouldAsk or true
  if not dns.hostsByName[hostname] and shouldAsk then
    dns.askHostname(hostname)
  end
  if dns.hostsByName[hostname] then
    return dns.hostsByName[hostname].address
  end
  return nil
end

function dns.getHostname(address)
  return dns.hostsByAddress[address].hostname
end

function dns.broadcastHostname()
  dns._modem.broadcast(dns.PORT_ARP, packet.type.ARP_RESPONSE, dns.hostname)
end

function dns.askHostname(hostname, timeout)
  timeout = timeout or 2
  dns._modem.broadcast(dns.PORT_ARP, packet.type.ARP_QUESTION, hostname)

  local startTime = computer.uptime()
  while not dns.hostsByName[hostname] and computer.uptime() - startTime < timeout do
    os.sleep(0.1)
  end
end

function dns._removeExpired()
  local now = computer.uptime()
  for k, v in pairs(dns.hostsByName) do
    if v.time < now - 65 then
      dns.hostsByName[k] = nil
      dns.hostsByAddress[v.address] = nil
    end
  end
end

return dns