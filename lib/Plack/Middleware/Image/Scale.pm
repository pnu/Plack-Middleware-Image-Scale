package Plack::Middleware::Image::Scale;
use Moose;
use Plack::Util;
use Try::Tiny;
use Image::Scale;

extends 'Plack::Middleware';

sub call {
    my ($self,$env) = @_;

    return $self->app->($env) unless 
        $env->{PATH_INFO} =~ m{^(.*)/(.+)_(.+)\.(jpg|png)$};

    my ($path,$basename,$prop,$ext) = ($1, $2, $3, $4);
    my ($width,$height) = split 'x', $prop;

    my $res;
    for my $oext ( qw( jpg png gif )) {
        local $env->{PATH_INFO} = "$path/$basename.$oext";
        $res = $self->app->($env);
        last if $res->[0] == 200;
    }

    return $self->app->($env) unless $res->[0] == 200;

    Plack::Util::response_cb( $res, sub {
        my $res = shift;
        my $buffer;
        Plack::Util::header_set( $res->[1], 'Content-Type',
            $ext eq 'jpg' ? 'image/jpeg' :
            $ext eq 'png' ? 'image/png'  : undef
        );
        return sub {
            my $chunk = shift;
            if ( defined $chunk ) {
                $buffer .= $chunk;
                return q{};
            } elsif ( defined $buffer ) {
                try {
                    my $img = Image::Scale->new(\$buffer);
                    $img->resize({
                        width => $width,
                        height => $height,
                        keep_aspect => 1,
                    });
                    my $scaled =
                        $ext eq 'jpg' ? $img->as_jpeg :
                        $ext eq 'png' ? $img->as_png  : undef;
                    undef $buffer;
                    return $scaled;
                } catch {
                    return;
                };
            } else {
                return;
            }
        };
    });
}

1;
