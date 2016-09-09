# Copyright 2015 Applied Research Laboratories, the University of
# Texas at Austin.
#
#    This file is part of XMLStoreContrib.
#
#    XMLStoreContrib is free software: you can redistribute it and/or
#    modify it under the terms of the GNU General Public License as
#    published by the Free Software Foundation, either version 3 of
#    the License, or (at your option) any later version.
#
#    XMLStoreContrib is distributed in the hope that it will be
#    useful, but WITHOUT ANY WARRANTY; without even the implied
#    warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#    See the GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with XMLStoreContrib.  If not, see <http://www.gnu.org/licenses/>.

=begin TML

---+ package Foswiki::Contrib::XMLStoreContrib::Element

Defines a single element of a Foswiki::Contrib::XMLStoreContrib store.
Should be used as a parent class rather than directly.

It is recommended that child classes redefine getAnchorTag() to return
something unique to the plug-in using this package, in order to allow
for the use of HTML anchors that do not conflict with other plug-ins.

=cut

package Foswiki::Contrib::XMLStoreContrib::Element;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func ();    # The plugins API

###############
# XML METHODS #
###############

=begin TML

---++ new($class, $nodeName) -> $Foswiki::Contrib::XMLStoreContrib::Element
   * =$class= - the name of the class being instantiated (implicit using -> syntax).
   * =$nodeName= - the name of XML node represented by this Element.

Constructor.  Creates and returns a
Foswiki::Contrib::XMLStoreContrib::Element containing a reference to
an XML::LibXML::Element with the given node name.

=cut

sub new {
    use XML::LibXML;
    my ( $class, $nodeName ) = @_;
    my $self = {};

    $self->{'node'}     = XML::LibXML::Element->new($nodeName);
    $self->{'instance'} = 1;
    return bless( $self, $class );
}

=begin TML

---++ fromXML($class, $node) -> $Foswiki::Contrib::XMLStoreContrib::Element
   * =$class= - the name of the class being instantiated (implicit using -> syntax).
   * =$node= - an XML node to be encapsulated by this Element.

Constructor.  Creates and returns a
Foswiki::Contrib::XMLStoreContrib::Element containing a reference to
the given XML::LibXML::Element.

=cut

sub fromXML {
    my ( $class, $node ) = @_;
    my $self = {};

    #Foswiki::Func::writeDebug("Element::fromXML $node->getAttribute('id')");
    $self->{'node'}     = $node;
    $self->{'instance'} = 1;
    return bless( $self, $class );
}

=begin TML

---++ toString($self, $level) -> $string
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$level= - [optional, default=0] formatting for document; regulates indentation (see XML::LibXML::Document::toString)

Convert the internal document representation into a string of XML text.

=cut

sub toString {
    my $self = shift;
    my $level = shift || 0;
    return $self->{'node'}->toString($level);
}

=begin TML

---++ hasAttribute($self, $attrName) -> $boolean
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$attrName= - the name of the XML attribute to look for in this Element

Return non-zero if the internal XML node has an attribute with the given name.

=cut

sub hasAttribute {
    my ( $self, $attrName ) = @_;
    return $self->{'node'}->hasAttribute($attrName);
}

=begin TML

---++ getAttribute($self, $attrName) -> $boolean
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$attrName= - the name of the XML attribute to look for in this Element

Return the value of the attribute with the given name as stored in the
internal XML node.

=cut

sub getAttribute {
    my ( $self, $attrName ) = @_;
    return $self->{'node'}->getAttribute($attrName);
}

#####################
# WIKI/HTML METHODS #
#####################

=begin TML

---++ getAnchorName($self) -> $HTML
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).

Returns a string that may be used as an HTML anchor for this object.

=cut

sub getAnchorName {
    my $self  = shift;
    my $ctype = ucfirst $self->{'node'}->getAttribute("id");
    my $tag   = $self->getAnchorTag();
    return "" unless $tag;

    # Use HTML instead of wiki syntax because it removes a layer of
    # processing and also because the wiki rejects characters in
    # anchor names that are valid.
    return "<a name=\"$tag$ctype\"></a>";
}

=begin TML

---++ getAnchorRef($self) -> $HTML
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).

Returns a string that may be used as an anchor to this object for
either a Foswiki link or URL (provided one was created in the document
using getAnchorName() above).

=cut

sub getAnchorRef {
    my $self  = shift;
    my $ctype = ucfirst $self->{'node'}->getAttribute("id");
    my $tag   = $self->getAnchorTag();
    return "" unless $tag;
    return "#$tag$ctype";
}

=begin TML

---++ getAnchorTag() -> $string

Return a string unique to the child implementation of this class
(i.e., should be overridden by child classes).  Used for constructing
HTML links.

=cut

sub getAnchorTag() { return ""; }

=begin TML

---++ getURL($self) -> $string
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).

Get the URL for this object, provided the internal XML node has the
required "web" and "topic" attributes.

=cut

sub getURL {
    my $self = shift;
    my $rv   = undef;
    if (   ( defined $self->{'node'} )
        && $self->{'node'}->hasAttribute("web")
        && $self->{'node'}->hasAttribute("topic") )
    {
        $rv = Foswiki::Func::getViewUrl(
            $self->{'node'}->getAttribute("web"),
            $self->{'node'}->getAttribute("topic")
        ) . $self->getAnchorRef();
    }
    return $rv;
}

1;
