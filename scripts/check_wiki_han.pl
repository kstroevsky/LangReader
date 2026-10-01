#!/usr/bin/env perl
use strict;
use warnings;

use Encode qw(decode FB_CROAK);

my $found_han = 0;

for my $path (@ARGV) {
    open my $handle, '<:raw', $path or do {
        print STDERR "$path: unable to open for Han-script scan: $!\n";
        exit 20;
    };

    my $line_number = 0;
    while (defined(my $bytes = <$handle>)) {
        $line_number += 1;
        my $decoded;
        eval { $decoded = decode('UTF-8', $bytes, FB_CROAK); 1 } or do {
            my $error = $@;
            chomp $error;
            print STDERR "$path:$line_number: UTF-8 decode error: $error\n";
            exit 20;
        };

        if ($decoded =~ /\p{Script=Han}/) {
            my %seen;
            my @han = grep { /\p{Script=Han}/ && !$seen{$_}++ } split //, $decoded;
            my $code_points = join(', ', map { sprintf('U+%04X', ord($_)) } @han);
            print STDERR "$path:$line_number: $code_points\n";
            $found_han = 1;
        }
    }

    close $handle or do {
        print STDERR "$path: unable to close after Han-script scan: $!\n";
        exit 20;
    };
}

exit($found_han ? 10 : 0);
