local cfg = {}
--TODO packets to send before ack
cfg.packet_retry_amount = 3  --how many times packet will be resend
cfg.packet_retry_time = 4
cfg.arp_port = 1
cfg.max_send_queue_size = 10
cfg.max_packet_size = 8192

return cfg