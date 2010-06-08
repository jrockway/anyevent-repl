use MooseX::Declare;

role AnyEvent::REPL::API::Sync {
    requires 'push_write';
    requires 'kill';
    requires 'do_command';
    requires 'do_eval';
}
