# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2009 Zouchaoqun
# (c) 2010 KissCool
require 'rubygems'
require 'socket'
# use Bundler if present
begin
  ENV['BUNDLE_GEMFILE'] = File.join(File.dirname(__FILE__), './Gemfile')
  require 'bundler/setup'
rescue LoadError
end
# let's load the DM stuff
require 'dm-core'
require 'dm-is-tree'
require 'dm-aggregates'

# a lot of this code has been forked from Zouchaoqun's ezFtpSearch project
# kuddos to his work

# the code has now become very different than ezFtpSearch


###############################################################################
################### LOAD OF CONFIGURATION

# here we load config options
require File.join(File.dirname(__FILE__), './config.rb')


###############################################################################
################### ORM MODEL CODE (do not edit if you don't know)

#
# the Entry class is a generic class for fields and directories 
class Entry
  include DataMapper::Resource
  property :id,             Serial
  property :parent_id,      Integer, :index => true
  property :entries_count,  Integer, :default => 0, :required => true
  property :name,           String, :required => true, :length => 255, :index => true
  property :size,           Float
  property :entry_datetime, DateTime
  property :directory,      Boolean, :default => false, :required => true
  property :index_version,  Integer, :default => 0, :required => true, :index => true # will help us avoid duplication during indexing
  #property :ftp_server_id,  Integer, :required => true, :key => true

  belongs_to :ftp_server
  is :tree, :order => :name

  ### methods

  # gives the full path of the directory above the entry
  def ancestors_path
    if parent
      p = ancestors.join('/')
      p + '/'
    else
      ''
    end
  end

  # gives the full path of the entry
  def full_path
    ancestors_path + name
  end

  # gives the remote path of the entry, eg. ftp://host/full_path
  def remote_path
    ftp_server.url + '/' +full_path
  end

  # no need to explain
  def to_s
    name
  end
  
  def get_size
    size
  end

  # return an array of entries
  def self.search(query)
    Entry.all(:name.like => "%#{query}%", :order => [:ftp_server_id.desc])
  end

  # return an array of entries
  # the params are :
  # query : searched string, in the form of "%foo%bar%"
  # page : offset of the page of results we must return
  # order : order string, in the form of "name", ""size" or "size.desc"
  # online : restrict the query to online FTP servers or to every known ones
  def self.complex_search(query="", page=1, order="ftp_server_id.asc", online=true)
    # here we define how many results we want per page
    per_page = 20

    # basic checks and default options
    query ||= ""
    page  ||= 1
    if page < 1
     page = 1
    end
    order ||= "ftp_server_id.asc"
    online ||= true

    # we build the order object
    t = order.split('.')
    build_order = DataMapper::Query::Operator.new(t[0], t[1] || 'asc')

    # we build the base query
    filter = {
      :name.like => "%#{query}%",                       # search an entry through a string
      #:index_version => FtpServer.first(:ftp_server).index_version,   # restrict to current index_version
      :links => [FtpServer.relationships[:versions]],   # do a JOIN on index_version
      :order => build_order,                            # apply a sort order
      :limit => per_page,                               # limit the number of results
      :offset => (page - 1) * per_page                  # with the following offset
    }
    # restrict the query to online FTP server or to every registered FTP servers
    if online
      filter.merge!({ :ftp_server => [:is_alive => true] })
    end

    # execute the query
    results = Entry.all(filter)
    
    # how many pages we will have
    filter.delete(:limit)
    filter.delete(:offset)
    page_count = (Entry.count(filter).to_f / per_page).ceil

    # finally we return both informations
    return [ page_count, results ]
  end

end

#
# each server is documented here
class FtpServer
  include DataMapper::Resource
  property :id,             Serial
  property :name,           String, :required => true
  property :host,           String, :required => true 
  property :port,           Integer, :default => 21, :required => true
  property :ftp_type,       String, :default => 'Unix', :required => true
  property :ftp_encoding,   String, :default => 'ISO-8859-1'
  property :force_utf8,     Boolean, :default => true, :required => true
  property :login,          String, :default => 'anonymous', :required => true
  property :password,       String, :default => 'garbage', :required => true
  property :ignored_dirs,   String, :default => '. .. .svn'
  property :note,           Text
  property :index_version,  Integer, :default => 0, :required => true # will help us avoid duplication during indexing
  property :updated_on,     DateTime
  property :last_ping,      DateTime
  property :is_alive,       Boolean, :default => false

  # each FtpServer is linked to entries from the Entry class
  # so we don't have to bother wether the entries are currently
  # in swap or not during our searches
  has n, :entries

  # this association will permit us to do JOIN requests during search queries in
  # order to return only relevant results (ie. those of the current valid index)
  has n, :versions, Entry, :parent_key => [ :id, :index_version ], :child_key => [ :ftp_server_id, :index_version ]

  ## methods ##
  
  # always handy to have one
  def to_s
    "id:#{id} NAME:#{name} HOST:#{host} FTP_TYPE:#{ftp_type} LOGIN:#{login}
     PASSWORD:#{password} IGNORED:#{ignored_dirs} NOTE:#{note}"
  end

  # gives the url of the FTP
  def url
    "ftp://" + host
  end

  # gives the total size of the whole FTP Server
  def size
    Entry.sum(:size, :ftp_server_id => id, :index_version => index_version, :directory => false)
  end

  # gives the number of files in the FTP
  def number_of_files
    Entry.all(:ftp_server_id => id, :index_version => index_version, :directory => false).count
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
      @logger.info("on #{host} : Trying ftp server #{name} (id=#{id})")
      ftp = Net::FTP.open(host, login, password)
      ftp.passive = true
    rescue => detail
      retries_count += 1
      @logger.error("on #{host} : Open ftp exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{host} : Retrying #{retries_count}/#{@max_retries}.")
      if (retries_count >= @max_retries)
        @logger.error("on #{host} : Retry reach max times, now exit.")
        @logger.close
        exit
      end
      ftp.close if (ftp && !ftp.closed?)
      @logger.error("on #{host} : Wait 30s before retry open ftp")
      sleep(30)
      retry
    end

    # Trying to get ftp entry-list
    get_list_retries = 0
    begin
      @logger.info("on #{host} : Server connected")
      start_time = Time.now
      @entry_count = 0
      
      # building the index
      get_list_of(ftp)
      # updating our index_version
      self.index_version += 1
      self.updated_on = Time.now
      save
      
      Entry.all(:ftp_server_id => id, :index_version.not => index_version).destroy
      @logger.info("on #{host} : Old ftp entries deleted after get entries")

      process_time = Time.now - start_time
      @logger.info("on #{host} : Finish getting list of server " + name + " in " + process_time.to_s + " seconds.")
      @logger.info("on #{host} : Total entries: #{@entry_count}. #{(@entry_count/process_time).to_i} entries per second.")
    rescue => detail
      get_list_retries += 1
      @logger.error("on #{host} : Get entry list exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{host} : Retrying #{get_list_retries}/#{@max_retries}.")
      raise if (get_list_retries >= @max_retries)
      retry
    ensure
      ftp.close if !ftp.closed?
      @logger.info("on #{host} : Ftp connection closed.")
      @logger.close
    end
  end

private

  

  # get entries under parent_path, or get root entries if parent_path is nil
  def get_list_of(ftp, parent_path = nil, parent_id = nil)
    ic = Iconv.new('UTF-8', ftp_encoding) if force_utf8
    ic_reverse = Iconv.new(ftp_encoding, 'UTF-8') if force_utf8

    retries_count = 0
    begin
      entry_list = parent_path ? ftp.list(parent_path) : ftp.list
    rescue => detail
      retries_count += 1
      @logger.error("on #{host} : Ftp LIST exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{host} : Retrying get ftp list #{retries_count}/#{@max_retries}")
      raise if (retries_count >= @max_retries)
      
      reconnect_retries_count = 0
      begin
        ftp.close if (ftp && !ftp.closed?)
        @logger.error("on #{host} : Wait 30s before reconnect")
        sleep(30)
        ftp.connect(host)
        ftp.login(login, password)
        ftp.passive = true
      rescue => detail2
        reconnect_retries_count += 1
        @logger.error("on #{host} : Reconnect ftp failed, exception: " + detail2.class.to_s + " detail: " + detail2.to_s)
        @logger.error("on #{host} : Retrying reconnect #{reconnect_retries_count}/#{@max_retries}")
        raise if (reconnect_retries_count >= @max_retries)
        retry
      end
      
      @logger.error("on #{host} : Ftp reconnected!")
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
          @logger.error("on #{host} : Iconv::IllegalSequence, file ignored. raw data: " + e)
          next
        end
      end
      entry = Net::FTP::List.parse(force_utf8 ? e_utf8 : e)

      next if ignored_dirs.include?(entry.basename)

      @entry_count += 1

      begin
        file_datetime = entry.mtime.strftime("%Y-%m-%d %H:%M:%S")
      rescue => detail3
        puts("on #{host} : strftime failed, exception: " + detail3.class.to_s + " detail: " + detail3.to_s)
        @logger.error("on #{host} : strftime failed, exception: " + detail3.class.to_s + " detail: " + detail3.to_s)   
        @logger.error("on #{host} : raw entry: " + e)
      end

      entry_basename = entry.basename.gsub("'","''")
     
      # the sql query from the legacy code has been replaced by a DM
      # insertion, apparently without sensible loss of performance
      # (only preliminary test) 
      new_entry = Entry.create!(
        :parent_id => parent_id,
        :name => entry_basename,
        :size => entry.filesize,
        :entry_datetime => file_datetime,
        :directory => entry.dir?,
        :ftp_server_id => id,
        :index_version => index_version+1
      )
      
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


