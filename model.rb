# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2009 Zouchaoqun
# (c) 2010 KissCool
require 'rubygems'
require 'socket'
# use Bundler if present
begin
  require 'bundler/setup'
rescue LoadError
end
# let's load the DM stuff
require 'dm-core'
require 'dm-is-tree'
require 'dm-aggregates'

# a lot of this code has been forked from Zouchaoqun's ezFtpSearch project
# kuddos to his work

# my main modifications have consisted to reduce code duplication and to
# migrate it from ActiveRecord to DataMapper


###############################################################################
################### LOAD OF CONFIGURATION

# here we load config options
require File.join(File.dirname(__FILE__), './config.rb')


###############################################################################
################### ORM MODEL CODE (do not edit if you don't know)

#
# the Entry class is a generic class for fiels and directories 
class Entry
  include DataMapper::Resource
  property :id,             Serial
  property :parent_id,      Integer
  property :entries_count,  Integer, :default => 0, :required => true
  property :name,           String, :required => true, :length => 255, :index => true
  property :size,           Float
  property :entry_datetime, DateTime
  property :directory,      Boolean, :default => false, :required => true
  property :type,           Discriminator # used to discriminate between FtpEntry and SwapFtpEntry

  belongs_to :ftp_server
  is :tree, :order => :name

  ### methods

  # gives the full path of the directory above the entry
  def ancestors_path
    if parent
      p = ancestors.join('/')
      '/' + p + '/'
    else
      '/'
    end
  end

  # gives the full path of the entry
  def full_path
    ancestors_path + name
  end

  # gives the remote path of the entry, eg. ftp://host/full_path
  def remote_path
    "ftp://" + ftp_server.host + full_path
  end

  # no need to explain
  def to_s
    name
  end
  
  def get_size
    size
  end

  # search in the index
  # return an array of entries
  def self.search(query)
    Entry.all(:name.like => "%#{query}%", :order => [:ftp_server_id.desc])
  end

  # version with pagination
  def self.search_with_page(query, page)
    # here we define how many results we want per page
    per_page = 5

    # basic checks and default options
    query ||= ""
    page  ||= 1
    if page <= 1
     page = 1
    end


    # we build the base query
    filter = {:name.like => "%#{query}%", :order => [:ftp_server_id.desc]}
    # query with a limited number of results
    results = Entry.all(filter.merge({:limit => per_page, :offset => (page - 1) * per_page}))
    
    # how many pages we will have
    page_count = (Entry.count(filter).to_f / per_page).ceil

    # finally we return both informations
    return [ page_count, results ]
  end

end

# this class is a subclass of Entry
# the switch between FtpEntry and SwapFtpEntry could be handled in another way
# but we keep it that way so we don't have to break entirely legacy code
class FtpEntry < Entry ; end

# this class is a subclass of Entry
class SwapFtpEntry < Entry ; end

# each server is documented here
class FtpServer
  include DataMapper::Resource
  property :id,           Serial
  property :name,         String, :required => true
  property :host,         String, :required => true 
  property :port,         Integer, :default => 21, :required => true
  property :ftp_type,     String, :default => 'Unix', :required => true
  property :ftp_encoding, String, :default => 'ISO-8859-1'
  property :force_utf8,   Boolean, :default => true, :required => true
  property :login,        String, :default => 'anonymous', :required => true
  property :password,     String, :default => 'garbage', :required => true
  property :ignored_dirs, String, :default => '. .. .svn'
  property :note,         Text
  property :in_swap,      Boolean, :default => true, :required => true
  property :updated_on,   DateTime
  property :last_ping,    DateTime
  property :is_alive,     Boolean, :default => false

  # each FtpServer is linked to entries from the Entry class
  # so we don't have to bother wether the entries are currently
  # in swap or not during our searches
  has n, :entries

  ## methods ##
  
  # always handy to have one
  def to_s
    "id:#{id} NAME:#{name} HOST:#{host} FTP_TYPE:#{ftp_type} LOGIN:#{login}
     PASSWORD:#{password} IGNORED:#{ignored_dirs} NOTE:#{note}"
  end

  # handle the ping scan backend
  def self.ping_scan_result(host, is_alive)
    # fist we check if the host is known in the database
    server = self.first(:host => host)
    if server.nil?
      # if the server doesn't exist
      if is_alive
        # but that he is a FTP server
        # then we create it
        # after a quick reverse DNS resolution
        begin
          name = Socket.getaddrinfo(line, 0, Socket::AF_UNSPEC, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME)[0][2]
        rescue
          name = "anonymous ftp"
        end
        self.create(
          :host       => host,
          :name       => name,
          :is_alive   => is_alive,
          :last_ping  => Time.now
        )
      end
    else
      # if the server exists in the database
      # then we update its status
      server.update(
        :is_alive   => is_alive,
        :last_ping  => Time.now
      )
    end
  end

  # this is the method which launch the process to index an FTP server
  def get_entry_list(max_retries = 5)
    require 'net/ftp'
    require 'net/ftp/list'
    require 'iconv'
    require 'logger'
    @max_retries = max_retries.to_i
    BasicSocket.do_not_reverse_lookup = true

    # Trying to open ftp server, exit on max_retries
    retries_count = 0
    begin
      @logger = Logger.new(File.dirname(__FILE__) + '/log/spider.log', 'monthly')
      @logger.formatter = Logger::Formatter.new
      @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      @logger.info("Trying ftp server #{name} (id=#{id}) on #{host}")
      ftp = Net::FTP.open(host, login, password)
      ftp.passive = true
    rescue => detail
      retries_count += 1
      @logger.error("Open ftp exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("Retrying #{retries_count}/#{@max_retries}.")
      if (retries_count >= @max_retries)
        @logger.error("Retry reach max times, now exit.")
        @logger.close
        exit
      end
      ftp.close if (ftp && !ftp.closed?)
      @logger.error("Wait 30s before retry open ftp")
      sleep(30)
      retry
    end

    # Trying to get ftp entry-list
    get_list_retries = 0
    begin
      @logger.info("Server connected")
      start_time = Time.now
      # Before get list, delete old ftp entries if there are any
      if in_swap
        FtpEntry.all(:ftp_server_id => id).destroy
        @logger.info("Old ftp entries in ftp_entry deleted before get entries")
      else
        SwapFtpEntry.all(:ftp_server_id => id).destroy
        @logger.info("Old ftp entries in swap_ftp_entry deleted before get entries")
      end
      @entry_count = 0
      get_list_of(ftp)
      self.in_swap = !in_swap
      save
      # After table swap, delete old ftp entries to save db space
      if in_swap
        FtpEntry.all(:ftp_server_id => id).destroy
        @logger.info("Old ftp entries in ftp_entry deleted after get entries")
      else
        SwapFtpEntry.all(:ftp_server_id => id).destroy
        @logger.info("Old ftp entries in swap_ftp_entry deleted after get entries")
      end

      process_time = Time.now - start_time
      @logger.info("Finish getting list of server " + name + " in " + process_time.to_s + " seconds.")
      @logger.info("Total entries: #{@entry_count}. #{(@entry_count/process_time).to_i} entries per second.")
    rescue => detail
      get_list_retries += 1
      @logger.error("Get entry list exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("Retrying #{get_list_retries}/#{@max_retries}.")
      raise if (get_list_retries >= @max_retries)
      retry
    ensure
      ftp.close if !ftp.closed?
      updated_on = Time.now
      @logger.info("Ftp connection closed.")
      @logger.close
    end
  end

private

  # get the tree in which we must insert between SwapFtpEntry and FtpEntry
  def tree_to_insert
    in_swap ? FtpEntry : SwapFtpEntry
  end
  

  # get entries under parent_path, or get root entries if parent_path is nil
  def get_list_of(ftp, parent_path = nil, parent_id = nil)
    ic = Iconv.new('UTF-8', ftp_encoding) if force_utf8
    ic_reverse = Iconv.new(ftp_encoding, 'UTF-8') if force_utf8

    retries_count = 0
    begin
      entry_list = parent_path ? ftp.list(parent_path) : ftp.list
    rescue => detail
      retries_count += 1
      @logger.error("Ftp LIST exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("Retrying get ftp list #{retries_count}/#{@max_retries}")
      raise if (retries_count >= @max_retries)
      
      reconnect_retries_count = 0
      begin
        ftp.close if (ftp && !ftp.closed?)
        @logger.error("Wait 30s before reconnect")
        sleep(30)
        ftp.connect(host)
        ftp.login(login, password)
        ftp.passive = true
      rescue => detail2
        reconnect_retries_count += 1
        @logger.error("Reconnect ftp failed, exception: " + detail2.class.to_s + " detail: " + detail2.to_s)
        @logger.error("Retrying reconnect #{reconnect_retries_count}/#{@max_retries}")
        raise if (reconnect_retries_count >= @max_retries)
        retry
      end
      
      @logger.error("Ftp reconnected!")
      retry
    end

    entry_list.each do |e|
      # Some ftp will send 'total nn' string in LIST command
      # We should ignore this line
      next if /^total/.match(e)

# usefull for debugging purpose
#puts "#{@entry_count} #{e}"

      if force_utf8
        begin
          e_utf8 = ic.iconv(e)
        rescue Iconv::IllegalSequence
          @logger.error("Iconv::IllegalSequence, file ignored. raw data: " + e)
          next
        end
      end
      entry = Net::FTP::List.parse(force_utf8 ? e_utf8 : e)

      next if ignored_dirs.include?(entry.basename)

      @entry_count += 1

      begin
        file_datetime = entry.mtime.strftime("%Y-%m-%d %H:%M:%S")
      rescue => detail3
        puts("strftime failed, exception: " + detail3.class.to_s + " detail: " + detail3.to_s)
        @logger.error("strftime failed, exception: " + detail3.class.to_s + " detail: " + detail3.to_s)   
        @logger.error("raw entry: " + e)
      end

      #sql = "insert into #{in_swap ? 'ftp_entries' : 'swap_ftp_entries'}"
      #sql +=  " (parent_id,name,size,entry_datetime,directory,ftp_server_id)"
      entry_basename = entry.basename.gsub("'","''")
      #sql += " VALUES (#{parent_id || 0},'#{entry_basename}',#{entry.filesize},'#{file_datetime}',#{entry.dir? ? 1 : 0},#{id})"
     
      # the sql query from the legacy code has been replaced by a DM
      # insertion, apparently without sensible loss of performance
      # (only preliminary test) 
      new_entry = tree_to_insert.create!(
        :parent_id => parent_id,
        :name => entry_basename,
        :size => entry.filesize,
        :entry_datetime => file_datetime,
        :directory => entry.dir?,
        :ftp_server_id => id
      )

      #entry_id = DataMapper.repository(:default).adapter.execute(sql).insert_id
      entry_id = new_entry.id
      if entry.dir?
        ftp_path = (parent_path ? parent_path : '') + '/' +
                          (force_utf8 ? ic_reverse.iconv(entry.basename) : entry.basename)
        get_list_of(ftp, ftp_path, entry_id)
      end

    end
  end



end


# check and initialise properties
DataMapper.finalize


