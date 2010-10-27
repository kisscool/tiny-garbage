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

  def human_date(datetime)
    datetime.strftime('%d/%m/%Y').gsub(/ 0(\d{1})/, ' \1')
  end

  def rfc_date(datetime)
    datetime.strftime("%Y-%m-%dT%H:%M:%SZ") # 2003-12-13T18:30:02Z
  end

  def partial(page, locals={})
    haml page, {:layout => false}, locals
  end

  # prepare a string to be used as a search query
  # eg. '"un espace" .flac' --> 'un espace%.flac'
  def format_query(query)
    tab = Shellwords.shellwords query
    tab.join("%")
  end

  # convert byte size in B, KB, MB.. human readable size
  # inspired from Actionpack method
  STORAGE_UNITS = ['B', 'KB', 'MB', 'GB', 'TB']
  def number_to_human_size(number)
    return nil if number.nil?
    max_exp  = STORAGE_UNITS.size - 1
    number   = Float(number)
    exponent = (Math.log(number) / Math.log(1024)).to_i # Convert to base 1024
    exponent = max_exp if exponent > max_exp # we need this to avoid overflow for the highest unit
    number  /= 1024 ** exponent

    "%n %u".gsub(/%n/, ((number * 100).round.to_f / 100).to_s).gsub(/%u/, STORAGE_UNITS[exponent])
  end

end
