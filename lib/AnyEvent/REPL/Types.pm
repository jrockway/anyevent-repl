package AnyEvent::REPL::Types;
use strict;
use warnings;

use MooseX::Types::Moose qw(CodeRef);
use MooseX::Types -declare => ['CondVar', 'Handler', 'REPL'];

class_type CondVar, { class => 'AnyEvent::CondVar' };

role_type REPL, { role => 'AnyEvent::REPL::API' };

subtype Handler, as CondVar|CodeRef;

1;
