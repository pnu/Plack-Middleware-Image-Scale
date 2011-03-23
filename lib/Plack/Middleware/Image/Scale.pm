package Plack::Middleware::Image::Scale;
use Moose;
use Plack::Util;
use Image::Scale;

extends 'Plack::Middleware';

sub call {
    my ($self,$env) = @_;
    
    return $self->app->($env) unless 
        $env->{PATH_INFO} =~ m{^(.*)/(.+)_(.+)\.(.+)$};
        
    my ($path,$basename,$prop,$ext) = ($1, $2, $3, $4);
    local $env->{PATH_INFO} = "$path/$basename.$ext";
    my ($width,$height) = split 'x', $prop;

    Plack::Util::response_cb( $self->app->($env), sub {
        my $res = shift;
        my $buffer;
        return sub {
            my $chunk = shift;
            if ( defined $chunk ) {
                $buffer .= $chunk;
                return q{};
            } elsif ( defined $buffer ) {
                my $scaled = $buffer; #scale it
                undef $buffer;
                return $scaled;
            } else {
                return;
            }
        };
    });
}

1;
