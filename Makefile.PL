use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Test::XmlServer',
    AUTHOR              => 'MIZUTANI Tociyuki <tociyuki@gmail.com>',
    VERSION_FROM        => 'lib/Test/XmlServer.pm',
    ABSTRACT_FROM       => 'lib/Test/XmlServer.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::Base' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
);
