version: '3.7'

services:
  vpn-core:
    image: ubuntu:latest
    volumes:
      - ${CONFIG_ROOT}/configs:/etc/vpn-configs
    network_mode: host
    restart: always
