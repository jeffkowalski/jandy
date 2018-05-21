#!/usr/bin/env ruby

require 'mechanize'
require 'date'
require 'thor'
require 'json'


LOGFILE = File.join(Dir.home, '.jandy.log')
CREDENTIALS_PATH = "credentials.yml"


class Jandy < Thor
  no_commands {
    def redirect_output
      unless LOGFILE == 'STDOUT'
        logfile = File.expand_path(LOGFILE)
        FileUtils.mkdir_p(File.dirname(logfile), :mode => 0755)
        FileUtils.touch logfile
        File.chmod 0644, logfile
        $stdout.reopen logfile, 'a'
      end
      $stderr.reopen $stdout
      $stdout.sync = $stderr.sync = true
    end

    def setup_logger
      redirect_output if options[:log]

      $logger = Logger.new STDOUT
      $logger.level = options[:verbose] ? Logger::DEBUG : Logger::INFO
      $logger.info 'starting'
    end
  }

  class_option :log,     :type => :boolean, :default => true, :desc => "log output to ~/.jandy.log"
  class_option :verbose, :type => :boolean, :aliases => "-v", :desc => "increase verbosity"


  desc "zzz", "testing"
  def zzz
    setup_logger


    credentials = YAML.load_file CREDENTIALS_PATH

    api_key = 'EOOEMOW4YR6QNB07'
    device_serial = credentials[:serial].tr('-','')
    session_id = nil

    uri = URI.parse('https://support.iaqualink.com')
    https = Net::HTTP.new(uri.host,uri.port)
    https.use_ssl = true
    https.verify_mode = OpenSSL::SSL::VERIFY_NONE

    https.start do |https|
      puts "\n--------------------------------------------------------------------------\n"
      uri = URI.parse('https://support.iaqualink.com/users/sign_in.json')
      puts uri
      req = Net::HTTP::Post.new(uri.path)
      req.body = {'api_key' => api_key,
                  'email' => credentials[:username],
                  'password' => credentials[:password]}.to_json

      req['content-type'] = 'application/json'
      p req.to_hash
      res = https.request(req)

      p "Response:"
      puts res
      res.header.each_header {|key,value| puts "#{key} = #{value}" }
      puts res.body

      result = JSON::parse(res.body)
      session_id = result['session_id']
      authentication_token = result['authentication_token']
      user_id = result['id'].to_s

      puts "\n--------------------------------------------------------------------------\n"

      uri = URI.parse('https://support.iaqualink.com/devices.json' +
                      '?api_key=' + api_key +
                      '&authentication_token=' + authentication_token +
                      '&user_id=' + user_id)
      puts uri
      req = Net::HTTP::Get.new(uri.path)
      p req.to_hash
      res = https.request(req)

      p "Response:"
      puts res
      res.header.each_header {|key,value| puts "#{key} = #{value}" }
      puts res.body

    end

    puts "\n--------------------------------------------------------------------------\n"

    uri = URI.parse('https://iaqualink-api.realtime.io/v1/mobile/session.json' +
	            '?actionID=command' +
	            '&command=get_home' +
	            '&serial=' + device_serial +
	            '&sessionID=' + session_id)
    puts uri
    https = Net::HTTP.new(uri.host,uri.port)
    https.use_ssl = true
    https.verify_mode = OpenSSL::SSL::VERIFY_NONE
    req = Net::HTTP::Get.new(uri.path)
    res = https.request(req)
    puts "Response:"
    puts res
    res.header.each_header {|key,value| puts "#{key} = #{value}" }
    puts res.body


    puts "\n--------------------------------------------------------------------------\n"
    uri = URI.parse("https://zodiac-ha-api.realtime.io/v1/mobile/session.json")
    puts uri
    https = Net::HTTP.new(uri.host,uri.port)
    https.use_ssl = true
    https.verify_mode = OpenSSL::SSL::VERIFY_NONE
    req = Net::HTTP::Post.new(uri.path)
    req['content-type'] = 'application/json'
    req.body = {'api_key' => api_key,
                'username' => credentials[:username],
                'password' => credentials[:password]}.to_json
    puts req.to_hash
    res = https.request(req)
    puts "Response:"
    puts res
    res.header.each_header {|key,value| puts "#{key} = #{value}" }
    puts res.body

  end

  desc "get-temp", "get temperature"
  def get_temp
    setup_logger

    begin
      @agent = Mechanize.new { |a|
        #a.user_agent_alias = 'Windows IE 10'
        #a.user_agent = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.75 Safari/537.36'
        a.agent.http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        a.log = $logger if options[:verbose]
      }

      #page = @agent.get "https://www.iaqualink.com/en/#/manage-pool"

      $logger.info "logging in"
      page = @agent.get "https://iaqualink.zodiacpoolsystems.com/start/iAqua3/?lang=en&sub=us"
      puts page.form_with(:name => "signin")
      credentials = YAML.load_file CREDENTIALS_PATH
      page = page.form_with(:name => "signin") do |login|
        login.userID = credentials[:username]
        login.userPassword = credentials[:password]
      end.submit
      #puts page.content

      $logger.info "getting locations"
      page = @agent.get "json/locations.json"
      #puts page.body
      require 'json'
      my_hash = JSON.parse(page.body, :symbolize_names => true)
      link = (my_hash[:locations].find { |loc| loc[:Name] == credentials[:location] })[:Link]
      puts link

      $logger.info "getting touch interface"
      page = @agent.get "https://touch.zodiacpoolsystems.com/?actionID=#{link}"
      #puts page.content

      $logger.info "getting stream"
      # e.g. xhr.open("GET", "/2S/WBJQCNAKLXU6TP825KI3/3TA02FMC1V", true);
      stream = page.content[/xhr\.open.*?"GET"\s*,\s*"(.*)"\s*,\s*true.*?;/, 1]
      #puts stream

      # puts @agent.cookies.join("; ")
      # require 'typhoeus'
      # request = Typhoeus::Request.new("https://touch.zodiacpoolsystems.com/#{stream}",
      #                                 headers: { cookie: @agent.cookies.join(";") },
      #                                 ssl_verifypeer: false)
      # request.on_body do |chunk|
      #   puts chunk
      #   exit
      # end
      # request.run

      # request-header: accept-encoding => gzip,deflate,identity
      # request-header: accept => */*
      # request-header: user-agent => Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.75 Safari/537.36
      # request-header: accept-charset => ISO-8859-1,utf-8;q=0.7,*;q=0.7
      # request-header: accept-language => en-us,en;q=0.5
      # request-header: cookie => newIOSession=ID%3DL7LCH1F29RZSFB21ZLJLH1Q9JOYSMIQN
      # request-header: host => touch.zodiacpoolsystems.com


      #  page = @agent.get_file uri
      #  page = @agent.agent.fetch uri
      #  puts page.content

      uri = URI.parse "https://touch.zodiacpoolsystems.com#{stream}"
      method = :get
      headers = {}
      params = []
      referer = @agent.agent.current_page
      redirects = 0

      referer_uri = referer ? referer.uri : nil
      uri         = @agent.agent.resolve uri, referer
      uri, params = @agent.agent.resolve_parameters uri, method, params
      request     = @agent.agent.http_request uri, method, params
      connection  = @agent.agent.connection_for uri

      @agent.agent.request_auth             request, uri
      @agent.agent.disable_keep_alive       request
      @agent.agent.enable_gzip              request
      @agent.agent.request_language_charset request
      @agent.agent.request_cookies          request, uri
      @agent.agent.request_host             request, uri
      @agent.agent.request_referer          request, uri, referer_uri
      @agent.agent.request_user_agent       request
      @agent.agent.request_add_headers      request, headers
      @agent.agent.pre_connect              request

      @agent.agent.request_log request

      begin
        response = connection.request(uri, request) { |res|
          @agent.agent.response_log res
          #      response_body_io = @agent.agent.response_read res, request, uri
          res.read_body { |part|
            p part
          }
          # res
        }
      rescue Mechanize::ChunkedTerminationError => e
        raise unless @ignore_bad_chunking

        response = e.response
        response_body_io = e.body_io
      end

    rescue Exception => e
      $logger.error e.message
      $logger.error e.backtrace.inspect
    end
  end

end

Jandy.start




__END__
class CookieJar < Hash
  def to_s
    self.map { |key, value| "#{key}=#{value}"}.join("; ")
  end

  def parse(cookie_strings)
    cookie_strings.each { |s|
      key, value = s.split('; ').first.split('=', 2)
      self[key] = value
    }
    self
  end
end

# Use like this:
response = Typhoeus::Request.get("http://www.example.com")
cookies = CookieJar.new.parse(response.headers_hash["Set-Cookie"])
Typhoeus::Request.get("http://www.example.com", headers: {Cookie: cookies.to_s})
