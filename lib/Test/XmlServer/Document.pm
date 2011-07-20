package Test::XmlServer::Document;
use strict;
use warnings;
use Carp;

# $Id$
use version; our $VERSION = '0.001';

my $ID = qr{[A-Za-z_:][A-Za-z0-9_:-]*}msx;
my $SP = qr{[\x20\t\n\r]}msx;
my $NL = qr{(?:\r\n?|\n)}msx;
my $ATTR = qr{($SP+)($ID)($SP*=$SP*\")([^<>\"]*)(\")}msx;
my $CACHE = 3;

sub new {
    my($class, $xml) = @_;
    if (! defined $xml) {
        $xml = q{};
    }
    return $class->_compose_document($xml);
}

sub find {
    my($self, $selector) = @_;
    if (exists $self->[$CACHE]{$selector}) {
        return @{$self->[$CACHE]{$selector}};
    }
    $self->[$CACHE]{$selector} = [];
    my @path = (undef);
    my @todo = ($self, 0);
    while (@todo) {
        pop @path;
        my $i = pop @todo;
        my $node = pop @todo;
         while ($i < @{$node->child_nodes || []}) {
            my $child = $node->child_nodes->[$i++];
            next if ! ref $child;
            next if $child->[0][1] ne q{<};
            if ($self->_match_selector_path($selector, @path, $child)) {
                push @{$self->[$CACHE]{$selector}}, $child;
            }
            next if $child->[0][5] eq q{/>};
            my($cont_node, $cont_i) = ($node, $i);
            ($node, $i) = ($child, 0);
            push @path, $child;
            push @todo, $cont_node, $cont_i;
        }
    }
    return @{$self->[$CACHE]{$selector}};
}

sub child_nodes { return shift->[1] }

sub tagname {
    my($self) = @_;
    # [[q{ }, q{<}, q{div}, [attribute...], q{ }, q{>}, "\n"], [], [..]]
    return $self->[0][2];
}

sub attribute {
    my($self, @arg) = @_;
    my $attr = $self->[0][3];
    # [(' ', 'name', '="', 'value', '"') ...]
    my @indecs = map { $_ * 5 } 0 .. -1 + int @{$attr} / 5;
    if (! @arg) {
        return map { @{$attr}[$_ + 1, $_ + 3] } @indecs;
    }
    my $name = shift @arg or return;
    for my $i (@indecs) {
        if ($attr->[$i + 1] eq $name) {
            return $attr->[$i + 3];
        }
    }
    return;
}

sub _match_selector_path {
    my($self, $selector, @path) = @_;
    my @selist = split /\s+/msx, $selector;
    return if ! (pop @path)->_match_selector_term(pop @selist);
    my $selector_term = shift @selist or return 1;
    for my $element (@path) {
        next if ! $element->_match_selector_term($selector_term);
        $selector_term = shift @selist or return 1;
    }
    return;
}

sub _match_selector_term {
    my($self, $selector_term) = @_;
    my $mine_tagname = $self->tagname;
    if ($selector_term =~ m{\A
        (?:($ID) (?:\#($ID)|[.]([a-zA-Z0-9_:-]+)|\[($ID)="([^"]+)"\])?
        |  [*]? (?:\#($ID)|[.]([a-zA-Z0-9_:-]+)|\[($ID)="([^"]+)"\])
        )
    \z}msxo) {
        my($tagname, $id, $classname) = ($1, $2 || $6, $3 || $7);
        my($attr, $value) = $id ? ('id', $id)
            : $classname ? ('class', $classname)
            : ($4 || $8, $5 || $9);
        return (! $tagname || $mine_tagname eq $tagname)
            && (! $attr
                || (0 <= index $self->attribute($attr) || q{}, $value));
    }
    return;
}

sub _compose_document {
    my($class, $xml) = @_;
    my $document = bless [
        [q{}, q{}, q{}, [], q{}, q{}, q{}], [], undef, {},
    ], $class;
    my $node = $document;
    my @ancestor;
    while($xml !~ m{\G\z}msxgc) {
        my($t) = $xml =~ m{\G([\x20\t]*)}msxogc;
        if ($xml =~ m{
            \G<
            (?: (?: ($ID) (.*?) ($SP*) (/?>)
                |   /($ID) ($SP*) >
                |   ([?].*?[?]|[!](?:--.*?--|\[CDATA\[.*?\]\]|DOCTYPE[^>]+?))>
                )
                ($NL*)
            )?
        }msxogc) {
            my($id1, $t2, $sp3, $gt4, $id5, $sp6, $t7, $nl8)
                = ($1, $2, $3, $4, $5, $6, $7, $8);
            if ($id1) {
                my $attr = [$t2 =~ m{$ATTR}msxog];
                my $element = bless [
                    [$t, q{<}, $id1, $attr, $sp3, $gt4, $nl8],
                ], $class;
                push @{$node->[1]}, $element;
                next if $gt4 eq q{/>};
                push @{$element}, [];
                push @ancestor, $node;
                $node = $element;
                next;
            }
            elsif ($id5) {
                my $id1 = $node->[0][2];
                $id5 eq $id1 or croak "<$id1> ne </$id5>";
                push @{$node}, [$t, q{</}, $id5, [], $sp6, q{>}, $nl8];
                $node = pop @ancestor;
                next;
            }
            elsif ($t7) {
                push @{$node->[1]}, bless [
                    [$t, q{}, q{}, [], "<$t7>", q{}, $nl8],
                ], $class;
                next;
            }
            else {
                $t .= q{<};
            }
        }
        $t .= $xml =~ m{\G([^<\r\n]+$NL*|$NL+)}msxogc ? $1 : q{};
        if (@{$node->[1]} == 0 || ref $node->[1][-1]) {
            push @{$node->[1]}, $t;
        }
        else {
            $node->[1][-1] .= $t;
        }
    }
    @ancestor == 0 or croak 'is not formal XML.';
    return $document;
}

1;

__END__

=pod

=head1 NAME

Test::XmlServer::Document - XML document tree.

=head1 VERSION

0.001

=head1 SYNOPSIS

    use Test::XmlServer::Document;

=head1 DESCRIPTION

=head1 METHODS

=over

=item C<< new($xhtml) >>

Constructs document tree from given XHTML text.

=item C<< find($selector) >>

Finds elements in the document matching CSS like selector.

=item C<< tagname >>

Gets tagname of the element.

=item C<< attribute($name) >>

Gets attribute value of the element.

=item C<< child_nodes >>

Gets child_nodes of the element as an arrayref.

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
