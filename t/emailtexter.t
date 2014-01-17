#!/usr/bin/perl

use Test::More;
use File::Slurp;
use Email::Texter;
use Text::Diff;
use strict;
use warnings;

sub test {
  my $name = shift;
  
  my $in = read_file($name);
  my $email = Email::MIME->new($in);
  ok( $email->isa('Email::MIME'), 'input is an Email::Mime object' );
  
  email_texter($email);
  
  my @parts = $email->parts;
  my @html_parts = grep { defined $_->content_type and $_->content_type =~ m:^text/html;?: } @parts;
  ok( @html_parts == 0, 'has no HTML part');
  
  my @text_parts = grep { defined $_->content_type and $_->content_type =~ m:^text/plain;?: } @parts;
  ok( @text_parts == 1, 'has exactly one text part');
  
  (my $outname = $name) =~ s/\.eml$/.txt/;
  # DOS and protocol \r's and missing newline at EOF produce bogus deltas
  my $out = read_file($outname);
  my $text = $text_parts[0]->body_str; $text =~ s/\r//gs; $text .= "\n";
  ok( $text eq $out, 'text part content is as expected') or print STDERR diff(\$out, \$text);
}

my @tests = glob('t/*.eml');
plan tests => @tests * 4;
test $_ foreach @tests;

# TODO:
# - attachment (should not be stripped)
# - multipart text/html
# - html-ification
