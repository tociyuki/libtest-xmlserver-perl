package DemoApplication;
use strict;
use warnings;

our $VERSION = '0.002';
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

package WebResponse;
use strict;
use warnings;
use Encode;
use Carp;
use parent qw(-norequire WebComponent);

__PACKAGE__->mk_accessors('code', 'body', 'controller');

sub content_type   { return shift->header('Content-Type' => @_) }
sub content_length { return shift->header('Content-Length' => @_) }

sub replace {
    my($self, $attr, @arg) = @_;
    if (ref $self->{$attr} eq 'HASH' && $attr ne 'env') {
        %{$self->{$attr}} = ();
        my $a = @arg == 1 && ref $arg[0] eq 'ARRAY' ? $arg[0] : \@arg;
        for (0 .. -1 + int @{$a} / 2) {
            my $i = $_ * 2;
            $self->$attr($a->[$i] => $a->[$i + 1]);
        }
    }
    else {
        $self->$attr(@arg);
    }
    return $self;
}

sub redirect {
    my($self, @arg) = @_;
    if (@arg) {
        $self->header('Location' => $arg[0]);
        $self->code(@arg > 1 ? $arg[1] : '303');
        $self->content_type(undef);
        $self->content_length(undef);
        $self->body(undef);
    }
    return $self->header('Location');
}

sub header {
    my($self, @arg) = @_;
    @arg or return keys %{$self->{'header'}};
    my $k = shift @arg;
    if (@arg) {
        if (@arg == 1 && ! defined $arg[0]) {
            return if ! exists $self->{'header'}{$k};
            my $v = delete $self->{'header'}{$k};
            return wantarray ? @{$v} : $v->[-1];
        }
        if (lc $k ne 'set-cookie') {
            $self->{'header'}{$k}[0] = $arg[0];
        }
        elsif (@arg == 1 && ref $arg[0] eq 'ARRAY') {
            @{$self->{'header'}{$k}} = @{$arg[0]};
        }
        else {
            push @{$self->{'header'}{$k}}, @arg;
        }
    }
    return if ! exists $self->{'header'}{$k};
    return wantarray ? @{$self->{'header'}{$k}} : $self->{'header'}{$k}[-1];
}

sub cookie {
    my($self, @arg) = @_;
    return keys %{$self->{'cookie'}} if ! @arg;
    my $k = shift @arg;
    if (@arg) {
        if (@arg == 1 && ! defined $arg[0]) {
            return delete $self->{'cookie'}{$k};
        }
        if (@arg == 1 && ref $arg[0] eq 'HASH') {
            $self->{'cookie'}{$k} = {'name' => $k, %{$arg[0]} };
        }
        else {
            $self->{'cookie'}{$k} = {'name' => $k, 'value' => @arg};
        }
    }
    return $self->{'cookie'}{$k};
}

sub finalize {
    my($self, $env) = @_;
    if (! $self->code) {
        $env->{'psgi.error'}->print("No status code\n");
        my $responder = $self->controller->new(
            'env' => $env,
            'response' => $self,
        );
        return $responder->internal_server_error->response->finalize($env);
    }
    $self->finalize_cookie;
    my $code = $self->code;
    my $code_most = substr $code, 0, 1;
    my $code_least = substr $code, 1;
    if ($code_most eq '4' || $code_most eq '5') {
        $self->header('Set-Cookie', undef);
        $self->header('Location', undef);
    }
    elsif (($env->{'SERVER_PROTOCOL'} || 'HTTP/1.0') eq 'HTTP/1.0') {
        if ($code == 303 || $code == 307) {
            $self->code(302);
            ($code_most, $code_least) = (3, 2);
        }
    }
    if ($code_most == 1 || $code == 204 || $code == 304) {
        $self->content_length(undef);
        $self->body(undef);
    }
    elsif (! defined $self->content_length) {
        use bytes;
        my $byte_size = defined $self->body ? bytes::length($self->body) : 0;
        $self->content_length($byte_size);
    }
    if ($env->{'REQUEST_METHOD'} eq 'HEAD') {
        $self->body(undef);
    }
    my $response = [$self->code, [], []];
    for my $name ($self->header) {
        push @{$response->[1]}, map {
            ($name => join "\x0d\x0a ", split /[\r\n]+[\t\040]*/msx, $_);
        } $self->header($name);
    }
    if (defined $self->body) {
        $response->[2][0] = $self->body;
        if (utf8::is_utf8($response->[2][0])) {
            $response->[2][0] = Encode::encode('UTF-8', $response->[2][0]);
        }
    }
    return $response;
}

sub finalize_cookie {
    my($self) = @_;
    my @a = qw(Sun Mon Tue Wed Thu Fri Sat);
    my @b = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    for my $key ($self->cookie) {
        my $cookie = $self->cookie($key);
        my @dough = (
            $self->encode_uri($cookie->{'name'})
            . q{=} . $self->encode_uri($cookie->{'value'}),
            ($cookie->{'domain'} ?
                'domain=' . $self->encode_uri($cookie->{'domain'}) : ()),
            ($cookie->{'path'}) ?
                'path=' . $self->encode_uri($cookie->{'path'}) : (),
        );
        if (defined $cookie->{'expires'}) {
            my($s, $min, $h, $d, $mon, $y, $w) = gmtime $cookie->{'expires'};
            push @dough, sprintf 'expires=%s, %02d-%s-%04d %02d:%02d:%02d GMT',
                $a[$w], $d, $b[$mon], $y + 1900, $h, $min, $s;
        }
        push @dough,
            ($cookie->{'secure'} ? 'secure' : ()),
            ($cookie->{'httponly'} ? 'HttpOnly' : ());
        $self->header('Set-Cookie' => join q{; }, @dough);
    }
    return $self;
}

package WebResponder;
use strict;
use warnings;
use Encode;
use Carp;
use parent qw(-norequire WebComponent);

__PACKAGE__->mk_accessors('env', 'response');

my %METHODS = (
    'HEAD' => 'get',
    'GET' => 'get',
    'POST' => 'post',
    'PUT' => 'put',
    'DELETE' => 'del',
);

sub psgi_application {
    my($class, @controller_list) = @_;
    return sub{
        my($env) = @_;
        my $responder = $class->new(
            'env' => $env,
            'response' => WebResponse->new('controller' => $class),
        );
        $responder->response->content_type('text/html; charset=utf-8');
        # based on Try::Tiny
        if (eval{
            my $path = $env->{'PATH_INFO'} || '/';
            my $method = $METHODS{$env->{'REQUEST_METHOD'} || 'UNKOWN'};
            $method ||= 'method_not_allowed';
            $responder->not_found;
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
                    $responder = $responder->detach($controller);
                    $responder->response->code(200);
                    $responder->response->body(undef);
                    $responder = $responder->$method(@param);
                    last;
                }
            }
            1;
        }) {
            # success. do nothing.
        }
        elsif (ref $@) {
            $responder = $@; # detach
        }
        else {
            $env->{'psgi.errors'}->print("$@");
            $responder->internal_server_error;
        }
        return $responder->response->finalize($env);
    };
}

sub detach {
    my($self, $other) = @_;
    return $other->new(
        'env' => $self->env,
        'response' => $self->response->replace('controller' => $other),
    );
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
    $self->response->code(400);
    $self->response->body($body);
    return $self;
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
    $self->response->code(404);
    $self->response->body($body);
    return $self;
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
    $self->response->code(405);
    $self->response->header('Allow' => $allow);
    $self->response->body($body);
    return $self;
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
    $self->response->code(500);
    $self->response->body($body);
    return $self;
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
use Carp;
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
    $self->response->body($body);
    return $self;
}

package TopPage;
use strict;
use warnings;
use Carp;
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
    $self->response->body($body);
    return $self;
}

sub redirect {
    my($self, @arg) = @_;
    $self->response->redirect(q{/});
    return $self if ! @arg;
    my($session) = @arg;
    if (ref $session) {
        $self->response->cookie('ssid' => {
            'value' => $session->session_id,
        });
    }
    else {
        $self->response->cookie('ssid' => {
            'value' => q{},
            'expires' => 978307200, # 1-Jan-2001 00:00:00 GMT
        });
    }
    return $self;
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
    $self->response->body($body);
    return $self;
}

sub redirect {
    my($self) = @_;
    $self->response->redirect('/signin');
    return $self;
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

0.002

=head1 SYNOPSYS

    my $application = require 'app.psgi';

=head1 DESCRIPTION

=head1 METHODS

=over

=over

=item C<< $class->new(%init_values) >>

=item C<< __PACKAGE__->mk_accessors(@names) >>

=item C<< $webcomponent->escape_xml($string) >>

=item C<< $webcomponent->escape_text($string) >>

=item C<< $webcomponent->decode_uri($url_encoded) >>

=item C<< $webcomponent->encode_uri($string) >>

=item C<< $webresponse->code([$numeric]) >>

=item C<< $webresponse->body([$string]) >>

=item C<< $webresponse->controller([$string]) >>

=item C<< $webresponse->content_type([$string]) >>

=item C<< $webresponse->content_length([$numeric]) >>

=item C<< $webresponse->replace($key, $values) >>

=item C<< $webresponse->redirect($location, [$code]) >>

=item C<< $webresponse->header([$name, [$value]]) >>

=item C<< $webresponse->cookie([$name, [\%value]]) >>

=item C<< $webresponse->finalize($env) >>

=item C<< $webresponse->finalize_cookie >>

=item C<< WebResponder->psgi_application >>

=item C<< $webresponder->env([$env]) >>

=item C<< $webresponder->response([$response]) >>

=item C<< $webresponder->detach($other_class) >>

=item C<< $webresponder->bad_request >>

=item C<< $webresponder->not_found >>

=item C<< $webresponder->method_not_allowed([$allow]) >>

=item C<< $webresponder->internal_server_error >>

=item C<< $webresponder->scan_form_urlencoded($string) >>

=item C<< $webresponder->scan_cookie($string) >>

=item C<< $webresponder->check(\%param, \%constraint) >>

=item C<< UserSession->new_mock(%init_value) >>

=item C<< UserSession->find($session_id) >>

=item C<< UserSession->signin($username, $password) >>

=item C<< UserSession->signout($session_id) >>

=item C<< $protectedpage->request_session_id >>

=item C<< $toppageuser->rendar >>

=item C<< $toppage->rendar >>

=item C<< $toppage->redirect([$session]) >>

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

