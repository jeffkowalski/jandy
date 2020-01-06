#!/usr/bin/env ruby
# frozen_string_literal: true

require 'date'
require 'thor'
require 'influxdb'
require 'yaml'
require 'rest-client'
require 'json'

LOGFILE = File.join(Dir.home, '.log', 'jandy.log')
CREDENTIALS_PATH = File.join(Dir.home, '.credentials', 'iaqualink.yaml')

class Jandy < Thor
  no_commands do
    def redirect_output
      unless LOGFILE == 'STDOUT'
        logfile = File.expand_path(LOGFILE)
        FileUtils.mkdir_p(File.dirname(logfile), mode: 0o755)
        FileUtils.touch logfile
        File.chmod 0o644, logfile
        $stdout.reopen logfile, 'a'
      end
      $stderr.reopen $stdout
      $stdout.sync = $stderr.sync = true
    end

    def setup_logger
      redirect_output if options[:log]

      @logger = Logger.new STDOUT
      @logger.level = options[:verbose] ? Logger::DEBUG : Logger::INFO
      @logger.info 'starting'
    end
  end

  class_option :log,     type: :boolean, default: true, desc: "log output to #{LOGFILE}"
  class_option :verbose, type: :boolean, aliases: '-v', desc: 'increase verbosity'

  no_commands do
    def describe_mode(mode)
      case mode.to_i
      when -1
        'not available'
      when 0
        'off'
      when 1
        'running'
      when 3
        'enabled, but not running'
      else
        'not available'
      end
    end
  end

  desc 'test', 'testing'
  def test
    setup_logger

    require 'yaml'
    require 'rest-client'
    require 'json'

    api_key = 'EOOEMOW4YR6QNB07'
    credentials = YAML.load_file CREDENTIALS_PATH

    @logger.info 'Session'
    response = RestClient.post 'https://support.iaqualink.com/users/sign_in.json',
                               api_key: api_key,
                               email: credentials[:username],
                               password: credentials[:password]
    session = JSON.parse response
    puts session

    @logger.info 'get_home'
    response = RestClient.get 'https://iaqualink-api.realtime.io/v1/mobile/session.json',
                              params: { actionID: 'command',
                                        command: 'get_home',
                                        attached_test: 'true',
                                        country: 'us',
                                        serial: credentials[:serial_number],
                                        sessionID: session['session_id'] }
    status = JSON.parse response
    @logger.info 'get_home - home_screen'
    status = status['home_screen'].reduce(:merge)
    puts status

    @logger.info 'get_home - response'
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

    @logger.info 'get_onetouch'
    response = RestClient.get 'https://iaqualink-api.realtime.io/v1/mobile/session.json',
                              params: { actionID: 'command',
                                        command: 'get_onetouch',
                                        serial: credentials[:serial_number],
                                        sessionID: session['session_id'] }
    status = JSON.parse response
    puts status

    @logger.info 'get_devices'
    response = RestClient.get 'https://iaqualink-api.realtime.io/v1/mobile/session.json',
                              params: { actionID: 'command',
                                        command: 'get_devices',
                                        serial: credentials[:serial_number],
                                        sessionID: session['session_id'] }
    devices = JSON.parse response
    # {"message"=>"",
    #  "devices_screen"=>[{"status"=>"Online"},
    #                     {"response"=>"AQU='72','7|1|2|3|4|5|6|7|0|1|0|0|Cleaner|0|1|0|0|Air Blower|0|1|0|0|Aux3|0|1|0|0|Aux4|0|1|0|0|Aux5|0|1|0|0|Aux6|0|1|0|0|Aux7'"},
    #                     {"group"=>"1"},
    #                     {"aux_1"=>[{"state"=>"0"}, {"label"=>"Cleaner"},    {"icon"=>"aux_1_0.png"}, {"type"=>"0"}, {"subtype"=>"0"}]},
    #                     {"aux_2"=>[{"state"=>"0"}, {"label"=>"Air Blower"}, {"icon"=>"aux_1_0.png"}, {"type"=>"0"}, {"subtype"=>"0"}]},
    #                     {"aux_3"=>[{"state"=>"0"}, {"label"=>"Aux3"},       {"icon"=>"aux_1_0.png"}, {"type"=>"0"}, {"subtype"=>"0"}]},
    #                     {"aux_4"=>[{"state"=>"0"}, {"label"=>"Aux4"},       {"icon"=>"aux_1_0.png"}, {"type"=>"0"}, {"subtype"=>"0"}]},
    #                     {"aux_5"=>[{"state"=>"0"}, {"label"=>"Aux5"},       {"icon"=>"aux_1_0.png"}, {"type"=>"0"}, {"subtype"=>"0"}]},
    #                     {"aux_6"=>[{"state"=>"0"}, {"label"=>"Aux6"},       {"icon"=>"aux_1_0.png"}, {"type"=>"0"}, {"subtype"=>"0"}]},
    #                     {"aux_7"=>[{"state"=>"0"}, {"label"=>"Aux7"},       {"icon"=>"aux_1_0.png"}, {"type"=>"0"}, {"subtype"=>"0"}]}]}
    puts devices
    aux = devices['devices_screen'].select do |node|
      !node.keys.grep(/aux_/).empty? && (node.values.first.reduce({}, :merge)['label'] == 'Cleaner')
    end
    cleaner = aux.first.values.first.reduce({}, :merge)
    puts cleaner

    @logger.info 'devices.json'
    res = RestClient.get 'https://support.iaqualink.com/devices.json',
                         params: { api_key: api_key,
                                   authentication_token: session['authentication_token'],
                                   user_id: session['id'] }
    devices = JSON.parse res
    puts devices

    # response = RestClient.post 'https://support.iaqualink.com/devices/QAR2QRS8NVE2/execute_read_command.json',
    #                            {api_key: api_key,
    #                             authentication_token: session['authentication_token'],
    #                             user_id: session['id'],
    #                             command: '/alldata/read'}
    # p response.to_hash
  end

  desc 'describe-status', 'describe the current state of the pool'
  def describe_status
    setup_logger

    require 'yaml'
    require 'rest-client'
    require 'json'

    api_key = 'EOOEMOW4YR6QNB07'
    credentials = YAML.load_file CREDENTIALS_PATH

    response = RestClient.post 'https://support.iaqualink.com/users/sign_in.json',
                               api_key: api_key,
                               email: credentials[:username],
                               password: credentials[:password]
    session = JSON.parse response

    response = RestClient.get 'https://iaqualink-api.realtime.io/v1/mobile/session.json',
                              params: { actionID: 'command',
                                        command: 'get_home',
                                        serial: credentials[:serial_number],
                                        sessionID: session['session_id'] }
    status = JSON.parse response
    status = status['home_screen'].reduce(:merge)

    response = RestClient.get 'https://iaqualink-api.realtime.io/v1/mobile/session.json',
                              params: { actionID: 'command',
                                        command: 'get_devices',
                                        serial: credentials[:serial_number],
                                        sessionID: session['session_id'] }
    devices = JSON.parse response
    aux = devices['devices_screen'].select do |node|
      !node.keys.grep(/aux_/).empty? && (node.values.first.reduce({}, :merge)['label'] == 'Cleaner')
    end
    cleaner = aux.first.values.first.reduce({}, :merge)

    text = ["The pool temperature is #{status['pool_temp'].empty? ? 'unknown' : (status['pool_temp'] + ' degrees')}.",
            "The air temperature is #{status['air_temp'].empty? ? 'unknown' : (status['air_temp'] + ' degrees')}.",
            "The filter pump is #{describe_mode status['pool_pump']}.",
            "The solar panels are #{describe_mode status['solar_heater']}.",
            "The cleaner is #{describe_mode cleaner['state']}."].join "\n"
    puts text
  end

  desc 'record-status', 'record the current state of the pool to database'
  method_option :dry_run, type: :boolean, aliases: '-d', desc: 'do not write to database'
  def record_status
    setup_logger

    begin
      api_key = 'EOOEMOW4YR6QNB07'
      credentials = YAML.load_file CREDENTIALS_PATH

      response = RestClient.post 'https://support.iaqualink.com/users/sign_in.json',
                                 api_key: api_key,
                                 email: credentials[:username],
                                 password: credentials[:password]
      session = JSON.parse response

      response = RestClient.get 'https://iaqualink-api.realtime.io/v1/mobile/session.json',
                                params: { actionID: 'command',
                                          command: 'get_home',
                                          serial: credentials[:serial_number],
                                          sessionID: session['session_id'] }
      status = JSON.parse response
      status = status['home_screen'].reduce(:merge)
      @logger.info status

      response = RestClient.get 'https://iaqualink-api.realtime.io/v1/mobile/session.json',
                                params: { actionID: 'command',
                                          command: 'get_devices',
                                          serial: credentials[:serial_number],
                                          sessionID: session['session_id'] }
      devices = JSON.parse response
      aux = devices['devices_screen'].select do |node|
        !node.keys.grep(/aux_/).empty? && (node.values.first.reduce({}, :merge)['label'] == 'Cleaner')
      end
      cleaner = aux.first.values.first.reduce({}, :merge)

      influxdb = InfluxDB::Client.new 'jandy'
      timestamp = Time.now.to_i

      data = {
        values: { value: status['pool_pump'].to_i, description: describe_mode(status['pool_pump']) },
        timestamp: timestamp
      }
      influxdb.write_point('filter_pump', data) unless options[:dry_run]

      data = {
        values: { value: status['solar_heater'].to_i, description: describe_mode(status['solar_heater']) },
        timestamp: timestamp
      }
      influxdb.write_point('solar_heater', data) unless options[:dry_run]

      data = {
        values: { value: cleaner['state'].to_i, description: describe_mode(cleaner['state']) },
        timestamp: timestamp
      }
      influxdb.write_point('cleaner', data) unless options[:dry_run]

      unless status['pool_temp'].empty?
        data = {
          values: { value: status['pool_temp'].to_i },
          timestamp: timestamp
        }
        influxdb.write_point('pool_temp', data) unless options[:dry_run]
      end

      unless status['air_temp'].empty?
        data = {
          values: { value: status['air_temp'].to_i },
          timestamp: timestamp
        }
        influxdb.write_point('air_temp', data) unless options[:dry_run]
      end
    rescue StandardError => e
      @logger.error e
    end
  end
end

Jandy.start
