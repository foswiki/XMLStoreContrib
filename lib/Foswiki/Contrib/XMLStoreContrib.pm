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
#
# Author: John Knutson
#
# Provide a basic interface for storing information in XML files.

=begin TML

---+ package Foswiki::Contrib::XMLStoreContrib

Defines an implementation of XML data storage for use by Foswiki plug-ins.

Use this class by deriving a new class/module from it that uses its
own specific derived Foswiki::Contrib::XMLStoreContrib::Element class.

Derived classes of this should override the newElement sub.

Currently only a basic structure of a document with a root node and
multiple child nodes of the same name is supported.  There may be any
number of children of the root node, and the children of those child
nodes may be anything at all.

XML elements stored by this package are expected to at a bare minimum
have "web", "topic" and "id" attributes.  Anything beyond that is up
to the implementer.

=cut

package Foswiki::Contrib::XMLStoreContrib;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func ();    # The plugins API
use XML::LibXML;         # for cross-reference document parsing
use Fcntl qw/:flock :seek/;    # import LOCK_* and SEEK_* constants

use version; our $VERSION = version->declare("v1.0.1");
our $RELEASE = '1.0.1';
our $SHORTDESCRIPTION =
'XMLStoreContrib is a package for storing plugin data in XML files on Foswiki servers';

=begin TML

---++ FAIL(...)

Like die(), but includes a stack trace for debugging.  Used for
internal errors.

=cut

sub FAIL {
    my $deathRattle = join( ' ', @_ );
    my $i = 0;
    my (
        $pkg,       $filename, $line,      $subroutine, $hasArgs,
        $wantArray, $evalText, $isRequire, $hints,      $bitMask
    );
    my @stack;
    my $frame = "";
    while (
        (
            $pkg,       $filename, $line,      $subroutine, $hasArgs,
            $wantArray, $evalText, $isRequire, $hints,      $bitMask
        )
        = caller( $i++ )
      )
    {
        $frame = "";
        $frame .= "\[$i\] ";
        $frame .= $pkg . "::" if ( defined $pkg );
        $frame .= $subroutine if ( defined $subroutine );
        if ( defined $filename ) {
            $frame .= " @ $filename";
            $frame .= ":$line" if ( defined $line );
        }
        push( @stack, $frame );
    }
    die( $deathRattle . "\n" . join( "\n", @stack ) . "\n" );
}

=begin TML

---++ new($class, $pluginName, $fileName, $rootName, $nodeName) -> $Foswiki::Contrib::XMLStoreContrib
   * =$class= - the name of the class being instantiated (implicit using -> syntax).
   * =$pluginName= - the name of the plugin creating the store; used as part of the directory containing the store file itself
   * =$fileName= - the name of the store file
   * =$rootName= - the name of the root XML node
   * =$nodeName= - the name of child nodes of the root XML node

Constructor, takes a file name and an XML root element name.  The file
store is created in the work area for the given $pluginName, using the
given $fileName.

=cut

sub new {
    use Foswiki::Plugins;
    my ( $class,
         $pluginName,
         $fileName,
         $rootName,
         $nodeName ) = @_;

    # this should only be used when running outside Foswiki, e.g. cron jobs
    #my $workArea = "/tmp";
    my $workArea = Foswiki::Func::getWorkArea($pluginName);
    my $path = "$workArea/$fileName";
    my $self = {
        'updated'  => {},
        'filename' => $fileName,
        'path'     => $path,
        'rootname' => $rootName,
        'nodename' => $nodeName,
    };
    if (-r $path) {
        open(my $fh, '<', $path)
            or FAIL("Can't open XMLStore file \"$path\" for input: $!");
        # drop all PerlIO layers possibly created by a use open pragma
        binmode $fh;
        # make sure we don't try to read in the middle of a write
        flock($fh, LOCK_SH)
            or FAIL("Cannot lock XMLStore file \"$path\": $!");
        $self->{'doc'} = XML::LibXML->load_xml(
            IO => $fh,
            no_blanks => 1);
        close($fh);
    } else {
        eval { $self->{'doc'} = XML::LibXML::Document->new( "1.0", "UTF-8" ); };
        FAIL( "Error creating XML document: " . $@->message() ) if ( ref($@) );
        FAIL( "Error creating XML document: " . $@ ) if ($@);
    }
    if ( !$self->{'doc'}->hasChildNodes() ) {
        eval {
            $self->{'doc'}
              ->setDocumentElement( XML::LibXML::Element->new("$rootName") );
        };
        FAIL( "Error creating XML Element: " . $@->message() ) if ( ref($@) );
        FAIL( "Error creating XML Element: " . $@ ) if ($@);
    }
    unless (-r $path) {
        # Create a file if it doesn't already exist.  Do this here
        # instead of in the earlier -r test because we need the root
        # document element added first.
        open(my $fh, ">>", $path)
            or FAIL("Can't create XMLStore file \"$path\": $!");
        # serialize access for writing
        flock($fh, LOCK_EX)
            or FAIL("Cannot lock XMLStore file \"$path\": $!");
        binmode $fh;
        # make sure the file hasn't been created in another session,
        # now that we have the lock.
        seek $fh, 0, SEEK_END;
        if (tell $fh == 0) {
            $self->{'doc'}->toFH($fh, 2);
        }
        close($fh);
    }
    return bless( $self, $class );
}

=begin TML

---++ toString($self, $level) -> $string
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$level= - formatting for document; regulates indentation (see XML::LibXML::Document::toString)

Convert the internal document representation into a string of XML text.

=cut

sub toString {
    my ( $self, $level ) = @_;
    return $self->{'doc'}->toString($level);
}

=begin TML

---++ save($self, $force)
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$force= - save the document even if unchanged.

Save the document represented by this object to disk.  If the document
has not changed since it was loaded, the store file will not actually
be updated, unless $force is non-zero.

=cut

sub save {
    my ( $self, $force ) = shift;
    return unless ( $self && $self->{'doc'} );

    # do nothing if no updates have been made
    if (scalar(keys %{ $self->{'updated'} }) == 0) {
        return;
    }
    open(my $out, '+<', $self->{'path'})
        or FAIL("Can't open XMLStore file \"" . $self->{'path'} . "\": $!");
    # serialize access for writing
    flock($out, LOCK_EX) or FAIL("Cannot lock XMLStore file: $!");
    # drop all PerlIO layers possibly created by a use open pragma
    binmode $out;
    # reload the document from disk in case another session has made changes
    my $doc = XML::LibXML->load_xml(
        IO => $out,
        no_blanks => 1);
    # Remove all nodes associated with the updated topic from the most
    # recent document, then add the possibly changed nodes back in.
    my $diskroot = $doc->documentElement();
    foreach my $web (sort keys %{ $self->{'updated'} }) {
        foreach my $topic (sort keys %{ $self->{'updated'}->{$web} }) {
            my @nodes = $doc->findnodes(
                "/" . $self->{'rootname'} . "/" . $self->{'nodename'} .
                "[\@web='$web' and \@topic='$topic']");
            foreach my $node (@nodes) {
                my $parent = $node->parentNode;
                $parent->removeChild($node);
                undef $node;
            }
            my $replnodelist = $self->getNodeList(
                "[\@web='$web' and \@topic='$topic']");
            foreach my $newnode ($replnodelist->get_nodelist()) {
                $diskroot->addChild($newnode);
            }
        }
    }
    # clear out the original contents before updating
    seek $out, 0, SEEK_SET;
    truncate $out, 0;
    $doc->toFH($out, 2);
    close($out);
    # free the old doc and replace it with the new
    undef $self->{'doc'};
    $self->{'doc'} = $doc;
    # clear the updated hash
    undef $self->{'updated'};
}

# =begin TML

# ---++ clear($self)
#    * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).

# Empty this document of all data (except the root node).

# =cut

# sub clear {
#     my ($self) = @_;
#     my $root = $self->{'doc'}->documentElement();
#     while ( $root->hasChildNodes() ) {
#         $root->removeChild( $root->firstChild );
#         $self->{'changed'} = 1;
#     }
#     $self->save();
# }

=begin TML

---++ getNodeList($self, $predicate) -> $XML::LibXML::NodeList
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$predicate= - [optional] an XPath expression to match specific nodes

Get either a complete list of nodes in this document (default), or
with $predicate specified, get a list of nodes matching the given
XPath expression relative to the child nodes of the root.

=cut

sub getNodeList {
    my $self      = shift;
    my $predicate = shift || "";
    my $rootName  = $self->{'rootname'};
    my $nodeName  = $self->{'nodename'};
    my $query     = "/$rootName/$nodeName$predicate";
    my $rv;
    eval { $rv = $self->{'doc'}->findnodes($query); };
    FAIL( "Error finding XML nodes: " . $@->message() . "\nquery: $query" )
      if ( ref($@) );
    FAIL( "Error finding XML nodes: " . $@ . "\nquery: $query" )
      if ($@);
    return $rv;
}

=begin TML

---++ getNode($self, $id) -> $XML::LibXML::Node
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$id= - a unique ID for the document element to find.

Get an XML::LibXML::Element with a matching ID from our document.

=cut

sub getNode {
    my ( $self, $id ) = @_;
    my $nodelist = $self->getNodeList("[\@id='$id']");
    return $nodelist->get_node(1);
}

=begin TML

---++ nodeExists($self, $id) -> $boolean
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$id= - a unique ID for the document element to find.

Return 0 if the document does not contain an element matching the given ID.

=cut

sub nodeExists {
    my ( $self, $id ) = @_;
    my $rootName = $self->{'rootname'};
    my $nodeName = $self->{'nodename'};
    my $query    = "/$rootName/$nodeName\[\@id='$id'\]";
    my $rv;
    eval { $rv = $self->{'doc'}->exists($query); };
    FAIL( "Error finding XML nodes: " . $@->message() . "\nquery: $query" )
      if ( ref($@) );
    FAIL( "Error finding XML nodes: " . $@ . "\nquery: $query" )
      if ($@);
    return $rv;
}

=begin TML

---++ fromXML($self, $xmlElem) -> $Foswiki::Contrib::XMLStoreContrib::Element
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$xmlElem= - an XML::LibXML::Element object reference to which a Foswiki::Contrib::XMLStoreContrib::Element is converted

Pseudo-constructor.  Builds the appropriate element for this store
from an XML Element.  Overridden by child classes.

=cut

sub fromXML {
    my ( $self, $xmlElem ) = @_;
    return Foswiki::Contrib::XMLStoreContrib::Element->fromXML($xmlElem);
}

=begin TML

---++ newElement($self, $id) -> $Foswiki::Contrib::XMLStoreContrib::Element
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$id= - a unique ID used to uniquely identify this newly created Element

Pseudo-constructor.  Builds the appropriate element for this store
from an ID.  Overridden by child classes.

Because this only sets the ID of the element, it is only intended to
be used when details are not otherwise available, e.g. a data type
is specified but not available in the database.

THIS METHOD SHOULD ALWAYS BE OVERRIDDEN (or not used at all)
Element::new behaves differently from children.

=cut

sub newElement {
    my ( $self, $id ) = @_;
    my %params = ( id => $id );
    FAIL "XMLStoreContrib::newElement called (it should be overridden)\n";
}

=begin TML

---++ getElement($self, $id) -> $Foswiki::Contrib::XMLStoreContrib::Element
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$id= - a unique ID for the document element to find.

Get a Foswiki::Contrib::XMLStoreContrib::Element with a matching ID
from our document.

=cut

sub getElement {
    my ( $self, $id ) = @_;
    # get an empty node if $id is undef
    my $xmlElem;
    $xmlElem = $self->getNode($id)
      if defined $id;
    my $rv = (
        defined $xmlElem
        ? $self->fromXML($xmlElem)
        : $self->newElement( $id || "" )
    );
    return $rv;
}

=begin TML

---++ getElementList($self, $predicate) -> @Foswiki::Contrib::XMLStoreContrib::Element
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$predicate= - [optional] an XPath expression to match specific nodes

Get either a complete list of
Foswiki::Contrib::XMLStoreContrib::Element references in this document
(default), or with $predicate specified, get a list of Element
references matching the given XPath expression relative to the child
nodes of the root.

=cut

sub getElementList {
    my ( $self, $predicate ) = @_;
    my $nodelist = $self->getNodeList($predicate);
    my @rv;
    push( @rv, $self->fromXML($_) ) foreach ( $nodelist->get_nodelist() );
    return @rv;
}

=begin TML

---++ getElementHash($self, $predicate) -> %Foswiki::Contrib::XMLStoreContrib::Element
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$predicate= - [optional] an XPath expression to match specific nodes

Get either a complete hash of all
Foswiki::Contrib::XMLStoreContrib::Element references in this document
(default), or with $predicate specified, get a hash of Element
references matching the given XPath expression relative to the child
nodes of the root.

The hash key is the identifier for the element.

=cut

sub getElementHash {
    my ( $self, $predicate ) = @_;
    my $nodelist = $self->getNodeList($predicate);
    my %rv;
    $rv{ $_->getAttribute('id') } = $self->fromXML($_)
      foreach ( $nodelist->get_nodelist() );
    return %rv;
}

=begin TML

---++ moveWikiPage($self, $oldWeb, $oldTopic, $newWeb, $newTopic, $extraPath) -> $boolean
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$oldWeb= - the original web location of the nodes being moved
   * =$oldTopic= - the original topic location of the nodes being moved
   * =$newWeb= - the target web location of the nodes being moved
   * =$newTopic= - the target topic location of the nodes being moved
   * =$extraPath= - [optional] an XPath expression to match specific nodes

Move store nodes using the given oldWeb.oldTopic to newWeb.newTopic.

Returns non-zero if changes were made to the store.

=cut

sub moveWikiPage {
    my ( $self, $oldWeb, $oldTopic, $newWeb, $newTopic, $extraPath ) = @_;
    my $addlPath = $extraPath || '';
    my $nodelist =
      $self->getNodeList(
        $addlPath . "[\@web='$oldWeb' and \@topic='$oldTopic']" );
    my $root = $self->{'doc'}->documentElement();

    foreach my $node ( $nodelist->get_nodelist() ) {
        $node->setAttribute( "web",   $newWeb );
        $node->setAttribute( "topic", $newTopic );
    }
    $self->markChanged($oldWeb, $oldTopic);
    $self->markChanged($newWeb, $newTopic);

    if ($nodelist) {
        return 1;
    }
    return 0;
}

=begin TML

---++ eraseWikiPage($self, $topic, $web) -> $boolean
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$web= - the web location of the nodes being deleted
   * =$topic= - the topic location of the nodes being deleted

Remove nodes from the store that match the specified wiki page.

Returns non-zero if changes were made to the store.

=cut

sub eraseWikiPage {
    my ( $self, $topic, $web ) = @_;
    my $nodelist = $self->getNodeList("[\@web='$web' and \@topic='$topic']");
    my $root     = $self->{'doc'}->documentElement();
    $root->removeChild($_) foreach ( $nodelist->get_nodelist() );
    $self->markChanged($topic, $web);
    if ($nodelist) {
        return 1;
    }
    return 0;
}

=begin TML

---++ updateDocFromNodes($self, $origNode, $newNode) -> $boolean
   * =$self= - a Foswiki::Contrib::XMLStoreContrib object reference (implicit using -> syntax).
   * =$origNode= - The original XML::LibXML::Node to be replaced
   * =$newNode= - The updated XML::LibXML::Node

Given an old node (possibly undefined) and a new node, add the new
node to $doc if the old node is undefined or replace the old node
with the new one if the two nodes differ.

=cut

sub updateDocFromNodes {
    my ( $self, $origNode, $newNode ) = @_;
    my $root = $self->{'doc'}->documentElement();
    if ( defined $origNode ) {
        if ( $newNode->toString ne $origNode->toString ) {
            $root->replaceChild( $newNode, $origNode );
            $self->markChanged(
                $origNode->getAttribute("web"),
                $origNode->getAttribute("topic"));
            $self->markChanged(
                $newNode->getAttribute("web"),
                $newNode->getAttribute("topic"));
            return 1;
        }
    } else {
        $root->addChild($newNode);
        $self->markChanged(
            $newNode->getAttribute("web"),
            $newNode->getAttribute("topic"));
        return 1;
    }
    return 0;
}


# Indicate that an element associated with a topic has been modified.
sub markChanged {
    my ($self,
        $web,
        $topic) = @_;
    $self->{'updated'}->{$web}->{$topic} = 1;
}


=begin TML

---++ DESTROY($self)

"Destructor" called by perl.  Saves the document, but should not be
relied upon to save data to disk.

=cut

sub DESTROY {
    my $self = shift;
    $self->save();
}

1;
