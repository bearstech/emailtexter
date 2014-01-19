#!/usr/bin/perl

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
  my $out = read_file($outname);
  my $text = $text_parts[0]->body_str;
  ok( $text eq $out, "$name: text part content is as expected") or print STDERR diff(\$out, \$text);
}

my @tests = glob('t/*.eml');
plan tests => @tests * 4;
test $_ foreach @tests;

# TODO:
# - attachment (should not be stripped)
# - multipart text/html
# - html-ification
