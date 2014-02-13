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

sub debug {
  print STDERR @_, "\n" if defined $ENV{DEBUG};
}

sub email_texter {
  my ($email, %args) = @_;
  debug "IN:\n", $email->debug_structure;

  local $text;
  local $html;
  sub traverse_parts {
    foreach (@_) {
      my $type = $_->content_type;
      debug "  checking part type: $type";
      return traverse_parts(reverse $_->parts) if $type =~ m:multipart/:;

      $text = $_->body_str if $type =~ m:^text/plain;?: or $type eq '';
      $html = $_->body_str if $type =~ m:^text/html;?:;
    }
  }

  # Parse MIME parts from end to begin in order that the first ones take precedence.
  traverse_parts(reverse $email->parts);
  debug "Text part: ", defined $text ? length($text) : '-';
  debug "HTML part: ", defined $html ? length($html) : '-';

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
      debug "$trim TAG: ", join(' ', @ts), " > ", join(' ', map { "$_='$attr->{$_}'" } keys %$attr);

      if (($name eq 'div' and $attr->{class} =~ /^gmail_quote|moz-cite-prefix$/) ||
          ($name eq 'blockquote' and $attr->{type} eq 'cite')) {
        $trim++;
        push(@ts, '_trim_'); # Mark in the stack when we started trimming
        debug "$trim TRIM: ", join(' ', @ts), " > ", join(' ', map { "$_='$attr->{$_}'" } keys %$attr);
      }
      $$tt .= "\n\n" if $name eq 'br' and not $trim;
    }

    sub text_h {
      my ($t) = @_;
      my $ctx = $ts[-1];
      debug "$trim TXT[$ctx] $t";
      return if $trim;

      $t =~ s/^\s+//;
      $t =~ s/\s+$//;
      $$tt .= $t;
      $$tt .= "\n\n" if $ctx =~ /^(div|p)$/;
    }

    sub end_h {
      my $t = pop @ts;
      debug "$trim ///  $t";

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

  # Do not allow more than one consecutive empty line
  $text =~ s/\n(\s*\n){2,}/\n\n/g;

  # Strip any leading empty (or whitespaced) lines
  $text =~ s/^(\s*\n)+//;

  # Make sure it ends with a single newline
  $text =~ s/(\s*\n)*$/\n/;

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

  # We want to update the email while keepint its structure as much as possible.
  # This is note easy with Email::MIME. Here this routine will blindly replace
  # all text and HMTL parts with our modified text_part.
  sub update_parts {
    my ($this) = @_;
    my @keep;
    my $replaced = 0;

    foreach ($this->parts) {
      my $type = $_->content_type;

      update_parts($_) if $type =~ m:multipart/:;  # We have to recurse, MIME is like that

      if ($type =~ m:^text/: or $type eq '') {
        # We might encounter 0, 1 or 2 text or HTML parts in this loop,
        # thus we use $replaced to see if we replace or ignore (aka delete).
        if (not $replaced) {
          push(@keep, $text_part);
          $replaced = 1;
          debug "  updating part type '$type' with our modified text_part";
        } else {
          debug "  removing part type '$type'";
        }
      } else {
        # We keep everything else (multiparts, attachments, etc.)
        push(@keep, $_);
        debug "  keeping  part type '$type'";
      }
    }
    $this->parts_set(\@keep);
  }

  update_parts($email);
  debug "OUT:\n", $email->debug_structure;
}

1;
