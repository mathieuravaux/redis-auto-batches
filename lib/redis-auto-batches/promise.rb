# TODO: contribute back to the promising-future gem
# https://github.com/bhuga/promising-future

##
# A delayed-execution promise.  Promises are only executed once.
#
# @example
#   x = promise { factorial 20 }
#   y = promise { fibonacci 10**6 }
#   a = x + 1     # => factorial 20 + 1 after factorial calculates
#   result = promise { a += y }
#   abort ""      # whew, we never needed to calculate y
#
# @example
#   y = 5
#   x = promise { y = y + 5 }
#   x + 5     # => 15
#   x + 5     # => 15
#

module RedisAutoBatches
  class Promise < BasicObject
    NOT_SET = ::Object.new.freeze

    instance_methods.each { |m| undef_method m unless m.to_s =~ /__/ }

    ##
    # Creates a new promise.
    #
    # @example Lazily evaluate a database call
    #   result = promise { @db.query("SELECT * FROM TABLE") }
    #
    # @yield  [] The block to evaluate lazily.
    # @see    Kernel#promise
    def initialize(&block)
      if block.arity > 0
        raise ArgumentError, "Cannot store a promise that requires an argument"
      end
      @block  = block
      @mutex  = ::Mutex.new
      @result = NOT_SET
      @error  = NOT_SET
    end

    ##
    # Force the evaluation of this promise immediately
    #
    # @return [Object]
    def __force__
      # ::Kernel.puts "__force__ called !"
      @mutex.synchronize do
        if pending?
          begin
            fulfill @block.call
          rescue ::Exception => error
            fail error
          end
        end
      end if pending?
      # BasicObject won't send raise to Kernel
      ::Kernel.raise(@error) if failed?
      @result
    end
    alias_method :force, :__force__

    def __fulfill__ result
      @result = result
    end
    alias_method :fulfill, :__fulfill__

    def __fail__ error
      @error = error
    end
    alias_method :fail, :__fail__
  
    def __fulfilled__?
      !@result.equal?(NOT_SET)
    end
    alias_method :fulfilled?, :__fulfilled__?
  
    def __failed__?
      !@error.equal?(NOT_SET)
    end
    alias_method :failed?, :__failed__?
  
    def __pending__?
      !(__fulfilled__? || __failed__?)
    end
    alias_method :pending?, :__pending__?

    ##
    # Does this promise support the given method?
    #
    # @param  [Symbol]
    # @return [Boolean]
    def respond_to?(method)
      [ :fulfill, :fail, :force, :chain, :fulfilled?, :failed?, :pending?,
        :__fulfill__, :__fail__, :__force__, :__chain__, :__fulfilled__?, :__failed__?, :__pending__?
      ].include?(method) || begin
        # ::Kernel.puts "__forcing__ due to respond_to?(#{method}) !"
        __force__.respond_to?(method)
      end
    end

    def __chain__ &block
      parent = self
      Promise.new {
        value = parent.__force__
        block.call(value)
      }
    end
    alias_method :chain, :__chain__

    def inspect
      if @result.equal?(NOT_SET)
        if @error.equal?(NOT_SET)
          "<RedisAutoBatches::Promise:pending:#{@block}>"
        else
          "<RedisAutoBatches::Promise:error:#{@error}>"
        end
      else
        "<RedisAutoBatches::Promise:fulfilled:#{@result}>"
      end
    end

    def self.ratio(part, total)
      self.new { if total.zero? then 0.0 else part.to_f / total.to_f end }
    end

    private

    def method_missing(method, *args, &block)
      # ::Kernel.puts "Forcing promise due to call of #{method.inspect} on it."
      __force__.__send__(method, *args, &block)
    end
  end

  def self.promise &block
    Promise.new(&block)
  end
end