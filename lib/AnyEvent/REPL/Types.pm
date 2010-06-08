package AnyEvent::REPL::Types;
use strict;
use warnings;

use MooseX::Types::Moose qw(CodeRef);
use MooseX::Types -declare => ['CondVar', 'Handler',
                               'REPL', 'SyncREPL', 'AsyncREPL'];

class_type CondVar, { class => 'AnyEvent::CondVar' };

role_type AsyncREPL, { role => 'AnyEvent::REPL::API::Async' };
role_type SyncREPL, { role => 'AnyEvent::REPL::API::Sync' };

subtype REPL, as SyncREPL|AsyncREPL; # useless?

subtype Handler, as CondVar|CodeRef;

1;
