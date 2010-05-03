use MooseX::Declare;

class AnyEvent::REPL {
    use AnyEvent;
    use AnyEvent::Handle;
    use AnyEvent::Subprocess;

    use AnyEvent::REPL::Backend;
    use AnyEvent::REPL::Frontend;
    use AnyEvent::REPL::Loop;

    use IO::Stty;
    use JSON::XS;

    use AnyEvent::REPL::Types qw(Handler);
    use feature 'switch';

    has 'backend_plugins' => (
        is      => 'ro',
        isa     => 'ArrayRef',
        default => sub { [
            '+Devel::REPL::Plugin::DDS',
            '+Devel::REPL::Plugin::LexEnv',
        ]},
    );

    has 'loop_traits' => (
        is      => 'ro',
        isa     => 'ArrayRef',
        default => sub { [] },
    );

    has 'repl_job' => (
        reader     => '_repl_job',
        does       => 'AnyEvent::Subprocess::Job',
        handles    => { _start_repl => 'run' },
        lazy_build => 1,
    );

    has 'repl' => (
        is         => 'ro',
        isa        => 'AnyEvent::Subprocess::Running',
        lazy_build => 1,
        predicate  => 'is_alive',
        handles    => {
            repl_comm => ['delegate', 'comm'],
            repl_pty  => ['delegate', 'pty'],
        },
    );

    has 'current_id' => (
        is      => 'ro',
        reader  => 'current_id',
        traits  => ['Counter'],
        default => 0,
        handles => { inc_id => 'inc' },
    );

    method get_id { $self->inc_id; $self->current_id }

    has 'response_handlers' => (
        traits  => ['Hash'],
        isa     => 'HashRef[HashRef]',
        default => sub { +{} },
        clearer => 'clear_response_handlers',
        lazy    => 1,
        handles => {
            _push_response_handler   => 'set',
            _get_response_handler    => 'get',
            _delete_response_handler => 'delete',
            _all_response_handlers   => 'values',
            _no_handlers             => 'is_empty',
        },
    );

    has 'request_queue' => (
        traits  => ['Array'],
        isa     => 'ArrayRef[HashRef]',
        default => sub { [] },
        clearer => 'clear_requests',
        lazy    => 1,
        handles => {
            _push_request            => 'push',
            _next_request            => 'shift',
            _no_outstanding_requests => 'is_empty',
        },
    );

    has 'capture_stderr' => (
        is      => 'ro',
        isa     => 'Bool',
        default => 1,
    );

    method _build_repl_job {
        my $job = AnyEvent::Subprocess->new(
            on_completion => sub { $self->_handle_exit },
            delegates     => [
                'CommHandle',
                { Pty => { stderr => $self->capture_stderr } },
            ],
            code => sub {
                my $args = shift;
                IO::Stty::stty(\*STDIN, 'raw');
                IO::Stty::stty(\*STDIN, '-echo');

                my $backend = AnyEvent::REPL::Backend->new;
                $backend->load_plugins(@{$args->{backend_plugins} || []});

                my $frontend = AnyEvent::REPL::Frontend->new(
                    fh => $args->{comm},
                );

                my $loop = AnyEvent::REPL::Loop->
                  with_traits(@{$args->{loop_traits} || []})->new(
                      frontend => $frontend,
                      backend  => $backend,
                );

                $loop->run;
            },
        );
    }

    method _build_repl {
        return $self->_start_repl({
            loop_traits     => $self->loop_traits,
            backend_plugins => $self->backend_plugins,
        });
    }

    method push_write(Str $data) {
        $self->repl_pty->handle->push_write( $data );
    }

    method push_eval(Str $code, CodeRef :$on_output?, Handler :$on_result, Handler :$on_error){
        $self->_push_request({
            token  => $self->get_id,
            code   => $code,
            output => $on_output,
            result => $on_result,
            error  => $on_error,
        });

        $self->_run_once;
    }

    method push_command(Str $type, HashRef $args, Handler :$on_result, Handler :$on_error){
        $self->_push_request({
            token   => $self->get_id,
            command => { %$args, type => $type },
            result  => $on_result,
            error   => $on_error,
        });

        $self->_run_once;
    }

    method _run_once {
        if($self->_no_handlers && !$self->_no_outstanding_requests){
            my $req = $self->_next_request;
            $self->_push_response_handler( $req->{token}, {
                error  => $req->{error},
                result => $req->{result},
                output => $req->{output},
            });

            # # just to be safe, kill reads and writes to the pty
            # delete $self->repl_pty->handle->{rbuf};
            # delete $self->repl_pty->handle->{wbuf};
            # delete $self->repl_pty->handle->{_queue};

            if(my $cb = $req->{output}){
                my $reader; $reader = sub {
                    my $h = shift;
                    #my $data = shift;
                    my $data = delete $h->{rbuf} || '';
                    $cb->($data) if length $data > 0;
                    $h->push_read($reader);
                    return 0;
                };
                $self->repl_pty->handle->push_read($reader);
            }

            $self->repl_comm->handle->push_read( json => sub {
                my ($h, $result) = @_;
                $self->_handle_result($result);
            });

            if($req->{code}){
                $self->repl_comm->handle->push_write( json => {
                    type  => 'eval',
                    token => $req->{token},
                    code  => $req->{code},
                });
            }
            elsif($req->{command}){
                $self->repl_comm->handle->push_write( json => {
                    %{$req->{command}},
                    token => $req->{token},
                });
            }
            $self->repl_comm->handle->push_write("\n");
        }
    }

    method _handle_result(HashRef $result) {
        my $token = $result->{token} || confess 'No token?';
        my $handlers = $self->_get_response_handler($token) ||
          confess "No handlers for $token!";
        $self->_delete_response_handler($token);

        if($handlers->{output}){
            # there could be output waiting that the event loop does
            # not have a chance to see; if so, do a nonblocking read
            # and get that.
            my $residual = delete $self->repl_pty->handle->{rbuf} || '';
            while(sysread $self->repl_pty->handle->fh, my $buf, 1024){
                $residual .= $buf;
            }
            $handlers->{output}->($residual) if length $residual > 0;
            delete $self->repl_pty->handle->{_queue}; # kill last push_read
        }

        given($result->{type}){
            when('success'){
                $handlers->{result}->($result->{result});
            }
            when('error'){
                $handlers->{error}->($result->{error});
            }
            default {
                $handlers->{error}->('bad response type received');
            }
        }

        $self->_run_once;
    }

    method _handle_exit {
        $self->clear_repl;
        for my $handler ($self->_all_response_handlers) {
            $handler->{error}->('REPL process died; aborting');
        }
        $self->clear_response_handlers;
        $self->_run_once; # continue to run queued jobs with a new REPL
    }

    method kill(Int $sig? = 9) {
        if($self->is_alive){
            $self->repl->kill($sig);
        }
    }
}
