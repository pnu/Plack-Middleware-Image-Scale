use strict;
use warnings;
use Plack::Builder;
use Config::General;

my $app = sub { return [200,[],[]] };

my %imagesize = Config::General->new('imagesize.conf')->getall;

my $imagesize = {
    small   => [ 40,100],
    medium  => [140,200],
    big     => [240,300],
};

builder {
    enable 'ConditionalGET';
    enable 'Image::Scale', size => $imagesize;
    enable 'Static', path => qr{^/images/};
    $app;
};

