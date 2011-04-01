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

Only matching URIs are processed with this module. The match is done against
L<PATH_INFO|PSGI/The_Environment>.
Non-matching requests are delegated to the next middleware layer or
application. The value must be a
L<RegexpRef|Moose::Util::TypeConstraints/Default_Type_Constraints>,
that returns 3 captures. Default value is:

    qr<^(.+)_(.+)\.(png|jpg|jpeg)$>

First capture is the path and basename of the requested image.
The original image will be fetched by L</fetch_orig> with this argument.
See L</call>.

Second capture is the size specification for the requested image.
See L</match_spec>.

Third capture is the extension for the desired output format. This extension
is mapped with L<Plack::MIME> to the Content-Type to be used in the HTTP
response. The content type defined the output format used in image processing.
Currently only jpeg and png format are supported.
See L</call>.

=cut

has match_path => (
    is => 'rw', lazy => 1, isa => 'RegexpRef',
    default => sub { qr<^(.+)_(.+)\.(png|jpg|jpeg)$> }
);

=attr match_spec

The size specification captured by L</match_path> is matched against this.
Only matching URIs are processed with this module. The value must be a
L<RegexpRef|Moose::Util::TypeConstraints/Default_Type_Constraints>.
Default values is:

    qr<^(\d+)?x(\d+)?(?:-(.+))?$>

First and second captures are the desired width and height of the
resulting image. Both are optional, but note that the "x" between is required.

Third capture is an optional flag. This value is parsed in the
L</image_scale> method during the conversion.

=cut

has match_spec => (
    is => 'rw', lazy => 1, isa => 'RegexpRef',
    default => sub { qr<^(\d+)?x(\d+)?(?:-(.+))?$> }
);

=attr orig_ext

L<ArrayRef|Moose::Util::TypeConstraints/Default_Type_Constraints>
of possible original image formats. See L</fetch_orig>.

=cut

has orig_ext => (
    is => 'rw', lazy => 1, isa => 'ArrayRef',
    default => sub { [qw( jpg png gif )] }
);

=attr memory_limit

Memory limit for the image scaling in bytes, as defined in
L<Image::Scale|Image::Scale/resize(_\%OPTIONS_)>.

=cut

has memory_limit => (
    is => 'rw', lazy => 1, isa => 'Int',
    default => 10_000_000 # bytes
);

=attr jpeg_quality

JPEG quality, as defined in
L<Image::Scale|Image::Scale/as_jpeg(_[_$QUALITY_]_)>.

=cut

has jpeg_quality => (
    is => 'rw', lazy => 1, isa => 'Maybe[Int]',
    default => undef
);

=method call

Process the request. The original image is fetched from the backend if 
L</match_path> and L</match_spec> match as specified. Normally you should
use L<Plack::Middleware::Static> or similar backend, that
returns a filehandle or otherwise delayed body. Content-Type of the response
is set according the request.

The body of the response is replaced with a
L<streaming body|PSGI/Delayed_Reponse_and_Streaming_Body>
that implements a content filter to do the actual resizing for the original
body. This means that if response body gets discarded due to header validation
(If-Modified-Since or If-None-Match for example), the body never needs to be
processed.

However, if the original image has been modified, for example the modification
date has been changed, the streaming body gets passed to the HTTP server
(or another middleware layer that needs to read it in), and the conversion
happens.

=cut

sub call {
    my ($self,$env) = @_;

    ## Check that uri matches and extract the pieces, or pass thru
    my @match_path = $env->{PATH_INFO} =~ $self->match_path;
    return $self->app->($env) unless @match_path;

    ## Extract image size and flags
    my ($basename,$prop,$ext) = @match_path;
    my @match_spec = $prop =~ $self->match_spec;
    return $self->app->($env) unless @match_spec;

    my $res = $self->fetch_orig($env,$basename);
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

The original image is fetched from the next layer or application.
The basename of the request URI, as matched by L</match_path>, and all
possible extensions defined in L</orig_ext> are used in order, to search
for the original image. All other responses except a straight 404 (as
returned by L<Plack::Middleware::Static> for example) are considered
matches.

=cut

sub fetch_orig {
    my ($self,$env,$basename) = @_;

    for my $ext ( @{$self->orig_ext} ) {
        local $env->{PATH_INFO} = "$basename.$ext";
        my $r = $self->app->($env);
        return $r unless ref $r eq 'ARRAY' and $r->[0] == 404;
    }
    return;
}

=method body_scaler

Create a content filter callback to do the conversion with specified arguments.
The callback binds to a closure with a buffer and the image_scale arguments.
The callback will buffer the response and call L</image_scale> after an EOF.

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

Do the actual scaling and cropping of the image.
Arguments are width, height and flags, as parsed in L</call>.

See L</DESCRIPTION> for description of various sizes and flags.

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

    # app.psgi
    
    builder {
        enable 'ConditionalGET';
        enable 'Image::Scale';
        enable 'Static', path => qr{^/images/};
        $app;
    };

=head1 DESCRIPTION

Suppose that you have images/foo.jpg in your filesystem. With above setup you
can make request to /images/foo_40x40.png, to receive it as scaled to 40x40 and
converted to png format. Scaling is done with L<Image::Scale> module.

The converted and/or scaled version is not stored. This middleware implements
a PSGI L<content filter|Plack::Middleware/RESPONSE_CALLBACK> to do the
processing.  The response headers (like Last-Modified or ETag) will be from
the original image, but the image processing happens only if the body is
actually used.

This middleware doesn't access the filesystem at all. The original image is
fetched from next middleware layer or application. The image requests should
return a filehandle body for optimal results. You can use
L<Plack::Middleware::Static>, or C<Catalyst::Plugin::Static::Simple> for
example.

This means that the response can be validated (with If-Modified-Since or
If-None-Match) against original image, without doing the expensive image
processing, or even reading the file content at all. This module should be
used with a proxy cache that implements validation.

See below for various size/format specifications that can be used
in the request URI. See L</ATTRIBUTES> for common configuration options
that you can give as named parameters to the C<enable>.

With default configuration, the format of the URI is
I<basename>_I<width>xI<height>-I<flags>.I<ext>

Only I<basename>, C<x> and I<ext> are required. If URI doesn't match, the
request is passed through. Any number of flags can be specified, separated
with C<->.  Flags can be boolean (exists or doesn't exist), or have a
numerical value. Flag name and value are separated with a zero-width word to
number boundary. For example C<z20> specifies flag C<z> with value C<20>.

=head2 basename

Original image is requested from URI I<basename>.I<orig_ext>, where
I<orig_ext> is list of filename extensions. See L</orig_ext>.

=head2 width

Width of the output image. If not defined, it can be anything
(to preserve the image aspect ratio).

=head2 height

Height of the output image. If not defined, it can be anything
(to preserve the image aspect ratio).

=head2 flags: fill

Image aspect ratio is preserved by scaling the image to fit within the
specified size. This means scaling to the smaller or the two possible sizes
that preserve aspect ratio.  Extra borders of background color are added to
fill the requested image size exactly.

    /images/foo_400x200-fill.png

If fill has a value, it specifies the background color to use. Undefined color
with png output means transparent background.
    
    /images/foo_40x20-fill0xff0000.png  ## red background

=head2 flags: crop

Image aspect ratio is preserved by scaling and cropping from middle of the
image. This means scaling to the bigger of the two possible sizes that
preserve the aspect ratio, and then cropping to the exact size.

=head2 flags: z

Zoom the specified width or height N percent bigger. For example C<z20> to
zoom 20%. The zooming applies only to width and/or height defined in the URI,
and does not change the crop size. Image is always cropped to the specified
pixel width, height or both.
    
    /images/foo_40x-crop-z20.png

=head1 CAVEATS

The cropping requires L<Imager>. This is a run-time dependency, and
fallback is not to crop the image to the desired size.

=head1 SEE ALSO

L<Image::Scale>

L<Imager>

L<Plack::App::ImageMagick>

=cut
