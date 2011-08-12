use strict;
use warnings;
use Test::Base;
use Test::XmlServer;

my %XML_SPECIAL = (
    q{&} => q{&amp;}, q{<} => q{&lt;}, q{>} => q{&gt;}, q{"} => q{&quot;},
    q{'} => q{&#39;}, q{\\} => q{&#92;},
);

sub escape_xmlall {
    my($str) = @_;
    $str =~ s{([&<>"'\\])}{ $XML_SPECIAL{$1} }egmosx;
    return $str;
}

my $application = sub{
    my($env) = @_;
my $body = <<"EOS";
<?xml version="1.0" encoding="UTF-8"?>
<html>
<head><title>mock</title></head>
<body>
<h1>mock</h1>
<p>
<span class="request_uri" title="@{[ escape_xmlall($env->{'REQUEST_URI'}) ]}"></span>
<span class="script_name" title="@{[ escape_xmlall($env->{'SCRIPT_NAME'}) ]}"></span>
<span class="path_info" title="@{[ escape_xmlall($env->{'PATH_INFO'} || '?') ]}"></span>
<span class="query_string" title="@{[ escape_xmlall($env->{'QUERY_STRING'} || '?') ]}"></span>
</p>
</body>
</html>
EOS
    return [200, ['Content-Type' => 'application/xml+xhtml; charset=utf-8'], [$body]];
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
    is_deeply $response->body, $expected->body, $block->name . ' body';
};

__END__

=== script_name only
--- request
[
    'GET', '/quick',
    [],
    [],
]
--- expected
[
    200,
    [
        'Content-Type' => 'application/xml+xhtml; charset=utf-8',
    ],
    {
        '.request_uri' => {
            'title' => '/quick',
        },
        '.script_name' => {
            'title' => '/quick',
        },
        '.path_info' => {
            'title' => '?',
        },
        '.query_string' => {
            'title' => '?',
        },
    },
]

=== empty query
--- request
[
    'GET', '/quick?',
    [],
    [],
]
--- expected
[
    200,
    [
        'Content-Type' => 'application/xml+xhtml; charset=utf-8',
    ],
    {
        '.request_uri' => {
            'title' => '/quick?',
        },
        '.script_name' => {
            'title' => '/quick',
        },
        '.path_info' => {
            'title' => '?',
        },
        '.query_string' => {
            'title' => '?',
        },
    },
]

=== query
--- request
[
    'GET', '/quick?jumps=over&the=lazy',
    [],
    [],
]
--- expected
[
    200,
    [
        'Content-Type' => 'application/xml+xhtml; charset=utf-8',
    ],
    {
        '.request_uri' => {
            'title' => '/quick?jumps=over&amp;the=lazy',
        },
        '.script_name' => {
            'title' => '/quick',
        },
        '.path_info' => {
            'title' => '?',
        },
        '.query_string' => {
            'title' => 'jumps=over&amp;the=lazy',
        },
    },
]

=== script_name path
--- request
[
    'GET', '/quick/brown/fox',
    [],
    [],
]
--- expected
[
    200,
    [
        'Content-Type' => 'application/xml+xhtml; charset=utf-8',
    ],
    {
        '.request_uri' => {
            'title' => '/quick/brown/fox',
        },
        '.script_name' => {
            'title' => '/quick',
        },
        '.path_info' => {
            'title' => '/brown/fox',
        },
        '.query_string' => {
            'title' => '?',
        },
    },
]

=== path+empty query
--- request
[
    'GET', '/quick/brown/fox?',
    [],
    [],
]
--- expected
[
    200,
    [
        'Content-Type' => 'application/xml+xhtml; charset=utf-8',
    ],
    {
        '.request_uri' => {
            'title' => '/quick/brown/fox?',
        },
        '.script_name' => {
            'title' => '/quick',
        },
        '.path_info' => {
            'title' => '/brown/fox',
        },
        '.query_string' => {
            'title' => '?',
        },
    },
]

=== path+query
--- request
[
    'GET', '/quick/brown/fox?jumps=over&the=lazy',
    [],
    [],
]
--- expected
[
    200,
    [
        'Content-Type' => 'application/xml+xhtml; charset=utf-8',
    ],
    {
        '.request_uri' => {
            'title' => '/quick/brown/fox?jumps=over&amp;the=lazy',
        },
        '.script_name' => {
            'title' => '/quick',
        },
        '.path_info' => {
            'title' => '/brown/fox',
        },
        '.query_string' => {
            'title' => 'jumps=over&amp;the=lazy',
        },
    },
]

=== POST path+query
--- request
[
    'POST', '/quick/brown/fox?jumps=over&the=lazy',
    [],
    [],
]
--- expected
[
    200,
    [
        'Content-Type' => 'application/xml+xhtml; charset=utf-8',
    ],
    {
        '.request_uri' => {
            'title' => '/quick/brown/fox?jumps=over&amp;the=lazy',
        },
        '.script_name' => {
            'title' => '/quick',
        },
        '.path_info' => {
            'title' => '/brown/fox',
        },
        '.query_string' => {
            'title' => 'jumps=over&amp;the=lazy',
        },
    },
]

