emailtexter
===========

Try hard to extract interesting textual information from whatever email (text, text+html, html, attachements, etc.)

This Perl module implement cruds hacks/heuristics to help mail-to-ticket gateways get rid of the cruft :

* convert mail with HTML an no text alternative to text
* remove signatures
* strip quotes when top-posting
* try to make sense of abuse or lack of newlines/paragraphs

It parses the incoming email with Email::MIME, only add/modify/delete text or HTML MIME parts, and preserve everything else (attachments and so on).

Right now it will always output UTF-8 encoded text, whatever was the incoming text charset.
