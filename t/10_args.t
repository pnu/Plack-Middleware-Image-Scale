use strict;
use warnings;
use lib 't/lib';
use Test::Invocation::Arguments;
use Test::More;
use Plack::Middleware::Static;
use Plack::Builder;
use Plack::Util;
use HTTP::Request::Common;
use HTTP::Response;
use Plack::Test;
use Image::Scale;
use Imager;
use Data::Dumper;

my $handler = builder {
    enable 'Image::Scale', memory_limit => undef;
    enable 'Static', path => qr{^/images/}, root => 't';
    sub { [
        404,
        [ 'Content-Type' => 'text/plain', 'Content-Length' => 8 ],
        [ 'not found' ]
    ] };
};

test_psgi $handler, sub {
    my $cb = shift;

    subtest 'Basic size arguments' => sub {

        my @sizetests = (
            [ '100x100_x.png', [{ width => 100, height => 100 }], undef ],
            [ '100x100_200x.png', [{ width => 200 }], undef ],
        );

        for my $row ( @sizetests ) {
            my ($filename, $resize, $crop) = @$row;
            subtest $filename => sub {
                my $resize_calls = Test::Invocation::Arguments->new(class => 'Image::Scale', method => 'resize');
                my $crop_calls = Test::Invocation::Arguments->new(class => 'Imager', method => 'crop');
                
                my $res = $cb->(GET "http://localhost/images/$filename");
                
                is $res->code, 200, 'Response HTTP status';
                is_deeply $resize_calls->pop, $resize, 'resize args';
                is_deeply $crop_calls->pop, $crop, 'crop args';
            };
        }

    };
};

done_testing;

