use MooseX::Declare;

class AnyEvent::REPL::CoroWrapper
  with (AnyEvent::REPL::API::Sync, AnyEvent::REPL::API::Async) {
    use AnyEvent::REPL::Types qw(AsyncREPL);
    use Coro::Util::Rouse qw(rouse_cb rouse_wait);

    has 'repl' => (
        is       => 'ro',
        isa      => AsyncREPL,
        required => 1,
        handles  => 'AnyEvent::REPL::API::Async',
    );

    method do_command(Str $command, HashRef $args){
        my ($ok, $err) = rouse_cb;
        $self->push_command(
            $command, $args,
            on_result => $ok,
            on_error  => $err,
        );
        return rouse_wait;
    }

    method do_eval(Str $code, CodeRef :$on_output?){
        my ($ok, $err) = rouse_cb;
        $self->push_eval(
            $code,
            on_result => $ok,
            on_error  => $err,
            $on_output ? (on_output => $on_output) : (),
        );
        return rouse_wait;
    }
}
