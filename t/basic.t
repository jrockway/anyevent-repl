use strict;
use warnings;
use Test::More;
use Test::Exception;

use EV;
use AnyEvent::REPL;

my $repl = AnyEvent::REPL->new;

{
    my $done = AnyEvent->condvar;
    my $buf;
    $repl->push_eval(
        'print "Hello, world!\n"',
        on_output => sub { $buf .= $_[0] },
        on_result => sub { $done->send( $_[0] ) },
        on_error  => sub { $done->croak( $_[0] ) },
    );

    my $result = $done->recv;

    is $result, '1', 'got result';
    ok chomp $buf, 'buf had newline :)';
    is $buf, 'Hello, world!', 'got stdout';
}

{
    # test to make sure our output-getter doesn't mess things up when
    # there is no output.
    my $done = AnyEvent->condvar;
    $repl->push_eval(
        '2 + 42',
        on_output => sub { warn "unexpected output: @_" },
        on_result => sub { $done->send( $_[0] ) },
        on_error  => sub { $done->croak( $_[0] ) },
    );

    my $result = $done->recv;

    is $result, '44', 'got result';
}


{
    # test push_write
    my $done = AnyEvent->condvar;
    $repl->push_eval(
        'my $data = <>;',
        on_result => sub { $done->send( $_[0] ) },
        on_error  => sub { $done->croak( $_[0] ) },
    );

    $repl->push_write("GOT ITEM!\n");

    my $result = $done->recv;

    is $result, "GOT ITEM!\n", 'got result';
}

{
    # test errors
    my $done = AnyEvent->condvar;
    $repl->push_eval(
        'this is probably not valid perl.',
        on_result => sub { $done->send( $_[0] ) },
        on_error  => sub { $done->croak( $_[0] ) },
    );

    eval {
        my $result = $done->recv;
    };
    like $@, qr/Compile error: syntax error at/, 'got error message';
}

{
    # test arbitrary commands
    my $done = AnyEvent->condvar;
    $repl->push_command(
        'OH_HAI', { args => 'go here' },
        on_result => sub { $done->send( $_[0] ) },
        on_error  => sub { $done->croak( $_[0] ) },
    );

    eval {
        my $result = $done->recv;
    };
    like $@, qr/No handler for OH_HAI/, 'got error message';
}

done_testing;
