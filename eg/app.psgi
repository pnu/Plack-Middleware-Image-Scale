use strict;
use warnings;
use Plack::Builder;

my $app = sub { return [200,[],[]] };

builder {
    # enable 'Cache';
    enable 'ConditionalGET';
    enable 'Image::Scale';
    enable 'ETag';
    enable 'Static', path => qr{^/images/}, root => '../t';
    $app;
};

