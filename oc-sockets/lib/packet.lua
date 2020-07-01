local packet = {}

packet.type = {
  TYPE_ARP = 0x01,
  TYPE_ACK = 0x02,
  TYPE_DATA = 0x03,
  TYPE_CONNECT = 0x04, --send this to server to receive port for connection
  TYPE_DISCONNECT = 0x05 --send to close connection
}

function packet.create(id, type, data, partCount, firstPartId)
  partCount = partCount or 1
  firstPartId = firstPartId or id
  data = data or {}
  return {
    id = id,
    type = type,
    part_count = partCount,
    first_part_id = firstPartId,
    data = data
  }
end

return packet