use strict;
use warnings;
use Test::More;
use Test::Exception;

use MooseX::Declare;
use AnyEvent::REPL;
class A {
    use AnyEvent::REPL::Types qw(SyncREPL);
    has 'repl' => (
        is       => 'ro',
        isa      => SyncREPL,
        required => 1,
        coerce   => 1,
    );
};

my $repl = AnyEvent::REPL->new;
ok !$repl->does('AnyEvent::REPL::API::Sync');

my $a;
lives_ok { $a = A->new( repl => $repl ) };
ok $a->repl->does('AnyEvent::REPL::API::Sync'), 'coerced ok';

done_testing;
