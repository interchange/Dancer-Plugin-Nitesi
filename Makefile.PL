use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Dancer::Plugin::Nitesi',
    AUTHOR              => q{Stefan Hornburg (Racke) <racke@linuxia.de>},
    VERSION_FROM        => 'lib/Dancer/Plugin/Nitesi.pm',
    ABSTRACT            => 'Dancer Plugin for Nitesi Open Source Shop Machine',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'YAML'       => 0,
	'Nitesi'     => 0.0031,
	'Nitesi::DBI' => 0.0032,
        'Dancer'     => 1.3071,
	'Dancer::Plugin::Database' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Dancer-Plugin-Nitesi-*' },
);
