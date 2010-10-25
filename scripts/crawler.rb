#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

# requires
require 'net/ftp'
require 'logger'
# loading the db model
require File.join(File.dirname(__FILE__), '../model.rb')

###########################################################
################### CONFIGURATION

@options = {
  :action   => "",
  :networks => "10.2.0.0/24"
}

###########################################################
################### CORE CODE

# this cron job will attempt to crawl each FTP server listed
# in the database
# the recommended frequency for this job is once a day
#
# a possible future optimization would be multi-threading
def index
  FtpServer.all(:is_alive => true).each do |ftp|
    ftp.get_entry_list
  end
end


# this cron job will attempt to ping an IP range with the 
# UNIX utility 'fping'
# the recommenced frequency for this job is one every 
# 10 minutes for a little network, or once an hour for a
# big network
def ping

  # static configs
  @max_retries = 3
  BasicSocket.do_not_reverse_lookup = true
  @logger = Logger.new(File.join(File.dirname(__FILE__), '../log/ping.log'), 'monthly')
  @logger.formatter = Logger::Formatter.new
  @logger.datetime_format = "%Y-%m-%d %H:%M:%S"

  # first we perform a massive ping on the whole network
  IO.popen "fping -a -g #{@options[:networks]}" do |io|
    io.each do |line|     # for each alive host
      puts line
      line.chomp!
      @logger.info("Trying alive host #{line} for FTP connexion}")
      # we check if its FTP port is open
      retries_count = 0
      begin
        ftp = Net::FTP.open(line, "anonymous", "garbage")
        # if the FTP port is responding, then we update
        # the database
        if ftp && !ftp.closed?
          @logger.info("Host #{line} did accept FTP connexion")
          FtpServer.ping_scan_result(line, true)
          ftp.close
        end
      rescue => detail
        # if it didn't accept connexion, we retry
        retries_count += 1
        if (retries_count >= @max_retries)
          # if we surpass @max_retries, then the host is
          # not considered as an FTP host
          @logger.info("Host #{line} didn't accept FTP connexion")
          FtpServer.ping_scan_result(line, false)
        else
          sleep(10)
          retry
        end
      end
    end
  end

  @logger.close
end



###########################################################
################### PARSING

banner = <<"EOF"
*** Tiny-Garbage Crawler ***

Ping or index your FTPs

Usage: #{$0.split("/").last} [-h] { ping [networks] | index }
  actions :
   * ping  : check if hosts in a network are alive and open to FTP
   * index : crawl known FTP servers and index their content
  options :
   * networks : networks specified as in fping documentation
EOF

cmd = ARGV.shift
case cmd
when "index"
  @options[:action] = cmd
when "ping"
  @options[:action]   = cmd
  @options[:networks] =  ARGV.join " " if ARGV != []
else
  puts banner
  exit
end

### here we run the code
case @options[:action]
when "ping"
  ping
when "index"
  index
else
  puts banner
  exit
end


