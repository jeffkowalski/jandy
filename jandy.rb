#!/usr/bin/env ruby

require 'mechanize'
require 'date'
require 'thor'


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

  desc "foo", "testing"
  def foo
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
    puts response
  end

end

Jandy.start
