#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

#require 'rdiscount'
require 'shellwords'

module MyHelpers
  include Rack::Utils
  alias_method :h, :escape_html

#  def markup(string)
#    RDiscount::new(string).to_html
#  end

  # prepare a string to be used as a search query
  # eg. '"un espace" .flac' --> 'un espace%.flac'
  def format_query(query)
    tab = Shellwords.shellwords query
    tab.join("%")
  end

  def human_date(datetime)
    datetime.strftime('%d/%m/%Y').gsub(/ 0(\d{1})/, ' \1')
  end

  def rfc_date(datetime)
    datetime.strftime("%Y-%m-%dT%H:%M:%SZ") # 2003-12-13T18:30:02Z
  end

  def partial(page, locals={})
    haml page, {:layout => false}, locals
  end

end
