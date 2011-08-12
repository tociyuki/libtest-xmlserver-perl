use strict;
use warnings;
use Test::Base;
use Test::XmlServer;

my $application = sub{
    my($env) = @_;
    my $body = $env->{'QUERY_STRING'} || q{};
    use bytes;
    my $res_length = bytes::length($body);
    return [
        200,
        [
            'Content-Type' => 'text/plain; charset=utf-8',
            'Content-Length' => $res_length,
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
    is $response->body, $expected->body, $block->name . ' body';
};

__END__

=== GET query
--- request
[
    'GET', '/quick?a=A&b=B',
    [],
    [],
]
--- expected
[
    200,
    [],
    'a=A&b=B',
]

=== GET form_data
--- request
[
    'GET', '/quick',
    [],
    ['a' => 'A', 'b' => 'B'],
]
--- expected
[
    200,
    [],
    'a=A&b=B',
]

=== GET query + form_data
--- request
[
    'GET', '/quick?a=A&b=B',
    [],
    ['c' => 'C', 'd' => 'D'],
]
--- expected
[
    200,
    [],
    'a=A&b=B&c=C&d=D',
]

=== GET empty query
--- request
[
    'GET', '/quick?',
    [],
    [],
]
--- expected
[
    200,
    [],
    '',
]

=== GET empty query + form_data
--- request
[
    'GET', '/quick?',
    [],
    ['c' => 'C', 'd' => 'D'],
]
--- expected
[
    200,
    [],
    'c=C&d=D',
]

