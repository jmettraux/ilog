#--
# Copyright (c) 2009, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Japan.
#++

require 'rubygems'

require 'thread'
require 'socket'
require 'rufus/scheduler' # sudo gem install rufus-scheduler


class Ilog

  def initialize (opts)

    @opts = opts

    @opts[:dir] ||= '.'

    @mutex = Mutex.new
    determine_target_file

    @con = TCPSocket.open(@opts[:server], @opts[:port].to_i)
    nick = @opts[:nick]

    send "USER #{nick} #{nick}0 #{nick}1 :#{nick}"
    send "NICK #{nick}"
    send "JOIN ##{@opts[:channel]}"

    #
    # log rotation

    @scheduler = Rufus::Scheduler.start_new(:frequency => 60)
    @scheduler.every('1h') { determine_target_file }

    #
    # select loop (listening)

    loop do
      ready = select([ @con ], nil, nil, nil)
      next unless ready
      for s in ready.first
        break if @con.eof
        line = @con.gets
        receive_line(line)
      end
    end
  end

  protected

  def determine_target_file

    @mutex.synchronize do

      @file.close if @file and @file != $stdout

      dir = @opts[:dir]

      if dir == '-'

        @file = $stdout

      else

        fn = [
          @opts[:server],
          @opts[:channel],
          Time.now.utc.strftime('%F'),
        ].join('_') + '.txt'

        path = "#{@opts[:dir]}/#{fn}"

        @file = File.open(path, 'a')
      end
    end
  end

  def send (s)

    #puts "out> #{s}"
    @con.send("#{s}\r\n", 0)
  end

  LREG = /^:(.*)!(.*) PRIVMSG (#.*) :(.*)$/
  LPING = /^PING :(.*)$/i

  def receive_line (l)

    if m = LPING.match(l)
      send "PONG :#{m[1]}"
      return
    end

    @mutex.synchronize do

      if m = LREG.match(l)
        @file.write "#{Time.now.utc.strftime('%F %T utc')} #{m[1]}: #{m[4]}"
      else
        @file.write l
      end
      @file.write "\n"
      @file.flush
    end
  end
end

if __FILE__ == $0

  rest = []
  opts = {}
  while arg = ARGV.shift do
    if arg.match(/^-/)
      opts[arg] = (ARGV.first &&  ! ARGV.first.match(/^-/)) ? ARGV.shift : true
    else
      rest << arg
    end
  end

  USAGE = %{
  = ilog

  stupid IRC channel logger, with log rotation

  == usage
  
  ruby #{__FILE__} -s {server} -p {port} -n {nick} -c {channel} [-d {dir}]

  == for example

    ruby ilog.rb -s toto.skynet.nl -p 6667 -n toto -c biking -d /var/logs/irc/
  }

  if opts['-h'] || opts['--help']
    puts USAGE
    exit 0
  end

  opts = %w[ server port nick channel dir ].inject({}) { |h, o|
    h[o.to_sym] = opts["-#{o[0, 1]}"]
    h
  }

  unless opts[:server] && opts[:port] && opts[:channel] && opts[:nick]
    puts USAGE
    exit 1
  end

  Ilog.new(opts)
end

