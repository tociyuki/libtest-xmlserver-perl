use strict;
use warnings;
use Test::Base;
use Test::XmlServer;

my $application = require 't/app.psgi';

plan tests => 3 * blocks;

filters {
    'request' => [qw(eval)],
    'expected' => [qw(eval)],
};

run {
    my($block) = @_;
    my $server = Test::XmlServer->new($block->request => $block->expected);
    $server->run($application);
    my $expected = $server->expected;
    my $response = $server->response;

    is $response->code, $expected->code, $block->name . ' code';
    is_deeply $response->{'header'}, $expected->{'header'},
        $block->name . ' header';
    is_deeply $response->body, $expected->body, $block->name . ' body';
};

__END__

=== get signin without session_id
--- request
[
    'GET', '/signin',
    [],
    [],
]
--- expected
[
    200,
    [
        'Content-Type' => 'text/html; charset=utf-8',
        'Set-Cookie' => undef,
    ],
    {
        'form#signin' => {
            'method' => 'POST',
        },
        'form#signin input[name="username"]' => {
            'type' => 'text',
        },
        'form#signin input[name="password"]' => {
            'type' => 'password',
        },
        'form#signin input[name="signin"]' => {
            'type' => 'submit',
        },
    },
]

=== post signin ok password
--- request
[
    'POST', '/signin',
    [
        'Content-Type' => 'multipart/form-data',
    ],
    [
        'username' => 'alice',
        'password' => 'sa^6Xwr_Ukej!dj2P',
        'signin' => ' Sign In ',
    ],
]
--- expected
[
    303,
    [
        'Location' => '/',
        'Set-Cookie' => 'ssid=Rr6Mq4gA1u93KXrHXDuNfFfclFcS5eB9',
    ],
    {},
]

=== post signin bad password
--- request
[
    'POST', '/signin',
    [
        'Content-Type' => 'multipart/form-data',
    ],
    [
        'username' => 'alice',
        'password' => 'alice!inval_password',
        'signin' => ' Sign In ',
    ],
]
--- expected
[
    200,
    [
        'Content-Type' => 'text/html; charset=utf-8',
        'Set-Cookie' => undef,
    ],
    {
        'form#signin' => {
            'method' => 'POST',
        },
        'form#signin input[name="username"]' => {
            'type' => 'text',
        },
        'form#signin input[name="password"]' => {
            'type' => 'password',
        },
        'form#signin input[name="signin"]' => {
            'type' => 'submit',
        },
    },
]

=== get signin with session_id
--- request
[
    'GET', '/signin',
    ['Cookie' => 'ssid=Rr6Mq4gA1u93KXrHXDuNfFfclFcS5eB9'],
    [],
]
--- expected
[
    303,
    [
        'Location' => '/',
        'Set-Cookie' => undef,
    ],
    {},
]

=== post signin ok password with session_id
--- request
[
    'POST', '/signin',
    [
        'Cookie' => 'ssid=Rr6Mq4gA1u93KXrHXDuNfFfclFcS5eB9',
        'Content-Type' => 'multipart/form-data',
    ],
    [
        'username' => 'alice',
        'password' => 'sa^6Xwr_Ukej!dj2P',
        'signin' => ' Sign In ',
    ],
]
--- expected
[
    303,
    [
        'Location' => '/',
        'Set-Cookie' => undef,
    ],
    {},
]

=== post signin bad password with session_id
--- request
[
    'POST', '/signin',
    [
        'Cookie' => 'ssid=Rr6Mq4gA1u93KXrHXDuNfFfclFcS5eB9',
        'Content-Type' => 'multipart/form-data',
    ],
    [
        'username' => 'alice',
        'password' => 'alice!inval_password',
        'signin' => ' Sign In ',
    ],
]
--- expected
[
    303,
    [
        'Location' => '/',
        'Set-Cookie' => undef,
    ],
    {},
]

=== get toppage with session_id
--- request
[
    'GET', '/',
    ['Cookie' => 'ssid=Rr6Mq4gA1u93KXrHXDuNfFfclFcS5eB9'],
    [],
]
--- expected
[
    200,
    [
        'Content-Type' => 'text/html; charset=utf-8',
        'Set-Cookie' => undef,
    ],
    {
        'span.username' => {
            'title' => 'alice',
        },
        'a[href="/signout"]' => {
            'href' => '/signout',
        },
    },
]

=== get toppage without session_id
--- request
[
    'GET', '/',
    [],
    [],
]
--- expected
[
    200,
    [
        'Content-Type' => 'text/html; charset=utf-8',
        'Set-Cookie' => undef,
    ],
    {
        'span.username' => {
            'title' => 'guest',
        },
        'a[href="/signin"]' => {
            'href' => '/signin',
        },
    },
]

=== get signout with session_id
--- request
[
    'GET', '/signout',
    ['Cookie' => 'ssid=Rr6Mq4gA1u93KXrHXDuNfFfclFcS5eB9'],
    [],
]
--- expected
[
    303,
    [
        'Location' => '/',
        'Set-Cookie' => 'ssid=; expires=Mon, 01-Jan-2001 00:00:00 GMT',
    ],
    {},
]

=== get signout without session_id
--- request
[
    'GET', '/signout',
    [],
    [],
]
--- expected
[
    303,
    [
        'Location' => '/',
        'Set-Cookie' => undef,
    ],
    {},
]

