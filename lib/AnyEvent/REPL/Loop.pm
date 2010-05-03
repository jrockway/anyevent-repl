use MooseX::Declare;

class AnyEvent::REPL::Loop with MooseX::Traits {
    use Try::Tiny;
    has 'frontend' => (
        is       => 'ro',
        isa      => 'AnyEvent::REPL::Frontend',
        required => 1,
    );

    has 'backend' => (
        is       => 'ro',
        does     => 'Devel::REPL::Backend::API',
        required => 1,
    );

    method run {
        local $SIG{USR1} = 'IGNORE';
        while ($self->run_once) {
            # keep looping
        }
    }

    method run_once {
        my $req = $self->frontend->read;

        my $res;
        try {
            my $type = $req->{type} || die 'need type';
            my $method = 'handle_'.$type;
            die "No handler for $type" unless
              $self->can($method);

            $res = $self->$method($req);
        }
        catch {
            $res = { type => 'error', error => $_ };
        };

        $res->{token} = $req->{token};
        $self->frontend->print($res);
        return 1;
    }

    method handle_eval(HashRef $req){
        my @result = do {
            local $SIG{USR1} = sub { die 'user interrupt' };
            $self->backend->eval($req->{code});
        };

        no warnings 'uninitialized';
        my $response;
        if ($self->backend->is_error($result[0])) {
            $response = {
                type  => 'error',
                error => join '', $self->backend->format_error(@result),
            };
        }
        else {
            $response = {
                type   => 'success',
                result => join '', $self->backend->format_result(@result),
            };
        }
        return $response;
    }
}
