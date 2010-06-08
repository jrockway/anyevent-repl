use strict;
use warnings;
use Test::More;

use Coro;
use AnyEvent::REPL;
use AnyEvent::REPL::CoroWrapper;
use Try::Tiny;

my $repl = AnyEvent::REPL->new;
my $wrapped = AnyEvent::REPL::CoroWrapper->new( repl => $repl );

sub foo {
    my $rand = $wrapped->do_eval('rand 10');
    my $plus_two = $wrapped->do_eval("$rand + 2");
    my $two = $wrapped->do_eval("$plus_two - $rand");
    return $two;
}

my $a_coro = async \&foo;
my $b_coro = async \&foo;

ok $a_coro;
ok $b_coro;

is $b_coro->join, 2, 'second coro worked';
is $a_coro->join, 2, 'first coro also worked';

my $e_coro = async {
    return try {
        $wrapped->do_eval('die "OH NOES"');
        return { result => 'fail' };
    }
    catch {
        chomp;
        s/ at .+$//;
        return { 'error' => $_ };
    };
};

is_deeply $e_coro->join, { error => 'Runtime error: OH NOES' }, 'dying works';

done_testing;
