local dns = require('dns')

for k, v in pairs(dns.hostsByName) do
    print(k .. ' => ' .. v.address)
end