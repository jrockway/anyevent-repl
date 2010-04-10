package AnyEvent::REPL::Types;
use strict;
use warnings;

use MooseX::Types::Moose qw(CodeRef);
use MooseX::Types -declare => ['CondVar', 'Handler'];

class_type CondVar, { class => 'AnyEvent::CondVar' };

subtype Handler, as CondVar|CodeRef;

1;
