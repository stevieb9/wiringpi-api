use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'WiringPi::API',
    VERSION_FROM      => 'lib/WiringPi/API.pm',
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/WiringPi/API.pm', # retrieve abstract from module
       AUTHOR         => 'Steve Bertrand <steveb@cpan.org>') : ()),
    LIBS              => ['-lwiringPi -lwiringPiDev'],
    DEFINE            => '',
    INC               => '-I.',
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            bugtracker => {
                web => 'https://github.com/stevieb9/wiringpi-api/issues',
            },
            repository => {
                type => 'git',
                url => 'https://github.com/stevieb9/wiringpi-api.git',
                web => 'https://github.com/stevieb9/wiringpi-api',
            },
        },
    },
    PREREQ_PM         => {
    },
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
