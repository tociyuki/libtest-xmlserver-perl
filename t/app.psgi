package DemoApplication;
use strict;
use warnings;

our $VERSION = '0.003';
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

sub escape_uri {
    my($self, $uri) = @_;
    if (utf8::is_utf8($uri)) {
        $uri = Encode::encode('utf-8', $uri);
    }
    $uri =~ s{([^a-zA-Z0-9_\-./:&;=+\#?~])}{ sprintf '%%%02X', ord $1 }egmosx;
    return $uri;
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

__PACKAGE__->mk_accessors('code', 'body', 'responder_class');

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
        $env->{'psgi.errors'}->print("No status code\n");
        my $responder = $self->responder_class->new(
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
        next if $name !~ m/\A[A-Za-z][A-Za-z0-9]+(?:[-][A-Za-z0-9]+)*\z/msx;
        if (lc $name eq 'location') {
            push @{$response->[1]}, $name, $self->encode_uri($self->header($name));
            next;
        }
        for my $value ($self->header($name)) {
            next if utf8::is_utf8($value);
            next if $value =~ tr/\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\xff//;
            push @{$response->[1]}, $name, 
                join "\x0d\x0a ", split /[\r\n]+[\t\040]*/msx, $value;
        }
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

__PACKAGE__->mk_accessors(
    qw(env response dependency location template_engine template),
    qw(controller session_controller),
);

my %METHODS = (
    'HEAD' => 'get',
    'GET' => 'get',
    'POST' => 'post',
    'PUT' => 'put',
    'DELETE' => 'del',
);

sub psgi_application {
    my($class, $responder_list, $dependency) = @_;
    return sub{
        my($env) = @_;
        my $responder = $class->new(
            'env' => $env,
            'response' => WebResponse->new('responder_class' => $class),
            'dependency' => $dependency,
        );
        for my $attribute (qw(controller session_controller)) {
            my $name = ":$attribute";
            if (exists $dependency->{$name}) {
                $responder->$attribute($responder->component($name));
            }
        }
        $responder->response->content_type('text/html; charset=utf-8');
        # based on Try::Tiny
        if (eval{
            my $path = $env->{'PATH_INFO'} || '/';
            my $method = $METHODS{$env->{'REQUEST_METHOD'} || 'UNKOWN'};
            $method ||= 'method_not_allowed';
            $responder->not_found;
            for (0 .. -1 + int @{$responder_list} / 2) {
                my $pattern = $responder_list->[$_ * 2];
                my $name = $responder_list->[$_ * 2 + 1];
                my $page_responder = $responder->forward($name);
                if (my @param = $path =~ m{\A$pattern\z}msx) {
                    if ($#- < 1) {
                        @param = ();
                    }
                    if (! $page_responder->can($method)) {
                        $method = 'method_not_allowed';
                    }
                    $page_responder->response->code(200);
                    $page_responder->response->body(undef);
                    $responder = $page_responder->$method(@param);
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

sub forward {
    my($self, $name) = @_;
    my $responder = $self->component($name);
    $responder->env($self->env);
    $responder->response($self->response);
    $responder->response->responder_class(ref $responder);
    $responder->dependency($self->dependency);
    $responder->controller($self->controller);
    $responder->session_controller($self->session_controller);
    return $responder;
}

sub component {
    my($self, $name) = @_;
    return $name->() if ref $name eq 'CODE';
    return $name if ! defined $name || ref $name;
    my $dict = $self->dependency || {};
    return $name if ! exists $dict->{$name};
    my $dependency = $dict->{$name};
    return $dependency if ref $dependency ne 'ARRAY';
    my($class, @attr_list) = @{$dependency};
    return \@attr_list if $class eq 'ARRAY';
    return +{@attr_list} if $class eq 'HASH';
    if (! eval{ $class->can('new') }) {
        eval "require $class;"; ## no critic qw(StringyEval)
        die $@ if $@;
    }
    my $obj = $class->new;
    for (0 .. -1 + int @attr_list / 2) {
        my $i = $_ * 2;
        my($attr, $value) = @attr_list[$i, $i + 1];
        eval{ $obj->can($attr) }
            or croak "class $class cannot $attr.";
        $obj->$attr($self->component($value));
    }
    return $obj;
}

sub bad_request {
    my($self) = @_;
    use utf8;
    my $body = <<'XHTML';
<!DOCTYPE html>
<html>
<head><meta encoding="utf-8" /><title>Bad Request</title></head>
<body><h1>Bad Request</h1></body>
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
<head><meta encoding="utf-8" /><title>Not Found</title></head>
<body><h1>Not Found</h1></body>
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
<head><meta encoding="utf-8" /><title>Not Found</title></head>
<body><h1>Not Found</h1></body>
</html>
XHTML
    $self->response->code(405);
    $self->response->header('Allow' => $allow);
    $self->response->body($body);
    return $self;
}

sub length_required {
    my($self) = @_;
    use utf8;
    my $body = <<'XHTML';
<!DOCTYPE html>
<html>
<head><meta encoding="utf-8" /><title>Length Required</title></head>
<body><h1>Length Required</h1></body>
</html>
XHTML
    $self->response->code(411);
    $self->response->body($body);
    return $self;
}

sub request_entity_too_large {
    my($self) = @_;
    use utf8;
    my $body = <<'XHTML';
<!DOCTYPE html>
<html>
<head><meta encoding="utf-8" /><title>Request Entity Too Large</title></head>
<body><h1>Request Entity Too Large</h1></body>
</html>
XHTML
    $self->response->code(413);
    $self->response->body($body);
    return $self;
}

sub internal_server_error {
    my($self) = @_;
    use utf8;
    my $body = <<'XHTML';
<!DOCTYPE html>
<html>
<head><meta encoding="utf-8" /><title>Internal Server Error</title></head>
<body><h1>Internal Server Error</h1></body>
</html>
XHTML
    $self->response->code(500);
    $self->response->body($body);
    return $self;
}

sub scan_formdata {
    my($self) = @_;
    my $env = $self->env;
    return +{} if $env->{'REQUEST_METHOD'} ne 'POST';
    my $fh = $env->{'psgi.input'};
    read $fh, my($data), $env->{'CONTENT_LENGTH'} or return +{};
    my $content_type = $env->{'CONTENT_TYPE'};
    if ($content_type =~ m{\Aapplication/x-www-form-urlencoded\b}msx) {
        return $self->split_urlencoded($data);
    }
    elsif ($content_type =~ m{
        \Amultipart/form-data;.*\bboundary=(?:"(.+?)"|([^;]+))
    }msx) {
        return $self->split_multipart_formdata($+, $data);
    }
    return +{};
}

sub split_urlencoded {
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

# in memory multipart/form-data splitter for small request entity.
sub split_multipart_formdata {
    my($self, $boundary, $multipart) = @_;
    my %param;
    if ($multipart =~ m/\G.*?--$boundary\x0d\x0a/gcmsx) {
        while ($multipart =~ m{\G
            (.*?\x0d\x0a)\x0d\x0a(.*?)\x0d\x0a--$boundary(?:\x0d\x0a|--)
        }gcmsx) {
            my($head, $body) = ($1, $2);
            $head =~ s/\x0d\x0a[\x20\t]+/ /gmsx;
            my %header;
            while ($head =~ m/^([^:]+):[\t\x20]*([^\x0d]*?)\x0d\x0a/gmsx) {
                $header{lc $1} = $2;
            }
            my $s = $header{'content-disposition'} or next;
            my %content_disposition;
            while ($s =~ m/\b((?:file)?name)=(?:"(.*?)"|([^;]*))/igmosx) {
                $content_disposition{lc $1} = $+;
            }
            my $name = $content_disposition{'name'} or next;
            if (exists $content_disposition{'filename'}) {
                unshift @{$param{$name}}, +{
                    'filename' => $content_disposition{'filename'},
                    'header' => \%header,
                    'body' => $body,
                };
            }
            else {
                unshift @{$param{$name}}, $body;
            }
        }
    }
    return \%param;
}

sub get_request_cookie {
    my($self, @arg) = @_;
    my $raw_cookie = $self->env->{'HTTP_COOKIE'} || q{};
    my %cookie;
    for my $pair (split /[;]\x20*/msx, $raw_cookie) {
        my @pair = split /=/msx, $pair, 2;
        next if @pair != 2 || $pair[0] eq q{};
        my($k, $v) = map {
            Encode::decode('UTF-8', $self->decode_uri($_))
        } @pair;
        unshift @{$cookie{$k}}, $v;
    }
    return \%cookie if ! @arg;
    my $name = shift @arg;
    return if ! exists $cookie{$name};
    if (wantarray) {
        return @{$cookie{$name}};
    }
    else {
        return if @{$cookie{$name}} != 1;
        return $cookie{$name}[0];
    }
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

{
    package WebResponder::Template;
    use strict;
    use warnings;
    use Carp;
    use Encode;

    my $MTIME = 9;

    my %_template;
    my %_mtime;

    sub rendar {
        my($class, $name, $h) = @_;
        if (! exists $_template{$name}
            || (stat $name)[$MTIME] > $_mtime{$name}
        ) {
            my $src = decode('UTF-8', _read_file($name));
            my $template = WebResponder::Template::Engine->new->parse($src);
            $_template{$name} = $template;
            $_mtime{$name} = time;
        }
        return $_template{$name}->apply($h)->result;
    }

    sub _read_file {
        my($filename) = @_;
        open my($fh), '<', $filename or croak "cannot open '$filename' : $!";
        binmode $fh;
        local $/ = undef;
        my $body = <$fh>;
        close $fh or croak "cannot close '$filename' : $!";
        return $body;
    }
}

package WebResponder::Template::Engine;
use Carp;
use parent qw(-norequire WebComponent);

my %NODE_FILTER = (
    'text' => 'text', 'html' => 'xml', 'xml' => 'xml',
    'uri' => 'uri', 'url' => 'uri', 'raw' => 'raw',
);

__PACKAGE__->mk_accessors(qw(source builder result));

sub apply {
    my($self, $h) = @_;
    if (! $self->builder) {
        $self->compile;
    }
    $self->result($self->builder->($self, $h));
    return $self;
}

sub compile {
    my($self) = @_;
    croak 'empty source' if ! $self->source;
    my $pkg = caller;
    my $code = eval "package $pkg;" . $self->source;
    croak $@ if $@;
    $self->builder($code);
    return $self;
}

sub parse {
    my($self, $s) = @_;
my $tmpl = <<'TMPL';
sub{
my($e, $h) = @_;
use utf8;
my $t = '';
TMPL
    my($t_eof, $t_end, $t_if, $t_for, $t_subst) = (2 .. 6);
    while ($s =~ m{\G
        (.*?)
        (?: (\z)
        |   \{\{ \s*
            (?: (end) \s*
            |   if \s* ([a-z][a-z0-9_]*) \s*
            |   for \s* ([a-z][a-z0-9_]*) \s*
            |   ([a-z][a-z0-9_]*) \s* (?: \| \s* (text|html|xml|uri|url|raw) \s*)?
            )
            \}\} \n?
        )
    }gmosx) {
        my($token, $var, $filter) = ($#-, $7 ? ($6, $7) : ($+));
        if ($1 ne q{}) {
            my $const = $1;
            $const =~ s/'/\\'/gmsx;
$tmpl .= <<"TMPL";
\$t .= '$const';
TMPL
        }
        last if $token == $t_eof;
        if ($token == $t_if) {
$tmpl .= <<"TMPL";
if (exists \$h->{'$var'} && defined \$h->{'$var'}) {
my \$g = ref \$h->{'$var'} eq 'HASH' ? \$h->{'$var'} : {};
for my \$h (\$g) {
TMPL
            next;
        }
        if ($token == $t_for) {
$tmpl .= <<"TMPL";
if (exists \$h->{'$var'} && defined \$h->{'$var'}) {
my \$a = ref \$h->{'$var'} eq 'ARRAY' ? \$h->{'$var'} : [\$h->{'$var'}];
for my \$i (0 .. \$#{\$a}) {
my \$h = {'i' => \$i + 1, 'odd' => (\$i % 2 == 0), 'even' => (\$i % 2 == 1),\%{\$a->[\$i]}};
TMPL
            next;
        }
        if ($token == $t_end) {
$tmpl .= <<'TMPL';
}
}
TMPL
            next;
        }
        if ($token >= $t_subst) {
            $filter = $NODE_FILTER{$filter || 'text'};
$tmpl .= <<"TMPL";
if (exists \$h->{'$var'} && defined \$h->{'$var'}) {
\$t .= \$e->escape_$filter(\$h->{'$var'});
}
TMPL
            next;
        }
    }
$tmpl .= <<'TMPL';
return $t;
}
TMPL
    $self->source($tmpl);
    return $self;
}

package UserSession;
use strict;
use warnings;
use Carp;
use parent qw(-norequire WebComponent);

__PACKAGE__->mk_accessors(qw(session_id user_id user_name user_secret));

sub check_session_id {
    my($class, $s) = @_;
    $s = defined $s ? $s : q{};
    return $s =~ m/\A[a-zA-Z0-9_-]{1,64}\z/msx;
}

sub check_username {
    my($class, $s) = @_;
    $s = defined $s ? $s : q{};
    return $s =~ m/\A[a-zA-Z0-9]+(?:[-_][a-zA-Z0-9]+)*\z/msx
        && 64 >= length $s;
}

sub check_password {
    my($class, $s) = @_;
    $s = defined $s ? $s : q{};
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

sub validate {
    my($self, $password) = @_;
    $self->check_password($password) or return;
    my $secret = $self->user_secret or return;
    return $secret eq crypt $password, $secret;
}

sub user_find {
    my($class, $username) = @_;
    $class->check_username($username) or return [];
    return [] if $username ne 'alice';
    return [$class->new_mock];
}

sub session_find {
    my($class, $id) = @_;
    $class->check_session_id($id) or return [];
    return [] if $id ne 'Rr6Mq4gA1u93KXrHXDuNfFfclFcS5eB9';
    return [$class->new_mock];
}

sub session_insert {
    my($self) = @_;
    defined $self->user_id or return;
    return $self->new_mock;
}

sub session_delete {
    my($self) = @_;
    return;
}

package SessionController;
use strict;
use warnings;
use Carp;
use parent qw(-norequire WebComponent);

__PACKAGE__->mk_accessors(qw(name content selection));

sub signin {
    my($self, $username, $password) = @_;
    $self->selection(undef);
    return if ! $self->content->check_username($username); 
    return if ! $self->content->check_password($password); 
    my $selection = $self->content->user_find($username)->[0] or return;
    $selection->validate($password) or return;
    return $self->selection($selection->session_insert);
}

sub signout {
    my($self) = @_;
    my $session = $self->selection or return;
    return $self->selection($self->selection->session_delete);
}

sub sync_agent {
    my($self, $responder) = @_;
    my $ssid = $responder->get_request_cookie($self->name) or return;
    return $self->selection($self->content->session_find($ssid)->[0]);
}

sub set_agent {
    my($self, $responder) = @_;
    $responder->response->cookie(
        $self->name => {'value' => $self->selection->session_id},
    );
    return $responder;
}

sub unset_agent {
    my($self, $responder) = @_;
    $responder->response->cookie($self->name => {
        'value' => q{},
        'expires' => 978307200, # 1-Jan-2001 00:00:00 GMT
    });
    return $responder;
}

package TopPage;
use strict;
use warnings;
use Carp;
use Encode;
use parent qw(-norequire WebResponder);

sub redirect {
    my($self, @arg) = @_;
    $self->response->redirect($self->location);
    return $self;
}

sub get {
    my($self) = @_;
    if ($self->session_controller->sync_agent($self)) {
        return $self->forward(':TopPage-SignedIn')->rendar;
    }
    else {
        return $self->forward(':TopPage-SignedOut')->rendar;
    }
}

package TopPage::SignedIn;
use strict;
use warnings;
use Carp;
use Encode;
use parent qw(-norequire WebResponder);

sub rendar {
    my($self) = @_;
    $self->response->body(
        $self->template_engine->rendar($self->template, {
            'username' => $self->session_controller->selection->user_name,
        }),
    );
    return $self;
}

sub redirect {
    my($self) = @_;
    $self->response->redirect($self->location);
    $self->session_controller->set_agent($self);
    return $self;
}

package TopPage::SignedOut;
use strict;
use warnings;
use Carp;
use Encode;
use parent qw(-norequire WebResponder);

sub rendar {
    my($self) = @_;
    $self->response->body(
        $self->template_engine->rendar($self->template, {}),
    );
    return $self;
}

sub redirect {
    my($self) = @_;
    $self->response->redirect($self->location);
    $self->session_controller->unset_agent($self);
    return $self;
}

package SigninPage;
use strict;
use warnings;
use Encode;
use parent qw(-norequire WebResponder);

sub form_constraint {
    return +{
        'signin' => ['FLAG', 'NOT NULL'],
        'username' => ['SCALAR', 'NOT NULL', qr/\A[a-zA-Z0-9_-]{1,64}\z/msx],
        'password' => ['SCALAR', 'NOT NULL', qr/\A[\x20-\x7e]{8,80}\z/msx],
    };
}

sub method_not_allowed {
    my($self) = @_;
    return $self->SUPER::method_not_allowed('GET,HEAD,POST');
}

sub rendar {
    my($self) = @_;
    $self->response->body(
        $self->template_engine->rendar($self->template, {}),
    );
    return $self;
}

sub get {
    my($self) = @_;
    if ($self->session_controller->sync_agent($self)) {
        return $self->forward(':TopPage')->redirect;
    }
    return $self->rendar;
}

sub post {
    my($self) = @_;
    if ($self->session_controller->sync_agent($self)) {
        return $self->forward(':TopPage')->redirect;
    }
    my $length = defined $self->env->{'CONTENT_LENGTH'}
        ? $self->env->{'CONTENT_LENGTH'} : $self->length_required;
    $length <= 4096 or $self->request_entity_too_large;
    my $form = $self->check($self->scan_formdata, $self->form_constraint)
        or return $self->rendar;
    my $session = $self->session_controller->signin(
        $form->{'username'}[0], $form->{'password'}[0],
    ) or return $self->rendar;
    return $self->forward(':TopPage-SignedIn')->redirect;
}

package SignoutPage;
use strict;
use warnings;
use parent qw(-norequire WebResponder);

sub get {
    my($self) = @_;
    if (! $self->session_controller->sync_agent($self)) {
        return $self->forward(':TopPage')->redirect;
    }
    $self->session_controller->signout;
    return $self->forward(':TopPage-SignedOut')->redirect;
}

package DemoApplication;
use strict;
use warnings;

my $dependency = {
    ':TOPPAGE_LOCATION' => '/',

    ':session_controller' => ['SessionController',
        'name' => 'ssid',
        'content' => 'UserSession',
    ],

    ':TopPage' => ['TopPage',
        'location' => ':TOPPAGE_LOCATION',
    ],
    ':TopPage-SignedIn' => ['TopPage::SignedIn',
        'location' => ':TOPPAGE_LOCATION',
        'template' => 't/template/toppage-signedin.html',
        'template_engine' => 'WebResponder::Template',
    ],
    ':TopPage-SignedOut' => ['TopPage::SignedOut',
        'location' => ':TOPPAGE_LOCATION',
        'template' => 't/template/toppage-signedout.html',
        'template_engine' => 'WebResponder::Template',
    ],
    ':SigninPage' => ['SigninPage',
        'location' => '/signin',
        'template' => 't/template/signin.html',
        'template_engine' => 'WebResponder::Template',
    ],
    ':SignoutPage' => ['SignoutPage',
        'location' => '/signout',
    ],
};

my $application = WebResponder->psgi_application([
    '/' => ':TopPage',
    '/signin' => ':SigninPage',
    '/signout' => ':SignoutPage',
], $dependency);

__END__

=pod

=head1 NAME

DemoApplication - demonstration for PSGI application of Test::XmlServer

=head1 VERSION

0.003

=head1 SYNOPSYS

    my $application = require 'app.psgi';

=head1 DESCRIPTION

briefs buildin template engine.

    {{ for var }} block {{ end }}
    {{ if var }} block {{ end }}
    {{ var }}         escape_text($h->{$var})
    {{ var | text }}  escape_text($h->{$var})
    {{ var | html }}  escape_xml($h->{$var})
    {{ var | xml }}   escape_xml($h->{$var})
    {{ var | uri }}   encode_uri($h->{$var})
    {{ var | raw }}   $var

=head1 METHODS

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

=item C<< WebResponder->psgi_application(\@controller) >>

=item C<< $webresponder->env([$env]) >>

=item C<< $webresponder->response([$response]) >>

=item C<< $webresponder->dependency([$dependency]) >>

=item C<< $webresponder->location([$location]) >>

=item C<< $webresponder->template_path([$template_path]) >>

=item C<< $webresponder->template_store([$template_store]) >>

=item C<< $webresponder->controller([$controller]) >>

=item C<< $webresponder->session_controller([$session_controller]) >>

=item C<< $webresponder->forward($component_name) >>

=item C<< $webresponder->component($component_name) >>

=item C<< $webresponder->bad_request >>

=item C<< $webresponder->not_found >>

=item C<< $webresponder->method_not_allowed([$allow]) >>

=item C<< $webresponder->length_required >>

=item C<< $webresponder->request_entity_too_large >>

=item C<< $webresponder->internal_server_error >>

=item C<< $webresponder->scan_formdata >>

=item C<< $webresponder->split_urlencoded($string) >>

=item C<< $webresponder->split_multipart_formdata($boundary, $string) >>

=item C<< $webresponder->get_request_cookie($string, [$name]) >>

=item C<< $webresponder->check(\%param, \%constraint) >>

=item C<< $webresponder_storefs->fetch($key) >>

Fetchs from the local file system as a Key-Value store.

=item C<< UserSession->new_mock(%init_value) >>

=item C<< UserSession->find($session_id) >>

=item C<< UserSession->signin($username, $password) >>

=item C<< UserSession->signout($session_id) >>

=item C<< $session_controller->name >>

Name of session cookie.

=item C<< $session_controller->content >>

=item C<< $session_controller->selection >>

=item C<< $session_controller->signin($username, $password) >>

=item C<< $session_controller->signout >>

=item C<< $session_controller->sync_agent($responder) >>

=item C<< $session_controller->set_agent($responder) >>

=item C<< $session_controller->unset_agent($responder) >>

=item C<< $toppage->redirect >>

=item C<< $toppage->get >>

=item C<< $toppage_signedin->rendar($session) >>

=item C<< $toppage_signedin->redirect($session) >>

=item C<< $toppage_signedout->rendar >>

=item C<< $toppage_signedout->redirect >>

=item C<< $signinpage->method_not_allowed >>

=item C<< $signinpage->rendar >>

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

