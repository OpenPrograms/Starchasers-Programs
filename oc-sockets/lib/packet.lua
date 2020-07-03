local packet = {}

packet.type = {
  ARP_QUESTION = 0x01,
  ARP_RESPONSE = 0x02,
  ACK = 0x03,
  DATA = 0x04,
  CONNECT = 0x05, --send this to server to receive port for connection
  DISCONNECT = 0x06, --send to close connection
  KEEP_ALIVE = 0x07
}

function packet.create(id, type, data, flags, partCount, firstPartId)
  partCount = partCount or 1
  firstPartId = firstPartId or id
  data = data or ''
  flags = flags or 0
  return {
    id = id,
    type = type,
    part_count = partCount,
    first_part_id = firstPartId,
    flags = flags,
    data = data
  }
end

return packet