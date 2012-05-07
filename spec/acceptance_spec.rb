require 'spec_helper'

describe 'Acceptance criteria' do
  let(:redis) { Redis.connect }
  subject { RedisAutoBatches::RedisPromiseProxy.new(redis) }

  before do
    redis.set("key1", 10)
    redis.set("key2", 20)
    redis.set("key3", 30)
  end

  include RedisMonitoring

  context "when used inside a unit of work" do
    context "when executing several read Redis commands" do
      it "does only one round-trip to Redis" do
        subject.unit_of_work do
          [ subject.get("key1"),
            subject.get("key2"),
            subject.get("key3")
          ]
        end
        
        actual_redis_commands.should == [
          'multi',
          'get key1',
          'get key2',
          'get key3',
          'exec'
        ]
      end
    end
    
    context "when issuing read commands after write commands" do
      def issue_operations
        subject.unit_of_work do
          [
            subject.get("key1"),
            subject.set("key1", "1000"),
            subject.get("key1")
          ]
        end
      end
      
      it "still does only one round-trip to redis" do
        pending "Threading issues"
        issue_operations
        
        commands = actual_redis_commands
        # puts commands.inspect
        nb_round_trips_to_redis(commands).should == 1
      end

      it "reads the newly written value, as expected" do
        values = issue_operations
        values.should == %w(10 OK 1000)
      end
    end
    
    
  end
end