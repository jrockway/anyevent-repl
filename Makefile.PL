use inc::Module::Install;
use strict;

name 'AnyEvent-REPL';
all_from 'lib/AnyEvent/REPL.pm';

requires 'AnyEvent';
requires 'AnyEvent::Subprocess';
requires 'Devel::REPL'; # the one from github.com/jrockway/devel-repl
requires 'IO::Stty';
requires 'JSON';
requires 'MooseX::Declare';
requires 'MooseX::Types';
requires 'MooseX::Traits' => '0.09';

requires 'Coro'; # for Coro-ized REPL
requires 'Coro::Util::Rouse'; # for Coro-ized REPL

WriteAll;
