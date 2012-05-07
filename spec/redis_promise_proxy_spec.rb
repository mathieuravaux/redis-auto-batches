require 'spec_helper'

describe RedisAutoBatches::RedisPromiseProxy do
  let(:redis) { stub(:redis) }
  subject { RedisAutoBatches::RedisPromiseProxy.new(redis) }
  
  # around(:each) do |example|
  #   subject.unit_of_work do
  #     example.run
  #     redis.should_receive(:multi)
  #   end
  # end
  
  def quacks_like_a_promise?(object)
    object.respond_to?(:__force__) &&
    object.respond_to?(:__chain__) &&
    object.respond_to?(:__pending__?) &&
    object.respond_to?(:__fulfilled__?) &&
    object.respond_to?(:__failed__?)
  end

  let(:keys) { %w[ key_1 key_2 key_3 key_4 key_5 ] }

  describe "#get" do
    it "returns a promise" do
      subject.stub(:outside_unit_of_work?, false)
      quacks_like_a_promise?(subject.get("key_1")).should be_true
    end

    context "when the result is used" do
      it "hits redis" do
        subject.unit_of_work do
          redis.should_receive(:get).with("key_1").and_return("fine")
          result = subject.get("key_1")
          result.length.should == 4
        end
      end
    end

    context "when the result isn't used" do
      it "doesn't hit redis" do
        subject.stub(:outside_unit_of_work?, false)
        redis.should_not_receive(:get)
        subject.get("key_1")
      end
    end
    
  end
  
  describe "succession of 5 gets" do
    it "returns 5 promises and fulfill it" do
      subject.unit_of_work do
        keys.each do |key|
          quacks_like_a_promise?(subject.get(key)).should be_true
        end
        redis.should_receive(:multi).exactly(1).times.and_return(nil)
        redis.should_receive(:get).exactly(5).times.and_return(nil)
        redis.should_receive(:exec).and_return(['1', '2', '3', '4', '5'])
      end
    end
    
    context "when the result is not used" do
      it "doesn't hit redis" do
        subject.stub(:outside_unit_of_work?, false)
        redis.should_not_receive(:multi)
        redis.should_not_receive(:get)
        redis.should_not_receive(:exec)
        keys.each { |key| subject.get(key) }
      end
    end
    
    context "when the result of one of the promises is used" do
      before do
        redis.should_receive(:multi).exactly(1).times.and_return(nil)
        redis.should_receive(:get).exactly(5).times.and_return(nil)
        redis.should_receive(:exec).and_return(['1', '2', '3', '4', '5'])
      end
      
      it "hits redis in a transaction" do
        subject.unit_of_work do
          results = keys.map { |key| subject.get(key) }
          results[3] + results[4]
        end
      end
      
      it "fulfills each promise with the respective correct value" do
        subject.unit_of_work do
          results = keys.map { |key| subject.get(key) }
          results.should == ['1', '2', '3', '4', '5']
        end
      end
    end
    
  end
  
  # get and set now behaves exactly the same
  # describe "#set" do
  #   it "hits redis immediately" do
  #     redis.should_not_receive(:multi)
  #     redis.should_not_receive(:exec)
  #     redis.should_receive(:set).with("key_1", "value_1").and_return('1')
  #     subject.set('key_1', 'value_1')
  #   end
  #   
  #   it "flushes pending buffered reads" do
  #     redis.should_receive(:multi).exactly(1).times.and_return(nil)
  #     redis.should_receive(:get).exactly(5).times.and_return(nil)
  #     redis.should_receive(:exec).and_return(['1', '2', '3', '4', '5'])
  #     redis.should_receive(:set).with("key_1", "value_1").and_return('1')
  #     keys.each { |key| subject.get(key) }
  #     subject.set('key_1', 'value_1')
  #   end
  #   
  # end
  
  context "repeated usage" do
    it "reinitializes correctly its data structures" do
      redis.should_receive(:multi).exactly(2).times.and_return(nil)
      redis.should_receive(:get).exactly(5).times.and_return(nil)
      redis.should_receive(:exec).and_return(['1', '2', '3'],  ['4', '5'])
      subject.unit_of_work do
        one, two, three = subject.get('key_1'), subject.get('key_2'), subject.get('key_3')
        one.pending?.should be_true
        two.pending?.should be_true
        three.pending?.should be_true

        three.to_i.should == 3
        one.fulfilled?.should be_true
        two.fulfilled?.should be_true
        three.fulfilled?.should be_true

        four, five = subject.get('key_4'), subject.get('key_5')
        four.pending?.should be_true
        five.pending?.should be_true
        four.to_i.should == 4
        five.fulfilled?.should be_true
        five.to_i.should == 5
      end
      
    end
  end
  
  context "with chaining of operations on the promise" do
    it "stays lazy" do
      subject.stub(:outside_unit_of_work?, false)
      redis.should_not_receive(:multi)
      redis.should_not_receive(:get)
      subject.get('key_1').chain {|v| v.to_i }
    end
    
    it "applies the computation in the expected way" do
      redis.should_receive(:get).and_return('12')
      subject.unit_of_work do
        subject.get('key_1').chain {|v| v.to_i }.should == 12
      end
      
    end
    
  end
  
  describe "#unit_of_work" do
    it "flush everything on the start of a new unit of work and restore correctly after" do
      subject.unit_of_work do
        subject.get('key_1')
        redis.should_receive(:get).with("key_1").and_return("fine")
        subject.unit_of_work do
          subject.get('key_2')
          redis.should_receive(:get).with("key_2").and_return("fine")
        end
        subject.get('key_3')
        redis.should_receive(:get).with("key_3").and_return("fine")
      end
    end
    it "execute immediately immediate commands (and flush waiting commands before)" do
      subject.unit_of_work do
        redis.should_receive(:expire).with("key_1", 14)
        subject.expire('key_1', 14)
      end
    end
    it "flush after MAX_BUFFERED_PROMISES" do
      subject.unit_of_work do
        redis.should_receive(:multi)
        redis.should_receive(:get).with("key_1").exactly(RedisAutoBatches::RedisPromiseProxy::MAX_BUFFERED_PROMISES).times.and_return(nil)
        redis.should_receive(:exec).and_return(["fine"])
        RedisAutoBatches::RedisPromiseProxy::MAX_BUFFERED_PROMISES.times { subject.get('key_1') }
        subject.get('key_1')
        redis.should_receive(:get).with("key_1").exactly(1).times.and_return("fine")
      end
    end
  end
end