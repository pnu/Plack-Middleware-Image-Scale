# NAME

Plack::Middleware::Image::Scale - Resize jpeg and png images on the fly

# VERSION

version 0.011

# SYNOPSIS

    ## example1.psgi
    use Plack::Builder;
    use Plack::Middleware::Image::Scale;
    my $app = sub { return [200,[],[]] };

    builder {
        enable 'ConditionalGET';
        enable 'Image::Scale';
        enable 'Static', path => qr{^/images/};
        $app;
    };

A request to /images/foo\_40x40.png will use images/foo.(png|jpg|gif|jpeg) as
original, scale it to 40x40 px size and convert to PNG format.

    ## example2.psgi
    use Plack::Builder;
    use Plack::App::File;
    use Plack::Middleware::Image::Scale;
    my $app = sub { return [200,['Content-Type'=>'text/plain'],['hello']] };

    my $thumber = builder {
        enable 'ConditionalGET';
        enable 'Image::Scale',
            width => 200, height => 100,
            flags => { fill => 'ff00ff' };
        Plack::App::File->new( root => 'images' );
    };

    builder {
        mount '/thumbs' => $thumber;
        mount '/' => $app;
    };

A request to /thumbs/foo.png will use images/foo.(png|jpg|gif|jpeg) as original,
scale it small enough to fit 200x100 px size, fill extra borders (top/down or
left/right, depending on the original image aspect ratio) with cyan
background, and convert to PNG format. Also clipping is available, see
["CONFIGURATION"](#configuration).

# DESCRIPTION

Scale and convert images to the requested format on the fly. By default the
size and other scaling parameters are extracted from the request URI.  Scaling
is done with [Image::Scale](https://metacpan.org/pod/Image::Scale).

The original image is not modified or even accessed directly by this module.
The converted image is not cached, but the request can be validated
(If-Modified-Since) against original image without doing the image processing.
This middleware should be used together a cache proxy, that caches the
converted images for all clients, and implements content validation.

The response headers (like Last-Modified or ETag) are from the original image,
but body is replaced with a PSGI [content
filter](https://metacpan.org/pod/Plack::Middleware#RESPONSE_CALLBACK) to do the image processing.  The
original image is fetched from next middleware layer or application with a
normal PSGI request. You can use [Plack::Middleware::Static](https://metacpan.org/pod/Plack::Middleware::Static), or
[Catalyst::Plugin::Static::Simple](https://metacpan.org/pod/Catalyst::Plugin::Static::Simple) for example.

See ["CONFIGURATION"](#configuration) for various size/format specifications that can be used
in the request URI, and ["ATTRIBUTES"](#attributes) for common configuration options
that you can use when constructing the middleware.

# ATTRIBUTES

## path

Must be a [RegexpRef](https://metacpan.org/pod/Moose::Util::TypeConstraints#Default_Type_Constraints),
[CodeRef](https://metacpan.org/pod/Moose::Util::TypeConstraints#Default_Type_Constraints),
[Str](https://metacpan.org/pod/Moose::Util::TypeConstraints#Default_Type_Constraints) or
[Undef](https://metacpan.org/pod/Moose::Util::TypeConstraints#Default_Type_Constraints).

The [PATH\_INFO](https://metacpan.org/pod/PSGI#The_Environment) is compared against this value to
evaluate if the request should be processed. Undef (the default) will match
always.  `PATH_INFO` is topicalized by settings it to `$_`, and it may be
rewritten during `CodeRef` matching. Rewriting can be used to relocate image
paths, much like `path` parameter for [Plack::Middleware::Static](https://metacpan.org/pod/Plack::Middleware::Static).

If path matches, next it will be compared against ["name"](#name). If path doesn't
match, the request will be delegated to the next middleware layer or
application.

## match

Must be a [RegexpRef](https://metacpan.org/pod/Moose::Util::TypeConstraints#Default_Type_Constraints),
or [CodeRef](https://metacpan.org/pod/Moose::Util::TypeConstraints#Default_Type_Constraints).

The [PATH\_INFO](https://metacpan.org/pod/PSGI#The_Environment), possibly rewritten during ["path"](#path)
matching, is compared against this value to extract `name`, `size`
and `ext`. The default value is:

    qr{^(.+)(?:_(.+?))?(?:\.(jpe?g|png|image))$}

The expression is evaluated in array context and may return three elements:
`name`, `size` and `ext`. Returning an empty array means no match.
Non-matching requests are delegated to the next middleware layer or
application.

If the path matches, the original image is fetched from `name`.["orig\_ext"](#orig_ext),
scaled with parameters extracted from `size` and converted to the content type
defined by `ext`. See also ["any\_ext"](#any_ext).

## size

Must be a [RegexpRef](https://metacpan.org/pod/Moose::Util::TypeConstraints#Default_Type_Constraints),
[CodeRef](https://metacpan.org/pod/Moose::Util::TypeConstraints#Default_Type_Constraints),
[HashRef](https://metacpan.org/pod/Moose::Util::TypeConstraints#Default_Type_Constraints),
[Undef](https://metacpan.org/pod/Moose::Util::TypeConstraints#Default_Type_Constraints).

The `size` extracted by ["match"](#match) is compared against this value to evaluate
if the request should be processed, and to map it into width, height and flags
for image processing. Undef will match always and use default width, height
and flags as defined by the ["ATTRIBUTES"](#attributes). The default value is:

    qr{^(\d+)?x(\d+)?(?:-(.+))?$}

The expression is evaluated in array context and may return three elements;
`width`, `height` and `flags`. Returning an empty array means no match.
Non-matching requests are delegated to the next middleware layer or
application.

Optionally a hash reference can be returned. Keys `width`, `height`, and any
remaining keys as an hash reference, will be unrolled from the hash reference.

## any\_ext

If defined and request `ext` is equal to this, the content type of the original
image is used in the output. This means that the image format of the original
image is preserved. Default is `image`.

## orig\_ext

[ArrayRef](https://metacpan.org/pod/Moose::Util::TypeConstraints#Default_Type_Constraints)
of possible original image formats. See ["fetch\_orig"](#fetch_orig).

## memory\_limit

Memory limit for the image scaling in bytes, as defined in
[Image::Scale](https://metacpan.org/pod/Image::Scale#resize-_-OPTIONS_).

## jpeg\_quality

JPEG quality, as defined in
[Image::Scale](https://metacpan.org/pod/Image::Scale#as_jpeg-_-_-QUALITY_-_).

## width

Use this to set and override image width.

## height

Use this to set and override image height.

## flags

Use this to set and override image processing flags.

# METHODS

## fetch\_orig

Call parameters: PSGI request HashRef $env, Str $basename.
Return value: PSGI response ArrayRef $res.

The original image is fetched from the next layer or application.  All
possible extensions defined in ["orig\_ext"](#orig_ext) are tried in order, to search for
the original image. All other responses except a straight 404 (as returned by
[Plack::Middleware::Static](https://metacpan.org/pod/Plack::Middleware::Static) for example) are considered matches.

## body\_scaler

Call parameters: @args. Return value: PSGI content filter CodeRef $cb.

Create the content filter callback and return a CodeRef to it. The filter will
buffer the data and call ["image\_scale"](#image_scale) with parameters `@args` when EOF is
received, and finally return the converted data.

## image\_scale

Call parameters: ScalarRef $buffer, String $ct, Int $width, Int $height, HashRef|Str $flags.
Return value: $imagedata

Read image from $buffer, scale it to $width x $height and
return as content-type $ct. Optional $flags to specify image processing
options like background fills or cropping.

# CONFIGURATION

The default match pattern for URI is
"_..._\__width_x_height_-_flags_._ext_".

If URI doesn't match, the request is passed through. Any number of flags can
be specified, separated with `-`.  Flags can be boolean (exists or doesn't
exist), or have a numerical value. Flag name and value are separated with a
zero-width word to number boundary. For example `z20` specifies flag `z`
with value `20`.

## width

Width of the output image. If not defined, it can be anything
(to preserve the image aspect ratio).

## height

Height of the output image. If not defined, it can be anything
(to preserve the image aspect ratio).

## flags: fill

Image aspect ratio is preserved by scaling the image to fit within the
specified size. This means scaling to the smaller or the two possible sizes
that preserve aspect ratio.  Extra borders of background color are added to
fill the requested image size exactly.

    /images/foo_400x200-fill.png

If fill has a value, it specifies the background color to use. Undefined color
with png output means transparent background.

## flags: crop

Image aspect ratio is preserved by scaling and cropping from middle of the
image. This means scaling to the bigger of the two possible sizes that
preserve the aspect ratio, and then cropping to the exact size.

## flags: fit

Image aspect ratio is preserved by scaling the image to the smaller of the two
possible sizes. This means that the resulting picture may have one dimension
smaller than specified, but cropping or filling is avoided.

See documentation in distribution directory `doc` for a visual explanation.

## flags: z

Zoom the original image N percent bigger. For example `z20` to zoom 20%.
Zooming applies only to explicitly defined width and/or height, and it does
not change the crop size.

    /images/foo_40x-z20.png

# EXAMPLES

    ## see example4.psgi

    my %imagesize = Config::General->new('imagesize.conf')->getall;

    # ...

    enable 'Image::Scale', size => \%imagesize;

A request to /images/foo\_medium.png will use images/foo.(png|jpg|gif|jpeg) as
original. The size and flags are taken from the configuration file as
parsed by Config::General.

    ## imagesize.conf

    <medium>
        width   200
        height  100
        crop
    </medium>
    <big>
        width   300
        height  100
        crop
    </big>
    <thumbred>
        width   50
        height  100
        fill    ff0000
    </thumbred>

For more examples, browse into directory
[eg](http://cpansearch.perl.org/src/PNU/) inside the distribution
directory for this version.

# CAVEATS

The cropping requires [Imager](https://metacpan.org/pod/Imager). This is a run-time dependency, and
fallback is not to crop the image to the expected size.

# SEE ALSO

[Image::Scale](https://metacpan.org/pod/Image::Scale)

[Imager](https://metacpan.org/pod/Imager)

[Plack::App::ImageMagick](https://metacpan.org/pod/Plack::App::ImageMagick)

# AUTHOR

Panu Ervamaa &lt;pnu@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2011-2016 by Panu Ervamaa.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
