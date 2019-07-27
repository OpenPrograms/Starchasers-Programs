local dns = {}

dns.hostsByName = {} --hostname:string -> {address:string, time:number}
dns.hostsByAddress = {} --address:string -> {hostname:string, time:number}

dns.getAddress = function(hostname)
    return dns.hostsByName[hostname].address
end

dns.getHostname = function(address)
    return dns.hostsByAddress[address].hostname
end

return dns