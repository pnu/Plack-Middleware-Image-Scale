use strict;
use warnings;
use Test::More;
use Plack::Middleware::Static;
use Plack::Builder;
use Plack::Util;
use HTTP::Request::Common;
use HTTP::Response;
use Plack::Test;
use Imager;

my $handler = builder {
    enable 'Image::Scale', jpeg_quality => 50;
    enable 'Static', path => qr{^/images/}, root => 't';
    sub { [
        404,
        [ 'Content-Type' => 'text/plain', 'Content-Length' => 8 ],
        [ 'not found' ]
    ] };
};

test_psgi $handler, sub {
    my $cb = shift;

    subtest 'Fall-thru the middleware layers' => sub {
        
        my $res = $cb->(GET "http://localhost/");
        is $res->code, 404, 'Response HTTP status';
        is $res->content_type, 'text/plain', 'Response Content-Type';
        is $res->content, 'not found', 'Response body';
    
    };

    subtest 'The Static middleware layer' => sub {

        subtest 'Existing image' => sub {
            my $res = $cb->(GET "http://localhost/images/100x100.png");
            is $res->code, 200, 'Response HTTP status';
            is $res->content_type, 'image/png', 'Response Content-Type';
        };

        subtest 'Non-existing image' => sub {
            my $res = $cb->(GET "http://localhost/images/nonexisting.png");
            is $res->code, 404, 'Response HTTP status';
        };
        
    };

    subtest 'Invalid cases' => sub {
        
        my @invalid = (
           '100x100_x.zip',   # invalid extension
           '100x100_x.',      # missing extension
           '100x100_x',
           '100x100_poo.png', # invalid spec
           '100x100_.png',    # missing spec
           '_x.png',          # missing basename
           '.png',            # missing basename and spec
        );

        for my $filename ( @invalid ) {
            my $res = $cb->(GET "http://localhost/images/$filename");
            is $res->code, 404, "$filename gives 404";
        }

    };
    
    subtest 'Basic size tests' => sub {
        
        my @sizetests = (
            [ '100x100_x.png',                 200, 100, 100 ],
            [ '100x100_200x.png',              200, 200, 200 ],
            [ '100x100_50x.png',               200,  50,  50 ],
            [ '100x100_x200.png',              200, 200, 200 ],
            [ '100x100_x50.png',               200,  50,  50 ],
            
            [ '100x100_x-z20.png',             200, 100, 100 ],
            [ '100x100_200x-z20.png',          200, 200, 240 ],
            [ '100x100_50x-z20.png',           200,  50,  60 ],
            [ '100x100_x200-z20.png',          200, 240, 200 ],
            [ '100x100_x50-z20.png',           200,  60,  50 ],
            
            [ '100x100_x-crop.png',            200, 100, 100 ],
            [ '100x100_200x-crop.png',         200, 200, 200 ],
            [ '100x100_50x-crop.png',          200,  50,  50 ],
            [ '100x100_x200-crop.png',         200, 200, 200 ],
            [ '100x100_x50-crop.png',          200,  50,  50 ],
            
            [ '100x100_200x100.png',           200, 200, 100 ],
            [ '100x100_200x100-fill.png',      200, 200, 100 ],
            [ '100x100_200x100-crop.png',      200, 200, 100 ],
            [ '100x100_200x100-crop-fill.png', 200, 200, 100 ],
            [ '100x100_200x100-crop-z0.png',   200, 200, 100 ],
            [ '100x100_200x100-crop-z20.png',  200, 200, 100 ],
            [ '100x100_200x100-crop-z100.png', 200, 200, 100 ],
            
            [ '100x100_200x100-fill0x00ff00.png', 200, 200, 100 ],
        );

        for my $row ( @sizetests ) {
            my ($filename, $status, $width, $height) = @$row;
            subtest $filename => sub {
                my $res = $cb->(GET "http://localhost/images/$filename");
                my $img = Imager->new( data => $res->content );
                is $res->code, $status, 'Response HTTP status';
                is $img->getwidth, $width, 'Response image width';
                is $img->getheight, $height, 'Response image height';
            };
        }
    
    };

    subtest 'Formats' => sub {
        
        my @formats = (
            [ 'jpg to png',  '75x75_x.png',  'image/png' ],
            [ 'jpg to jpg',  '75x75_x.jpg',  'image/jpeg' ],
            [ 'jpg to jpeg', '75x75_x.jpeg', 'image/jpeg' ],
            
            [ 'png to png',  '100x100_x.png',  'image/png' ],
            [ 'png to jpg',  '100x100_x.jpg',  'image/jpeg' ],
            [ 'png to jpeg', '100x100_x.jpeg', 'image/jpeg' ],
        );

        for my $row ( @formats ) {
            my ($name, $filename, $ct) = @$row;
            subtest $name => sub {
                my $res = $cb->(GET "http://localhost/images/$filename");
                is $res->code, 200, 'Response HTTP status';
                is $res->content_type, $ct, 'Response Content-Type';
            };
        }
    
    };
};

done_testing;

