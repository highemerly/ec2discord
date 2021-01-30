require 'dotenv'
require 'net/http'
require 'logger'
require 'socket'


module Ec2discord
  class SocketServer
    def initialize
      @server = TCPServer.open(ENV["SOCKET_SERVER_PORT"])
      @dns = CloudFlare.new() if ENV["CLOUDFLARE"] = "true"
    end

    def run
      loop do
        begin
          client = @server.accept
          res = client.recv(2048)
          client.puts "RECEIVE"

          if res.start_with?("public_ipv4:") then
            @ipv4_addr = res.gsub(/public_ipv4:/,'').strip
          end
          p "[Socket Server]: Received EC2 public ipv4 address, #{@ipv4_addr}"
          $log.info("[Socket Server]: Recieved EC2 public ipv4 address, #{ipv4_addr}")

          @dns.update(@ipv4_addr)

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