#!/usr/bin/env perl
use strict;
use warnings;

my $print_notices = 0;
if (@ARGV && $ARGV[0] eq '--print-notices') {
    $print_notices = 1;
    shift @ARGV;
}
my ($base, $notice_path) = @ARGV;
defined $base or die "usage: classify-license.pl [--print-notices] <base dir> [notice file] < relative paths\n";

my $license_words = qr/copyright|\(c\)|permission|warranty|redistribution|licen[sc]e|as[- ]is|rights reserved|public domain|neither the name|this notice|acknowledg|based in part|conditions|independent jpeg|disclaim|liabilit|damages|restrictions/;

sub lines_of {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "classify-license: cannot read $path: $!\n";
    my @lines = <$fh>;
    close $fh;
    s/\r?\n$// for @lines;
    return \@lines;
}

sub header_lines {
    my ($lines) = @_;
    my @header;
    my $in_block = 0;
    for my $line (@$lines) {
        my $current = $line;
        if ($in_block) {
            $in_block = 0 if $current =~ s{\*/.*$}{};
            push @header, $current;
            next;
        }
        next if $current =~ /^\s*$/ || $current =~ /^#!/;
        if ($current =~ m{^\s*/\*(.*)$}) {
            my $rest = $1;
            $in_block = 1 unless $rest =~ s{\*/.*$}{};
            push @header, $rest;
            next;
        }
        if ($current =~ m{^\s*(?://|;|@)(.*)$}) {
            push @header, $1;
            next;
        }
        if ($current =~ /^\s*#(?!\s*(?:include|if|ifdef|ifndef|define|undef|pragma|else|elif|endif|error|warning)\b)(.*)$/) {
            push @header, $1;
            next;
        }
        last;
    }
    return \@header;
}

sub normalized {
    my ($lines) = @_;
    my $text = join ' ', map {
        my $line = $_;
        $line =~ s/^\s*(?:\*+|\/\/+|;+|#+|\@)\s?//;
        $line;
    } @$lines;
    $text =~ s/\s+/ /g;
    $text =~ s/^ | $//g;
    return lc $text;
}

sub comment_blocks {
    my ($lines) = @_;
    my $text = join "\n", @$lines;
    my @blocks;
    while ($text =~ m{/\*(.*?)\*/}gs) {
        push @blocks, [ split /\n/, $1 ];
    }
    my @run;
    for my $line (@$lines, '') {
        if ($line =~ m{^\s*(?://|;|@)(.*)$}) {
            push @run, $1;
        } elsif (@run) {
            push @blocks, [@run];
            @run = ();
        }
    }
    return \@blocks;
}

sub notice_tags {
    my ($text) = @_;
    my @tags;
    push @tags, 'boost' if $text =~ /permission is hereby granted, free of charge, to any person or organization/;
    push @tags, 'mit' if $text =~ /permission is hereby granted, free of charge, to any person obtaining/;
    push @tags, 'bsd' if $text =~ /redistribution and use in source and binary forms/;
    push @tags, 'isc' if $text =~ /permission to use, copy, modify,? and\/?or distribute/;
    push @tags, 'zlib' if $text =~ /this software is provided 'as-is'/;
    push @tags, 'ijg' if $text =~ /independent jpeg group/;
    push @tags, 'apache' if $text =~ /licensed under the apache license/;
    push @tags, 'public-domain' if $text =~ /public domain/;
    return @tags;
}

sub grant_of {
    my ($text) = @_;
    return 'lgpl' if $text =~ /gnu (?:lesser|library) general public licen[sc]e/ || $text =~ /(?<![a-z])lgpl/;
    return 'gpl' if $text =~ /gnu general public licen[sc]e/ || $text =~ /(?<![a-z])gpl(?![a-z])/;
    return 'none';
}

sub paragraphs_of {
    my ($block) = @_;
    my (@paragraphs, @current);
    for my $line (@$block, '') {
        my $clean = $line;
        $clean =~ s/^\s*(?:\*+|\/\/+|;+|#+|\@)\s?//;
        if ($clean =~ /^\s*$/) {
            push @paragraphs, [@current] if @current;
            @current = ();
        } else {
            push @current, $clean;
        }
    }
    return \@paragraphs;
}

sub notice_paragraphs {
    my ($blocks) = @_;
    my @notices;
    for my $block (@$blocks) {
        next unless notice_tags(normalized($block));
        for my $paragraph (@{ paragraphs_of($block) }) {
            my $text = normalized($paragraph);
            next if $text =~ /gnu (?:lesser|library)|lesser general public/ || $text =~ /^file\b/;
            next unless $text =~ $license_words;
            push @notices, $paragraph;
        }
    }
    return \@notices;
}

my $notice_text = defined $notice_path ? normalized(lines_of($notice_path)) : undef;

while (my $relative = <STDIN>) {
    chomp $relative;
    next if $relative eq '';
    my $lines = lines_of("$base/$relative");
    my $blocks = comment_blocks($lines);
    my $grant = grant_of(normalized(header_lines($lines)));
    my %seen;
    my @tags = grep { !$seen{$_}++ } map { notice_tags(normalized($_)) } @$blocks;
    my $paragraphs = @tags ? notice_paragraphs($blocks) : [];
    if ($print_notices) {
        next unless @tags;
        printf "%s (%s)\n\n", $relative, join(', ', @tags);
        print join("\n", @$_), "\n\n" for @$paragraphs;
        next;
    }
    my $status = '';
    if (defined $notice_text && @tags) {
        my $complete = @$paragraphs && index($notice_text, lc $relative) >= 0;
        for my $paragraph (@$paragraphs) {
            $complete &&= index($notice_text, normalized($paragraph)) >= 0;
        }
        $status = $complete ? "\tin-notice" : "\tmissing-notice";
    }
    printf "%s\t%s\t%s%s\n", $grant, @tags ? join(',', @tags) : '-', $relative, $status;
}
