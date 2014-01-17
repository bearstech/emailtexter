package Email::Texter;

use Email::MIME;
use HTML::Strip;

use Exporter 'import';
@EXPORT = qw/ email_texter /;

sub email_texter {
  my $email = shift;

  my $text;
  my $html;
  foreach (reverse $email->parts) {
    my $type = $_->content_type;
    $text = $_->body_str if $type =~ m:^text/plain;?: or $type eq '';
    $html = $_->body_str if $type =~ m:^text/html;?:;
  }
  die "No text or HTML MIME part found, exiting" unless defined $text or defined $html;
 
  if (not defined $text) {
    # Strip Thunderbird signatures
    $html =~ s/<pre class="moz-signature".*//s;
 
    my $hs = HTML::Strip->new();
    $text = $hs->parse($html);
    $hs->eof;
  } else {
    # Strip oldschool signature (after the '--' line)
    $text =~ s/\n--\s*\n.*/\n/s;

    # TODO: strip '> replies' if they extended to the end (top posting!)
  }
 
  # Strip leading and trailing blanks
  $text =~ s/^\s+//s;
  $text =~ s/\s+$//s;
 
  # Do not allow more than one consecutive empty line
  $text =~ s/\n(\s*\n){2,}/\n\n/sg;

  # Make sure it ends with a single newline
  $text =~ s/\n+$/\n/sg;

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
