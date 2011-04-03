use strict;
use warnings;
use Plack::Builder;

my $app = sub { return [200,[],[]] };

my $imgsizes = {
    thumbred => [ 50, 100, { fill => 'ff0000' } ],
    medium   => [ 200, 100, 'crop' ],
    big      => [ 300, 100, 'crop' ],
};

builder {
    enable 'ConditionalGET';
    enable 'Image::Scale', path => sub {
        s{^(.+)_(.+)\.(jpg|png)$}{$1.$3} || return;
        return @{ $imgsizes->{$2} || [] };
    };
    enable 'Static', path => qr{^/images/};
    $app;
};

