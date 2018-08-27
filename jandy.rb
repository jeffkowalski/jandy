#!/usr/bin/env ruby

require 'mechanize'
require 'date'
require 'thor'


LOGFILE = File.join(Dir.home, '.jandy.log')
CREDENTIALS_PATH = File.join(Dir.home, '.credentials', "iaqualink.yaml")


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


  no_commands {
    def describe_mode mode
      case mode.to_i
      when -1
        "not available"
      when 0
        "off"
      when 1
        "running"
      when 3
        "enabled, but not running"
      else
        "not available"
      end
    end
  }


  desc "test", "testing"
  def test
    setup_logger

    require 'yaml'
    require 'rest-client'
    require 'json'

    api_key = 'EOOEMOW4YR6QNB07'
    credentials = YAML.load_file CREDENTIALS_PATH

    response = RestClient.post 'https://support.iaqualink.com/users/sign_in.json',
                               {api_key: api_key,
                                email: credentials[:username],
                                password: credentials[:password]}
    session = JSON::parse response
    puts session

    response = RestClient.get 'https://iaqualink-api.realtime.io/v1/mobile/session.json',
        	              {params: {actionID: 'command',
        	                        command: 'get_home',
                                        attached_test: 'true',
                                        country: 'us',
        	                        serial: credentials[:serial_number],
        	                        sessionID: session['session_id']}}
    status = JSON::parse response
    status = status['home_screen'].reduce(:merge)
    puts status

    # "AQU='70','0C 00 01 02 03 04 05 06 07 08 0E 0F 1A 01 00 00 00 03 00 66 00 68 00 3A 00 47 00 00 00'"
    measures = status['response'].split(',')[1].split(' ').map { |m| m.to_i(16) }
    # index 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18  19 20  21 22 23 24  25 26 27 28
    # data  0  0  1  2  3  4  5  6  7  8 14 15 26  1  0  0  0  3  0 102  0 104  0 58  0  71  0  0  0
    # data  0  0  1  2  3  4  5  6  7  8 14 15 26  1  0  0  0  1  0 102  0 104  0 60  0  71  0  0  0
    # data  0  0  1  2  3  4  5  6  7  8 14 15 26  1  0  0  0  0  0 102  0 104  0 56  0  70  0  0  0
    # 13 = pool pump?
    # 17 = solar heater
    # 19 = pool set point
    # 21 = spa set point
    # 23 = air temp
    # 25 = pool temp
    puts measures.join ' '

    response = RestClient.get 'https://iaqualink-api.realtime.io/v1/mobile/session.json',
        	              {params: {actionID: 'command',
        	                        command: 'get_onetouch',
        	                        serial: credentials[:serial_number],
        	                        sessionID: session['session_id']}}
    status = JSON::parse response
    puts status

    # res = RestClient.get "https://support.iaqualink.com/devices.json",
    #                      {params: {api_key: api_key,
    #                                authentication_token: session['authentication_token'],
    #                                user_id: session['id']}}
    # devices = JSON::parse res
    # puts devices

    # response = RestClient.post "https://support.iaqualink.com/devices/QAR2QRS8NVE2/execute_read_command.json",
    #                            {api_key: api_key,
    #                             authentication_token: session['authentication_token'],
    #                             user_id: session['id'],
    #                             command: "/alldata/read"}
    # p response.to_hash
  end

  desc "describe-status", "describe the current state of the pool"
  def describe_status
    setup_logger

    require 'yaml'
    require 'rest-client'
    require 'json'

    api_key = 'EOOEMOW4YR6QNB07'
    credentials = YAML.load_file CREDENTIALS_PATH

    response = RestClient.post 'https://support.iaqualink.com/users/sign_in.json',
                               {api_key: api_key,
                                email: credentials[:username],
                                password: credentials[:password]}
    session = JSON::parse response

    response = RestClient.get 'https://iaqualink-api.realtime.io/v1/mobile/session.json',
        	              {params: {actionID: 'command',
		                        command: 'get_home',
		                        serial: credentials[:serial_number],
		                        sessionID: session['session_id']}}
    status = JSON::parse response
    status = status['home_screen'].reduce(:merge)

    text = ["The pool temperature is #{status['pool_temp'].empty? ? 'unknown' : (status['pool_temp'] + ' degrees')}.",
            "The air temperature is #{status['air_temp'].empty? ? 'unknown' : (status['air_temp'] + ' degrees')}.",
            "The filter pump is #{describe_mode status['pool_pump']}.",
            "The solar panels are #{describe_mode status['solar_heater']}."].join "\n"
    puts text
  end

  desc "record-status", "record the current state of the pool to database"
  def record_status
    setup_logger

    require 'yaml'
    require 'rest-client'
    require 'json'

    api_key = 'EOOEMOW4YR6QNB07'
    credentials = YAML.load_file CREDENTIALS_PATH

    response = RestClient.post 'https://support.iaqualink.com/users/sign_in.json',
                               {api_key: api_key,
                                email: credentials[:username],
                                password: credentials[:password]}
    session = JSON::parse response

    response = RestClient.get 'https://iaqualink-api.realtime.io/v1/mobile/session.json',
        	              {params: {actionID: 'command',
		                        command: 'get_home',
		                        serial: credentials[:serial_number],
		                        sessionID: session['session_id']}}
    status = JSON::parse response
    status = status['home_screen'].reduce(:merge)

    timestamp = Time.now.iso8601
    open(File.join(Dir.home, '.pool.dat'), 'a') { |f|
      f.puts timestamp + "\t" + "pool_temp=#{status['pool_temp']}"  unless status['pool_temp'].empty?
      f.puts timestamp + "\t" + "air_temp=#{status['air_temp']}"    unless status['air_temp'].empty?
      f.puts timestamp + "\t" + "filter_pump=#{describe_mode(status['pool_pump'])}"
      f.puts timestamp + "\t" + "solar_heater=#{describe_mode(status['solar_heater'])}"
    }
  end

end

Jandy.start
