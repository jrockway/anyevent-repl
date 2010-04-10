use strict;
use warnings;
use Test::More;

use AnyEvent::REPL;

use feature 'state';

my $repl = AnyEvent::REPL->new;

my $got_msg = AnyEvent->condvar;
my $cv = AnyEvent->condvar;
my $cv2 = AnyEvent->condvar;

$repl->push_eval(
    'print "hello\n"; while(1){ no warnings; "OH NOES" }',
    on_error  => $cv,
    on_result => $cv,
    on_output => sub {
        state $msg = "";
        $msg .= $_[0];
        $got_msg->send($msg) if $msg =~ "\n";
    },
);

$repl->push_eval(
    '42',
    on_error  => $cv2,
    on_result => $cv2,
);

is $got_msg->recv, "hello\n", 'got the message from the first job';

$repl->kill;

is $cv->recv, 'REPL process died; aborting', 'first task was killed with fire';
is $cv2->recv, '42', 'second job restarted the REPL and ran to completion';

done_testing;
