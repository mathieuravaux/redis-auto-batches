# TODO: think about and manage the use of the multi / exec commands, so that
# we have a transparent behavior between a multi and an exec command.

module RedisAutoBatches
  class RedisPromiseProxy
    class PromiseWithIndex < RedisAutoBatches::Promise
      attr_accessor :promise_index
      def initialize(index, &block)
        promise_index = index
        super(&block)
      end
    
      # def respond_to?(method)
      #   method.equal?(:promise_index) || super(method)
      # end
    end
  
    MAX_BUFFERED_PROMISES = 1_000

    READ_COMMANDS = ::Set.new(%w[
      ttl sort
      randomkey keys srandmember type
      get mget mapped_mget [] []=
      exists hexists
      hget hmget hkeys hgetall hvals hlen
      lindex llen lrange
      zscore zcard zcount zrange zrank zrangebyscore zrevrange zrevrangebyscore zrevrank
      smembers sismember sdiff sunion sinter scard
      dbsize debug
    ].map(&:to_sym))
  
  
    WRITE_COMMANDS = ::Set.new(%w[
      incr decr incrby decrby hincrby zincrby
      del expireat getset hdel hmset hset hsetnx info lastsave lpop lpush lrem lset ltrim
      mapped_hmset move mset msetnx rename
      renamenx rpop rpoplpush rpush sadd sdiffstore select set setnx
      sinterstore smove spop srem subscribe sunionstore zadd
      zinterstore zrem zremrangebyrank zremrangebyscore zunionstore
    ].map(&:to_sym))
  
    IMMEDIATE_COMMANDS = Set.new(%w[
      auth bgrewtriteaof bgsave blpop brpop brpoplpush config debug flushall flushdb monitor
      persist expire setex psubscribe publish punsubscribe quit save shutdown slaveof unwatch watch
    ].map(&:to_sym))

    attr_accessor :redis
    attr_accessor :buffered_promises
    attr_accessor :in_unit_of_work
  
    ##
    # Creates a new proxy that will be usable just like a normal
    #   Redis object, but will buffer Redis commands in transactions
    #   to minimize the number of necessary round-trips
    #
    # @example 
    #   redis = Statistics::RedisPromiseProxy.new(Redis.new)
    #   user_ids = [<user_1>, <user_2>, <user_3>, <user_4>, ]
    #   friend_counts = user_ids.map { |id| redis.scard("users:#{id}:friendships") }
    #   friend_counts.count # => 4
    #   friend_counts[0] # => 174 # the Redis request is made right here
    #
    # @param  Redis
    # @see    Redis.new
    def initialize(redis)
      @redis = redis
      @queue_mutex = ::Mutex.new
      @flush_mutex = ::Mutex.new
      @buffered_promises = []
    end
  

    ##
    # if _command_ is a read command, return a promise of the result of calling this command
    #   else, realize the buffered promises and then call the command, directly returning its result
    #   TODO: maybe we should wrap the result of the command in a promise in any case
    def method_missing(command, *args, &block)
      promise_redis_result(command, *args, &block)
    end

    def promise_redis_result(command, *args, &block)
      @queue_mutex.synchronize do
        if IMMEDIATE_COMMANDS.include?(command)
          # puts "Will flush non-read command called on Redis (#{command.inspect})."
          flush
          @redis.send(command, *args, &block)
        else
          if outside_unit_of_work?
            # if Rails.env.test?
            # #   unless caller.any? { |line| line.include?('/rspec/core/') && line.include?('run_before_each') }
            # #     puts "\t#{caller.join("\n\t")}"
            #     raise RuntimeError.new("Accessing to redis outside a unit of work")
            # #   end
            # end
            # puts "Forcing the creation of a unit of work..."
            start_unit_of_work
          end

          #delay with a promise
          raise NotImplementedError.new("Passing a block when calling a Redis command is not currently supported.") if block_given?
          index = @buffered_promises.count
        
          promise = PromiseWithIndex.new(index) do
            # puts "Will flush since value accessed for promise ##{index} (#{command}, #{args.inspect})"
            flush
            promise.force
          end
          @buffered_promises << [promise, command, args]
          flush if flush_needed?
          promise
        end
      end
    end

    #TODO: add this to monitor_with_new_relic and log the executions times
    def flush
      @flush_mutex.synchronize do
        return if @buffered_promises.empty?
    
        results = if @buffered_promises.length == 1
          (prom, command, args) = @buffered_promises.first
          # puts "command: #{command}(#{args.inspect})"
          res = @redis.send(command, *args)
          [res]
        else
          @redis.multi
          @buffered_promises.each do |promise, command, args|
            @redis.send(command, *args)
          end
          @redis.exec
        end
      
        results.each.with_index do |result, index|
          # puts " ==> #{result}, #{index}"
          @buffered_promises[index][0].fulfill(result)
        end
    
        @buffered_promises = []
      end
    end
  
    # Redis.unit_of_work method like mongoid that will flush the previous unit_of_work and ensure the termination of the current unit_of_work
    def unit_of_work
      previous_state = @in_unit_of_work
      begin
        start_unit_of_work
        yield if block_given?
      ensure
        end_unit_of_work(previous_state)
      end
    end
  
    def start_unit_of_work
      flush
      @in_unit_of_work = true
    end
  
    def end_unit_of_work(previous_state)
      flush
      @in_unit_of_work = previous_state
    end
  
    def outside_unit_of_work?
      ! @in_unit_of_work
    end
  
    # we flush every 1000 promises (at least)
    def flush_needed?
      @buffered_promises.length >= MAX_BUFFERED_PROMISES
    end

  end
end
