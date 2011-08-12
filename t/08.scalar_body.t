use strict;
use warnings;
use Test::Base;
use Test::XmlServer;

my $application = sub{
    my($env) = @_;
    my $input = $env->{'psgi.input'};
    my $req_length = $env->{'CONTENT_LENGTH'} || 0;
    my $req_type = $env->{'CONTENT_TYPE'} || q{};
    my $body = q{};
    if ($req_length > 0) {
        read $input, $body, $req_length;
    }
    use bytes;
    my $res_length = bytes::length($body);
    return [
        200,
        [
            'Content-Type' => 'text/plain; charset=utf-8',
            'Content-Length' => $res_length,
            'X-Req-Type' => $req_type,
            'X-Req-Length' => $req_length,
        ],
        [$body],
    ];
};

plan tests => 3 * blocks;

filters {
    'request' => [qw(eval)],
    'expected' => [qw(eval)],
};

run {
    my($block) = @_;
    my $server = Test::XmlServer->new(
        $block->request => $block->expected, '/quick',
    );
    $server->run($application);
    my $expected = $server->expected;
    my $response = $server->response;

    is $response->code, $expected->code, $block->name . ' code';
    is_deeply $response->{'header'}, $expected->{'header'},
        $block->name . ' header';
    if (ref $expected->body) {
        is_deeply $response->body, $expected->body, $block->name . ' body (deeply)';
    }
    else {
        is $response->body, $expected->body, $block->name . ' body (is)';
    }
};

__END__

=== POST formdata to scalar
--- request
[
    'POST', '',
    [],
    [
        'a' => 'A',
        'b' => 'B',
    ],
]
--- expected
[
    200,
    [
        'Content-Type' => 'text/plain; charset=utf-8',
        'X-Req-Type' => 'application/x-www-form-urlencoded',
        'X-Req-Length' => 7,
    ],
    'a=A&b=B',
]

=== POST scalar to scalar
--- request
[
    'POST', '',
    ['Content-Type' => 'application/xml; charset=utf-8'],
    '<entry><a>alice</a><b>bob</b></entry>',
]
--- expected
[
    200,
    [
        'Content-Type' => 'text/plain; charset=utf-8',
        'X-Req-Type' => 'application/xml; charset=utf-8',
        'X-Req-Length' => length '<entry><a>alice</a><b>bob</b></entry>',
    ],
    '<entry><a>alice</a><b>bob</b></entry>',
]

=== POST scalar to hash
--- request
[
    'POST', '',
    ['Content-Type' => 'application/xml; charset=utf-8'],
    '<entry><a>alice</a><b>bob</b></entry>',
]
--- expected
[
    200,
    [
        'Content-Type' => 'text/plain; charset=utf-8',
        'X-Req-Type' => 'application/xml; charset=utf-8',
        'X-Req-Length' => length '<entry><a>alice</a><b>bob</b></entry>',
    ],
    {
        'a' => {
            '-text' => 'alice',
        },
        'b' => {
            '-text' => 'bob',
        },
    },
]

=== PUT formdata to scalar
--- request
[
    'PUT', '',
    [],
    [
        'a' => 'A',
        'b' => 'B',
    ],
]
--- expected
[
    200,
    [
        'Content-Type' => 'text/plain; charset=utf-8',
        'X-Req-Type' => 'application/x-www-form-urlencoded',
        'X-Req-Length' => 7,
    ],
    'a=A&b=B',
]

=== PUT scalar to scalar
--- request
[
    'PUT', '',
    ['Content-Type' => 'application/xml; charset=utf-8'],
    '<entry><a>alice</a><b>bob</b></entry>',
]
--- expected
[
    200,
    [
        'Content-Type' => 'text/plain; charset=utf-8',
        'X-Req-Type' => 'application/xml; charset=utf-8',
        'X-Req-Length' => length '<entry><a>alice</a><b>bob</b></entry>',
    ],
    '<entry><a>alice</a><b>bob</b></entry>',
]

=== PUT scalar to hash
--- request
[
    'PUT', '',
    ['Content-Type' => 'application/xml; charset=utf-8'],
    '<entry><a>alice</a><b>bob</b></entry>',
]
--- expected
[
    200,
    [
        'Content-Type' => 'text/plain; charset=utf-8',
        'X-Req-Type' => 'application/xml; charset=utf-8',
        'X-Req-Length' => length '<entry><a>alice</a><b>bob</b></entry>',
    ],
    {
        'a' => {
            '-text' => 'alice',
        },
        'b' => {
            '-text' => 'bob',
        },
    },
]

