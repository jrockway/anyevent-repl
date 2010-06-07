use MooseX::Declare;

role AnyEvent::REPL::API {
    requires 'push_write';
    requires 'push_eval';
    requires 'push_command';
    requires 'kill';
}
