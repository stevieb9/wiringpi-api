package WiringPi::API;  

use strict;
use warnings;

our $VERSION = '3.1801';

use Carp qw(croak);

# WPIPinType pin-numbering constants for the wiringpi_setup_pin_type() /
# wiringpi_setup_gpio_device() variants. WPI_PIN_PHYS (3) is intentionally NOT
# exposed - physical-pin setup mode was removed (see Changes); the wrappers
# croak if anything other than these two is passed.
use constant {
    WPI_PIN_BCM => 1,
    WPI_PIN_WPI => 2,
};

# Interrupt edge-trigger constants (mirror wiringPi's INT_EDGE_* #defines).
# INT_EDGE_SETUP (0) is a setup-only mode, not a real trigger, so set_interrupt()
# rejects it - the valid triggers are FALLING (1), RISING (2) and BOTH (3).
use constant {
    INT_EDGE_SETUP   => 0,
    INT_EDGE_FALLING => 1,
    INT_EDGE_RISING  => 2,
    INT_EDGE_BOTH    => 3,
};

require XSLoader;
XSLoader::load('WiringPi::API', $VERSION);

require Exporter;
our @ISA = qw(Exporter);

my @wpi_c_functions = qw(
    wiringPiSetup       wiringPiSetupGpio   pinMode
    pullUpDnControl
    digitalRead         digitalWrite        digitalWriteByte
    pwmWrite            getAlt              piGpioLayout
    wpiPinToGpio        physPinToGpio       pwmSetRange
    lcdInit             lcdHome             lcdClear
    lcdDisplay          lcdCursor           lcdCursorBlink
    lcdSendCommand      lcdPosition         lcdCharDef
    lcdPutchar          lcdPuts             wiringPiISRStop
    sr595Setup          bmp180Setup         bmp180Pressure
    bmp180Temp          analogRead          analogWrite
    physPinToWpi        wiringPiVersion     ads1115Setup
    pseudoPinsSetup     wiringPiSPISetup    spiDataRW
    wiringPiSPIGetFd    wiringPiSPISetupMode wiringPiSPIClose
    softToneCreate      softToneStop        softToneWrite
    wiringPiI2CSetup    wiringPiI2CSetupInterface
    wiringPiI2CRead     wiringPiI2CReadReg8 wiringPiI2CReadReg16
    wiringPiI2CWrite    wiringPiI2CWriteReg8 wiringPiI2CWriteReg16
    wiringPiI2CReadBlockData                 wiringPiI2CRawRead
    wiringPiI2CWriteBlockData                wiringPiI2CRawWrite
    pinModeAlt          serialOpen          serialFlush
    serialPutchar       serialPuts          serialDataAvail
    serialGetchar       pwmSetClock         pwmSetMode
    delay               delayMicroseconds   millis
    micros              piMicros64          piHiPri
    setPadDrive         setPadDrivePin      pwmToneWrite
    gpioClockSet        piBoardId           piBoard40Pin
    piRP1Model          getPinModeAlt       wiringPiGlobalMemoryAccess
    wiringPiUserLevelAccess                 wiringPiSetupPinType
    wiringPiSetupGpioDevice                 wiringPiGpioDeviceGetFd
);

my @wpi_perl_functions = qw(
    setup           setup_gpio      pull_up_down        read_pin
    write_pin       pwm_write
    get_alt         gpio_layout     wpi_to_gpio         phys_to_gpio
    lcd_init        lcd_home        lcd_clear
    lcd_display     lcd_cursor      lcd_cursor_blink    lcd_send_cmd
    lcd_position    lcd_char_def    lcd_put_char        lcd_puts
    set_interrupt   interrupt_fd        dispatch_interrupts
    wait_interrupts interrupt_dropped   stop_interrupt
    stop_interrupts
    bmp180_setup    bmp180_pressure     bmp180_temp
    shift_reg_setup analog_read     analog_write        pin_mode
    ads1115_setup   spi_setup       spi_data            i2c_setup
    i2c_interface   i2c_read        i2c_read_byte       i2c_read_word
    i2c_write       i2c_write_byte  i2c_write_word
    i2c_read_block  i2c_raw_read    i2c_write_block     i2c_raw_write
    spi_get_fd      spi_setup_mode  spi_close
    soft_tone_create                soft_tone_stop      soft_tone_write
    phys_to_wpi     pin_mode_alt    serial_open         serial_flush
    serial_put_char serial_puts     serial_data_avail   serial_get_char 
    serial_close    serial_gets     pwm_set_range       pwm_set_clock
    pwm_set_mode    wiringpi_version
    soft_pwm_create soft_pwm_write   soft_pwm_stop       pi_lock
    pi_unlock       digital_read_byte                    digital_read_byte2
    digital_write_byte                  digital_write_byte2
    delay_microseconds                  pi_micros64         pi_hi_pri
    set_pad_drive   set_pad_drive_pin   pwm_tone_write      gpio_clock_set
    pi_board_id     pi_board40_pin      pi_rp1_model        get_pin_mode_alt
    wiringpi_global_memory_access        wiringpi_user_level_access
    wiringpi_setup_pin_type             wiringpi_setup_gpio_device
    wiringpi_gpio_device_get_fd
);

my @wpi_constants = qw(
    WPI_PIN_BCM     WPI_PIN_WPI
    INT_EDGE_SETUP  INT_EDGE_FALLING    INT_EDGE_RISING     INT_EDGE_BOTH
);

our @EXPORT_OK;

@EXPORT_OK = (@wpi_c_functions, @wpi_perl_functions, @wpi_constants);
our %EXPORT_TAGS;

$EXPORT_TAGS{wiringPi} = [@wpi_c_functions];
$EXPORT_TAGS{perl} = [@wpi_perl_functions];
$EXPORT_TAGS{constants} = [@wpi_constants];
$EXPORT_TAGS{all} = [@wpi_c_functions, @wpi_perl_functions, @wpi_constants];

# Interrupt dispatch state (per-interpreter). The callback registry lives here
# in Perl - the wiringPi ISR thread only writes event records to the self-pipe
# (see API.xs); dispatch runs callbacks in whichever interpreter services the fd.
my %_interrupt_cb;                  # pin => CODE ref
my $_interrupt_fh;                  # cached read handle (dup of interrupt_fd())
my $_interrupt_fh_fd;               # the fd $_interrupt_fh was opened on

sub new {
    return bless {}, shift;
}

# serial functions

sub serial_open {
    shift if @_ > 2;
    my ($dev_ptr, $baud) = @_;
    my $fd = serialOpen($dev_ptr, $baud);
    croak "could not open serial device $dev_ptr\n" if $fd == -1;
    return $fd;
}
sub serial_close {
    shift if @_ > 1;
    my ($fd) = @_;
    serialClose($fd);
}
sub serial_flush {
    shift if @_ > 1;
    my ($fd) = @_;
    serialFlush($fd);
}
sub serial_put_char {
    shift if @_ > 2;
    my ($fd, $unsigned_char) = @_;
    serialPutchar($fd, $unsigned_char);
}
sub serial_puts {
    shift if @_ > 2;
    my ($fd, $char) = @_;
    serialPuts($fd, $char);
}
sub serial_data_avail {
    shift if @_ > 1;
    my ($fd) = @_;
    serialDataAvail($fd);
}
sub serial_get_char {
    shift if @_ > 1;
    my ($fd) = @_;
    serialGetchar($fd);
}
sub serial_gets {
    shift if @_ > 2;
    my ($fd, $nbytes) = @_;
    my $buf = "";
    my $char_ptr = serialGets($fd, $buf, $nbytes);
    my $unpacked = unpack "A*", $char_ptr;
    return $unpacked;
}

# interrupt functions

sub set_interrupt {
    shift if @_ && ref $_[0];   # drop $self on method calls ($pin is never a ref)
    my ($pin, $edge, $callback, $debounce_us) = @_;

    if (! defined $pin || $pin !~ /^\d+$/) {
        croak "set_interrupt() requires \$pin to be a positive integer";
    }

    if (! defined $edge || $edge !~ /^[123]$/) {
        croak "set_interrupt() \$edge must be INT_EDGE_FALLING (1), " .
            "INT_EDGE_RISING (2) or INT_EDGE_BOTH (3)";
    }

    if (! defined $callback || ref $callback ne 'CODE') {
        croak "set_interrupt() requires \$callback to be a CODE reference";
    }

    $debounce_us = 0 if ! defined $debounce_us;

    if ($debounce_us !~ /^\d+$/) {
        croak "set_interrupt() \$debounce_us must be a non-negative integer";
    }

    # The callback stays in Perl, keyed by the user's pin; the ISR thread only
    # writes {pin, edge, ts} records to the self-pipe. dispatch_interrupts()
    # fans them back out to these callbacks in the consuming interpreter.
    $_interrupt_cb{$pin} = $callback;

    return _arm_interrupt($pin, $edge, $debounce_us);
}
sub dispatch_interrupts {
    shift if @_ == 1;

    my $fh = _interrupt_fh();
    return 0 if ! defined $fh;

    my $dispatched = 0;

    while (1) {
        my $buf = "";
        my $n = sysread($fh, $buf, 16);

        if (! defined $n) {
            next if $!{EINTR};      # interrupted before any data - retry
            last;                   # EAGAIN (drained) or a real error - stop
        }

        last if $n == 0;            # EOF: all write ends closed
        last if $n != 16;           # short read (16-byte writes are atomic)

        my ($pin, $edge, $ts_us) = unpack "i i q", $buf;

        my $cb = $_interrupt_cb{$pin};
        $cb->($edge, $ts_us) if $cb;

        $dispatched++;
    }

    return $dispatched;
}
sub wait_interrupts {
    shift if @_ && ref $_[0];   # drop $self on method calls
    my ($timeout_ms) = @_;

    my $fh = _interrupt_fh();
    return 0 if ! defined $fh;

    my $rin = "";
    vec($rin, fileno($fh), 1) = 1;

    my $timeout = defined $timeout_ms ? $timeout_ms / 1000 : undef;
    my $nfound = select(my $rout = $rin, undef, undef, $timeout);

    return 0 if ! $nfound || $nfound < 0;   # timeout or error

    return dispatch_interrupts();
}
sub stop_interrupt {
    shift if @_ == 2;
    my ($pin) = @_;

    if (! defined $pin || $pin !~ /^\d+$/) {
        croak "stop_interrupt() requires \$pin to be a positive integer";
    }

    wiringPiISRStop($pin);
    delete $_interrupt_cb{$pin};

    return 1;
}
sub stop_interrupts {
    shift if @_ == 1;

    stop_interrupt($_) for keys %_interrupt_cb;

    # Drop our cached read dup, then close the C-side pipe (this discards any
    # records still buffered) and reset the dropped counter. A later
    # set_interrupt() lazily re-creates the pipe.
    if (defined $_interrupt_fh) {
        close $_interrupt_fh;
        $_interrupt_fh    = undef;
        $_interrupt_fh_fd = undef;
    }

    _close_interrupt_pipe();

    return 1;
}

sub _interrupt_fh {
    my $fd = interrupt_fd();
    return undef if $fd < 0;

    # Re-open if the pipe was torn down and re-armed onto a different fd. A dup
    # ("<&") gives us our own fd sharing the pipe's non-blocking description, so
    # closing this handle never closes the C-side interrupt_fd().
    if (! defined $_interrupt_fh || ! defined $_interrupt_fh_fd
        || $_interrupt_fh_fd != $fd) {
        close $_interrupt_fh if defined $_interrupt_fh;
        open($_interrupt_fh, "<&", $fd)
            or croak "could not access the interrupt fd ($fd): $!";
        $_interrupt_fh_fd = $fd;
    }

    return $_interrupt_fh;
}

# system functions

sub setup {
    return wiringPiSetup();
}
sub setup_gpio {
    return wiringPiSetupGpio();
}
sub wiringpi_setup_pin_type {
    shift if @_ == 2;
    my ($pin_type) = @_;

    if (! defined $pin_type
        || $pin_type !~ /^\d+$/
        || ($pin_type != WPI_PIN_BCM && $pin_type != WPI_PIN_WPI)) {
        croak "wiringpi_setup_pin_type() requires WPI_PIN_BCM or WPI_PIN_WPI " .
              "(physical-pin setup is not supported)";
    }

    return wiringPiSetupPinType($pin_type);
}
sub wiringpi_setup_gpio_device {
    shift if @_ == 2;
    my ($pin_type) = @_;

    if (! defined $pin_type
        || $pin_type !~ /^\d+$/
        || ($pin_type != WPI_PIN_BCM && $pin_type != WPI_PIN_WPI)) {
        croak "wiringpi_setup_gpio_device() requires WPI_PIN_BCM or " .
              "WPI_PIN_WPI (physical-pin setup is not supported)";
    }

    return wiringPiSetupGpioDevice($pin_type);
}
sub wiringpi_gpio_device_get_fd {
    return wiringPiGpioDeviceGetFd();
}
sub wiringpi_version {
    my $ver = wiringPiVersion();

    if (wantarray) {
        my ($major, $minor) = split /\./, $ver;
        return ($major, $minor);
    }

    return $ver;
}

# pin functions

sub pin_mode {
    shift if @_ == 3;
    my ($pin, $mode) = @_;
    if (! grep {$mode == $_} qw(0 1 2 3)){
        croak "pin_mode() requires either 0, 1, 2 or 3 as a param";
    }
    pinMode($pin, $mode);
}
sub pin_mode_alt {
    shift if @_ == 3;
    my ($pin, $alt) = @_;

    if (! grep {$alt == $_} 0..7){
        croak "pin_mode_alt() requires 0-7 as a param";
    }

    # 0     INPUT
    # 1     OUTPUT
    # 4     ALT0
    # 5     ALT1
    # 6     ALT2
    # 7     ALT3
    # 3     ALT4
    # 2     ALT5

    pinModeAlt($pin, $alt);
}
sub pull_up_down {
    shift if @_ == 3;
    my ($pin, $value) = @_;
    # off, down up = 0, 1, 2
    pullUpDnControl($pin, $value);
    select(undef, undef, undef, 0.02);
}
sub read_pin {
    shift if @_ == 2;
    my $pin = shift;
    return digitalRead($pin);
}
sub write_pin {
    shift if @_ == 3;
    my ($pin, $value) = @_;
    digitalWrite($pin, $value);
}
sub pwm_write {
    shift if @_ == 3;
    my ($pin, $value) = @_;
    pwmWrite($pin, $value);
}
sub get_alt {
    shift if @_ == 2;
    my $pin = shift;
    return getAlt($pin);
}
sub analog_read {
    shift if @_ == 2;
    my ($pin) = @_;
    return analogRead($pin)
}
sub analog_write {
    shift if @_ == 3;
    my ($pin, $value) = @_;
    return analogWrite($pin, $value);
}
sub digital_read_byte {
    return digitalReadByte();
}
sub digital_read_byte2 {
    return digitalReadByte2();
}
sub digital_write_byte {
    shift if @_ == 2;
    my ($value) = @_;
    digitalWriteByte($value);
}
sub digital_write_byte2 {
    shift if @_ == 2;
    my ($value) = @_;
    digitalWriteByte2($value);
}

# board functions

sub gpio_layout {
    return piGpioLayout();
}
sub wpi_to_gpio {
    shift if @_ == 2;
    my $pin = shift;
    return wpiPinToGpio($pin);
}
sub phys_to_gpio {
    shift if @_ == 2;
    my $pin = shift;
    return physPinToGpio($pin);
}
sub phys_to_wpi {
    shift if @_ == 2;
    my $pin = shift;
    return physPinToWpi($pin);
}
sub pwm_set_range {
    shift if @_ > 1;
    my $range = shift;
    pwmSetRange($range);
}
sub pwm_set_clock {
    shift if @_ > 1;
    my $divisor = shift;
    pwmSetClock($divisor);
}
sub pwm_set_mode {
    shift if @_ > 1;
    my $mode = shift;
    pwmSetMode($mode);
}

# soft pwm functions

sub soft_pwm_create {
    shift if @_ == 4;
    my ($pin, $value, $range) = @_;
    return softPwmCreate($pin, $value, $range);
}
sub soft_pwm_write {
    shift if @_ == 3;
    my ($pin, $value) = @_;
    softPwmWrite($pin, $value);
}
sub soft_pwm_stop {
    shift if @_ == 2;
    my ($pin) = @_;
    softPwmStop($pin);
}

# soft tone functions

sub soft_tone_create {
    shift if @_ == 2;
    my ($pin) = @_;
    return softToneCreate($pin);
}
sub soft_tone_stop {
    shift if @_ == 2;
    my ($pin) = @_;
    softToneStop($pin);
}
sub soft_tone_write {
    shift if @_ == 3;
    my ($pin, $freq) = @_;
    softToneWrite($pin, $freq);
}

# thread/lock functions

sub pi_lock {
    shift if @_ == 2;
    my ($key) = @_;
    piLock($key);
}
sub pi_unlock {
    shift if @_ == 2;
    my ($key) = @_;
    piUnlock($key);
}

# timing functions

# delay(), millis(), micros() are exported directly as their wiringPi C names
# (under the :wiringPi tag); a same-named Perl wrapper would shadow the XS sub.

sub delay_microseconds {
    shift if @_ == 2;
    my ($us) = @_;
    delayMicroseconds($us);
}
sub pi_micros64 {
    return piMicros64();
}
sub pi_hi_pri {
    shift if @_ == 2;
    my ($pri) = @_;
    return piHiPri($pri);
}

# pad drive / pwm tone / gpio clock functions

sub set_pad_drive {
    shift if @_ == 3;
    my ($group, $value) = @_;
    setPadDrive($group, $value);
}
sub set_pad_drive_pin {
    shift if @_ == 3;
    my ($pin, $value) = @_;
    setPadDrivePin($pin, $value);
}
sub pwm_tone_write {
    shift if @_ == 3;
    my ($pin, $freq) = @_;
    pwmToneWrite($pin, $freq);
}
sub gpio_clock_set {
    shift if @_ == 3;
    my ($pin, $freq) = @_;
    gpioClockSet($pin, $freq);
}

# board / identity functions

sub pi_board_id {
    my ($model, $rev, $mem, $maker, $over_volted) = piBoardId();

    if (wantarray) {
        return ($model, $rev, $mem, $maker, $over_volted);
    }

    return {
        model       => $model,
        rev         => $rev,
        mem         => $mem,
        maker       => $maker,
        over_volted => $over_volted,
    };
}
sub pi_board40_pin {
    return piBoard40Pin();
}
sub pi_rp1_model {
    return piRP1Model();
}
sub get_pin_mode_alt {
    shift if @_ == 2;
    my ($pin) = @_;
    return getPinModeAlt($pin);
}
sub wiringpi_global_memory_access {
    return wiringPiGlobalMemoryAccess();
}
sub wiringpi_user_level_access {
    return wiringPiUserLevelAccess();
}

# lcd functions

sub lcd_init {
    shift if @_ == 27;
    my %params = @_;

    my @required_args = qw(
        rows cols bits rs strb
        d0 d1 d2 d3 d4 d5 d6 d7
    );

    my @args;
    for (@required_args){
        if (! defined $params{$_}) {
            croak "\n'$_' is a required param for WiringPi::API::lcd_init()\n";
        }
        push @args, $params{$_};
    }

    my $fd = lcdInit(@args); # LCD handle
    return $fd;
}
sub lcd_home {
    shift if @_ == 2;
    lcdHome($_[0]);
}
sub lcd_clear {
    shift if @_ == 2;
    lcdClear($_[0]);
}
sub lcd_display {
    shift if @_ == 3;
    my ($fd, $state) = @_;
    lcdDisplay($fd, $state);
}
sub lcd_cursor {
    shift if @_ == 3;
    my ($fd, $state) = @_;
    lcdCursor($fd, $state);
}
sub lcd_cursor_blink {
    shift if @_ == 3;
    my ($fd, $state) = @_;
    lcdCursorBlink($fd, $state);
}
sub lcd_send_cmd {
    shift if @_ == 3;
    my ($fd, $cmd) = @_;
    lcdSendCommand($fd, $cmd);
}
sub lcd_position {
    shift if @_ == 4;
    my ($fd, $x, $y) = @_;
    lcdPosition($fd, $x, $y);
}
sub lcd_char_def {
    shift if @_ == 4;
    my ($fd, $index, $data) = @_;
    my $unsigned_char = pack "C[8]", @$data;
    lcdCharDef($fd, $index, $unsigned_char);
}
sub lcd_put_char {
    shift if @_ == 3;
    my ($fd, $data) = @_;
    lcdPutchar($fd, $data);
}
sub lcd_puts {
    shift if @_ == 3;
    my ($fd, $string) = @_;
    lcdPuts($fd, $string);
}

# ads1115 functions

sub ads1115_setup {
    shift if @_ == 3;
    my ($pin_base, $addr) = @_;

    return ads1115Setup($pin_base, $addr);
}

# shift register functions

sub shift_reg_setup {
    shift if @_ == 6;
    my ($pin_base, $num_pins, $data_pin, $clock_pin, $latch_pin) = @_;

    croak "\$pin_base must be an integer\n" if $pin_base !~ /^\d+$/;

    if ($num_pins < 0 || $num_pins > 32){
        croak "\$num_pins must be between 0 and 32\n";
    }

    for ($data_pin, $clock_pin, $latch_pin){
        if ($_ < 0 || $_ > 40){
            croak "$data_pin, $clock_pin and $latch_pin must all be valid " .
                "GPIO pin numbers\n";
        }
    }

    sr595Setup($pin_base, $num_pins, $data_pin, $clock_pin, $latch_pin);
}

# I2C functions

sub i2c_setup {
    shift if @_ == 2;
    my ($addr) = @_;

    if (! defined $addr){
        croak "i2c_setup() requires an \$addr param\n";
    }

    if ($addr =~ /^0x[0-9a-fA-F]+$/){
        $addr = hex($addr);
    }
    elsif ($addr !~ /^\d+$/){
        croak "i2c_setup() address param must be an integer or hex value\n";
    }

    # file descriptor

    return wiringPiI2CSetup($addr);
}
sub i2c_interface {
    shift if @_ > 2;
    my ($device, $dev_id) = @_;

    if (! defined $device){
        croak "i2c_interface() requires a \$device param\n";
    }
    if (! defined $dev_id){
        croak "i2c_interface() requires a \$dev_id param\n";
    }

    return wiringPiI2CSetupInterface($device, $dev_id);
}
sub i2c_read {
    shift if @_ > 1;
    my ($fd) = @_;

    if (! defined $fd){
        croak "i2c_read() requires an \$fd param\n";
    }

    return wiringPiI2CRead($fd);
}
sub i2c_read_byte {
    shift if @_ > 2;
    my ($fd, $reg) = @_;

    if (! defined $fd){
        croak "i2c_read_byte() requires an \$fd param\n";
    }
    if (! defined $reg){
        croak "i2c_read_byte() requires a \$register param\n";
    }

    return wiringPiI2CReadReg8($fd, $reg);
}
sub i2c_read_word {
    shift if @_ > 2;
    my ($fd, $reg) = @_;

    if (! defined $fd){
        croak "i2c_read_word() requires an \$fd param\n";
    }
    if (! defined $reg){
        croak "i2c_read_word() requires a \$register param\n";
    }

    return wiringPiI2CReadReg16($fd, $reg);
}
sub i2c_write {
    shift if @_ > 2;
    my ($fd, $data) = @_;

    if (! defined $fd){
        croak "i2c_write() requires an \$fd param\n";
    }
    if (! defined $data){
        croak "i2c_write() requires a \$data param\n";

    }
    return wiringPiI2CWrite($fd, $data);
}
sub i2c_write_byte {
    shift if @_ > 3;
    my ($fd, $reg, $data) = @_;

    if (! defined $fd){
        croak "i2c_write_byte() requires an \$fd param\n";
    }
    if (! defined $reg){
        croak "i2c_write_byte() requires a \$register param\n";
    }
    if (! defined $data){
        croak "i2c_write_byte() requires a \$data param\n";
    }

    return wiringPiI2CWriteReg8($fd, $reg, $data);
}
sub i2c_write_word {
    shift if @_ > 3;
    my ($fd, $reg, $data) = @_;

    if (! defined $fd){
        croak "i2c_write_word() requires an \$fd param\n";
    }
    if (! defined $reg){
        croak "i2c_write_word() requires a \$register param\n";
    }
    if (! defined $data){
        croak "i2c_write_word() requires a \$data param\n";
    }

    return wiringPiI2CWriteReg16($fd, $reg, $data);
}
sub i2c_read_block {
    shift if @_ > 3;
    my ($fd, $reg, $size) = @_;

    if (! defined $fd){
        croak "i2c_read_block() requires an \$fd param\n";
    }
    if (! defined $reg){
        croak "i2c_read_block() requires a \$register param\n";
    }
    if (! defined $size){
        croak "i2c_read_block() requires a \$size param\n";
    }

    return wiringPiI2CReadBlockData($fd, $reg, $size);
}
sub i2c_raw_read {
    shift if @_ > 2;
    my ($fd, $size) = @_;

    if (! defined $fd){
        croak "i2c_raw_read() requires an \$fd param\n";
    }
    if (! defined $size){
        croak "i2c_raw_read() requires a \$size param\n";
    }

    return wiringPiI2CRawRead($fd, $size);
}
sub i2c_write_block {
    shift if @_ > 3;
    my ($fd, $reg, $values) = @_;

    if (! defined $fd){
        croak "i2c_write_block() requires an \$fd param\n";
    }
    if (! defined $reg){
        croak "i2c_write_block() requires a \$register param\n";
    }
    if (ref $values ne 'ARRAY'){
        croak "i2c_write_block() requires an array reference of bytes\n";
    }

    return wiringPiI2CWriteBlockData($fd, $reg, $values);
}
sub i2c_raw_write {
    shift if @_ > 2;
    my ($fd, $values) = @_;

    if (! defined $fd){
        croak "i2c_raw_write() requires an \$fd param\n";
    }
    if (ref $values ne 'ARRAY'){
        croak "i2c_raw_write() requires an array reference of bytes\n";
    }

    return wiringPiI2CRawWrite($fd, $values);
}

# SPI functions

sub spi_setup {
    shift if @_ == 3;
    my ($channel, $speed) = @_;

    if ($channel != 0 && $channel != 1){
        croak "spi_setup() channel param must be 0 or 1\n";
    }

    $speed = 1000000 if ! defined $speed;

    return wiringPiSPISetup($channel, $speed);
}
sub spi_data {
    shift if @_ == 4;
    my ($chan, $data, $len) = @_;

    if ($chan != 0 && $chan != 1){
        croak "spi_data() channel param must be 0 or 1\n";
    }

    if (ref $data ne 'ARRAY'){
        croak "spi_data() data param must be an array reference\n";
    }
    if (@$data != $len){
        croak "spi_data() array reference must have \$len param count\n";
    }

    my $buf;

    for (@$data){
        push @$buf, $_;
    }

    return spiDataRW($chan, $buf, $len);
}
sub spi_get_fd {
    shift if @_ > 1;
    my ($channel) = @_;

    if (! defined $channel || ($channel != 0 && $channel != 1)){
        croak "spi_get_fd() channel param must be 0 or 1\n";
    }

    return wiringPiSPIGetFd($channel);
}
sub spi_setup_mode {
    shift if @_ > 3;
    my ($channel, $speed, $mode) = @_;

    if (! defined $channel || ($channel != 0 && $channel != 1)){
        croak "spi_setup_mode() channel param must be 0 or 1\n";
    }
    if (! defined $speed){
        croak "spi_setup_mode() requires a \$speed param\n";
    }
    if (! defined $mode){
        croak "spi_setup_mode() requires a \$mode param\n";
    }

    return wiringPiSPISetupMode($channel, $speed, $mode);
}
sub spi_close {
    shift if @_ > 1;
    my ($channel) = @_;

    if (! defined $channel || ($channel != 0 && $channel != 1)){
        croak "spi_close() channel param must be 0 or 1\n";
    }

    return wiringPiSPIClose($channel);
}

# bmp180 pressure sensor functions

sub bmp180_setup {
    shift if @_ == 2;
    my $base = shift;

    if (! defined $base || $base !~ /^\d+$/){
        croak "bmp180 setup parametermust be an integer\n";
    }

    bmp180Setup($base);
}
sub bmp180_temp {
    shift if ref $_[0];
    my ($pin, $want) = @_;

    $want = 'f' if ! defined $want;
    
    my $temp = bmp180Temp($pin);
    my $c = $temp / 10;

    if ($want eq 'f'){
        # returning farenheit
        return $c * 1.8 + 32;
    }
    else {
        # returning celcius
        return $c;
    }
}
sub bmp180_pressure {
    shift if ref $_[0];
    my ($pin) = @_;

    # return kPa
    return bmp180Pressure($pin) / 100;
}
sub _vim{1;};

1;
__END__

=head1 NAME

WiringPi::API - API for wiringPi, providing access to the Raspberry Pi's board,
GPIO and connected peripherals

=head1 SYNOPSIS

No matter which import option you choose, before you can start making calls,
you must initialize the software by calling one of the C<setup*()> routines.

    use WiringPi::API qw(:all)

    # use as a base class with OO functionality

    use parent 'WiringPi::API';

    # use in the traditional Perl OO way

    use WiringPi::API;

    my $api = WiringPi::API->new;

=head1 DESCRIPTION

This is an XS-based module, and requires L<wiringPi|http://wiringpi.com> version
3.18+ to be installed. The C<wiringPiDev> shared library is also required (for
the LCD functionality), but it's installed by default with C<wiringPi>.

See the documentation on the L<wiringPi|http://wiringpi.com> website for a more
in-depth description of most of the functions it provides. Some of the
functions we've wrapped are not documented, they were just selectively plucked
from the C code itself. Each mapped function lists which C function it is
responsible for.

=head1 EXPORT_OK

Exported with the C<:all> tag, or individually.

Perl wrapper functions for the XS functions. Not all of these are direct
wrappers; several have additional/modified functionality than the wrapped
versions, but are still 100% compatible.

    setup           setup_gpio      pull_up_down        read_pin
    write_pin       pwm_write
    get_alt         gpio_layout     wpi_to_gpio         phys_to_gpio
    pwm_set_range   lcd_init        lcd_home            lcd_clear
    lcd_display     lcd_cursor      lcd_cursor_blink    lcd_send_cmd
    lcd_position    lcd_char_def    lcd_put_char        lcd_puts
    set_interrupt   pin_mode        analog_read         analog_write
    shift_reg_setup bmp180_setup    bmp180_pressure     bmp180_temp
    ads1115_setup   spi_setup       spi_data            phys_to_wpi
    serial_open     serial_flush    serial_put_char     serial_puts
    serial_get_char serial_close    serial_data_avail   pwm_set_clock
    pwm_set_mode

=head1 EXPORT_TAGS

See L<EXPORT_OK>

=head2 :all

Exports all available exportable functions.

=head2 :perl

Export only Perlish snake_case named version of the functions.

=head2 :wiringPi

Export only the C based camelCase version of the function names.

=head1 FUNCTION TABLE OF CONTENTS

=head2 CORE

See L</CORE FUNCTIONS>.

=head2 BOARD

See L</BOARD FUNCTIONS>.

=head2 LCD

See L</LCD FUNCTIONS>.

=head2 INTERRUPT

See L</INTERRUPT FUNCTIONS>.

=head2 ANALOG TO DIGITAL CONVERTER

See L</ADC FUNCTIONS>.

=head2 SHIFT REGISTER

See L</SHIFT REGISTER FUNCTIONS>

=head2 SERIAL

See L</SERIAL FUNCTIONS>

=head2 I2C

See L</I2C FUNCTIONS>

=head2 SPI

See L</SPI FUNCTIONS>

=head2 BAROMETRIC SENSOR

See L</BMP180 PRESSURE SENSOR FUNCTIONS>.

=head1 CORE FUNCTIONS

=head2 new()

NOTE: After an object is created, one of the C<setup*> methods must be called
to initialize the Pi board.

Returns a new C<WiringPi::API> object.

=head2 setup()

Maps to C<int wiringPiSetup()>

Sets the pin number mapping scheme to C<wiringPi>.

See L<pinout.xyz|https://pinout.xyz/pinout/wiringpi> for a pin number
conversion chart, or on the command line, run C<gpio readall>.

Note that only one of the C<setup*()> methods should be called per program run.

=head2 setup_gpio()

Maps to C<int wiringPiSetupGpio()>

Sets the pin numbering scheme to C<GPIO>.

Personally, this is the setup routine that I always use, due to the GPIO numbers
physically printed right on the Pi board.

=head2 wiringpi_setup_pin_type($pin_type)

Maps to C<int wiringPiSetupPinType(enum WPIPinType pinType)>

A unified setup routine that takes the pin-numbering scheme as a parameter,
rather than having a separate function per scheme. C<$pin_type> must be one of
the exported constants C<WPI_PIN_BCM> (equivalent to C<setup_gpio()>) or
C<WPI_PIN_WPI> (equivalent to C<setup()>).

Physical-pin setup (C<WPI_PIN_PHYS>) is B<not supported> - that constant is not
exported, and passing it (or any other value) causes a C<croak>.

=head2 wiringpi_setup_gpio_device($pin_type)

Maps to C<int wiringPiSetupGpioDevice(enum WPIPinType pinType)>

As C<wiringpi_setup_pin_type()>, but initialises wiringPi over the GPIO
character-device (libgpiod) interface instead of the legacy C</dev/gpiomem>
memory-mapped path. C<$pin_type> takes the same C<WPI_PIN_BCM> / C<WPI_PIN_WPI>
constants and is validated the same way.

This is offered as an opt-in alternative; the default C<setup()> / C<setup_gpio()>
routines are unchanged.

=head2 wiringpi_gpio_device_get_fd()

Maps to C<int wiringPiGpioDeviceGetFd()>

Returns the open file descriptor of the GPIO character device, when wiringPi was
initialised via C<wiringpi_setup_gpio_device()>.

The pin-type constants C<WPI_PIN_BCM> and C<WPI_PIN_WPI> are available
individually or via the C<:constants> / C<:all> export tags.

=head2 wiringpi_version()

Maps to C<void wiringPiVersion(int *major, int *minor)>.

Returns the version of the installed B<wiringPi C library> (eg. C<3.18>). This
is the underlying library version, B<not> the C<$VERSION> of this Perl
distribution.

In scalar context, returns the version as a string (eg. C<"3.18">). In list
context, returns the C<($major, $minor)> integer pair (eg. C<(3, 18)>).

The exported C-level C<wiringPiVersion()> always returns the version string.

=head2 pin_mode($pin, $mode)

Maps to C<void pinMode(int pin, int mode)>

Puts the pin in either INPUT, OUTPUT, PWM or GPIO_CLOCK mode.

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

    $mode

Mandatory: C<0> for INPUT, C<1> OUTPUT, C<2> PWM_OUTPUT and C<3> GPIO_CLOCK.

=head2 pin_mode_alt($pin, $alt)

Maps to the undocumented C<void pinModeAlt(int pin, int mode)>

Allows you to set any pin to any mode. ALT modes allowed:

    value   mode
    ------------
    0       INPUT
    1       OUTPUT
    4       ALT0
    5       ALT1
    6       ALT2
    7       ALT3
    3       ALT4
    2       ALT5

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

    $alt

Mandatory, Integer: The mode you want to put the pin into. See the list above
for the relevant values for this parameter.

=head2 read_pin($pin);

Maps to C<int digitalRead(int pin)>

Returns the current state (HIGH/on, LOW/off) of a given pin.

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

=head2 write_pin($pin, $state)

Maps to C<void digitalWrite(int pin, int state)>

Sets the state (HIGH/on, LOW/off) of a given pin.

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

    $state

Mandatory: C<1> to turn the pin on (HIGH), and C<0> to turn it LOW (off).

=head2 analog_read($pin);

Maps to C<int analogRead(int pin)>

Returns the data for an analog pin. Note that the Raspberry Pi doesn't have
analog pins, so this is used when connected through an ADC or to pseudo analog
pins.

Parameters:

    $pin

Mandatory: The pseudo pin number, in the pin numbering scheme dictated by
whichever C<setup*()> routine you used.

=head2 analog_write($pin, $value)

Maps to C<void analogWrite(int pin, int value)>

Writes the value to the corresponding analog pseudo pin.

Parameters:

    $pin

Mandatory: The pseudo pin number, in the pin numbering scheme dictated by
whichever C<setup*()> routine you used.

    $value

Mandatory: The data which you want to write to the pseudo pin. 

=head2 pull_up_down($pin, $direction)

Maps to C<void pullUpDnControl(int pin, int pud)>

Enable/disable the built-in pull up/down resistors for a specified pin.

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

    $direction

Mandatory: C<2> for UP, C<1> for DOWN and C<0> to disable the resistor.

=head2 pwm_write($pin, $value)

Maps to C<void pwmWrite(int pin, int value)>

Sets the Pulse Width Modulation duty cycle (on-time) of the pin.

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

    $value

Mandatory: C<0> to C<1023>. C<0> is 0% (off) and C<1023> is 100% (fully on).

=head2 get_alt($pin)

Maps to C<int getAlt(int pin)>

This returns the current mode of the pin (using C<getAlt()> C call). Modes are
INPUT C<0>, OUTPUT C<1>, PWM_OUT C<2> and CLOCK C<3>.

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

=head2 digital_read_byte()

Maps to C<unsigned int digitalReadByte()>

Reads all eight bits of the first 8-bit GPIO bank at once and returns the value
as a single integer (C<0>-C<255>).

B<Note:> the byte-bank operations (C<digital_read_byte()>,
C<digital_read_byte2()>, C<digital_write_byte()>, C<digital_write_byte2()>) are
B<not supported on the Raspberry Pi 5>. On a Pi 5, the underlying wiringPi call
prints a diagnostic and terminates the process.

=head2 digital_read_byte2()

Maps to C<unsigned int digitalReadByte2()>

As C<digital_read_byte()>, but reads the second 8-bit GPIO bank.

=head2 digital_write_byte($value)

Maps to C<void digitalWriteByte(int value)>

Writes the 8-bit C<$value> (C<0>-C<255>) to the first 8-bit GPIO bank in a
single operation.

Parameters:

    $value

Mandatory: An integer C<0>-C<255>; each bit is written to the corresponding pin
of the bank.

=head2 digital_write_byte2($value)

Maps to C<void digitalWriteByte2(int value)>

As C<digital_write_byte()>, but writes to the second 8-bit GPIO bank.

=head1 BOARD FUNCTIONS

=head2 gpio_layout()

Maps to C<int piGpioLayout()>

Returns the Raspberry Pi board's GPIO layout (ie. the board revision).

=head2 wpi_to_gpio($pin_num)

Maps to C<int wpiPinToGpio(int pin)>

Converts a C<wiringPi> pin number to the Broadcom (GPIO) representation, and
returns it.

Parameters:

    $pin_num

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

=head2 phys_to_gpio($pin_num)

Maps to C<int physPinToGpio(int pin)>

Converts the pin number on the physical board to the C<GPIO> representation,
and returns it.

Parameters:

    $pin_num

Mandatory: The pin number on the physical Raspberry Pi board.

=head2 phys_to_wpi($pin_num)

Maps to C<int physPinToWpi(int pin)>

Converts the pin number on the physical board to the C<wiringPi> numbering
representation, and returns it.

Parameters:

    $pin_num

Mandatory: The pin number on the physical Raspberry Pi board.

=head2 pwm_set_range($range)

Maps to C<void pwmSetRange(int range)>

Sets the range register of the Pulse Width Modulation (PWM) functionality. It
defaults to C<1024> (C<0-1023>).

Parameters:

    $range

Mandatory: An integer between C<0> and C<1023>.

=head2 pwm_set_clock($divisor)

Maps to C<void pwmSetClock(int divisor)>.

The PWM clock can be set to control the PWM pulse widths. The PWM clock is
derived from a 19.2MHz clock. You can set any divider.

For example, say you wanted to drive a DC motor with PWM at about 1kHz, and
control the speed in 1/1024 increments from 0/1024 (stopped) through to
1024/1024 (full on). In that case you might set the clock divider to be 16, and
the RANGE to 1024. The pulse repetition frequency will be
1.2MHz/1024 = 1171.875Hz.

Parameters:

    $divisor

Mandatory, Integer: An unsigned integer to set the pulse width to.

=head2 pwm_set_mode($mode)

Each PWM channel can run in either Balanced or Mark-Space mode. In Balanced
mode, the hardware sends a combination of clock pulses that results in an
overall DATA pulses per RANGE pulses. In Mark-Space mode, the hardware sets the
output HIGH for DATA clock pulses wide, followed by LOW for RANGE-DATA clock
pulses.

Parameters:

    $mode

Mandatory, Integer: C<0> for Mark-Space mode, or C<1> for Balanced mode.

Note: If using L<RPi::WiringPi::Constant>, you can use C<PWM_MODE_MS> or
C<PWM_MODE_BAL>.

=head1 SOFT PWM FUNCTIONS

Software-driven PWM on any GPIO pin. See
L<wiringPi softPwm page|http://wiringpi.com/reference/software-pwm-library/>.

=head2 soft_pwm_create($pin, $value, $range)

Maps to C<int softPwmCreate(int pin, int value, int range)>

Creates a software-controlled PWM pin. Returns C<0> on success.

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

    $value

Mandatory: The initial duty-cycle value, between C<0> and C<$range>.

    $range

Mandatory: The PWM range (a typical value is C<100>).

=head2 soft_pwm_write($pin, $value)

Maps to C<void softPwmWrite(int pin, int value)>

Updates the PWM duty-cycle value on a pin previously set up with
C<soft_pwm_create()>.

Parameters:

    $pin

Mandatory: The pin number.

    $value

Mandatory: The new duty-cycle value, between C<0> and the range the pin was
created with.

=head2 soft_pwm_stop($pin)

Maps to C<void softPwmStop(int pin)>

Stops software PWM on the given pin.

Parameters:

    $pin

Mandatory: The pin number.

=head1 SOFT TONE FUNCTIONS

Software-generated tone (square-wave frequency) output on any GPIO pin. See
L<wiringPi softTone page|http://wiringpi.com/reference/software-tone-library/>.

(Note: wiringPi's C<softServo> library is not built into the wiringPi 3.18
shared library and is therefore not wrapped.)

=head2 soft_tone_create($pin)

Maps to C<int softToneCreate(int pin)>

Sets up a pin for software tone output. Returns C<0> on success.

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

=head2 soft_tone_write($pin, $freq)

Maps to C<void softToneWrite(int pin, int freq)>

Sets the frequency (in Hz) of the tone on a pin previously set up with
C<soft_tone_create()>. A frequency of C<0> stops the tone.

Parameters:

    $pin

Mandatory: The pin number.

    $freq

Mandatory: The frequency in Hz.

=head2 soft_tone_stop($pin)

Maps to C<void softToneStop(int pin)>

Stops the software tone on the given pin.

Parameters:

    $pin

Mandatory: The pin number.

=head1 THREAD/LOCK FUNCTIONS

Mutex locks provided by wiringPi for synchronising access between threads.

=head2 pi_lock($key)

Maps to C<void piLock(int key)>

Acquires the lock identified by C<$key>, waiting until it is available.

Parameters:

    $key

Mandatory: The lock number, C<0> to C<3>.

=head2 pi_unlock($key)

Maps to C<void piUnlock(int key)>

Releases the lock identified by C<$key>.

Parameters:

    $key

Mandatory: The lock number, C<0> to C<3>.

=head1 TIMING FUNCTIONS

wiringPi timing and scheduling helpers. See
L<wiringPi timing page|http://wiringpi.com/reference/timing/>.

C<delay()>, C<millis()> and C<micros()> are exported under the C<:wiringPi> tag
as their native wiringPi names.

=head2 delay($ms)

Maps to C<void delay(unsigned int ms)>

Pauses execution for at least C<$ms> milliseconds.

=head2 delay_microseconds($us)

Maps to C<void delayMicroseconds(unsigned int us)>

Pauses execution for at least C<$us> microseconds.

=head2 millis()

Maps to C<unsigned int millis()>

Returns the number of milliseconds elapsed since the program called one of the
C<setup*()> routines, as an integer.

=head2 micros()

Maps to C<unsigned int micros()>

Returns the number of microseconds elapsed since the program called one of the
C<setup*()> routines, as an integer.

=head2 pi_micros64()

Maps to C<unsigned long long piMicros64()>

As C<micros()>, but returns a 64-bit microsecond count (does not wrap as
quickly). Requires a 64-bit Perl (C<use64bitint>).

=head2 pi_hi_pri($priority)

Maps to C<int piHiPri(const int pri)>

Attempts to set a high (real-time) scheduling priority for the running program.
Returns C<0> on success, C<-1> on failure (e.g. insufficient privileges).

Parameters:

    $priority

Mandatory: The priority, C<0> (lowest) to C<99> (highest).

=head1 PAD DRIVE / TONE / CLOCK FUNCTIONS

=head2 set_pad_drive($group, $value)

Maps to C<void setPadDrive(int group, int value)>

Sets the drive strength for a group of GPIO pins.

Parameters:

    $group

Mandatory: The pad group (C<0>, C<1> or C<2>).

    $value

Mandatory: The drive strength, C<0> to C<7>.

=head2 set_pad_drive_pin($pin, $value)

Maps to C<void setPadDrivePin(int pin, int value)>

Sets the drive strength for a single GPIO pin.

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

    $value

Mandatory: The drive strength, C<0> to C<7>.

=head2 pwm_tone_write($pin, $freq)

Maps to C<void pwmToneWrite(int pin, int freq)>

Writes a tone of the given frequency (in Hz) to a PWM-capable pin.

Parameters:

    $pin

Mandatory: The pin number.

    $freq

Mandatory: The frequency in Hz. A frequency of C<0> stops the tone.

=head2 gpio_clock_set($pin, $freq)

Maps to C<void gpioClockSet(int pin, int freq)>

Sets the output frequency (in Hz) on a GPIO clock pin.

Parameters:

    $pin

Mandatory: The pin number.

    $freq

Mandatory: The clock frequency in Hz.

=head1 BOARD IDENTITY FUNCTIONS

=head2 pi_board_id()

Maps to C<void piBoardId(int *model, int *rev, int *mem, int *maker, int *overVolted)>

Returns identifying information about the board. In list context, returns
C<($model, $rev, $mem, $maker, $over_volted)>. In scalar context, returns a hash
reference with keys C<model>, C<rev>, C<mem>, C<maker> and C<over_volted>. The
values are the integer codes used by wiringPi.

=head2 pi_board40_pin()

Maps to C<int piBoard40Pin()>

Returns true if the board has the standard 40-pin GPIO header.

=head2 pi_rp1_model()

Maps to C<int piRP1Model()>

Returns the RP1 model code on boards that use the RP1 I/O controller (e.g. the
Raspberry Pi 5), or a falsey value on boards without one.

=head2 get_pin_mode_alt($pin)

Maps to C<enum WPIPinAlt getPinModeAlt(int pin)>

Like C<get_alt()>, but returns the pin's current mode as a C<WPIPinAlt> enum
value: C<-1> (unknown), C<0> (input), C<1> (output), then the C<ALT> modes.

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

=head2 wiringpi_global_memory_access()

Maps to C<int wiringPiGlobalMemoryAccess()>

Returns a value indicating the level of direct GPIO memory access available to
the current process (C<0> if none).

=head2 wiringpi_user_level_access()

Maps to C<int wiringPiUserLevelAccess()>

Returns true if user-level (non-root) GPIO access is available (e.g. via
C</dev/gpiomem>).

=head1 LCD FUNCTIONS

There are several methods to drive standard Liquid Crystal Displays. See
L<wiringPiDev LCD page|http://wiringpi.com/dev-lib/lcd-library/> for full
details.

=head2 lcd_init(%args)

Maps to:

    int lcdInit(
        rows, cols, bits, rs, strb,
        d0, d1, d2, d3, d4, d5, d6, d7
    );

Initializes the LCD library, and returns an integer representing the handle
(file descriptor) of the device.

Parameters:

    %args = (
        rows => $num,       # number of rows. eg: 2 or 4
        cols => $num,       # number of columns. eg: 16 or 20
        bits => 4|8,        # width of the interface (4 or 8)
        rs => $pin_num,     # pin number of the LCD's RS pin
        strb => $pin_num,   # pin number of the LCD's strobe (E) pin
        d0 => $pin_num,     # pin number for LCD data pin 1
        ...
        d7 => $pin_num,     # pin number for LCD data pin 8
    );

Mandatory: All entries must have a value. If you're only using four (4) bit
width, C<d4> through C<d7> must be set to C<0>.

Note: When in 4-bit mode, the C<d0> through C<3> parameters actually map to
pins C<d4> through C<d7> on the LCD board, so you need to connect those pins
to their respective selected GPIO pins.

NOTE: There is an upper limit of the number of LCDs that can be initialized
simultaneously. This number is 8 (0-7). Always check the return of this
function to ensure you're under the maximum file descriptors. If you receive a
`-1`, you're out of bounds, and any functions called on the LCD will cause a 
segmentation fault.

=head2 lcd_home($fd)

Maps to C<void lcdHome(int fd)>

Moves the LCD cursor to the home position (top row, leftmost column).

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

=head2 lcd_clear($fd)

Maps to C<void lcdClear(int fd)>

Clears the LCD display.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

=head2 lcd_display($fd, $state)

Maps to C<void lcdDisplay(int fd, int state)>

Turns the LCD display on and off.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

    $state

Mandatory: C<0> to turn the display off, and C<1> for on.

=head2 lcd_cursor($fd, $state)

Maps to C<void lcdCursor(int fd, int state)>

Turns the LCD cursor on and off.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

    $state

Mandatory: C<0> to turn the cursor off, C<1> for on.

=head2 lcd_cursor_blink($fd, $state)

Maps to C<void lcdCursorBlink(int fd, int state)>

Allows you to enable/disable a blinking cursor.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

    $state

Mandatory: C<0> to turn the cursor blink off, C<1> for on. Default is off
(C<0>).

=head2 lcd_send_cmd($fd, $command)

Maps to C<void lcdSendCommand(int fd, char command)>

Sends any arbitrary command to the LCD.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

    $command

Mandatory: A command to submit to the LCD.

=head2 lcd_position($fd, $x, $y)

Maps to C<void lcdPosition(int fd, int x, int y)>

Moves the cursor to the specified position on the LCD display.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

    $x

Mandatory: Column position. C<0> is the left-most edge.

    $y

Mandatory: Row position. C<0> is the top row.

=head2 lcd_char_def($fd, $index, $data)

Maps to C<void lcdCharDef(int fd, unsigned char data [8])>. This function is

This allows you to re-define one of the 8 user-definable characters in the
display.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

    $index

Mandatory: Index of the display character. Values are C<0-7>. Once the char
is stored at this index, it can be used at any time with the C<lcd_put_char()>
function.

    $data

Mandatory: Array reference of exactly 8 elements. Each element is a single
unsigned char byte. These bytes represent the character from the top-line to
the bottom line. 

Note that the characters are actually 5 x 8, so only the lower 5 bits are of
each element are used (ie. `0b11111` or 0b00011111`). The index is from 0 to 7
and you can subsequently print the character defined using the lcdPutchar()
call using the same index sent in to this function.

=head2 lcd_put_char($fd, $char)

Maps to C<void lcdPutchar(int fd, unsigned char data)>

Writes a single ASCII character to the LCD display, at the current cursor
position.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

    $char

Mandatory: The character byte to print to the LCD. Note that 0-7 are reserved
for custom characters, as defined with C<lcd_char_def()>. To print one of your
custom chars, C<$char> should be the same integer of the C<$index> you used to
store it in that function.

=head2 lcd_puts($fd, $string)

Maps to C<void lcdPuts(int fd, char *string)>

Writes a string to the LCD display, at the current cursor position.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

    $string

Mandatory: A string to display.

=head1 INTERRUPT FUNCTIONS

=head2 set_interrupt($pin, $edge, $callback, $debounce_us)

Arms an interrupt handler on C<$pin>. Maps to wiringPi's C<wiringPiISR2()>.

The wiringPi interrupt thread never calls into Perl: when an edge fires it
writes a small event record to an internal pipe (the "self-pipe"). Your
C<$callback> runs later, in B<your> interpreter, when you service that pipe with
C<wait_interrupts()> or C<dispatch_interrupts()>. Because Perl is only ever
entered by the interpreter that owns it, this works on B<any> Perl - threaded or
not - and the old "interrupts need a threaded Perl or they segfault" caveat no
longer applies.

Arm in the same process that will dispatch. For background handling while your
main program does other work, C<fork> a child that arms and dispatches (see the
examples below).

Parameters:

    $pin

Mandatory: The pin number, in the pin numbering scheme dictated by whichever
C<setup*()> routine you used.

    $edge

Mandatory: one of C<INT_EDGE_FALLING> (C<1>), C<INT_EDGE_RISING> (C<2>) or
C<INT_EDGE_BOTH> (C<3>). C<INT_EDGE_SETUP> (C<0>) is B<not> a valid trigger and
is rejected. These constants are importable via the C<:constants> or C<:all>
tags.

    $callback

Mandatory: A code reference that runs when the interrupt is dispatched. It
receives two arguments: the edge that fired and the event timestamp in
microseconds.

    $debounce_us

Optional: debounce period in microseconds, passed through to C<wiringPiISR2()>
(default C<0> = no debounce).

Re-arming the same pin is safe - the previous listener is stopped first, so a
second wiringPi thread is never stacked on the pin.

=head2 dispatch_interrupts()

Non-blocking. Reads every event currently waiting in the self-pipe, runs the
registered callback for each, and returns the number dispatched (C<0> if none
were waiting). Never blocks waiting for an edge.

=head2 wait_interrupts($timeout_ms)

Blocks until at least one interrupt event is available (or C<$timeout_ms>
milliseconds elapse), dispatches all pending events via C<dispatch_interrupts()>,
and returns the number dispatched (C<0> on timeout). An undefined C<$timeout_ms>
blocks indefinitely. The usual single-threaded pattern is:

    wait_interrupts(1000) while 1;

=head2 interrupt_fd()

Returns the readable file descriptor of the self-pipe (an integer), or C<-1>
before any interrupt has been armed. Use this to drive your own C<select>/C<poll>
loop instead of C<wait_interrupts()>; call C<dispatch_interrupts()> when it
becomes readable.

=head2 interrupt_dropped()

Returns the number of interrupt events dropped because the self-pipe was full
when an edge fired (bursts beyond the pipe buffer). Normally C<0>; reset by
C<stop_interrupts()>.

=head2 stop_interrupt($pin)

Stops the interrupt on C<$pin> (C<wiringPiISRStop()>) and forgets its callback.

=head2 stop_interrupts()

Stops every armed interrupt, closes the self-pipe and resets interrupt state.
There is no dispatcher thread to join. A later C<set_interrupt()> re-creates the
pipe automatically.

=head3 Example - single-threaded event loop (any Perl)

    use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts
                         INT_EDGE_RISING);

    setup();
    pin_mode(0, 0);
    set_interrupt(0, INT_EDGE_RISING, sub {
        my ($edge, $ts_us) = @_;
        print "edge $edge at $ts_us us\n";
    });

    wait_interrupts(1000) while 1;   # dispatches in THIS process

=head3 Example - background handling via fork

    use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts
                         INT_EDGE_RISING);

    setup();                          # once, in the parent, before forking
    pin_mode(0, 0);

    my $pid = fork // die "fork: $!";
    if ($pid == 0) {                  # child owns + dispatches the interrupt
        set_interrupt(0, INT_EDGE_RISING, sub {
            my ($edge, $ts_us) = @_;
            # ... handle the edge ...
        });
        wait_interrupts(1000) while 1;
        exit 0;
    }

    # parent is free to do other work; reap $pid at exit

=head1 ADC FUNCTIONS

Analog to digital converters (ADC) allow you to read analog data on the
Raspberry Pi, as the Pi doesn't have any analog input pins.

This section is broken down by type/model.

=head2 ADS1115 MODEL

=head3 ads1115_setup($pin_base, $addr)

Maps to `ads1115Setup(int pinBase, int addr)`.

The ADS1115 is a four channel, 16-bit wide ADC.

Parameters:

    $pin_base

Mandatory: Signed integer, higher than that of all GPIO pins. This is the base
number we'll use to access the pseudo pins on the ADC. Example: If C<400> is
sent in, ADC pin C<A0> (or C<0>) will be pin 400, and C<AD3> (the fourth analog
pin) will be 403.

Parameters:

    $addr

Mandatory: Signed integer. This parameter depends on how you have the C<ADDR>
pin on the ADC connected to the Pi. Below is a chart showing if the C<ADDR> pin
is connected to the Pi C<Pin>, you'll get the address. You can also use
C<i2cdetect -y 1> to find out your ADC address.

    Pin     Address
    ---------------
    Gnd     0x48
    VDD     0x49
    SDA     0x4A
    SCL     0x4B

=head1 SHIFT REGISTER FUNCTIONS

Shift registers allow you to add extra output pins by multiplexing a small
number of GPIO.

Currently, we support the SR74HC595 unit, which provides eight outputs by using
only three GPIO. To further, this particular unit can be daisy chained up to
four wide to provide an additional 32 outputs using the same three GPIO pins.

=head2 shift_reg_setup

This function configures the Raspberry Pi to use a shift register (The
SR74HC595 is currently supported).

Parameters:

    $pin_base

Mandatory: Signed integer, higher than that of all existing GPIO pins. This
parameter registers pin 0 on the shift register to an internal GPIO pin number.
For example, setting this to 100, you will be able to access the first output
on the register as GPIO 100 in all other functions.

    $num_pins

Mandatory: Signed integer, the number of outputs on the shift register. For a
single SR74HC595, this is eight. If you were to daisy chain two together, this
parameter would be 16.

    $data_pin

Mandatory: Integer, the GPIO pin number connected to the register's C<DS> pin
(14). Can be any GPIO pin capable of output.

    $clock_pin

Mandatory: Integer, the GPIO pin number connected to the register's C<SHCP> pin
(11). Can be any GPIO pin capable of output.

    $latch_pin

Mandatory: Integer, the GPIO pin number connected to the register's C<STCP> pin
(12). Can be any GPIO pin capable of output.

=head1 SERIAL FUNCTIONS

These functions provide basic access to read and write to a serial device.

=head2 serial_open($device, $baud)

Maps to C<int serialOpen(const char *device, const int baud)>

Opens a serial device for read/write access.

Parameters:

    $device

Mandatory, String: The name of the serial device, eg: C</dev/ttyACM0>.

    $baud

Mandatory, Integer: The speed of the serial device. (eg: C<9600>).

Return, Integer: The file descriptor of the device.

=head2 serial_close($fd)

Maps to C<void serialClose(const int fd)>

Closes an already open serial device.

Parameters:

    $fd

Mandatory, Integer: The file descriptor returned by your call to C<serial_open()>.

=head2 serial_flush($fd)

Maps to C<serialFlush(const int fd)>

Flushes the serial device's buffer.

Parameters:

    $fd

Mandatory, Integer: The file descriptor returned by your call to C<serial_open()>.

=head2 serial_data_avail($fd)

Maps to C<serialDataAvail(const int fd)>

Check if there is any data available on the serial interface.

Parameters:

    $fd

Mandatory, Integer: The file descriptor returned by your call to C<serial_open()>.

=head2 serial_get_char($fd)

Maps to C<serialGetchar(const int fd)>

Read a single byte from the serial interface.

Parameters:

    $fd

Mandatory, Integer: The file descriptor returned by your call to C<serial_open()>.

=head2 serial_put_char($fd, $char)

Maps to C<serialPutchar(const int fd, const unsigned char c)>

Write a single byte to the interface.

Parameters:

    $fd

Mandatory, Integer: The file descriptor returned by your call to C<serial_open()>.

    $char

Mandatory, Byte: A single byte to write to the serial interface.

=head2 serial_puts($fd, $string)

Maps to C<serialPuts(const int fd, const char* string)>

Write an arbitrary length string to the serial interface.

Parameters:

    $fd

Mandatory, Integer: The file descriptor returned by your call to C<serial_open()>.

    $string

Mandatory, String: The content to write to the device.

=head1 I2C FUNCTIONS

These functions allow you to read and write devices on the Inter-Integrated
Circuit (I2C) bus.

=head2 i2c_setup($addr)

Maps to C<int wiringPiI2CSetup(int devId)>

Configures the I2C bus in preparation for communicating with a device.

Parameters:

    $addr

Mandatory: Integer, the address of your device as seen by running for example:
C<i2cdetect -y 1>.

=head2 i2c_interface($device, $addr)

Maps to C<int wiringPiI2CSetupInterface(const char* device, int devId)>

Like C<i2c_setup()>, but lets you name the I2C device file explicitly (e.g.
C</dev/i2c-1>) instead of relying on the default.

Parameters:

    $device

Mandatory: String, the path to the I2C device file (e.g. C</dev/i2c-1>).

    $addr

Mandatory: Integer, the I2C address of the device.

Returns: Integer, the file descriptor for the device (as C<i2c_setup()>).

=head2 i2c_read($fd)

Performs a quick one-off, one-byte read without needing to specify the register
value. Some very simple devices operate without register values needed.

Parameters:

    $fd

Mandatory: Integer, the file descriptor that was returned from C<i2c_setup()>.

Returns: A single byte of data from the device on the I2C bus.

=head2 i2c_read_byte($fd, $reg)

Reads a single byte from the specified register.

Parameters:

    $fd

Mandatory: Integer, the file descriptor that was returned from C<i2c_setup()>.

    $reg

Mandatory: Integer, the register to read data from.

Returns: A single byte of data from the device on the I2C bus from the selected
register.

=head2 i2c_read_word($fd, $reg)

Reads two bytes from the specified register.

Parameters:

    $fd

Mandatory: Integer, the file descriptor that was returned from C<i2c_setup()>.

    $reg

Mandatory: Integer, the register to read data from.

Returns: Integer, two bytes of data from the device on the I2C bus from the
selected register.

=head2 i2c_write($fd, $data)

Performs a quick one-off, one-byte write without needing to specify the register
value. Some very simple devices operate without register values needed.

Parameters:

    $fd

Mandatory: Integer, the file descriptor that was returned from C<i2c_setup()>.

    $data

Mandatory: Integer, the value to write to the device.

Returns: The value of the C<ioctl()> call, C<0> on success.

=head2 i2c_write_byte($fd, $reg, $data)

Writes a single byte to the register specified.

Parameters:

    $fd

Mandatory: Integer, the file descriptor that was returned from C<i2c_setup()>.

    $reg

Mandatory: Integer, the register to write the data to.

    $data

Mandatory: Integer, the value to write to the device.

Returns: The value of the C<ioctl()> call, C<0> on success.

=head2 i2c_write_word($fd, $reg, $data)

Writes two bytes to the register specified.

Parameters:

    $fd

Mandatory: Integer, the file descriptor that was returned from C<i2c_setup()>.

    $reg

Mandatory: Integer, the register to write the data to.

    $data

Mandatory: Integer, the value to write to the device.

Returns: The value of the C<ioctl()> call, C<0> on success.

=head2 i2c_read_block($fd, $reg, $size)

Maps to C<int wiringPiI2CReadBlockData(int fd, int reg, uint8_t *values, uint8_t size)>

Reads up to C<$size> bytes (max 255) in a single block transaction starting at
register C<$reg>.

Parameters:

    $fd

Mandatory: Integer, the file descriptor returned from C<i2c_setup()>.

    $reg

Mandatory: Integer, the register to read from.

    $size

Mandatory: Integer C<0>-C<255>, the number of bytes to read.

Returns: A list of the bytes read (its length is the actual count returned by
the device). Croaks on a read error.

=head2 i2c_raw_read($fd, $size)

Maps to C<int wiringPiI2CRawRead(int fd, uint8_t *values, uint8_t size)>

As C<i2c_read_block()>, but reads directly from the device without a register
address.

Parameters:

    $fd

Mandatory: Integer, the file descriptor returned from C<i2c_setup()>.

    $size

Mandatory: Integer C<0>-C<255>, the number of bytes to read.

Returns: A list of the bytes read. Croaks on a read error.

=head2 i2c_write_block($fd, $reg, \@bytes)

Maps to C<int wiringPiI2CWriteBlockData(int fd, int reg, const uint8_t *values, uint8_t size)>

Writes a block of up to 255 bytes in a single transaction starting at register
C<$reg>.

Parameters:

    $fd

Mandatory: Integer, the file descriptor returned from C<i2c_setup()>.

    $reg

Mandatory: Integer, the register to write to.

    \@bytes

Mandatory: An array reference of byte values (C<0>-C<255>), at most 255 elements.

Returns: The value of the underlying call, C<0> on success.

=head2 i2c_raw_write($fd, \@bytes)

Maps to C<int wiringPiI2CRawWrite(int fd, const uint8_t *values, uint8_t size)>

As C<i2c_write_block()>, but writes directly to the device without a register
address.

Parameters:

    $fd

Mandatory: Integer, the file descriptor returned from C<i2c_setup()>.

    \@bytes

Mandatory: An array reference of byte values (C<0>-C<255>), at most 255 elements.

Returns: The value of the underlying call, C<0> on success.

=head1 SPI FUNCTIONS

These functions allow you to set up and read/write to devices on the serial
peripheral interface (SPI) bus.

=head2 spi_setup

Maps to C<int wiringPiSPISetup(int channel, int speed)>

Configure the SPI bus for use to communicate with its connected devices.

Parameters:

    $channel

Mandatory: Integer, the SPI channel the device is connected to. C<0> for channel
C</dev/spidev0.0> and C<1> for channel C</dev/spidev0.1>.

    $speed

Optional: Integer, the speed for SPI communication. Defaults to 1000000 (1MHz).

Note that it's wise to do some error checking when attempting to open the SPI
bus. We return the return value of an C<ioctl()> call, so this does the trick:

    if ((spi_setup(0, 1000000) < 0){
        croak "failed to open the SPI bus...\n";
    }

=head2 spi_data

Maps to: C<int spiDataRW(int channel, AV* data, int len)>, which calls
C<int wiringPiSPIDataRW(int channel, unsigned char* data, int len)>.

Writes, and then reads a block of data over the SPI bus. The read following the
write is read into the transmit buffer, so it'll be overwritten and sent back
as a Perl array.

Parameters:

    $channel

Mandatory: Integer, the SPI channel the device is connected to. C<0> for channel
C</dev/spidev0.0> and C<1> for channel C</dev/spidev0.1>.

    $data

Mandatory: An array reference, with each element containing a single unsigned
8-bit byte that you want to write to the device. If you want to read-only, send
in an aref with all the elements set to C<0>. These will be overwritten with
the read data, and sent back as a Perl array.

    $len

Mandatory: Integer, the number of bytes contained in the C<$data> parameter
array reference that will be sent to the device. I could just count the number
of elements, but this keeps things consistent, and ensures the user is fully
aware of the data they are sending on the bus.

Returns a Perl array containing the same number of elements you sent in. 

    # read-only... three bytes

    my $buf = [0x00, 0x00, 0x00];

    my @ret = spiDataRW($chan, $buf, 3);

=head2 spi_get_fd($channel)

Maps to C<int wiringPiSPIGetFd(int channel)>

Returns the open file descriptor for an SPI channel that was previously set up.

Parameters:

    $channel

Mandatory: Integer, C<0> or C<1>.

=head2 spi_setup_mode($channel, $speed, $mode)

Maps to C<int wiringPiSPISetupMode(int channel, int speed, int mode)>

As C<spi_setup()>, but also selects the SPI mode (clock polarity/phase).

Parameters:

    $channel

Mandatory: Integer, C<0> or C<1>.

    $speed

Mandatory: Integer, the bus speed in Hz (e.g. C<1000000>).

    $mode

Mandatory: Integer C<0>-C<3>, the SPI mode.

Returns: Integer, the file descriptor on success or C<-1> on error.

=head2 spi_close($channel)

Maps to C<int wiringPiSPIClose(const int channel)>

Closes the given SPI channel, releasing its file descriptor.

Parameters:

    $channel

Mandatory: Integer, C<0> or C<1>.

=head1 BMP180 PRESSURE SENSOR FUNCTIONS

These functions configure and fetch data from the BMP180 barometric pressure
sensor.

=head2 bmp180_setup($pin_base)

Configures the system to read from a BMP180 pressure sensor.

These functions can not return the raw values from the sensor. See each
function documentation to learn how to do so.

Parameters:

    $pin_base

Mandatory: Integer, the number at which to place the pseudo analog pins in the 
GPIO stack. For example, if you use C<200>, pin C<200> represents the
temperature feature of the sensor, and C<201> represents the pressure feature.

Return: undef.

=head2 bmp180_temp($pin, $want)

Returns the temperature from the sensor.

Parameters:

    $pin

Mandatory: Integer, represents the C<$pin_base> used in the setup function C<+ 0>.

    $want

Optional: C<'c'> for Celcius, and C<'f'> for Farenheit. Defaults to C<'f'>.

Return: A floating point number in the requested conversion.

NOTE: To get the raw sensor temperature, call the C function 
C<bmp180Temp($pin)> directly.

=head2 bmp180_pressure($pin)

Returns the current air pressure in kPa.

Parameters:

    $pin

Mandatory: Integer, represents the C<$pin_base> used in the setup function C<+ 1>.

Return: A floating point number that represents the air pressure in kPa.

NOTE: To get the raw sensor pressure, call the C function 
C<bmp180Pressure($pin)> directly.

=head1 DEVELOPER FUNCTIONS

These functions are under testing, or don't potentially have a use to the end
user. They may be risky to use, so use at your own risk.

The functions in this section do not have a Perl wrapper equivalent.

=head2 pseudoPinsSetup(int pinBase)

This function allocates shared memory for the pseudo pins used to communicate
with devices that are beyond the reach of the Pi's GPIO (eg: shift registers,
ADCs etc).

Parameters:

    pinBase

Mandatory: Integer, larger than the highest GPIO pin number. Eg: C<500> will be
the base for the analog pins on an ADS1115 ADC. Pin C<A0> would be C<500>, and
ADC pin C<A3> would be C<503>.

=head2 pinModeAlt(int pin, int mode)

Undocumented function that allows any pin to be set to any mode.

Parameters:

    pin

Mandatory: Signed integer, any valid GPIO pin number.

    mode

Mandatory: Signed integer, any valid wiringPi pin mode.

=head2 digitalWriteByte(const int value)

Writes an 8-bit byte to the first eight GPIO pins.

Parameters:

    value

Mandatory: Unsigned int, the byte value you want to send in.

Return: void

=head2 digitalWriteByte2(const int value)

Same as L</digitalWriteByte(const int value)>, but writes to the second group
of eight GPIO pins.

=head2 digitalReadByte()

Reads an 8-bit byte from the first eight GPIO pins on the Pi.

Takes no parameters, returns the byte value as an unsigned int.

=head2 digitalReadByte2()

Same as L</digitalReadByte()>, but reads from the second group of eight GPIO pins.

=head1 AUTHOR

Steve Bertrand, E<lt>steveb@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2017-2026 by Steve Bertrand

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.18.2 or,
at your option, any later version of Perl 5 you may have available.

