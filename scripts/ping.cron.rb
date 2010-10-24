#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

# this cron job will attempt to ping an IP range with the 
# UNIX utility 'fping'
# the recommenced frequency for this job is one every 
# 10 minutes for a little network, or once an hour for a
# big network

###########################################################
################### CONFIGURATION

# several addresses of networks can be mixed here, just like
# specified in fping documentation
NETWORK="10.2.0.0/24"

###########################################################
################### CODE

# loading the db model and needed libs
require File.join(File.dirname(__FILE__), '../model.rb')
require 'net/ftp'
require 'logger'

# static configs
@max_retries = 3
BasicSocket.do_not_reverse_lookup = true
@logger = Logger.new(File.dirname(__FILE__) + '/log/ping.log', 'monthly')
@logger.formatter = Logger::Formatter.new
@logger.datetime_format = "%Y-%m-%d %H:%M:%S"

# first we perform a massive ping on the whole network
IO.popen "fping -a -g #{NETWORK}" do |io|
  io.each do |line|     # for each alive host
    puts line
    @logger.info("Trying alive host #{line} for FTP connexion}")
    # we check if its FTP port is open
    retries_count = 0
    begin
      Net::FTP.open(line, "anonymous", "garbage") do |ftp|
        # if the FTP port is responding, then we update
        # the database
        @logger.info("Host #{line} did accept FTP connexion")
        FtpServer.ping_scan_result(line, true)
      end
    rescue
      # if it didn't accept connexion, we retry
      retries_count += 1
      if (retries_count >= @max_retries)
        # if we surpass @max_retries, then the host is
        # not considered as an FTP host
        @logger.info("Host #{line} didn't accept FTP connexion")
        FtpServer.ping_scan_result(line, false)
        break
      end
      sleep(10)
      retry
    end
  end
end

@logger.close
