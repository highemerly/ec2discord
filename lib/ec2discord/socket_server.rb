require 'dotenv'
require 'net/http'
require 'logger'
require 'socket'


module Ec2discord
  class SocketServer
    def initialize
      @server = TCPServer.open(ENV["SOCKET_SERVER_PORT"])
    end

    def run
      loop do
        client = @server.accept
        res = client.recv(2048)
        client.puts "RECEIVE"

        if res.start_with?("public_ipv4:") then
          @ipv4_addr = res.delete("public_ipv4:").strip
        end
        p "[Socket Server]: Received EC2 public ipv4 address, #{@ipv4_addr}"

        client.close
      end
    end

    def ipv4_addr
      @ipv4_addr
    end
  end
end