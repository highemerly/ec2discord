require 'dotenv'
require 'discordrb'
require 'net/http'
require 'open3'
require 'logger'
require 'sqlite3'

SSH_CONNECT_TIMEOUT = 5 #sec
SSH_STRICT_KEY_CHECK = "no"

module Ec2discord
  class Bot
    def initialize
      read_env
      set_parameter
      @bot = Discordrb::Commands::CommandBot.new(
        client_id: ENV["DC_CLIENT_ID"],
        token:     ENV["DC_BOT_TOKEN"],
        prefix:    @prefix,
      )
      @db = Ec2discordDB.new(@settings["sqlite_filepath"])
      @msg_help = Hash.new
    end

    def read_env
      if ARGV[0] == nil then
        Dotenv.load ".env"
        $log.info("Reading .env ...")
        puts "Reading .env ..."
      else
        if File.exist?(ARGV[0]) then
          Dotenv.load ARGV[0]
          $log.info("Reading #{ARGV[0].to_s} ...")
          puts "Reading #{ARGV[0].to_s} ..."
        else
          $log.fatal("Cannot open #{ARGV[0].to_s}. Existed.")
          puts "Cannot open #{ARGV[0].to_s}. Existed."
          exit
        end
      end
    end

    def set_parameter
      @prefix = ENV["DC_COMMAND_PREFIX"].nil? ? "!" : ENV["DC_COMMAND_PREFIX"].to_s
      @last_control_time = 0

      @settings = Hash.new

      @settings["start_uri"]         = URI.parse(ENV["AWS_EC2START_URI"])
      @settings["start_interval"]    = ENV["SV_START_MIN_INTERVAL"].to_i > 0 ? ENV["SV_START_MIN_INTERVAL"].to_i : 0
      @settings["stop_interval"]     = ENV["SV_STOP_MIN_INTERVAL"].to_i > 0 ? ENV["SV_STOP_MIN_INTERVAL"].to_i : 0
      @settings["service_stop_wait"] = ENV["SV_STOP_WAIT"].to_i > 0 ? ENV["SV_STOP_WAIT"].to_i : 0
      @settings["sqlite_filepath"]   = ENV["SQLITE_PATH"].nil? ? "ec2discord.db" : ENV["SQLITE_PATH"]
      @settings["default_hostname"]  = ENV["SV_SSH_HOSTNAME"].nil? ? "0.0.0.0" : ENV["SV_SSH_HOSTNAME"]

      sh_port       = ENV["SV_SSH_PORT"].nil? ? "" : " -p #{ENV["SV_SSH_PORT"]}"
      sh_user       = ENV["SV_SSH_USERNAME"].nil? ? "" : " -l #{ENV["SV_SSH_USERNAME"]}"
      sh_key        = ENV["SV_SSH_PRIVATE_KEY"].nil? ? "" : " -i #{ENV["SV_SSH_PRIVATE_KEY"]}"
      @sh_ssh       = "ssh -o StrictHostKeyChecking=#{SSH_STRICT_KEY_CHECK} -o 'ConnectTimeout #{SSH_CONNECT_TIMEOUT.to_s}'#{sh_port}#{sh_user}#{sh_key} "
    end

    def hostname
      if (@socket.ipv4_addr != nil) then
        $log.debug("Hostname check... from socket server: #{@socket}")
        @socket.ipv4_addr
      else
        $log.debug("Hostname check... from env file")
        @settings["default_hostname"]
      end
    end

    def sh_stop
      sh_stop_app   = @sh_ssh + hostname + " sudo systemctl stop " + ENV["SV_SERVICENAME"]
      sh_stop_sv    = @sh_ssh + hostname + " sudo shutdown -h now"
      sh = ENV["SV_SERVICENAME"].nil? ? sh_stop_sv : sh_stop_app + " && sleep " + @settings["service_stop_wait"].to_s + " && " + sh_stop_sv
      $log.debug(sh)
      sh
    end

    def sh_status
      sh = ENV["SV_SERVICENAME"].nil? ? @sh_ssh + hostname + " pwd" : @sh_ssh + hostname + " sudo systemctl status " + ENV["SV_SERVICENAME"] + " | grep Active"
      $log.debug(sh)
      sh
    end

    def sh_df
      sh = @sh_ssh + hostname + " LANG=C df -h /"
      $log.debug(sh)
      sh
    end

    def sh_cpu
      sh = @sh_ssh + hostname + " uptime | awk 'match($0, /average: .*/) {print substr($0,RSTART+9,RLENGTH+9)}'"
      $log.debug(sh)
      sh
    end

    def setup_command_bot
      @msg_help["server"] = "サーバ(OS)の制御要求，または状態確認を行います。"
      @bot.command :server do |event, cmd|
        case cmd
        when "start" then
          if Time.now.to_i - @last_control_time > @settings["start_interval"] then
            @last_control_time = Time.now.to_i
            res = Net::HTTP.get_response(@settings["start_uri"])
            if res.code.to_i == 200 then
              $log.debug("Success start request.")
              event.respond("サーバの起動を要求しました。しばらくお待ちください。")
            else
              $log.error("Fail to request AWS endpoint. Error code: #{res.code}, Error body: #{res.body}")
              print "Error: (", res.code, ") ",res.body
              event.respond("【Error】致命的なエラーが発生したため，サーバの起動処理に失敗しました。管理者に問合せてください。")
            end
          else
            event.respond("前回の起動要求との間隔が短すぎます。エラーを防ぐため，" + @settings["start_interval"].to_s + "秒以上待ってから再度コマンドを発行してください。")
          end
        when "stop" then
          if Time.now.to_i - @last_control_time > @settings["stop_interval"] then
            @last_control_time = Time.now.to_i
            event.respond("サーバの停止を要求します。")
            stdout, stderr = Open3.capture3(sh_stop)
            $log.debug("Success stop request.")
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
          stdout, stderr = Open3.capture3(sh_status)
          unless stderr.include?("timed")
            msg  = "サーバは起動しています。\n"
            msg += "アプリの状態は以下のとおりです。\n"
            msg += "```\n"
            msg += stdout
            msg += "```\n"
            unless @socket.ipv4_addr == nil then
              msg += "サーバのIPv4アドレスは #{@socket.ipv4_addr} です。\n"
            end
            msg
          else
            "サーバは起動していません。"
          end
        when "df" then
          msg  = "```\n"
          msg += `#{sh_df}`
          msg += "```\n"
        when "cpu" then
          msg  = "1分平均,5分平均,15分平均＝"
          msg += `#{sh_cpu}`
        else
          msg  = ""
          unless cmd == "help" || cmd == nil then
	        	msg += "存在しないコマンドです。"
	        end
          msg += "```\n"
          msg += @prefix + "server [command]\n"
          msg += "       " + @msg_help["server"] + "\n"
          msg += "\n"
          msg += " [command]\n"
          msg += "   start...サーバを起動します。\n"
          msg += "   stop....サーバを停止します。\n"
          msg += "   status..サーバとサービスの状態を表示します。\n"
          msg += "   df......サーバのディスク容量を表示します。\n"
          msg += "   cpu.....サーバのCPU利用率を表示します。\n"
          msg += "   help....このメッセージを表示します。\n"
          msg += "```\n"
        end
      end

      @msg_help["memo"] = "共有メモへの書込み/読出ができます。"
      @bot.command :memo do |event, action, *option|
      	case action
        when "register"
          @db.update_dictionary(
            key: option[0],
            value: option[1],
            author_username: event.user.name,
            author_discriminator: event.user.discriminator,
            locked: option.include?("private")
            )
        when "update"
          @db.update_dictionary(
            key: option[0],
            value: option[1],
            author_username: event.user.name,
            author_discriminator: event.user.discriminator,
            locked: option.include?("private"),
            overwrite: true
            )
        when "show"
          if option.include?("all") then
            @db.show_dictionary_all(author_discriminator: event.user.discriminator)
          elsif option.include?("user") then
            @db.show_dictionary_all(author_discriminator: option[1].to_i)
          else
            exist, msg, res = @db.show_dictionary(option[0])
            if exist then
              if option.include?("detail") then
                msg  = "```\n"
                res.each do |id, value|
                   msg += "#{id}: #{value}\n"
                end
                msg += "```\n"
              end
            end
            msg
          end
        when "delete"
          @db.delete_dictionary(
            key: option[0],
            author_discriminator: event.user.discriminator
            )
        else
          msg  = ""
          unless action == "help" || action == nil then
            msg += "存在しないコマンドです。"
          end
          msg += "```\n"
          msg += @prefix + "memo [action] (keyword) (value) (option) \n"
          msg += "       " + @msg_help["memo"] + "\n"
          msg += "\n"
          msg += " [action]\n"
          msg += "   register (keyword) (value) (option)...メモを登録します。\n"
          msg += "      └(option) private:  他人が更新できなくなります。\n"
          msg += "\n"
          msg += "   update (keyword) (value) (option).....メモを更新します。\n"
          msg += "      └(option) private:  他人が更新できなくなります。\n"
          msg += "\n"
          msg += "   show (keyword) (option)...............メモを表示します。\n"
          msg += "      └(option) detail:   詳細な情報を表示します。\n"
          msg += "                all:      自分が登録した全メモのkeywordを表示します。\n"
          msg += "                user [ID] 特定ユーザの全メモのkeywordを表示します。\n"
          msg += "                          [ID]には#の後の数字(概ね3~5桁)を入力します。\n"
          msg += "\n"
          msg += "   delete (keyword)......................メモを削除します。\n"
          msg += "   help..................................このメッセージを表示します。\n"
          msg += "\n"
          msg += " 利用例:\n"
          msg += "   #{@prefix}memo register 路線図 https://example.com/abc.png\n"
          msg += "   #{@prefix}memo show 路線図\n"
          msg += "     → 登録したURLを呼び出せます。\n"
          msg += "   #{@prefix}memo register エンドポータル 10,-4,523\n"
          msg += "   #{@prefix}memo show エンドポータル\n"
          msg += "     → 座標を登録し，上の例同様に呼び出せます。\n"
          msg += " 注意:\n"
          msg += "   - keywordとvalueには空白文字を含むことができません。\n"
          msg += "   - update後にprivateを維持したい場合は，privateを明示的に指定する必要があります。\n"
          msg += "   - keywordの名前空間は全員共通です。\n"
          msg += "```\n"
        end
      end

      @bot.command :help do |event|
        max_cmd_length = 0
        @msg_help.each do |cmd, txt|
          if cmd.length > max_cmd_length then
            max_cmd_length = cmd.length
          end
        end

        msg  = "```\n"
        @msg_help.each do |cmd, txt|
          msg += @prefix + cmd
          (max_cmd_length-cmd.length+2).times do
            msg += "."
          end
          msg += txt + "\n"
        end

        msg += @prefix + "help"
        (max_cmd_length-4+2).times do
          msg += "."
        end
        msg += "このメッセージを出力します。\n"
        msg += "```\n"
      end
    end

    def setup_socket_server
      @socket = SocketServer.new()
    end

    def setup
      setup_command_bot
      setup_socket_server
    end

    def run
      setup
      $log.info("Start bot...")
      puts "Start bot..."
      server = Thread.new { @socket.run }
      bot = Thread.new { @bot.run }
      server.join
      bot.join
    end
  end
end