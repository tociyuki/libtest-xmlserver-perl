package Test::XmlServer::CommonData;
use strict;
use warnings;
use Encode ();

# $Id$
use version; our $VERSION = '0.001';

__PACKAGE__->_mk_attributes(
    \&_scalar_accessor => qw(method path_info code body),
);
__PACKAGE__->_mk_attributes(
    \&_param_accessor => qw(header param),
);

sub new {
    my($class, @arg) = @_;
    if (@arg == 1 && ref $arg[0] eq 'HASH') {
        @arg = %{$arg[0]};
    }
    my $self = bless {
        (ref $class ? %{$class} : ()),
        header => {},
        cookie => {},
        param => {},
    }, ref $class ? ref $class : $class;
    for (0 .. -1 + int @arg / 2) {
        my $i = $_ * 2;
        $self->replace($arg[$i] => $arg[$i + 1]);
    }
    return $self;
}

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

sub formdata {
    my($self) = @_;
    my @q;
    for my $k (sort $self->param) {
        my $ek = _encode_uri($k);
        push @q, map { $ek . q{=} . _encode_uri($_) } $self->param($k);
    }
    return join q{&}, @q;
}

sub _encode_uri {
    my($uri) = @_;
    if (utf8::is_utf8($uri)) {
        $uri = Encode::encode('utf-8', $uri);
    }
    $uri =~ s{([^a-zA-Z0-9_,\-./])}{ sprintf '%%%02X', ord $1 }egmosx;
    return $uri;
}

sub _scalar_accessor {
    my($attr) = @_;
    return sub{
        my($self, @arg) = @_;
        if (@arg) {
            $self->{$attr} = $arg[0];
        }
        return $self->{$attr};
    };
}

sub _param_accessor {
    my($attr) = @_;
    return sub{
        my($self, @arg) = @_;
        @arg or return keys %{$self->{$attr}};
        my $k = shift @arg;
        if (@arg) {
            if ($attr eq 'header' && lc $k ne 'set-cookie') {
                $self->{$attr}{$k}[0] = $arg[0];
            }
            elsif (@arg == 1 && ref $arg[0] eq 'ARRAY') {
                @{$self->{$attr}{$k}} = @{$arg[0]};
            }
            else {
                push @{$self->{$attr}{$k}}, @arg;
            }
        }
        return if ! exists $self->{$attr}{$k};
        return wantarray ? @{$self->{$attr}{$k}} : $self->{$attr}{$k}[-1];
    };
}

sub _mk_attributes {
    my($class, $accessor, @attrlist) = @_;
    for my $attr (@attrlist) {
        no strict 'refs'; ## no critic qw(NoStrict)
        *{"${class}::${attr}"} = $accessor->($attr);
    }
    return;
}

1;

__END__

=pod

=head1 NAME

Test::XmlServer::CommonData - Prepared request, response, and expected data.

=head1 VERSION

0.001

=head1 SYNOPSIS

    use Test::XmlServer::CommonData;

=head1 DESCRIPTION

=head1 METHODS 

=over

=item C<< new(%init_values) >>

=item C<< replace('attribute' => @values) >>
=item C<< replace('attribute' => \@values) >>

=item C<< formdata >>

Creates application/x-www-form-urlencoded formdata text.

=item C<< method([$REQUEST_METHOD]) >>

Gets/Sets request method.

=item C<< path_info([$PATH_INFO]) >>

Gets/Sets path info.

=item C<< code([$STATUS_CODE]) >>

Gets/Sets code of status line.

=item C<< header([$name [=> $value]]) >>

Gets/Sets header.
If both $name and $value omit, returns header names in an array. 

=item C<< param([$name [=> $value]]) >>

Gets/Sets parameters of formdata.
If both $name and $value omit, returns names of parameters in an array. 

=item C<< body >>

=back

=head1 DEPENDENCIES

None.

=head1 AUTHOR

MIZUTANI Tociyuki  C<< <tociyuki@gmail.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2011, MIZUTANI Tociyuki C<< <tociyuki@gmail.com> >>.
All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
