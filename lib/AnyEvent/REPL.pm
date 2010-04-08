use MooseX::Declare;

class AnyEvent::REPL {
    use JSON::XS;

    use AnyEvent;
    use AnyEvent::Handle;
    use AnyEvent::Subprocess;
    use AnyEvent::REPL::Backend;
    use feature 'switch';

    has 'plugins' => (
        is      => 'ro',
        isa     => 'ArrayRef',
        default => sub { [qw/+Devel::REPL::Plugin::DDS +Devel::REPL::Plugin::LexEnv/] },
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
        handles => {
            _push_request            => 'push',
            _next_request            => 'shift',
            _no_outstanding_requests => 'is_empty',
        },
    );

    method _build_repl_job {
        my $job = AnyEvent::Subprocess->new(
            on_completion => sub { $self->_handle_exit },
            delegates     => [
                'CommHandle',
                { Pty => { stderr => 1 } },
            ],
            code => sub {
                my $args = shift;
                `stty raw -echo`;

                my $repl = AnyEvent::REPL::Backend->new;
                $repl->load_plugins(@{$args->{plugins} || []});

                my $comm = $args->{comm};

                while( my $request_json = <$comm> ){
                    chomp $request_json;
                    my $request = decode_json $request_json;

                    my $response;
                    eval {
                        my @result = $repl->eval($request->{code});
                        if($repl->is_error($result[0])){
                            $response = {
                                type  => 'error',
                                error => join '', $repl->format_error(@result),
                            };
                        }
                        else {
                            $response = {
                                type   => 'success',
                                result => join '', $repl->format_result(@result),
                            };
                        }
                    };
                    if( $@ ) {
                        $response = { type => 'error', error => $@ };
                    }

                    $response->{token} = $request->{token};
                    syswrite $comm, encode_json $response;
                }
            },
        );
    }

    method _build_repl { $self->_start_repl({ plugins => $self->plugins }) }

    method push_write(Str $data) {
        $self->repl_pty->handle->push_write( $data );
    }

    method push_eval(Str $code, CodeRef :$on_output?, CodeRef :$on_result, CodeRef :$on_error){
        $self->_push_request({
            token  => $self->get_id,
            code   => $code,
            output => $on_output,
            result => $on_result,
            error  => $on_error,
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

            $self->repl_comm->handle->push_write( json => {
                token => $req->{token},
                code  => $req->{code},
            });

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
        $self->_run_once;
    }
}
