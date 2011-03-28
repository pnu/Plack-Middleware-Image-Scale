use strict;
package Plack::Middleware::Image::Scale;
# ABSTRACT: Resize jpeg and png images on the fly

use Moose;
use Class::MOP;
use Plack::Util;
use Plack::MIME;
use Try::Tiny;
use Image::Scale;
use List::Util qw( max );
use Carp;

extends 'Plack::Middleware';

=attr match_path
=cut
has match_path => (
    is => 'rw', lazy => 1, isa => 'RegexpRef',
    default => sub { qr<^(.*)/(.+)_(.+)\.(png|jpg|jpeg)$> }
);

=attr match_spec
=cut
has match_spec => (
    is => 'rw', lazy => 1, isa => 'RegexpRef',
    default => sub { qr<^(\d+)?x(\d+)?(?:-(.+))?$> }
);

=attr orig_ext
=cut
has orig_ext => (
    is => 'rw', lazy => 1, isa => 'ArrayRef',
    default => sub { [qw( jpg png gif )] }
);

=attr memory_limit
=cut
has memory_limit => (
    is => 'rw', lazy => 1, isa => 'Int',
    default => 10_000_000 # bytes
);

=attr jpeg_quality
=cut
has jpeg_quality => (
    is => 'rw', lazy => 1, isa => 'Maybe[Int]',
    default => undef
);

=method call
=cut
sub call {
    my ($self,$env) = @_;

    ## Check that uri matches and extract the pieces, or pass thru
    my @match_path = $env->{PATH_INFO} =~ $self->match_path;
    return $self->app->($env) unless @match_path;

    ## Extract image size and flags
    my ($path,$basename,$prop,$ext) = @match_path;
    my @match_spec = $prop =~ $self->match_spec;
    return $self->app->($env) unless @match_spec;

    my $res = $self->fetch_orig($env,$path,$basename);
    return $self->app->($env) unless $res;

    ## Post-process the response with a body filter
    Plack::Util::response_cb( $res, sub {
        my $res = shift;
        my $ct = Plack::MIME->mime_type(".$ext");
        Plack::Util::header_set( $res->[1], 'Content-Type', $ct );
        return $self->body_scaler( $ct, @match_spec );
    });
}

=method fetch_orig
=cut
sub fetch_orig {
    my ($self,$env,$path,$basename) = @_;

    for my $ext ( @{$self->orig_ext} ) {
        local $env->{PATH_INFO} = "$path/$basename.$ext";
        my $r = $self->app->($env);
        return $r unless ref $r eq 'ARRAY' and $r->[0] == 404;
    }
    return;
}

=method body_scaler
=cut
sub body_scaler {
    my $self = shift;
    my @args = @_;

    my $buffer = q{};
    my $filter_cb = sub {
        my $chunk = shift;

        ## Buffer until we get EOF
        if ( defined $chunk ) {
            $buffer .= $chunk;
            return q{}; #empty
        }

        ## Return EOF when done
        return if not defined $buffer;

        ## Process the buffer
        my $img = $self->image_scale(\$buffer,@args);
        undef $buffer;
        return $img;
    };

    return $filter_cb;
}

=method image_scale
=cut
sub image_scale {
    my ($self, $bufref, $ct, $width, $height, $flags) = @_;
    my %flag = map { (split /(?<=\w)(?=\d)/, $_, 2)[0,1]; } split '-', $flags || '';
    my $owidth  = $width;
    my $oheight = $height;

    if ( defined $flag{z} and $flag{z} > 0 ) {
        $width  *= 1 + $flag{z} / 100 if $width;
        $height *= 1 + $flag{z} / 100 if $height;
    }

    my $output;
    try {
        my $img = Image::Scale->new($bufref);

        if ( exists $flag{crop} and defined $width and defined $height ) {
            my $ratio = $img->width / $img->height;
            $width  = max $width , $height * $ratio;
            $height = max $height, $width / $ratio;
        }

        unless ( defined $width or defined $height ) {
            ## We want to keep the size, but Image::Scale
            ## doesn't return data unless we call resize.
            $width = $img->width; $height = $img->height;
        }
        $img->resize({
            defined $width  ? (width  => $width)  : (),
            defined $height ? (height => $height) : (),
            exists  $flag{fill} ? (keep_aspect => 1) : (),
            defined $flag{fill} ? (bgcolor => hex $flag{fill}) : (),
            memory_limit => $self->memory_limit,
        });

        $output = $ct eq 'image/jpeg' ? $img->as_jpeg($self->jpeg_quality || ()) :
                  $ct eq 'image/png'  ? $img->as_png :
                  die "Conversion to $ct is not implemented";
    } catch {
        carp $_;
        return;
    };

    if ( defined $owidth  and $width  > $owidth or
         defined $oheight and $height > $oheight ) {
        try {
            Class::MOP::load_class('Imager');
            my $img = Imager->new;
            $img->read( data => $output ) || die;
            my $crop = $img->crop(
                defined $owidth  ? (width  => $owidth)  : (),
                defined $oheight ? (height => $oheight) : (),
            );
            $crop->write( data => \$output, type => (split '/', $ct)[1] );
        } catch {
            carp $_;
            return;
        };
    }

    return $output;
}

1;

=head1 SYNOPSIS

    builder {
        enable 'ConditionalGET';
        enable 'Image::Scale';
        enable 'Static', path => qr{^/images/};
        $app;
    };

=head1 DESCRIPTION

This is a trial release. The interface may change.

The conversion is done on the fly, but happens only if the
response body is actually read. This means that the normal
validation checks (if-modified-since) can be done before
expensive conversion actually happens, for example by activating
ConditionalGET middleware.

This module should be use in conjunction with a cache that stores
and revalidates the entries.

=cut

=head1 SEE ALSO

Image::Scale

=cut
