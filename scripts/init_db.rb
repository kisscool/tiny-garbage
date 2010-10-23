#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

# loading the db model
require File.join(File.dirname(__FILE__), '../model.rb')

require 'dm-migrations'

# let there be light
DataMapper.auto_migrate!

# server de test
@server = FtpServer.new(
  :name => "erebor",
  :host => "10.2.0.1"
)

@server.save

#query = "id = '#{ENV['server']}'"
query = "id = 1"
FtpServer.all.each do |ftp|
  ftp.get_entry_list
end

