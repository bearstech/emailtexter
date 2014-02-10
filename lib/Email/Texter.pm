# Email::Texter - extract essentials from verbose emails
# Copyright (C) 2014 Bearstech
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Email::Texter;

use Email::MIME;
use HTML::Parser;

use Exporter 'import';
@EXPORT = qw/ email_texter /;

sub email_texter {
  my ($email, %args) = @_;

  my $text;
  my $html;
  # Parse MIME parts from end to begin in order that the first ones take precedence
  foreach (reverse $email->parts) {
    my $type = $_->content_type;
    $text = $_->body_str if $type =~ m:^text/plain;?: or $type eq '';
    $html = $_->body_str if $type =~ m:^text/html;?:;
  }
  # No text or HTML MIME part found, we leave the email untouched
  return unless defined $text or defined $html;
 
  # If there's an HTML part, use it. Wich means we prefer HTML over text when
  # an email has both text+HTML as multipart/alternative, because it's more
  # structured and it's easier to remove signatures and quotes
  if (defined $html) {
    # HTML::Parser does not emit 'end's for well known non-closing tags, very annoying
    # for the event-based traversal. We fix this with <br> -> <br/> crude transforms.
    $html =~ s:<\s*(br|hr)\s*>:<$1/>:ig;
 
    my @ts;        # tag stack
    my $trim = 0;  # we trim an HTML subtree if $trim > 0
    my $tt = \$text;
    $text = '';
    my $p = HTML::Parser->new( api_version => 3,
      unbroken_text => 1,
      start_h => [ \&start_h, 'tagname,attr' ],
      text_h  => [ \&text_h, 'dtext' ],
      end_h   => [ \&end_h ],
    );
    $p->empty_element_tags(1);
    $p->ignore_elements(qw(script style));

    sub start_h {
      my ($name, $attr) = @_;
      push(@ts, $name);
      print STDERR "$trim TAG: ", join(' ', @ts), " > ", join(' ', map { "$_='$attr->{$_}'" } keys %$attr), "\n" if defined $ENV{DEBUG};

      if (($name eq 'div' and $attr->{class} =~ /^gmail_quote|moz-cite-prefix$/) ||
          ($name eq 'blockquote' and $attr->{type} eq 'cite')) {
        $trim++;
        push(@ts, '_trim_'); # Mark in the stack when we started trimming
        print STDERR "$trim TRIM: ", join(' ', @ts), " > ", join(' ', map { "$_='$attr->{$_}'" } keys %$attr), "\n" if defined $ENV{DEBUG};
      }
      $$tt .= "\n\n" if $name eq 'br' and not $trim;
    }

    sub text_h {
      my ($t) = @_;
      my $ctx = $ts[-1];
      print STDERR "$trim TXT[$ctx] $t\n" if defined $ENV{DEBUG};
      return if $trim;

      $t =~ s/^\s+//;
      $t =~ s/\s+$//;
      $$tt .= $t;
      $$tt .= "\n\n" if $ctx =~ /^(div|p)$/;
    }

    sub end_h {
      my $t = pop @ts;
      print STDERR "$trim ///  $t\n" if defined $ENV{DEBUG};

      if ($t eq '_trim_') {  # Stop trimming, we unrolled up to the corresponding closing tag
        $trim-- if $trim > 0;
        pop @ts;
      }
    }
    $p->parse($html);
    $p->eof;
  } else {
    # Strip oldschool signature (after the '--' line)
    $text =~ s/\n--\s*\n.*/\n/s;

    # Strip '> replies' if they extended to the end (top posting!)
    # 1. Remove last lines with begin with '>' if any
    if ($text =~ s/(\n\s*>.*)+(\n\s*)*$/\n/) {
      # Try to remove the "This guy wrote :" header if present
      $text =~ s/\n.*:\s*$/\n/;
    }
  }
 
  # Remove \r (nomalize on Unix mail format, easier for the next regexes)
  $text =~ s/\r//g;

  # Strip leading and trailing blanks
  $text =~ s/^\s+//;
  $text =~ s/\s+$//;
 
  # Do not allow more than one consecutive empty line
  $text =~ s/\n(\s*\n){2,}/\n\n/g;

  # Make sure it ends with a single newline
  $text =~ s/\n*$/\n/;

  # Run user-defined transform if defined
  $text = $args{text_edit}->($text) if defined $args{text_edit};

  $text_part = Email::MIME->create(
    attributes => {
      content_type => 'text/plain',
      encoding     => '8bit',
      charset      => 'utf-8',
    },
    body_str => $text
  );

  my @newparts = ($text_part, grep { $_->content_type !~ m:^text/: } $email->parts);
  $email->parts_set(\@newparts);
}

1;
