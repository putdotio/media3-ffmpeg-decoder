#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;

my ($tree, $record_dir) = @ARGV;
defined $record_dir or die "usage: list-compiled-sources.pl <ffmpeg tree> <recorded abi dir>\n";

my @depfiles;
find(sub { push @depfiles, $File::Find::name if /\.d$/ }, $record_dir);
@depfiles or die "list-compiled-sources: no depfiles in $record_dir\n";

my (%objects, %sources, %includes);
for my $depfile (@depfiles) {
    open my $fh, '<', $depfile or die "list-compiled-sources: cannot read $depfile: $!\n";
    local $/;
    my $text = <$fh>;
    close $fh;
    $text =~ s/\\\r?\n/ /g;
    my ($rule) = $text =~ /^(.*?:(?:\s|$).*)$/m;
    defined $rule or die "list-compiled-sources: no rule in $depfile\n";
    my ($object, $prereqs) = $rule =~ /^(\S+?):\s*(.*)$/;
    defined $object && $object =~ /\.o$/ or die "list-compiled-sources: no object in $depfile\n";
    $object =~ s{^\./}{};
    my @prereqs = split ' ', $prereqs;
    @prereqs or die "list-compiled-sources: $object has no source\n";
    my $source = shift @prereqs;
    $source =~ s{^\./}{};
    -f "$tree/$source" or die "list-compiled-sources: $object source $source is not in the tree\n";
    $objects{$object} = 1;
    $sources{$source} = 1;
    for my $prereq (@prereqs) {
        $prereq =~ s{^\./}{};
        next if $prereq =~ m{^/};
        $includes{$prereq} = 1 if -f "$tree/$prereq";
    }
}

print "object\t$_\n" for sort keys %objects;
print "source\t$_\n" for sort keys %sources;
print "include\t$_\n" for sort grep { !$sources{$_} } keys %includes;
