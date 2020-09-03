require 'sinatra/base'
require 'concurrent-ruby'

module Sinatra
  # It's there for Keep Alive in the sse stream.
  class RepeatTimer
    def initialize
      @loop_block = ->(interval, continue = nil, block){
        continue ||= Concurrent::Atom.new(true) 

        Concurrent::Promises.schedule(interval, continue){|continue|
          block.call if continue.value
        }.then{
          @loop_block.call(interval, continue, block) if continue.value
        }

        continue
      }
    end

    def start(interval, &block)
      return false if @continue.present?
      @interval = interval
      @block = block
      @continue = @loop_block.call(interval, block) 
      true
    end

    def start!(interval, &block)
      result = start(interval, &block)
      raise "You are trying to start without stopping." unless result
    end

    # If there is a running block, it will not kill. It will stop before the next run.
    def stop
      @continue.reset false
      @continue = nil
    end

    def reset
      stop
      start(@interval, &@block)
    end
  end

  # rack response body
  class SseStream
    def initialize(keep_alive, tcp_socket, &block)
      @keep_alive = keep_alive
      @block = block
      @timer = RepeatTimer.new
      @socket = tcp_socket
    end

    def each(&writer)
      @writer = writer
      @timer.start(@keep_alive){blank_comment}

      futures = []
      futures << Concurrent::Promises.future(self) do |me|
        @block.call me
      end

      future = observe_client_close
      futures << future if future

      Concurrent::Promises.any(*futures)
        .then(self){|value, me| me.close}.value!
    end

    def write(text=nil, retry_time: nil, event: nil, data: nil, comment: nil, id: nil)
      message = ""
      message += "retry: #{retry_time}\n" if retry_time
      message += "event: #{event}\n" if event
      message += "data: #{data || text}\n" if data || text
      message += ":#{comment}" if comment
      message += "id: #{id}\n" if id
      message += "\n"

      @writer.call message
      @timer.reset
    end
    alias << write

    # Sets the Proc that will be executed when the connection is closed.
    #
    # Example:
    #   sse do |out|
    #     out.on_close do
    #       redis.unsubscribe
    #     end
    #
    #     redis.subscribe(:foo) do |on|
    #       on.message do |event|
    #         out << event.data
    #       end
    #     end
    #   end
    def on_close(&block)
      @on_close = block
    end

    # for keep alive
    def blank_comment
      @writer&.call ":\n\n"
    end

    protected

    def close
      @timer.stop
      @on_close&.call
    end

    def observe_client_close
      if @socket
        Concurrent::Promises.future(@socket, @on_close) do |socket, on_close|
          socket.eof
          puts 'eof'
          on_close&.call
        end
      else
        logger.warn(<<~DOC)
          Not found TCP socket.
          The on_close callback is not called when the client disconnects.
          If it is a puma server, it will be found automatically.
          To pass the socket manually:
            sse(tcp_socket: xxx) do |out|
              # ...
            end
        DOC
        nil
      end
    end
  end


  module SseHelper
    # SSE stream
    #
    # Example:
    #  sse do |out|
    #   10.times{|i|
    #     out.write i
    #     sleep 1
    #   }
    #  end
    def sse(keep_alive: 15, tcp_socket: nil, &block) # :yields: SseStream
      content_type 'text/event-stream'

      tcp_socket ||= env['puma.socket']
      body SseStream.new(keep_alive, tcp_socket, &block)
    end

    # Http header "Last-Event-ID"
    #
    # Example:
    #   start = last_event_id || 1
    #
    #   sse do |out|
    #     (start..10).each do |i|
    #       out.write i * 2, id: i
    #     end
    #   end
    def last_event_id
      env['HTTP_LAST_EVENT_ID']
    end

    # Send no content response.
    #
    # spec: https://html.spec.whatwg.org/multipage/server-sent-events.html#server-sent-events-intro
    #
    # Clients will reconnect if the connection is closed; a client can be told to stop reconnecting using the HTTP 204 No Content response code.
    #
    # Example:
    #   no_content if last_event_id == 10
    #
    #   sse do |out|
    #     (1..10).each{|i| out.write i * 2, id: i}
    #   end
    def no_content
      halt 204
    end
  end

  helpers SseHelper
end
