require 'epoxy'
require 'methlab'
require 'thread'

module RDBI
    #
    # FIXME would like to use methlab here, but am not entirely sure how to do this best.
    #
    class << self
        #
        # Every database handle allocated throughout the lifetime of the
        # program. This functionality is subject to change and may be pruned
        # during disconnection.
        attr_reader :all_connections
        #--
        #attr_reader :drivers
        #++
        #
        # The last database handle allocated. This may come from pooled connections or regular ones.
        attr_reader :last_dbh
    end

    #
    # connect() takes a class name, which may be represented as:
    #
    # * The full class name, such as RDBI::Driver::Mock
    # * A symbol representing the significant portion, such as :Mock, which corresponds to RDBI::Driver::Mock
    # * A string representing the same data as the symbol.
    #
    # Additionally, arguments that are passed on to the driver for consumption
    # may be passed. Please refer to the driver documentation for more
    # information.
    #
    # connect() returns an instance of RDBI::Database. In the instance a block
    # is provided, it will be called upon connection success, with the
    # RDBI::Database object provided in as the first argument.
    def self.connect(klass, *args)

        klass = begin
                    klass.kind_of?(Class) ? klass : self::Driver.const_get(klass.to_s)
                rescue
                    raise ArgumentError, "Invalid argument for driver name; must be Class, Symbol, or String"
                end

        driver = klass.new(*args)
        dbh = @last_dbh = driver.new_handle

        @all_connections ||= []
        @all_connections.push(dbh)

        yield dbh if block_given?
        return dbh
    end

    #
    # connect_cached() works similarly to connect, but yields a database handle
    # copied from a RDBI::Pool. The 'default' pool is the ... default, but this
    # may be manipulated by providing :pool_name to the connection arguments.
    #
    # If a pool does not exist already, it will be created and a database
    # handle instanced from your connection arguments.
    #
    # If a pool *already* exists, your connection arguments will be ignored and
    # it will instance from the Pool's connection arguments.
    def self.connect_cached(klass, *args)
        args = args[0]
        pool_name = args[:pool_name] || :default

        dbh = nil

        if RDBI::Pool[pool_name]
            dbh = RDBI::Pool[pool_name].get_dbh
        else
            dbh = RDBI::Pool.new(pool_name, [klass, *args]).get_dbh
        end

        @last_dbh = dbh

        yield dbh if block_given?
        return dbh
    end

    #
    # Retrieves a RDBI::Pool. See RDBI::Pool.[].
    def self.pool(pool_name=:default)
        RDBI::Pool[pool_name]
    end

    #
    # Connects to and pings the database. Arguments are the same as for RDBI.connect.
    def self.ping(klass, *args)
        connect(klass, *args).ping
    end
   
    #
    # Reconnects all known connections. See RDBI.all_connections.
    def self.reconnect_all
        @all_connections.each(&:reconnect)
    end
   
    #
    # Disconnects all known connections. See RDBI.all_connections.
    def self.disconnect_all
        @all_connections.each(&:disconnect)
    end
end

class RDBI::Database
    extend MethLab

    # the driver class that is responsible for creating this database handle.
    attr_accessor :driver

    # are we currently in a transaction?
    attr_reader :in_transaction

    # the last query sent, as a string.
    attr_reader :last_query

    # the mutex for this database handle.
    attr_reader :mutex

    inline(:connected, :connected?) { @connected }

    inline(:reconnect)  { @connected = true  }
    inline(:disconnect) { @connected = false }

    inline(
            :ping, 
            :transaction, 
            :table_schema, 
            :schema,
            :preprocess_query,
            :bind_style,
            :last_statement
          ) { |*args| raise NoMethodError, "this method is not implemented in this driver" }

    inline(:commit, :rollback) { @in_transaction = false }

    def initialize(*args)
        # FIXME symbolify
        @connect_args = args[0]
        @connected    = true
        @mutex        = Mutex.new
    end

    def transaction(&block)
        mutex.synchronize do
            @in_transaction = true
            begin
                yield self
                commit if @in_transaction
            rescue
                rollback 
            ensure
                @in_transaction = false
            end
        end
    end

    def prepare(query)
        @last_query = query
    end

    def execute(query, *binds)
        @last_query = query
    end

    def preprocess_query(query, *binds)
        @last_query = query
        ep = Epoxy.new(query)
        ep.quote { |x| %Q{'#{binds[x].gsub(/'/, "''")}'} }
    end
end

require 'rdbi/pool'

# vim: syntax=ruby ts=4 et sw=4 sts=4
