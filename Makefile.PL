use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'RPi::WiringPi::Core',
    VERSION_FROM      => 'lib/RPi/WiringPi/Core.pm',
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/RPi/WiringPi/Core.pm', # retrieve abstract from module
       AUTHOR         => 'Steve Bertrand <steveb@cpan.org>') : ()),
    LIBS              => ['-lwiringPi -lwiringPiDev'],
    DEFINE            => '',
    INC               => '-I.',
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            bugtracker => {
                web => 'https://github.com/stevieb9/p5-rpi-wiringpi-core/issues',
            },
            repository => {
                type => 'git',
                url => 'https://github.com/stevieb9/p5-rpi-wiringpi-core.git',
                web => 'https://github.com/stevieb9/p5-rpi-wiringpi-core',
            },
        },
    },
    PREREQ_PM         => {
        'RPi::WiringPi::Constant' => 0.01,
    },
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
