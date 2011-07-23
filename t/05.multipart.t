use strict;
use warnings;
use Test::Base;
use Test::XmlServer;

plan tests => 9;

filters {
    'request' => [qw(eval)],
    'expected' => [qw(eval)],
};

run {
    my($block) = @_;
    my $server = Test::XmlServer->new($block->request => $block->expected);
    my $stub = StubApplication->new;
    $server->run(sub{ $stub->respond(@_) });

    my $content_type = $stub->{'env'}{'CONTENT_TYPE'};

    like $content_type, qr{^multipart/form-data; boundary=}, 'content_type';

    my($boundary) = $content_type =~ m{boundary=(.*)}msx;

    like $boundary, qr{\A[A-Za-z0-9]+\z}msx, 'boundary';

    my %param;
    my $body = $stub->{'body'};

    ok $body =~ m{\G--$boundary\x0d\x0a}gcmsx, 'top boundary';

    ok $body =~ m{\G
        Content-Disposition: \x20* form-data; \x20* name="([^"])" \x0d\x0a
        \x0d\x0a
        (.*?) \x0d\x0a
        --$boundary\x0d\x0a
    }gcmsx, '1st part';
    push @{$param{$1}}, $2;

    ok $body =~ m{\G
        Content-Disposition: \x20* form-data; \x20* name="([^"])" \x0d\x0a
        \x0d\x0a
        (.*?) \x0d\x0a
        --$boundary\x0d\x0a
    }gcmsx, '2nd part';
    push @{$param{$1}}, $2;

    ok $body =~ m{\G
        Content-Disposition: \x20* form-data; \x20* name="([^"])" \x0d\x0a
        \x0d\x0a
        (.*?) \x0d\x0a
        --$boundary\x0d\x0a
    }gcmsx, '3rd part';
    push @{$param{$1}}, $2;

    ok $body =~ m{\G
        Content-Disposition: \x20* form-data; \x20* name="([^"])" \x0d\x0a
        \x0d\x0a
        (.*?) \x0d\x0a
        --$boundary--\x0d\x0a
    }gcmsx, 'last part';
    push @{$param{$1}}, $2;
    
    ok $body =~ m{\G\z}msx, 'end body';

    is_deeply \%param, {
        'a' => ['&A', '>A1'],
        'b' => ['<B'],
        'c' => ['"C'],
    }, 'param';
};

package StubApplication;

sub new {
    my($class) = @_;
    return bless {
        'env' => undef,
        'body' => undef,
    };
}

sub respond {
    my($self, $env) = @_;
    $self->{'env'} = $env;
    my $input = $env->{'psgi.input'};
    my $size = $env->{'CONTENT_LENGTH'};
    read $input, my($body), $size;
    $self->{'body'} = $body;
    return [200,
        ['Content-Type' => 'text/html; charset=utf8'],
        ['<html><head><title>stub</title></head><body><h1>stub</h1></body></html>'],
    ];
}

__END__

=== post multipart
--- request
[
    'POST', '/',
    [
        'Content-Type' => 'multipart/form-data',
    ],
    [
        'a' => '&A',
        'b' => '<B',
        'a' => '>A1',
        'c' => '"C',
    ],
]
--- expected
[
    200,
    [],
    {
        'h1' => {'-text' => 'stub'},
    },
]

