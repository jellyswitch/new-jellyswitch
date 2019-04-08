require 'singleton'

module StripeHelpers
  class StripeMock
    include Singleton

    @pid = nil
    @port = -1

    # Starts stripe-mock, if necessary. Returns the port on which stripe-mock is listening.
    def self.start
      unless @pid.nil?
        puts("stripe-mock already running on port #{@port}")
        return @port
      end

      puts("Starting stripe-mock...")

      @stdout, @child_stdout = ::IO.pipe
      @stderr, @child_stderr = ::IO.pipe

      @pid = ::Process.spawn(
        ["stripe-mock", "stripe-mock"],
        "-http-port",
        "0", # have stripe-mock select a port
        out: @child_stdout,
        err: @child_stderr
      )

      [@child_stdout, @child_stderr].each(&:close)

      # Look for port in "Listening for HTTP on port: 50602"
      buffer = ""
      loop do
        buffer += @stdout.readpartial(4096)
        if (matches = buffer.match(/ port: (\d+)/))
          @port = matches[1]
          break
        end
        sleep(0.1)
      end

      status = (::Process.wait2(@pid, ::Process::WNOHANG) || []).last
      if status.nil?
        puts("Started stripe-mock; PID = #{@pid}, port = #{@port}")
      else
        abort("stripe-mock terminated early: #{status}")
      end

      @port
    end

    # Stops stripe-mock, if necessary.
    def self.stop
      return if @pid.nil?
      puts("Stopping stripe-mock...")
      ::Process.kill(:SIGTERM, @pid)
      ::Process.waitpid2(@pid)
      @pid = nil
      @port = -1
      puts("Stopped stripe-mock")
    end
  end
end
