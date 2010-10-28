
= ilog

stupid IRC channel logger with file rotation.

== usage

  ruby ilog.rb -s freenode.example.net -p 6667 -c fishing -n the_logger -d .

will log the channel #fishing and place the logs in the current (.) directory.

File are rotated every day.


== requirements

ruby 1.8.6 or better, gem install rufus-scheduler


== license

MIT

