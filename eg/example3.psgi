use strict;
use warnings;
use Plack::Builder;
use Config::General;

my $app = sub { return [200,[],[]] };

my %imagesize = Config::General->new('imagesize.conf')->getall;

builder {
    enable 'ConditionalGET';
    enable 'Image::Scale', path => sub {
        s{^(.+)_(.+)\.(jpg|png)$}{$1.$3} || return;
        ( my %entry = %{$imagesize{$2} || {}} ) || return;
        return delete @entry{'width','height'}, \%entry;
    };
    enable 'Static', path => qr{^/images/};
    $app;
};

