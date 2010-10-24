#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

# loading the db model
require File.join(File.dirname(__FILE__), '../model.rb')

# this cron job will attempt to crawl each FTP server listed
# in the database
# the recommended frequency for this job is once a day
#
# a possible future optimization would be multi-threading

FtpServer.all.each do |ftp|
  ftp.get_entry_list
end

