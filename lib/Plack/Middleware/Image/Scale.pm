package Plack::Middleware::Image::Scale;
use Moose;
use Plack::Util;
use Try::Tiny;
use Image::Scale;

extends 'Plack::Middleware';

has path => (
    is => 'rw', lazy => 1,
    isa => 'RegexpRef',
    default => sub { qr{^(.*)/(.+)_(.+)\.(jpg|png)$} }
);

has prop => (
    is => 'rw', lazy => 1,
    isa => 'RegexpRef',
    default => sub { qr{^(\d+)x(\d+)(?:-(\w+))?$} }
);

has oext => (
    is => 'rw', lazy => 1,
    isa => 'ArrayRef',
    default => sub { [qw( jpg png gif )] }
);

sub original {
    my ($self,$env,$path,$basename) = @_;

    my $res;
    for my $oext ( @{$self->oext} ) {
        local $env->{PATH_INFO} = "$path/$basename.$oext";
        $res = $self->app->($env);
        last if $res->[0] == 200;
    }

    return $res; 
}

sub call {
    my ($self,$env) = @_;

    return $self->app->($env) unless
        my ($path,$basename,$prop,$ext) =
        $env->{PATH_INFO} =~ $self->path;

    return $self->app->($env) unless
        my ($width,$height,$flag) =
        $prop =~ $self->prop;

    my $res = $self->original($env,$path,$basename);

    return $self->app->($env) unless
        $res->[0] == 200;

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
