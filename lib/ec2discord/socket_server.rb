require 'net/http'
require 'logger'
require 'socket'


module Ec2discord
  class SocketServer
    def initialize(s)
      @settings = s
      @server = TCPServer.open(@settings["socket_server_port"])
      @ipv4_addr = "0.0.0.0"
      @dns = CloudFlare.new(@settings) if @settings["enable_cloudflare"]
    end

    def run
      loop do
        begin
          client = @server.accept
          res = client.recv(2048)

          if res.start_with?("public_ipv4:") then
            client.puts "RECEIVE public_ipv4"
            new_ipv4_addr = res.gsub(/public_ipv4:/,'').strip
            $log.info("[Socket Server]: Received EC2 public ipv4 address, #{new_ipv4_addr}")
            p "[Socket Server]: Received EC2 public ipv4 address, #{new_ipv4_addr}"

            unless new_ipv4_addr == @ipv4_addr then
              @ipv4_addr = new_ipv4_addr
              $log.debug("[Socket Server]: Update EC2 public ipv4 address")
              @dns.update(@ipv4_addr) if @settings["enable_cloudflare"]
            end
          else
            client.puts "RECEIVE UNRECOGNIZED DATA"
            $log.debug("[Socket Server]: Received unrecoginized data: #{res}")
          end

          client.close
        rescue => e
          $log.error("[Socket Server]: At #{e.class}, #{e.message}.")
        end
      end
    end

    def ipv4_addr
      @ipv4_addr
    end
  end
end