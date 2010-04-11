use MooseX::Declare;

# example.

class AnyEvent::REPL::Terminal with MooseX::Runnable {
    use AnyEvent::REPL;
    use Term::ReadLine;
    use AnyEvent::Term;
    use AnyEvent::Term::ReadLine;
    use AnyEvent::Pump qw(pump);

    has 'repl' => (
        is      => 'ro',
        isa     => 'AnyEvent::REPL',
        default => sub { AnyEvent::REPL->new },
    );

    has 'input' => (
        is      => 'ro',
        isa     => 'AnyEvent::Term::ReadLine',
        default => sub {
            my $self = shift;
            AnyEvent::Term::ReadLine->new(
                prompt   => 'PERL> ',
                on_error => sub { warn "Dying from terminal illness"; exit 1 },
            );
        },
    );

    method run {
        my $term = AnyEvent::Term->instance;
        $term->stdin_handle->on_read(sub {
            my $h = shift;
            if( $h->{rbuf} =~ /^(.*)$/ ){
                $self->repl->kill(9);
                $h->{rbuf} = $1;
            }
        });
        my $done = 0;
        while( !$done ){
            my $prompt_pump = pump $self->input->pty->handle, $term;
            my $input_pump  = pump $term, $self->input->pty->handle;
            my $cv = AnyEvent->condvar;

            my $t;
            $self->input->push_readline( sub {
                my $line = shift;
                $term->push_write("\n");

                undef $prompt_pump;
                undef $input_pump;

                if($line =~ /^,exit$/){
                    $done = 1;
                    $cv->send('');
                }

                $self->repl->push_eval(
                    $line,
                    on_output => sub { $term->push_write(@_) },
                    on_error  => $cv,
                    on_result => $cv,
                );

                # kill the REPL if it seems locked up
                $t = AnyEvent->timer( after => 2, cb => sub { $self->repl->kill(9) } );
            });

            $term->push_write($cv->recv);
            undef $t;
        };

        $term->DEMOLISH; # safer than SMASH_WITH_HAMMER

        return 0;
    }
}
