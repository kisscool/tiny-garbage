#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

# loading the db model
require File.join(File.dirname(__FILE__), '../model.rb')



FtpServer.all(:name => "erebor").each do |ftp|
  ftp.get_entry_list
  puts "etat in_swap : #{ftp.in_swap}"
end

