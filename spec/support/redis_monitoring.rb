module RedisMonitoring

  def self.included(base)
    base.class_eval do
      before do
        @called_commands = []
        start_redis_monitoring
      end

      after do
        @verif_thread.kill
      end
    end
  end

  def start_redis_monitoring
    mutex_for_redis_verification_startup = Mutex.new

    @verif_thread = Thread.new do
      mutex_for_redis_verification_startup.lock
      Redis.connect.monitor do |command|
        if command.include? 'monitor'
          mutex_for_redis_verification_startup.unlock
        end

        if command.include? 'ping'
          # puts "Killing verif thread"
          Thread.current.kill
        end

        unless /"monitor"|OK|ping$/ =~ command
          command_without_timestamp = command.gsub(/^\d+\.\d+ /, '').gsub('"', '')
          @called_commands << command_without_timestamp
        end
      end
    end

    # let the verif thread acquire the mutex and wait on it while the verif starts up
    @verif_thread.run
    mutex_for_redis_verification_startup.lock
    # puts "Rocknroll !"
  end



  def nb_round_trips_to_redis(commands)
    # puts "\n\nCounting nb_round_trips_to_redis"
    round_trips = 0
    in_a_transaction = false
    
    # puts commands.inspect
    commands.each do |command|
      # puts command.inspect
      if command == 'multi'
        round_trips += 1
        in_a_transaction = true
      elsif command == 'exec'
        in_a_transaction = false
      elsif !in_a_transaction
        round_trips += 1
      end
    end
    
    # puts "Counted #{round_trips} round_trips !\n\n\n"
    round_trips
  end
  

  def actual_redis_commands
    # wait for the redis monitor thread to receive feedback on the sent commands
    # puts "sending a ping ! #{@called_commands.inspect}"
    
    redis.ping
    
    @verif_thread.join
    
    @called_commands
  end

end
