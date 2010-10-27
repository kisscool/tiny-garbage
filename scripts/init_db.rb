#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

# loading the db model
require File.join(File.dirname(__FILE__), '../model.rb')

require 'dm-migrations'

# let there be light
DataMapper.auto_migrate!


