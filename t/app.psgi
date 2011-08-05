package DemoApplication;
use strict;
use warnings;

our $VERSION = '0.006';
# $Id$
# DemoApplication - demonstration for PSGI application of Test::XmlServer

package WebComponent;
use strict;
use warnings;
use Carp;
use Time::Piece;

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
    return q{} if $string eq q{};
    $string =~ s{(?:([<>"'\\])|\&(?:($AMP);)?)}{
        $1 ? $XML_SPECIAL{$1} : $2 ? qq{\&$2;} : '&amp;'
    }egmosx;
    return $string;
}

sub escape_xmlall {
    my($self, $string) = @_;
    $string =~ s{([&<>"'\\])}{ $XML_SPECIAL{$1} }egmosx;
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

sub escape_uriall {
    my($self, $uri) = @_;
    if (utf8::is_utf8($uri)) {
        $uri = Encode::encode('utf-8', $uri);
    }
    $uri =~ s{([^a-zA-Z0-9_\-./])}{ sprintf '%%%02X', ord $1 }egmosx;
    return $uri;
}

sub decode_uri {
    my($self, $string) = @_;
    $string =~ tr/+/ /;
    $string =~ s{%([0-9A-F]{2})}{chr hex $1}iegmsx;
    return $string;
}

my @WEEK_NAME = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
my @WEEK_ABBR = qw(Sun Mon Tue Wed Thu Fri Sat);
my @MONTH_NAME = qw(January February March April May June July August
    September October November December);
my @MONTH_ABBR = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my @AMPM_NAME = qw(AM PM);

sub strftime {
    my($class, $fmt, @arg) = @_;
    $fmt ||= '%Oc';
    $fmt =~ s/%c/%a %b %2d %H:%M:%S %Y/gmsx; # ANSI C's asctime() format
    $fmt =~ s/%Oc/%a, %d %b %Y %H:%M:%S GMT/gmsx; # RFC1123
    $fmt =~ s/%F/%Y-%m-%d/gmsx;
    $fmt =~ s/%R/%H:%M/gmsx;
    $fmt =~ s/%T/%H:%M:%S/gmsx;
    my $is_utc = $fmt =~ m{GMT|UTC|[+-]00:?00|%-?[0-9]*[mdMS]Z\b};
    my %t;
    $t{'s'} = $class->decode_datetime(@arg);
    @t{qw(S M H d _b _y _a j _dst)} =
        $is_utc ? CORE::gmtime $t{'s'} : CORE::localtime $t{'s'};
    @t{qw(Y m w)} = ($t{'_y'} + 1900, $t{'_b'} + 1, $t{'_a'});
    @t{qw(y C)} = ($t{'Y'} % 100, int $t{'Y'} / 100);
    @t{qw(I _p)} = ($t{'H'} % 12 || 12, $t{'H'} < 12 ? 0 : 1);
    @t{qw(A a)} = ($WEEK_NAME[$t{'_a'}], $WEEK_ABBR[$t{'_a'}]);
    @t{qw(B b)} = ($MONTH_NAME[$t{'_b'}], $MONTH_ABBR[$t{'_b'}]);
    @t{qw(P p)} = ($AMPM_NAME[$t{'_p'}], lc $AMPM_NAME[$t{'_p'}]);
    if ($is_utc) {
        @t{qw(Z z Oz)} = ('UTC', '+0000', 'Z');
    }
    else {
        @t{qw(Oz z Z)} = unpack 'a5a5a*', localtime->strftime('%z%z%Z');
        substr $t{'Oz'}, 3, 0, q{:};
    }
    my %p = ('Y' => '%04d', 'j' => '%d', 'w' => '%d', 's' => '%d');
    $fmt =~ s{
        \%
        (?: (\%)
        |   (-?[0-9]*)(?:([SMHIdmYyCjws])) # 2 3
        |   ([aAbBpPzZ]|Oz) # 4
        |   \(([^\)]*)\)([abp]) # 5 6
        )
    }{
          $1 ? $1
        : $4 ? $t{$4}
        : $6 ? (split /\s/msx, $5)[$t{"_$6"}]
        : (sprintf $2 ne q{} ? "%$2d" : $p{$3} ? $p{$3} : '%02d', $t{$3})
    }egmsx;
    return $fmt;
}

my $APART = 'S(?:at|un)|Mon|Wed|T(?:hu|ue)|Fri';
my $BPART = 'A(?:pr|ug)|Dec|Feb|J(?:an|u[nl])|Ma[ry]|Nov|Oct|Sep';
my $TPART = '([0-9]{2})[:]([0-9]{2})[:]([0-9]{2})';
my %B2MONTH = map { $MONTH_ABBR[$_] => $_ } 0 .. $#MONTH_ABBR;

sub decode_datetime {
    my($class, $timestamp) = @_;
    return $timestamp->epoch if eval{ $timestamp->can('epoch') };
    return time if ! defined $timestamp || $timestamp eq 'now';
    return $timestamp if $timestamp =~ m/\A[0-9]+(?:[.][0-9]+)?\z/msx;
    if ($timestamp =~ m{
        \A(?: ([0-9]{4})[/-]([0-9]{2}) (?:[/-]([0-9]{2}))?
            (?: [T\x20] ([0-9]{2})[:]([0-9]{2}) (?:[:]([0-9]{2})(?:[.][0-9]+)?)?)?
            (Z|\x20*(?:GMT|UTC|[+-]00[:]?00))?
        |   ([0-9]{2})[:]([0-9]{2}) (?:[:]([0-9]{2})(?:[.][0-9]+)?)?
        )\z
    }msx) {
        my($y, $mon, $d) = ($1 || 2000, $2 || 1, $3 || 1);
        my($h, $min, $s) = ($4 || $8 || 0, $5 || $9 || 0, $6 || $10 || 0);
        return defined $7 ? timegm($s, $min, $h, $d, $mon - 1, $y - 1900)
            : timelocal($s, $min, $h, $d, $mon - 1, $y - 1900);
    }
    if (my($d, $b, $y, $h, $min, $s, $zone) = $timestamp =~ m{
        \b(?:${APART}),\x20*([0-9]{1,2})\x20(${BPART})\x20([0-9]{4})\x20${TPART}
        (?:\x20+(GMT|UTC|[+-]0000))?
    }msx) {
        return defined $zone ? timegm($s, $min, $h, $d, $B2MONTH{$b}, $y - 1900)
            : timelocal($s, $min, $h, $d, $B2MONTH{$b}, $y - 1900);        
    }
    if (my($b, $d, $h, $min, $s, $y, $zone) = $timestamp =~ m{
        \b(?:${APART})\x20(${BPART})\x20+([0-9]{1,2})\x20${TPART}\x20([0-9]{4})
        (?:\x20+(GMT|UTC|[+-]0000))?
    }msx) {
        return defined $zone ? timegm($s, $min, $h, $d, $B2MONTH{$b}, $y - 1900)
            : timelocal($s, $min, $h, $d, $B2MONTH{$b}, $y - 1900);        
    }
    croak 'invalid time stamp format.';
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
    my $result = [$self->code, [], []];
    for my $name ($self->header) {
        next if $name !~ m/\A[A-Za-z][A-Za-z0-9]+(?:[-][A-Za-z0-9]+)*\z/msx;
        if (lc $name eq 'location') {
            push @{$result->[1]}, $name, $self->escape_uri($self->header($name));
            next;
        }
        for my $value ($self->header($name)) {
            next if utf8::is_utf8($value);
            next if $value =~ tr/\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\xff//;
            push @{$result->[1]}, $name, 
                join "\x0d\x0a ", split /[\r\n]+[\t\040]*/msx, $value;
        }
    }
    if (defined $self->body) {
        $result->[2][0] = $self->body;
        if (utf8::is_utf8($result->[2][0])) {
            $result->[2][0] = Encode::encode('UTF-8', $result->[2][0]);
        }
    }
    return $result;
}

sub finalize_cookie {
    my($self) = @_;
    for my $key ($self->cookie) {
        my $cookie = $self->cookie($key);
        my @dough = (
            $self->escape_uriall($cookie->{'name'})
            . q{=} . $self->escape_uriall($cookie->{'value'}),
            ($cookie->{'domain'} ?
                'domain=' . $self->escape_uriall($cookie->{'domain'}) : ()),
            ($cookie->{'path'}) ?
                'path=' . $self->escape_uriall($cookie->{'path'}) : (),
        );
        if (defined $cookie->{'expires'}) {
            my $t = $cookie->{'expires'};
            push @dough, $self->strftime('expires=%a, %d-%b-%Y %T GMT', $t);
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
    qw(controller session_controller responder_class),
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

sub bad_request { return shift->error_response('Bad Request', 400) }
sub not_found { return shift->error_response('Not Found', 404) }
sub length_required { return shift->error_response('Length Required', 411) }

sub request_entity_too_large {
    return shift->error_response('Request Entity Too Large', 413);
}

sub internal_server_error {
    return shift->error_response('Internal Server Error', 500);
}

sub method_not_allowed {
    my($self, $allow) = @_;
    $self->response->header('Allow' => $allow || 'GET,HEAD');
    return $self->error_response('Method Not Allowed', 405);
}

sub error_response {
    my($self, $errstr, $code) = @_;
    $errstr = $self->escape_xml($errstr || 'Error');
    use utf8;
    my $body = <<"XHTML";
<!DOCTYPE html>
<html>
<head><meta charset="utf-8" /><title>$errstr</title></head>
<body><h1>$errstr</h1></body>
<p><a href="/">return top page</a>.
</html>
XHTML
    $self->response->code($code || 500);
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

# in memory multipart/form-data splitter for small size request entity.
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

package Text::CurlyCurly;
use strict;
use warnings;
use Carp;
use Encode;
use parent qw(-norequire WebComponent);

{
    my $MTIME = 9;

    my %_template;
    my %_template_mtime;

    sub rendar {
        my($class, $name, $h) = @_;
        if (! exists $_template{$name}
            || (stat $name)[$MTIME] > $_template_mtime{$name}
        ) {
            my $src = decode('UTF-8', _read_file($name));
            my $template = $class->new({'source' => $src});
            $_template{$name} = $template;
            $_template_mtime{$name} = time;
        }
        return $_template{$name}->apply($h)->result;
    }
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

our %FILTER_VOCABURARY = (
    'escape' => 'escape_xml',
    'html' => 'escape_xml', 'xml' => 'escape_xml', 'text' => 'escape_xml',
    'htmlall' => 'escape_xmlall', 'xmlall' => 'escape_xmlall',
    'uri' => 'escape_uri', 'url' => 'escape_uri',
    'uriall' => 'escape_uriall', 'urlall' => 'escape_uriall',
    'raw' => '_filter_raw',
    'default' => '_filter_default',
    'nl2br' => '_filter_nl2br',
    'strip' => '_filter_strip',
    'strip_tag' => '_filter_strip_tag',
    'date_format' => '_filter_date_format',
);
our %FILTER_ESCAPER = map { $_ => $_ } qw(
    escape_xml escape_xmlall escape_uri escape_uriall _filter_raw
);

__PACKAGE__->mk_accessors(qw(source perl_source perl_code result error));

sub _filter_raw { return $_[1] }

sub _filter_default {
    my($class, $string, $default) = @_;
    return defined $string && $string ne q{} ? $string : $default;
}
sub _filter_strip {
    my($class, $string) = @_;
    $string =~ tr/\x00-\x09\x0b-\x1f\x7f//d;
    $string =~ tr/ / /s;
    $string =~ s{(?:\x20*(?:\r\n?|\n))+}{\n}gmsx;
    return $string;
}

sub _filter_strip_tag {
    my($class, $string) = @_;
    $string =~ s{<[^>]*>}{}gmsx;
    return $string;
}

sub _filter_nl2br {
    my($class, $string) = @_;
    $string =~ s{(\r\n?|\n)}{<br />$1}gmsx;
    return $string;
}

sub _filter_date_format {
    my($class, $timestamp, $fmt) = @_;
    return $class->strftime($fmt || '%FT%T', $timestamp);
}

sub apply {
    my($self, $param) = @_;
    if (! $self->perl_code) {
        eval { $self->make_perl_code };
    }
    my $code = $self->perl_code or croak $self->error('lost perl_code');
    ref $code eq 'CODE' or croak $self->error('invalid perl_code');
    my $result;
    if (eval {
        $result = $code->($self, $param);
        1;
    }) {
        $self->result($result);
        $self->error(undef);
    }
    else {
        $self->result(undef);
        croak $self->error($@);
    }
    return $self;
}

sub make_perl_code {
    my($self) = @_;
    if (! $self->perl_source) {
        eval { $self->make_perl_source };
    }
    my $source = $self->perl_source or croak $self->error('lost perl_source');
    my $code = eval $source; ## no critic qw(StringyEval)
    die $self->error($@) if $@; ## no critic qw(Carping)
    $self->error(undef);
    $self->perl_code($code);
    return $self;
}

sub make_perl_source {
    my($self) = @_;
    my $s = $self->source or croak $self->error('lost source');
my $tmpl = <<'TMPL';
sub{
my($c,$h)=@_;
use utf8;
my$t='';
TMPL
    my($t_eof, $t_rem, $t_end, $t_if, $t_for, $t_subst) = (2 .. 7);
    while ($s =~ m{\G
        (.*?)
        (?: (\z)
        |   \{\{\s*
            (?: (\#)
            |   (end) \s*
            |   if \s* ([a-z][a-z0-9_]*) \s*
            |   for \s* ([a-z][a-z0-9_]*) \s*
            |   ([a-z][a-z0-9_]*) \s*
                ((?:\|\s*[a-z][a-z0-9_]*\s*(?:[:]\s*(?:"[^"]*"|'[^']*')\s*)*)*)
            )
            [^\{\}]*
            \}\}\n?
        )
    }gmosx) {
        my($token, $var, $modifier) = ($#-, $7 ? ($7, $8 || q{}) : ($+));
        if ($1 ne q{}) {
            my $const = $1;
            $const =~ s/'/\\'/gmsx;
$tmpl .= <<"TMPL";
\$t.='$const';
TMPL
        }
        last if $token == $t_eof;
        next if $token == $t_rem;
        if ($token >= $t_subst) {
            my $subst = $self->_modifier("\$h->{'$var'}", $modifier);
$tmpl .= <<"TMPL";
if(exists\$h->{'$var'}&&defined\$h->{'$var'}){
\$t.=$subst;
}
TMPL
            next;
        }
        if ($token == $t_if) {
$tmpl .= <<"TMPL";
if(exists\$h->{'$var'}&&\$h->{'$var'}){
my\$g=ref\$h->{'$var'}eq'HASH'?\$h->{'$var'}:{};
for my\$h(\$g){
TMPL
            next;
        }
        if ($token == $t_for) {
$tmpl .= <<"TMPL";
if(exists\$h->{'$var'}&&defined\$h->{'$var'}){
my\$a=ref\$h->{'$var'}eq'ARRAY'?\$h->{'$var'}:[\$h->{'$var'}];
for my\$i(0..\$#{\$a}){
my\$h={'nth'=>\$i+1,'odd'=>(\$i%2==0),'even'=>(\$i%2==1),'halfway'=>\$i<\$#{\$a},\%{\$a->[\$i]}};
TMPL
            next;
        }
        if ($token == $t_end) {
$tmpl .= <<'TMPL';
}}
TMPL
            next;
        }
    }
$tmpl .= <<'TMPL';
return $t;
}
TMPL
    $self->perl_source($tmpl);
    return $self;
}

sub _modifier {
    my($self, $x, $modifier) = @_;
    my $esc = 0;
    while ($modifier =~ m{
        \| \s* ([a-z][a-z0-9_]*) \s* ((?:[:] \s* (?:"[^"]*"|'[^']*')\s*)*)
    }gmsx) {
        my $func = $FILTER_VOCABURARY{$1} or next;
        my $string_arg = $2;
        my @arg;
        while ($string_arg =~ m{[:] \s* (?:"([^"]*)"|'([^']*)')}gmsx) {
            my $s = $+;
            $s =~ s/'/\\'/g;
            push @arg, qq{'$s'};
        }
        $x = '$c->' . $func . q{(} . (join q{,}, $x, @arg) . q{)};
        $esc ||= $FILTER_ESCAPER{$func};
    }
    if (! $esc) {
        $x = '$c->' . $FILTER_VOCABURARY{'escape'} . q{(} . $x . q{)};
    }
    return $x;
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
        'template_engine' => 'Text::CurlyCurly',
    ],
    ':TopPage-SignedOut' => ['TopPage::SignedOut',
        'location' => ':TOPPAGE_LOCATION',
        'template' => 't/template/toppage-signedout.html',
        'template_engine' => 'Text::CurlyCurly',
    ],
    ':SigninPage' => ['SigninPage',
        'location' => '/signin',
        'template' => 't/template/signin.html',
        'template_engine' => 'Text::CurlyCurly',
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

0.004

=head1 SYNOPSYS

    my $application = require 'app.psgi';

=head1 DESCRIPTION

=head1 METHODS

=over

=item C<< $class->new(%init_values) >>

=item C<< __PACKAGE__->mk_accessors(@names) >>

=item C<< $webcomponent->escape_xml($string) >>

    & to &amp;
    < to &lt;
    > to &gt;
    " to &quot;
    ' to &#39;
    \ to &#92;

    &foo; to &foo;
    &#55; to &#55;
    &#x37; to &#x37;

=item C<< $webcomponent->escape_xmlall($string) >>

    & to &amp;
    < to &lt;
    > to &gt;
    " to &quot;
    ' to &#39;
    \ to &#92;

    &foo; to &amp;foo;
    &#55; to &amp;#55;
    &#x37; to &amp;#x37;

=item C<< $webcomponent->escape_uri($string) >>

    http://example.net/foo/bar?a=1&b=2#baz
      to http://example.net/foo/bar?a=1&b=2#baz

    [^a-zA-Z0-9_\-./:&;=+\#?~] to %XX

    control characters: [\x00-\x1f\x7f] to %XX
    symbol signs: [ !"$%'()*,<>\@\[\\\]^`{|}] to %XX
    wide characters \x{UUUU} to %XX%XX%XX (encode utf-8)

=item C<< $webcomponent->escape_uriall($string) >>

    http://example.net/foo/bar?a=1&b=2#baz
      to http%3A//example.net/foo/bar%3Fa%3D1%26b%3D2%23baz

    [^a-zA-Z0-9_\-./] to %XX

    control characters: [\x00-\x1f\x7f] to %XX
    symbol signs: [ !"#\$%&'()*+,:;<=>?\@\[\\\]^`{|}~] to %XX
    wide characters \x{UUUU} to %XX%XX%XX (encode utf-8)

=item C<< $webcomponent->decode_uri($url_encoded) >>

=item C<< $webcomponent->strftime($format, $epoch) >>

Similar as POSIX's strftime(3) function.
When $format =~ /GMT|UTC|[+-]00:?00|%-?[0-9]*[mdMS]Z\b/,
use gmtime $epoch, otherwise localtime $epoch internally.

format:
        %% - % itself
        %c - '%a %b %2d %H:%M:%S %Y' ANSI C's asctime() format
        %Oc - '%a, %d %b %Y %H:%M:%S GMT' RFC1123
        %F - '%Y-%m-%d'
        %T - '%H:%M:%S'

        %-?[0-9]*Y - 2000 year
        %-?[0-9]*C - 20 century
        %-?[0-9]*y - 00 year % 100
        
        %-?[0-9]*m - 01 month
        %b - Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec
        %B - January February March April May June July August
             September October November December
        %(ja fe mr ap my jn jl au se oc no de)b - custom month name
        
        %-?[0-9]*d - 01 month day
        
        %-?[0-9]*H - 00 24 hour
        %-?[0-9]*I - 12 12 hour
        %p - am pm
        %P - AM PM
        %(a p)p - cutom am/pm
        
        %-?[0-9]*M - 00 min.
        %-?[0-9]*S - 00 sec.
        
        %-?[0-9]*j - year days.
        
        %a - Sun Mon Tue Wed Thu Fri Sat
        %A - Sunday Monday Tuesday Wednesday Thursday Friday Saturday
        %(su mo tu we th fr st)a - custom week name
        %-?[0-9]*w - week number

        %Z - JST timezone
        %z - +0900 timezone offset for RFC1123
        %Oz - +09:00 timezone offset for ISO8601

=item C<< $webcomponent->decode_datetime($timestamp) >>

Gets epoch from various date time string.

    1. DateTime, Time::Piece, or any object that can epoch.
    2. string 'now' or undef.
    3. integer.
    4. '%Y-%m-%d %H:%M:%S' or '%Y-%m-%d %H:%M:%SZ'
    5. '%Y-%m-%dT%H:%M:%S' or '%Y-%m-%dT%H:%M:%SZ'
    6. '%Y-%m-%d %H:%M' or '%Y-%m-%d %H:%MZ'
    7. '%Y-%m-%dT%H:%M' or '%Y-%m-%dT%H:%MZ'
    8. '%Y-%m-%d' or '%Y-%m-%dZ'
    9. '%H:%M:%S' or '%H:%M:%SZ' (assume date is '2000-01-01')
    10. '%a, %d %b %Y %H:%M:%S' or '%a, %d %b %Y %H:%M:%S GMT'
    11. '%a %b %d %H:%M:%S %Y' or '%a %b %d %H:%M:%S %Y GMT'

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

=item C<< $webresponder->error_response($errstr, $code) >>

=item C<< $webresponder->scan_formdata >>

=item C<< $webresponder->split_urlencoded($string) >>

=item C<< $webresponder->split_multipart_formdata($boundary, $string) >>

=item C<< $webresponder->get_request_cookie($string, [$name]) >>

=item C<< $webresponder->check(\%param, \%constraint) >>

=item C<< Text::CurlyCurly->rendar($file_name, $param) >>

render template file name with parameters.

briefs buildin double curly template engine.

    {{ for var }} block {{ end }}  for (@{$param->{var}}) { apply($_) }
    {{ if var }} block {{ end }}   if ($param->{var}) { apply($param->{var}) }
    {{ var }}           substitute escape_xml($param->{var})
    {{ var | html }}    substitute escape_xml($param->{var})
    {{ var | xml }}     substitute escape_xml($param->{var})
    {{ var | htmlall }} substitute escape_xmlall($param->{var})
    {{ var | xmlall }}  substitute escape_xmlall($param->{var})
    {{ var | uri }}     substitute escape_uri($param->{var})
    {{ var | uriall }}  substitute escape_uriall($param->{var})
    {{ var | raw }}     substitute $param->{var}
    {{ var | html | nl2br }}    substitute "\n" to "<br />\n" last.
    {{ var | strip }}           strip whitespaces.
    {{ var | strip_tag }}       strip all HTML tags.
    {{ var | default : 'foo' }} substitute to 'foo' if var is blank
    {{ var | date_format : '%F %T' }} substitute strftime
    {{ # comment }}     comment out

=item C<< $textcurly->source($source_string) >>

=item C<< $textcurly->perl_source($perl_source_string) >>

=item C<< $textcurly->perl_code($perl_coderef) >>

=item C<< $textcurly->result >>

=item C<< $textcurly->error >>

=item C<< $textcurly->apply($param) >>

=item C<< $textcurly->make_perl_source >>

=item C<< $textcurly->make_perl_code >>

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

