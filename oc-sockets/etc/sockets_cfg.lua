local cfg = {}
cfg.packet_retry_amount = 3  --how many times packet will be resend
cfg.packet_retry_time = 4
cfg.arp_port = 1
cfg.max_active_packets = 10 --how many packets can wait for ack at the same time. Following packets will be queued
cfg.max_packet_size = 8192
cfg.keep_alive_interval = 20

return cfg