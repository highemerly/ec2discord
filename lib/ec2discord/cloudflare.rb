require 'dotenv'
require 'httpclient'


module Ec2discord
  class CloudFlare
    def initialize

      if ENV["CLOUDFLARE_DOMAIN"].nil? || ENV["CLOUDFLARE_API_TOKEN"].nil? || ENV["CLOUDFLARE_ZONE_ID"].nil? then
        p "Error: Cloudflare configuration is not enough."
        $log.error("Cloud not start CloudFlare function.")
        exit
      end

      @client = HTTPClient.new()

      @zone_list_url = "https://api.cloudflare.com/client/v4/zones/#{ENV["CLOUDFLARE_ZONE_ID"]}/dns_records/"
      @domains = ENV["CLOUDFLARE_DOMAIN"].split(/,/)
      p @domains
      @header = [["Authorization", "Bearer #{ENV["CLOUDFLARE_API_TOKEN"]}"], ['Content-Type', 'application/json']]
      @domain_ids = Hash.new()

      @domains.each do | domain |
        query = {'type' => 'a', 'name' => domain }
        res = @client.get(@zone_list_url, query: query, header: @header, follow_redirect: true)

        unless res.code.to_i == 200
          p "Could not connect CloudFlare server."
          $log.error("[CloudFlare] Could not connect CloudFlare server. Return #{res.code.to_s}.")
        end

        json = JSON.parse(res.body)

        if json["result"].nil? then
          p "Could not find #{domain}."
          $log.error("[CloudFlare] Cloud not find #{domain}.")
        else
          @domain_ids[domain] = json["result"][0]["id"]
          p "CloudFlare: ID checked. #{domain}, #{@domain_ids[domain]}"
          $log.debug("[CloudFlare] ID checked. #{domain}, #{@domain_ids[domain]}")
        end
      end
    end

    def update(ipv4)
      @domain_ids.each do | domain, id |
        url = @zone_list_url + id
        query = {"type" => 'a', 'name' => domain , 'content' => ipv4, 'ttl' => '1'}
        res = @client.put(url, body: query.to_json, header: @header)
        unless res.code.to_i == 200
          $log.error("[CloudFlare] Cloud not update A #{domain} #{ipv4}. Return #{res.code.to_s}.")
        else
          p "[CloudFlare] Update A record #{domain}, #{ipv4}"
        end
      end
    end
  end
end