require 'logger'

LOG_FILENAME = "log/production.log" unless defined?(LOG_FILENAME)
LOG_LEVEL = 0 unless defined?(LOG_LEVEL)

unless ENV["LOG_FILENAME"] == nil then
  LOG_FILENAME = ENV["LOG_FILENAME"].to_s
end
unless ENV["LOG_LEVEL"] == nil then
  LOG_LEVEL = ENV["LOG_LEVEL"]
end

$log = Logger.new(LOG_FILENAME.to_s)

$log.level =
case LOG_LEVEL.to_s
  when "0", "debug", "development", "dev" then Logger::DEBUG
  when "1", "info", "test", "ci"          then Logger::INFO
  when "2", "warn"                        then Logger::WARN
  when "3", "error", "production"         then Logger::ERROR
  when "4", "fatal"                       then Logger::FATAL
end