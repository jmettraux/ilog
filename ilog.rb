#--
# Copyright (c) 2009-2010, John Mettraux, jmettraux@gmail.com
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

  HISTORY_MAX = 100
    # remembers at max 100 lines of history

  def initialize (opts)

    @opts = opts

    @opts[:dir] ||= '.'

    @history = []
    @history_max = HISTORY_MAX

    @admins = (@opts[:admins] || '').split(',')

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
    # history regex

    @lhistory = @admins.empty? ?
      nil :
      /^:(.*)!(.*) PRIVMSG #{@opts[:nick]} :history( .*)?$/

    #
    # memos

    @memos = @admins.empty? ? nil : {}

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

  def stime

    Time.now.utc.strftime('%F %T utc')
  end

  def send (s)

    #puts "out> #{s}"
    @con.send("#{s}\r\n", 0)
  end

  LREG = /^:(.*)!(.*) PRIVMSG (#[^ ]+?) :(.*)$/
  LPING = /^PING :(.*)$/i
  LMEMO = /^memo ([^ :]+) *:(.+)$/
  LJOIN = /^:(.*)!(.*) JOIN /

  def receive_line (l)

    puts l

    l = l.strip

    return if l == ''

    if m = LPING.match(l)
      send "PONG :#{m[1]}"
      return
    end

    # history

    if @lhistory && (m = @lhistory.match(l)) && @admins.include?(m[1])

      offset = (m[3] || 10).to_i rescue 10
      offset = @history.length - offset
      offset = 0 if offset < 0

      @history[offset..-1].each do |hl|
        send "PRIVMSG #{m[1]} :#{hl}"
        sleep 0.500 # trying to avoid getting caught for flooding
      end
    end

    # on join

    if m = LJOIN.match(l)

      (@memos.delete(m[1]) || []).each do |author, time, memo|
        sleep 0.300
        msg = "#{m[1]}: (memo from #{author} at #{time}) #{memo}"
        send "PRIVMSG ##{@opts[:channel]} :#{msg}"
        @mutex.synchronize { @file.puts("#{stime} #{@opts[:nick]}: #{msg}") }
      end
    end

    # ...

    m = LREG.match(l)

    # memo

    if m and @admins.include?(m[1]) and mm = LMEMO.match(m[4])
      (@memos[mm[1]] ||= []) << [ m[1], Time.now.to_s, mm[2].strip ]
    end

    # regular logging

    @mutex.synchronize do

      @file.write("#{stime} ")

      if m
        ll = "#{m[1]}: #{m[4]}"
        @history << ll
        @file.write(ll)
      else
        @history << l
        @file.write(l)
      end
      @file.write("\n")
      @file.flush
    end

    while @history.length > @history_max
      @history.shift
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

== advanced usage

  -a {nick[s]_of_admin}
    : specifies a admin, a person who has the right to talk to
      the logger and issue a 'history' command to it
      It's OK to specify a comma separated list of admin nicks.
  }

  if opts['-h'] || opts['--help']
    puts USAGE
    exit 0
  end

  opts = %w[ server port nick channel dir admins ].inject({}) { |h, o|
    h[o.to_sym] = opts["-#{o[0, 1]}"]
    h
  }

  unless opts[:server] && opts[:port] && opts[:channel] && opts[:nick]
    puts USAGE
    exit 1
  end

  Ilog.new(opts)
end

