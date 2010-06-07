use MooseX::Declare;

class AnyEvent::REPL::CoroWrapper with AnyEvent::REPL::API {
    use AnyEvent::REPL::API;
    use AnyEvent::REPL::Types qw(REPL);
    use Coro::Util::Rouse qw(rouse_cb rouse_wait);

    has 'repl' => (
        is       => 'ro',
        isa      => REPL,
        required => 1,
        handles  => 'AnyEvent::REPL::API',
    );

    method eval_now(Str $code, CodeRef :$on_output?){
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
