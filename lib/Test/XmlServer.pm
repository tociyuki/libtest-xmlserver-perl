package Test::XmlServer;
use strict;
use warnings;
use Test::XmlServer::CommonData;
use Test::XmlServer::Document;

# $Id$
use version; our $VERSION = '0.005';

sub request { return shift->{'request'} }
sub expected { return shift->{'expected'} }
sub response { return shift->{'response'} }
sub script_name { return shift->{'script_name'} }

sub new {
    my($class, $block_request, $block_expected, $script_name) = @_;
    my $request = Test::XmlServer::CommonData->new;
    $request->method($block_request->[0]);
    if (defined $block_request->[1]) {
        $request->request_uri($block_request->[1]);
    }
    $request->replace('header' => $block_request->[2]);
    if (ref $block_request->[3] eq 'ARRAY') {
        $request->replace('param' => $block_request->[3]);
    }
    elsif (defined $block_request->[3] && ! ref $block_request->[3]) {
        $request->body($block_request->[3]);
    }
    my $expected = Test::XmlServer::CommonData->new;
    $expected->code($block_expected->[0]);
    $expected->replace('header' => $block_expected->[1]);
    $expected->body($block_expected->[2]);
    return bless {
        'request' => $request,
        'expected' => $expected,
        'response' => Test::XmlServer::CommonData->new,
        'script_name' => $script_name || q{},
    }, $class;
}

sub run {
    my($self, $application) = @_;
    my $env = $self->_prepare_env;
    if ($env->{'REQUEST_METHOD'} eq 'POST' || $env->{'REQUEST_METHOD'} eq 'PUT') {
        my $content;
        $env->{'CONTENT_TYPE'} ||= 'application/x-www-form-urlencoded';
        if (defined $self->request->body) {
            $content = $self->request->body;
        }
        elsif ($env->{'CONTENT_TYPE'} eq 'application/x-www-form-urlencoded') {
            $content = $self->request->formdata;
        }
        elsif ($env->{'CONTENT_TYPE'} eq 'multipart/form-data') {
            my @c = ('A'..'Z', 'a'..'z', '0'..'9');
            my $boundary = join q{}, map { $c[rand @c] } 1 .. 64;
            $content = $self->request->multipart_formdata($boundary);
            $env->{'CONTENT_TYPE'} .= qq{; boundary=$boundary};
        }
        $env->{'CONTENT_LENGTH'} = length $content;
        open my($inputh), '<', \$content;
        $env->{'psgi.input'} = $inputh;
        $self->_finalize_response($application->($env));
        close $inputh;
        return $self;
    }
    $self->_finalize_response($application->($env));
    return $self;
}

sub _prepare_env {
    my($self) = @_;
    my $method = $self->request->method || 'GET';
    my $script_name = $self->script_name;
    my $request_uri = Test::XmlServer::CommonData::_encode_uri(
        $self->request->request_uri || $script_name,
    );
    my($path, $q, $query) = $request_uri =~ m{\A([^?#]*)(?:(\?)([^#]*))?\z}msx;
    if ($method ne 'POST' && $method ne 'PUT') {
        my $formdata = $self->request->formdata;
        if ($formdata ne q{}) {
            if (defined $query && $query ne q{}) {
                $query .= q{&} . $formdata;
            }
            else {
                $query = $formdata;
            }
            $q = q{?};
            $request_uri = $path . q{?} . $query;
        }
    }
    if ($script_name eq substr $path, 0, length $script_name) {
        substr $path, 0, length $script_name, "";
    }
    $path = Test::XmlServer::CommonData::_decode_uri($path);
    my $env = {
        'psgi.version' => [1, 0],
        'psgi.url_scheme' => 'http',
        'psgi.input' => \*STDIN,
        'psgi.errors' => \*STDERR,
        'psgi.multithread' => 0,
        'psgi.multiprocess' => 0,
        'SERVER_NAME' => 'localhost',
        'SERVER_PORT' => 80,
        'SERVER_PROTOCOL' => 'HTTP/1.1',
        'REQUEST_METHOD' => $method,
        'REQUEST_URI' => $request_uri,
        'SCRIPT_NAME' => $script_name,
        'PATH_INFO' => $path ne q{} ? $path : undef,
        'QUERY_STRING' => $q ? $query : undef,
    };
    for my $h ($self->request->header) {
        next if ! defined $self->request->header($h);
        my $header = join q{_}, map { uc } split /-/msx, $h;
        if ('CONTENT_' ne substr $header, 0, 8) {
            $header = 'HTTP_' . $header;
        }
        $env->{$header} = $self->request->header($h);
    }
    return $env;
}

sub _finalize_response {
    my($self, $psgi_res) = @_;
    $self->response->code($psgi_res->[0]);
    my $res = Test::XmlServer::CommonData->new('header' => $psgi_res->[1]);
    for my $name ($self->expected->header) {
        $self->response->header($name => scalar $res->header($name));
    }
    my $content = join q{}, @{$psgi_res->[2]};
    if (! ref $self->expected->body) {
        $self->response->body($content);
        return $self;
    }
    $self->response->body({});
    my $doc = Test::XmlServer::Document->new($content);
    for my $selector (keys %{$self->expected->body}) {
        my($element) = $doc->find($selector);
        if (! defined $self->expected->body->{$selector} && ! $element) {
            $self->response->body->{$selector} = undef;
            next;
        }
        $element or next;
        for my $attr (keys %{$self->expected->body->{$selector}}) {
            $self->response->body->{$selector}{$attr} = 
                $attr eq '-text' ? join q{}, @{$element->child_nodes}
                :                   $element->attribute($attr);
        }
    }
    return $self;
}

1;

__END__

=pod

=head1 NAME

Test::XmlServer - easy to test your PSGI Application responding XHTML.

=head1 VERSION

0.005

=head1 SYNOPSIS

    use Test::Base;
    use Test::XmlServer;
    
    my $application = require 'app.psgi';
    
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
        is_deeply $response->header, $expected->header, $block->name . ' header';
        is_deeply $response->body, $expected->body, $block->name . ' body';
    };
    
    __END__
    
    === signin ok password
    --- request
    [
        # request method and path info
        'POST', '/signin',
        # request headers
        [],
        # request formdata
        [
            'username' => 'alice',
            'password' => 'alice+password',
            'signin' => ' Sign In ',
        ],
    ]
    --- expected
    [
        # response status code
        303,
        # response headers
        [
            'Location' => '/example/',
            'Set-Cookie' => 'ssid=alice_session_id',
        ],
        # response document
        {},
    ]
    
    === signin bad password
    --- request
    [
        'POST', '/signin',
        [
            # turn on enctype="multipart/form-data"
            'Content-Type' => 'multipart/form-data',
        ],
        [
            'username' => 'bob',
            'password' => 'bob!password',
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
        # response document
        {
            # CSS-like selector
            'form#signin' => {
                # attribute name => attribute value
                'method' => 'POST',
                # '-text' => child's text
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

=head1 DESCRIPTION

=head1 METHODS 

=over

=item C<< new($block_request, $block_expected, [$script_name]) >>

Create a test server for given Test::Base's block.

=item C<< run(\&application) >>

Applies PSGI application the cooked request.

=item C<< request >>

Returns the cooked request.

=item C<< response >>

Returns the cooked response.

=item C<< expected >>

Returns the cooked expected.

=back

=head1 DEPENDENCIES

None.

=head1 REPOSITORY

L<https://github.com/tociyuki/libtest-xmlserver-perl>

=head1 AUTHOR

MIZUTANI Tociyuki  C<< <tociyuki@gmail.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2011, MIZUTANI Tociyuki C<< <tociyuki@gmail.com> >>.
All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

