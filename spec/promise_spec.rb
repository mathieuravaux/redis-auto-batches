require "spec_helper"

describe RedisAutoBatches::Promise do

  it "can be instantiated" do
    RedisAutoBatches::Promise.new { }
  end

  it "can be instantiated as a method call, like the Integer class" do
    RedisAutoBatches.promise {}
  end

  it "doesn't call the passed proc when created" do
    RedisAutoBatches.promise { fail "I shouldn't have been evaluated " }
  end

  it "calls the passed proc when it's evaluation is forced" do
    task = mock(:task).tap { |mock| mock.should_receive(:work) }
    p = RedisAutoBatches.promise { task.work }
    p.force
  end

  it "presents the wrapped value transparently" do
    (RedisAutoBatches.promise { 5 } + 3).should == 8
    (3 + RedisAutoBatches.promise { 5 }).should == 8
    RedisAutoBatches.promise { 5 }.to_s.should == "5"
  end

  it "lets exceptions bubble up naturally" do
    p = RedisAutoBatches.promise { 1/0 }
    expect { p.force }.to raise_error(ZeroDivisionError)
  end

  describe "#inspect" do
    context "with a new RedisAutoBatches::Promise" do
      it "doesn't force it to evaluate" do
        task = mock(:task).tap { |mock| mock.should_not_receive(:work) }
        p = RedisAutoBatches.promise { task.work }
        p.inspect
      end
    
      it "prints a helpful message" do
        message = RedisAutoBatches.promise { 5 }.inspect
        message.should include("<RedisAutoBatches::Promise:pending:#<Proc:")
        message.should include("spec/promise_spec.rb:") 
      
      end
    end
  
    context "with a fulfilled promise" do
      it "presents itself as a fulfilled promise, with the result" do
        p = RedisAutoBatches.promise { 5 }
        p.force
        p.inspect.should == "<RedisAutoBatches::Promise:fulfilled:5>"
      end
    end
  
    context "with a failed promise" do
      it "presents itself as a failed promise, with the error" do
        p = RedisAutoBatches.promise {1/0}
        p.force rescue nil
        p.inspect.should == "<RedisAutoBatches::Promise:error:divided by 0>"
      end
    end
  end

  describe "#chain" do
    it "returns a promise" do
      RedisAutoBatches.promise { 5 }.chain(&:to_s).inspect.should include("<RedisAutoBatches::Promise:pending")
    end
  
    it "doesn't force the evaluation" do
      task = mock(:task).tap { |mock| mock.should_not_receive(:work) }
      p = RedisAutoBatches.promise { task.work }
      p.chain { |work_result| work_result.use }
    end
  
    it "applies both evaluations when the result of the second promise is forced" do
      task = mock(:task).tap { |mock| mock.should_receive(:work) }
      p = RedisAutoBatches.promise { task.work }
      q = p.chain { }
      q.force
    end
  end

  describe "Promise.ratio" do
    let(:numerator) { RedisAutoBatches.promise { 2 } }
    let(:denominator) { RedisAutoBatches.promise { 10 } }

    it "evaluates lazily both operands" do
      numerator, denominator = 2.times.map { RedisAutoBatches.promise { fail "U Can't Touch this !"} }
      RedisAutoBatches::Promise.ratio(numerator, denominator)
    end
  
    it "evaluates both operands when evaluated itself" do
      ratio = RedisAutoBatches::Promise.ratio(numerator, denominator)
      ratio.should == 0.2
    end
  
    it "serializes as JSON as the result would" do
      require "json"
      ratio = RedisAutoBatches::Promise.ratio(numerator, denominator)
      {:accuracy => ratio}.to_json.should == %Q({"accuracy":0.2})
    end

  end
end
