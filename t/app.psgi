package DemoApplication;
use strict;
use warnings;

our $VERSION = '0.001';
# $Id$
# DemoApplication - demonstration for PSGI application of Test::XmlServer

package WebComponent;
use strict;
use warnings;

sub new {
    my($class, @arg) = @_;
    if (@arg == 1 && ref $arg[0] eq 'HASH') {
        @arg = %{$arg[0]};
    }
    return bless {
        (ref $class ? %{$class} : ()),
        @arg,
    }, ref $class || $class;
}

# Based on Class::Accessor::Fast
sub mk_accessors {
    my($pkg, @field) = @_;
    for my $f (@field) {
        my $accessor = sub{
            my($self, @arg) = @_;
            if (@arg) {
                $self->{$f} = $arg[0];
            }
            return $self->{$f};
        };
        no strict 'refs'; ## no critic qw(NoStrinct)
        *{"${pkg}::${f}"} = $accessor;
    }
    @field = ();
    return;
}

package WebResponder;
use strict;
use warnings;
use Encode;
use Carp;
use parent qw(-norequire WebComponent);

__PACKAGE__->mk_accessors('env');

my %METHODS = (
    'HEAD' => 'get',
    'GET' => 'get',
    'POST' => 'post',
    'PUT' => 'put',
    'DELETE' => 'del',
);
my $AMP = qr{(?:[a-z][a-z0-9_]*|\#(?:[0-9]{1,5}|x[0-9A-F]{2,4}))}imsx;
my %XML_SPECIAL = (
    q{&} => q{&amp;}, q{<} => q{&lt;}, q{>} => q{&gt;},
    q{"} => q{&quot;}, q{'} => q{&#39;}, q{\\} => q{&#92;},
);

sub escape_xml {
    my($self, $string) = @_;
    $string =~ s{([&<>"'\\])}{ $XML_SPECIAL{$1} }egmosx;
    return $string;
}

sub escape_text {
    my($self, $string) = @_;
    return q{} if $string eq q{};
    $string =~ s{(?:([<>"'\\])|\&(?:($AMP);)?)}{
        $1 ? $XML_SPECIAL{$1} : $2 ? qq{\&$2;} : '&amp;'
    }egmosx;
    return $string;
}

sub decode_uri {
    my($self, $string) = @_;
    $string =~ tr/+/ /;
    $string =~ s{%([0-9A-F]{2})}{chr hex $1}iegmsx;
    return $string;
}

sub encode_uri {
    my($self, $uri) = @_;
    if (utf8::is_utf8($uri)) {
        $uri = Encode::encode('utf-8', $uri);
    }
    $uri =~ s{([^a-zA-Z0-9_\-./])}{ sprintf '%%%02X', ord $1 }egmosx;
    return $uri;
}

sub psgi_application {
    my($class, @controller_list) = @_;
    return sub{
        my($env) = @_;
        my $path = $env->{'PATH_INFO'} || '/';
        my $method = $METHODS{$env->{'REQUEST_METHOD'} || 'UNKOWN'};
        $method ||= 'method_not_allowed';
        for (0 .. -1 + int @controller_list / 2) {
            my $pattern = $controller_list[$_ * 2];
            my $controller = $controller_list[$_ * 2 + 1];
            if (my @param = $path =~ m{\A$pattern\z}msx) {
                if ($#- < 1) {
                    @param = ();
                }
                if (! $controller->can($method)) {
                    $method = 'method_not_allowed';
                }
                return $controller->new($env)->$method(@param);
            }
        }
        return $class->new($env)->not_found;
    };
}

sub new {
    my($class, $env) = @_;
    return bless {'env' => $env}, $class;
}

sub detach {
    my($self, $other) = @_;
    return $other->new($self->env);
}

sub response {
    my($self, $body, $code, @header) = @_;
    $body = Encode::encode('UTF-8', $body);
    return [
        $code || 200,
        [
            'Content-Type' => 'text/html; charset=utf-8',
            'Content-Length' => length $body,
            @header,
        ],
        [$body],
    ];    
}

sub bad_request {
    my($self) = @_;
    use utf8;
    my $body = <<'XHTML';
<!DOCTYPE html>
<html>
<head>
<meta encoding="utf-8" />
<title>Bad Request</title>
</head>
<body>
<h1>Bad Request</h1>
</body>
</html>
XHTML
    return $self->response($body, 400);
}

sub not_found {
    my($self) = @_;
    use utf8;
    my $body = <<'XHTML';
<!DOCTYPE html>
<html>
<head>
<meta encoding="utf-8" />
<title>Not Found</title>
</head>
<body>
<h1>Not Found</h1>
</body>
</html>
XHTML
    return $self->response($body, 404);
}

sub method_not_allowed {
    my($self, $allow) = @_;
    $allow ||= 'GET,HEAD';
    use utf8;
    my $body = <<'XHTML';
<!DOCTYPE html>
<html>
<head>
<meta encoding="utf-8" />
<title>Not Found</title>
</head>
<body>
<h1>Not Found</h1>
</body>
</html>
XHTML
    return $self->response($body, 405, 'Allow' => $allow);
}

sub internal_server_error {
    my($self) = @_;
    use utf8;
    my $body = <<'XHTML';
<!DOCTYPE html>
<html>
<head>
<meta encoding="utf-8" />
<title>Internal Server Error</title>
</head>
<body>
<h1>Internal Server Error</h1>
</body>
</html>
XHTML
    return $self->response($body, 500);
}

sub scan_form_urlencoded {
    my($self, $data) = @_;
    my %param;
    for my $pair (split /[&;]/msx, $data) {
        my @pair = split /=/msx, $pair, 2;
        if (@pair == 1) {
            unshift @pair, 'KEYWORD';
        }
        next if @pair != 2 || $pair[0] eq q{};
        my($k, $v) = map { $self->decode_uri($_) } @pair;
        unshift @{$param{$k}}, $v;
    }
    return \%param;
}

sub scan_cookie {
    my($self, $raw_cookie) = @_;
    my %cookie;
    for my $pair (split /[;]\x20*/msx, $raw_cookie) {
        my @pair = split /=/msx, $pair, 2;
        next if @pair != 2 || $pair[0] eq q{};
        my($k, $v) = map {
            Encode::decode('UTF-8', $self->decode_uri($_))
        } @pair;
        unshift @{$cookie{$k}}, $v;
    }
    return \%cookie;
}

sub check {
    my($self, $hash_array, $constraint) = @_;
    my %param = %{$hash_array};
    while (my($name, $definition) = each %{$constraint}) {
        my($type, $null, $pattern) = @{$definition};
        return if $null eq 'NOT NULL' && ! exists $param{$name};
        my $value_list = delete $param{$name};
        return if $type eq 'FLAG' && @{$value_list} > 1;
        return if $type eq 'SCALAR' && @{$value_list} != 1;
        next if $type eq 'FLAG';
        for my $item (@{$value_list}) {
            return if $item !~ m/$pattern/msx;
        }
    }
    return if %param;
    return $hash_array;
}

package UserSession;
use strict;
use warnings;
use Carp;
use parent qw(-norequire WebComponent);

__PACKAGE__->mk_accessors(qw(session_id user_id user_name user_secret));

sub _validate_session_id {
    my($class, $s) = @_;
    return $s =~ m/\A[a-zA-Z0-9_-]{1,64}\z/msx;
}

sub _validate_username {
    my($class, $s) = @_;
    return $s =~ m/\A[a-zA-Z0-9]+(?:[-_][a-zA-Z0-9]+)*\z/msx
        && 64 >= length $s;
}

sub _validate_password {
    my($class, $s) = @_;
    return $s =~ m/\A[\x20-\x7e]{8,80}\z/msx;
}

sub new_mock {
    return shift->new(
        'session_id' => 'Rr6Mq4gA1u93KXrHXDuNfFfclFcS5eB9',
        'user_id' => 100,
        'user_name' => 'alice',
        'user_secret' => crypt 'sa^6Xwr_Ukej!dj2P', '$1$e8dYdwa/d$',
    );
}

sub find {
    my($class, $id) = @_;
    $class->_validate_session_id($id) or return [];
    return [] if $id ne 'Rr6Mq4gA1u93KXrHXDuNfFfclFcS5eB9';
    return [$class->new_mock];
}

sub signin {
    my($class, $username, $password) = @_;
    $class->_validate_username($username) or return;
    $class->_validate_password($password) or return;
    my $self = $class->new_mock;
    my $secret = $self->user_secret;
    return if $secret ne crypt $password, $secret;
    return $self;
}

sub signout {
    my($class, $id) = @_;
    $class->_validate_session_id($id);
    return;
}

package ProtectedPage;
use strict;
use warnings;
use parent qw(-norequire WebResponder);

sub request_session_id {
    my($self) = @_;
    my $raw_cookie = $self->env->{'HTTP_COOKIE'} || q{};
    my $cookie = $self->scan_cookie($raw_cookie);
    return if ! exists $cookie->{'ssid'} || @{$cookie->{'ssid'}} != 1;
    my $ssid = $cookie->{'ssid'}[0];
    $ssid = defined $ssid ? $ssid : q{};
    return if $ssid !~ m/\A[a-zA-Z0-9_-]{1,64}\z/msx;
    return $ssid;
}

package TopPageUser;
use strict;
use warnings;
use Encode;
use parent qw(-norequire ProtectedPage);

sub rendar {
    my($self, $session) = @_;
    my $username = $self->escape_text($session->user_name);
    use utf8;
    my $body = <<"XHTML";
<!DOCTYPE html>
<html>
<head>
<meta encoding="utf-8" />
<title>Example</title>
</head>
<body>
<h1>Example</h1>
<h2>TopPage</h2>
<ul>
<li>Welcome to <span class="username" title="$username">$username</span></li>
<li><a href="/signout">sign out</a></li>
</ul>
</body>
</html>
XHTML
    return $self->response($body, 200);
}

package TopPage;
use strict;
use warnings;
use Encode;
use parent qw(-norequire ProtectedPage);

sub rendar {
    my($self) = @_;
    use utf8;
    my $body = <<'XHTML';
<!DOCTYPE html>
<html>
<head>
<meta encoding="utf-8" />
<title>Example</title>
</head>
<body>
<h1>Example</h1>
<h2>TopPage</h2>
<ul>
<li>Welcome to <span class="username" title="guest">guest</span></li>
<li><a href="/signin">sign in</a></li>
</ul>
</body>
</html>
XHTML
    return $self->response($body, 200);
}

sub redirect {
    my($self, @arg) = @_;
    return [303, ['Location' => q{/}], []] if ! @arg;
    my($session) = @arg;
    my $ssid = ref $session ? $self->encode_uri($session->session_id)
        : '; expires=Mon, 01-Jan-2001 00:00:00 GMT';
    return [
        303,
        [
            'Location' => q{/},
            'Set-Cookie' => "ssid=$ssid",
        ],
        [],
    ];
}

sub get {
    my($self) = @_;
    if (my $ssid = $self->request_session_id) {
        my $session = UserSession->find($ssid)->[0];
        if ($session) {
            return $self->detach('TopPageUser')->rendar($session);
        }
    }
    return $self->rendar;
}

package SigninPage;
use strict;
use warnings;
use Encode;
use parent qw(-norequire ProtectedPage);

sub method_not_allowed {
    my($self) = @_;
    return $self->SUPER::method_not_allowed('GET,HEAD,POST');
}

sub rendar {
    my($self) = @_;
    use utf8;
    my $body = <<'XHTML';
<!DOCTYPE html>
<html>
<head>
<meta encoding="utf-8" />
<title>サインイン - Example</title>
</head>
<body>
<h1>Example</h1>
<h2>サインイン</h2>
<form id="signin" action="/signin" method="POST">
<table>
<tr><th>ユーザ名</th><td><input type="text" name="username" /></td></tr>
<tr><th>パスワード</th><td><input type="password" name="password" /></td></tr>
<tr><td style="text-align: right" colspan="2"><input type="submit" name="signin" value=" サインイン " /></td></tr>
</table>
</form>
</body>
</html>
XHTML
    return $self->response($body);
}

sub redirect {
    my($self) = @_;
    return [303, ['Location' => '/signin'], []];
}

sub get {
    my($self) = @_;
    my $ssid = $self->request_session_id;
    if ($ssid && UserSession->find($ssid)->[0]) {
        return $self->detach('TopPage')->redirect;
    }
    return $self->rendar;
}

sub post {
    my($self) = @_;
    my $ssid = $self->request_session_id;
    if ($ssid && UserSession->find($ssid)->[0]) {
        return $self->detach('TopPage')->redirect;
    }
    my $env = $self->env;
    my $fh = $env->{'psgi.input'};
    my $length = $env->{'CONTENT_LENGTH'} or return $self->bad_request();
    $length < 4096 or return $self->bad_request();
    read $fh, my($data), $length;
    my $param = $self->check(
        $self->scan_form_urlencoded($data), {
            'signin' => ['FLAG', 'NOT NULL'],
            'username' => ['SCALAR', 'NOT NULL', qr/\A[a-zA-Z0-9_-]{1,64}\z/msx],
            'password' => ['SCALAR', 'NOT NULL', qr/\A[\x20-\x7e]{8,80}\z/msx],
    }) or return $self->rendar;
    my $username = $param->{'username'}[0];
    my $password = $param->{'password'}[0];
    if (my $session = UserSession->signin($username, $password)) {
        return $self->detach('TopPage')->redirect($session);
    }
    return $self->rendar;
}

package SignoutPage;
use strict;
use warnings;
use parent qw(-norequire ProtectedPage);

sub get {
    my($self) = @_;
    my $ssid = $self->request_session_id;
    if ($ssid && UserSession->find($ssid)->[0]) {
        UserSession->signout($ssid);
        return $self->detach('TopPage')->redirect(undef);
    }
    return $self->detach('TopPage')->redirect;
}

package DemoApplication;
use strict;
use warnings;

my $application = WebResponder->psgi_application(
    '/' => 'TopPage',
    '/signin' => 'SigninPage',
    '/signout' => 'SignoutPage',
);

__END__

=pod

=head1 NAME

DemoApplication - demonstration for PSGI application of Test::XmlServer

=head1 VERSION

0.001

=head1 SYNOPSYS

    my $application = require 'app.psgi';

=head1 DESCRIPTION

=head1 METHODS

=over

=item C<< WebComponent->new(%init_values) >>

=item C<< __PACKAGE__->mk_accessors(@names) >>

=item C<< WebResponder->psgi_application(@controller_mappings) >>

=item C<< WebResponder->new($env) >>

=item C<< $webresponder->detach($other_responder_class) >>

=item C<< $webresponder->bad_request >>

=item C<< $webresponder->not_found >>

=item C<< $webresponder->method_not_allowed >>

=item C<< $webresponder->internal_server_error >>

=item C<< $webresponder->escape_xml >>

=item C<< $webresponder->escape_text >>

=item C<< $webresponder->decode_uri >>

=item C<< $webresponder->encode_uri >>

=item C<< $webresponder->scan_form_urlencoded >>

=item C<< $webresponder->scan_cookie >>

=item C<< $webresponder->check(\%param, \%constraint) >>

=item C<< Session->find($id) >>

=item C<< Session->signin($username, $password) >>

=item C<< $protectedpage->request_session_id >>

=item C<< $toppage->rendar >>

=item C<< $toppage->redirect >>

=item C<< $toppage->get >>

=item C<< $signinpage->method_not_allowed >>

=item C<< $signinpage->rendar >>

=item C<< $signinpage->redirect >>

=item C<< $signinpage->get >>

=item C<< $signinpage->post >>

=item C<< $signoutpage->get >>

=back

=head1 DEPENDENCIES

None.

=head1 SEE ALSO

None.

=head1 AUTHOR

MIZUTANI Tociyuki  C<< <tociyuki@gmail.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2011, MIZUTANI Tociyuki C<< <tociyuki@gmail.com> >>.
All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

