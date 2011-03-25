package Plack::Middleware::Image::Scale;
use Moose;
use Plack::Util;
use Plack::MIME;
use Try::Tiny;
use Image::Scale;

extends 'Plack::Middleware';

has match_path => (
    is => 'rw', lazy => 1, isa => 'RegexpRef',
    default => sub { qr{^(.*)/(.+)_(.+)\.(jpg|jpeg|png)$} }
);

has match_spec => (
    is => 'rw', lazy => 1, isa => 'RegexpRef',
    default => sub { qr{^(\d*)x(\d*)(?:-(\w+))?$} }
);

has orig_ext => (
    is => 'rw', lazy => 1, isa => 'ArrayRef',
    default => sub { [qw( jpg png gif )] }
);

has memory_limit => (
    is => 'rw', lazy => 1, isa => 'Int',
    default => 10_000_000 # bytes
);

sub call {
    my ($self,$env) = @_;

    ## Check that uri matches and extract the pieces, or pass thru
    return $self->app->($env) unless
        my ($path,$basename,$prop,$ext) =
        $env->{PATH_INFO} =~ $self->match_path;

    ## Extract image size and options (flag)
    return $self->app->($env) unless
        my ($width,$height,$flag) =
        $prop =~ $self->match_spec;

    my $res = $self->fetch_orig($env,$path,$basename);
    return $self->app->($env) unless
        $res->[0] == 200;

    ## Post-process the response with a body filter
    Plack::Util::response_cb( $res, sub {
        my $res = shift;
        my $ct = Plack::MIME->mime_type(".$ext");
        Plack::Util::header_set( $res->[1], 'Content-Type', $ct );
        return $self->body_scaler( $width, $height, $flag, $ct );
    });
}

sub fetch_orig {
    my ($self,$env,$path,$basename) = @_;

    my $res;
    for my $ext ( @{$self->orig_ext} ) {
        local $env->{PATH_INFO} = "$path/$basename.$ext";
        $res = $self->app->($env);
        last if $res->[0] == 200;
    }

    return $res; 
}

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

sub image_scale {
    my ($self, $bufref, $width, $height, $flag, $ct) = @_;

    $width  = 0  unless $width;
    $height = 0  unless $height;
    $flag   = '' unless $flag;

    my $output;
    try {
        my $img = Image::Scale->new($bufref);

        ## TODO: skip if only converting format..
        ## Looks like Image::Scale doesn't return data unless we call scale.
        $img->resize({
            $width  > 0     ? (width  => $width)  : (),
            $height > 0     ? (height => $height) : (),
            $flag eq 'fill' ? (keep_aspect => 1)  : (),
            memory_limit => $self->memory_limit,
        });

        $output = $ct eq 'image/jpeg' ? $img->as_jpeg :
                  $ct eq 'image/png'  ? $img->as_png  :
                  undef;
    };

    return $output;
}

1;
