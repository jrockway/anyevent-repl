use MooseX::Declare;

class AnyEvent::REPL::Backend  {
    with 'Devel::REPL::Backend::Default';

    with 'MooseX::Object::Pluggable';
    has '+_plugin_ns' => ( default => 'Devel::REPL::Plugin::' );
}
