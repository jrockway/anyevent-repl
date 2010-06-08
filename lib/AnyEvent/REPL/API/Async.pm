use MooseX::Declare;

role AnyEvent::REPL::API::Async {
    requires 'push_write';
    requires 'kill';
    requires 'push_eval';
    requires 'push_command';
}
