use MooseX::Declare;

class AnyEvent::REPL::Frontend with Devel::REPL::Frontend::API {
    use JSON;

    has 'pty' => (
        is       => 'ro',
        isa      => 'GlobRef',
        required => 1,
    );

    method read {
        my $fh = $self->pty;

        my $request_json = <$fh>;
        return if !$request_json;

        my $request = decode_json $request_json;
        return $request;
    }

    method print(Ref $response) {
        syswrite $self->pty, encode_json $response;
    }
}
