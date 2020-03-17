require 'dotenv'
require 'discordrb'
require 'net/http'
require 'open3'

module Ec2discord
  class Bot
    def initialize
      set_env
      @bot = Discordrb::Commands::CommandBot.new(
        client_id: ENV["DC_CLIENT_ID"],
        token:     ENV["DC_BOT_TOKEN"],
        prefix:    @prefix,
      )
    end

    def set_env
      @prefix = ENV["DC_COMMAND_PREFIX"].nil? ? "!" : ENV["DC_COMMAND_PREFIX"].to_s
      @last_control_time = 0

      @settings = Hash.new

      @settings["start_uri"]      = URI.parse(ENV["AWS_EC2START_URI"])
      @settings["start_interval"] = ENV["SV_START_MIN_INTERVAL"].to_i > 0 ? ENV["SV_START_MIN_INTERVAL"].to_i : 0
      @settings["stop_interval"]  = ENV["SV_STOP_MIN_INTERVAL"].to_i > 0 ? ENV["SV_STOP_MIN_INTERVAL"].to_i : 0

      @sh = Hash.new

      hostname      = ENV["SV_SSH_HOSTNAME"].nil? ? "localhost" : ENV["SV_SSH_HOSTNAME"]
      sh_ssh        = "ssh -o 'ConnectTimeout 5' "
      sh_stop_app   = ENV["SV_SERVICENAME"].nil? ? "" : sh_ssh + hostname + " sudo systemctl stop " + ENV["SV_SERVICENAME"]
      sh_stop_sv    = sh_ssh + hostname + " sudo shutdown -h now"

      @sh["stop"]   = ENV["SV_SERVICENAME"].nil? ? sh_stop_sv : sh_stop_app + " && sleep " + ENV["SV_STOP_WAIT"] + " && " + sh_stop_sv
      @sh["status"] = ENV["SV_SERVICENAME"].nil? ? "" : sh_ssh + hostname + " sudo systemctl status " + ENV["SV_SERVICENAME"] + " | grep Active"
      @sh["df"]     = "ssh " + hostname + " LANG=C df -h /"
      @sh["cpu"]    = "ssh " + hostname + " uptime | awk '{print $10 $11 $12}'"
    end

    def run
      setup
      @bot.run
    end

    def setup
      @bot.command :server do |event, cmd|
        case cmd
        when "start" then
          if Time.now.to_i - @last_control_time > @settings["start_interval"] then
            @last_control_time = Time.now.to_i
            res = Net::HTTP.get_response(@settings["start_uri"])
            if res.code.to_i == 200 then
              event.respond("サーバの起動を要求しました。しばらくお待ちください。")
            else
              print "Error: (", res.code, ") ",res.body
              event.respond("【Error】致命的なエラーが発生したため，サーバの起動処理に失敗しました。管理者に問合せてください。")
            end
          else
            event.respond("前回の起動要求との間隔が短すぎます。エラーを防ぐため，" + @settings["start_interval"].to_s + "秒以上待ってから再度コマンドを発行してください。")
          end
        when "stop" then
          if Time.now.to_i - @last_control_time > @settings["stop_interval"] then
            @last_control_time = Time.now.to_i
            event.respond("サーバの停止を要求しました。")
            stdout, stderr = Open3.capture3(@sh["stop"])
            if (stdout+stderr).include?("closed")
              event.respond("サーバの電源がオフになりました。ご利用ありがとうございました。")
            elsif stderr.include?("timed")
              event.respond("サーバに接続出来ません。サーバが起動していない可能性があります。")
            else
              print stderr
              event.respond("【Error】サーバの終了を確認出来ませんでした。管理者に問い合わせてください。")
            end
          else
            event.respond("前回の起動要求との間隔が短すぎます。エラーを防ぐため，" + @settings["stop_interval"].to_s + "秒以上待ってから再度コマンドを発行してください。")
          end
        when "status" then
          stdout, stderr = Open3.capture3(@sh["status"])
          unless stderr.include?("timed")
            msg  = "サーバは起動しています。\n"
            msg += "アプリの状態は以下のとおりです。\n"
            msg += "```\n"
            msg += stdout
            msg += "```\n"
          else
            "サーバは起動していません。"
          end
        when "df" then
          msg  = "```\n"
          msg += `#{@sh["df"]}`
          msg += "```\n"
        when "cpu" then
          msg  = "1分平均,5分平均,15分平均＝"
          msg += `#{@sh["cpu"]}`
        else
          msg  = "不正なコマンドです。"
          msg += "```\n"
          msg += @prefix + "server start: サーバを起動します\n"
          msg += @prefix + "server stop: サーバを停止します\n"
          msg += @prefix + "server status: サービスの状態を表示します\n"
          msg += @prefix + "server df: サーバのディスク状態を表示します\n"
          msg += @prefix + "server cpu: CPUロードアベレージを表示します\n"
          msg += "```\n"
        end
      end

      @bot.command :help do |event|
        msg  = "```\n"
        msg += @prefix + "server [command]: サーバの起動・終了をします（command: start or stop）。\n"
        msg += @prefix + "help : このメッセージを出力します。\n"
        msg += "```\n"
      end
    end
  end
end