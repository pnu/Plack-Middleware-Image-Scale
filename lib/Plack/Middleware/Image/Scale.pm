package Plack::Middleware::Image::Scale;
use Moose;
use Class::MOP;
use Plack::Util;
use Plack::MIME;
use Try::Tiny;
use Image::Scale;
use List::Util qw( max );
use Carp;

extends 'Plack::Middleware';

has match_path => (
    is => 'rw', lazy => 1, isa => 'RegexpRef',
    default => sub { qr<^(.*)/(.+)_(.+)\.(jpg|jpeg|png)$> }
);

has match_spec => (
    is => 'rw', lazy => 1, isa => 'RegexpRef',
    default => sub { qr<^(\d+)?x(\d+)?(?:-(.+))?$> }
);

has orig_ext => (
    is => 'rw', lazy => 1, isa => 'ArrayRef',
    default => sub { [qw( jpg png gif )] }
);

has memory_limit => (
    is => 'rw', lazy => 1, isa => 'Int',
    default => 10_000_000 # bytes
);

has quality => (
    is => 'rw', lazy => 1, isa => 'Maybe[Int]',
    default => undef
);

sub call {
    my ($self,$env) = @_;

    ## Check that uri matches and extract the pieces, or pass thru
    return $self->app->($env) unless
        my ($path,$basename,$prop,$ext) =
        $env->{PATH_INFO} =~ $self->match_path;

    ## Extract image size and flags
    return $self->app->($env) unless
        my ($width,$height,$flags) =
        $prop =~ $self->match_spec;

    my $res = $self->fetch_orig($env,$path,$basename);
    return $self->app->($env) unless $res->[0] == 200;

    ## Post-process the response with a body filter
    Plack::Util::response_cb( $res, sub {
        my $res = shift;
        my $ct = Plack::MIME->mime_type(".$ext");
        Plack::Util::header_set( $res->[1], 'Content-Type', $ct );
        return $self->body_scaler( $ct, $width, $height, $flags );
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

        if ( exists $flag{crop} ) {
            my $ratio = $img->width / $img->height;
            $width  = max $width  || 0, $height * $ratio;
            $height = max $height || 0, $width / $ratio;
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

        $output = $ct eq 'image/jpeg' ? $img->as_jpeg($self->quality || ()) :
                  $ct eq 'image/png'  ? $img->as_png  :
                  undef;
    } catch {
        # ...
        carp $_;
        $output = $$bufref;
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
            # ...
            carp $_;
        };
    }

    return $output;
}

1;
