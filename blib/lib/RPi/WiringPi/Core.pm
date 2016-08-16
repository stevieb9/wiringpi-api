package RPi::WiringPi::Core;

use strict;
use warnings;

our $VERSION = '0.07';

use RPi::WiringPi::Constant qw(:all);

require XSLoader;
XSLoader::load('RPi::WiringPi::Core', $VERSION);

# not yet implemented:
#extern void pinModeAlt          (int pin, int mode) ;
#extern int  analogRead          (int pin) ;
#extern void analogWrite         (int pin, int value) ;

sub new {
    return bless {}, shift;
}

# interrupt functions

sub register_interrupt {
    my ($pin, $edge, $interrupt_num) = @_;
    registerInterrupt($pin, $edge, $interrupt_num);
}

# system functions

sub setup {
    return wiringPiSetup();
}
sub setup_sys {
    return wiringPiSetupSys();
}
sub setup_phys {
    return wiringPiSetupPhys();
}
sub setup_gpio {
    return wiringPiSetupGPIO();
}

# pin functions

sub pin_mode {
    shift if @_ == 3;
    my ($pin, $mode) = @_;
    pinMode($pin, $mode);
}
sub pull_up_down {
    shift if @_ == 3;
    my ($pin, $value) = @_;
    # off, down up = 0, 1, 2
    pullUpDnControl($pin, $value);
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

# board functions

sub board_rev {
    return piBoardRev();
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
    shift if @_ == 2;
    my $range = shift;
    pwmSetRange($range);
}

# lcd functions

sub lcd_init {
    if (ref $_[0] =~ /RPi::WiringPi/ || $_[0] =~ /RPi::WiringPi/){
        shift;
    }
    my @args = @_;
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
    warn "\nlcdSendCommand() wiringPi function isn't documented!\n";
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
    lcdCharDef($fd, $index, $data);
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
sub _vim{1;};

1;
__END__

=head1 NAME

RPi::WiringPi::Core - Tight Perl wrapper for Rasperry Pi's wiringPi C library
functionality

=head1 DESCRIPTION

WARNING: Until version 1.00 has been released, the API along with functionality
may change at any time without any notice. If you happen to be testing with 
this software and find something broken, please contact me.

This is an XS-based module, and requires L<wiringPi|http://wiringpi.com> to be
installed. The C<wiringPiDev> shared library is also required (for the LCD
functionality), but it's installed by default with C<wiringPi>.

=head1 CORE METHODS

=head2 new()

Returns a new C<RPi::WiringPi::Core> object.

=head2 setup()

Maps to C<int wiringPiSetup()>

See L<wiringPi setup functions|http://wiringpi.com/reference/setup> for
for information on this method.

Note that only one of the C<setup*()> methods can be called per program run.

=head2 setup_sys()

Maps to C<int wiringPiSetupSys()>

See L<wiringPi setup functions|http://wiringpi.com/reference/setup> for
for information on this method.

Note that only one of the C<setup*()> methods can be called per program run.

=head2 setup_phys()

Maps to C<int wiringPiSetupPhys()>

See L<wiringPi setup functions|http://wiringpi.com/reference/setup> for
for information on this method.

Note that only one of the C<setup*()> methods can be called per program run.

=head2 setup_gpio()

Maps to C<int wiringPiSetupGpio()>

See L<wiringPi setup functions|http://wiringpi.com/reference/setup> for
for information on this method.

Note that only one of the C<setup*()> methods can be called per program run.

=head2 pin_mode($pin, $mode)

Maps to C<void pinMode(int pin, int mode)>

Puts the GPIO pin in either INPUT or OUTPUT mode.

Parameters:

    $pin

Mandatory: The GPIO pin number, using wiringPi's pin number representation.

    $mode

Mandatory: C<0> for INPUT, C<1> OUTPUT, C<2> PWM_OUTPUT and C<3> GPIO_CLOCK.

=head2 read_pin($pin);

Maps to C<int digitalRead(int pin)>

Returns the current state (HIGH/on, LOW/off) of a given pin.

Parameters:
    
    $pin

Mandatory: The wiringPi number representation of the GPIO pin.

=head2 write_pin($pin, $state)

Maps to C<void digitalWrite(int pin)>

Sets the state (HIGH/on, LOW/off) of a given pin.

Parameters:

    $pin

Mandatory: The wiringPi number representation of the GPIO pin.

    $state

Mandatory: C<1> to turn the pin on (HIGH), and C<0> to turn it LOW (off).

=head2 pull_up_down($pin, $direction)

Maps to C<void pullUpDnControl(int pin, int pud)>

Enable/disable the built-in pull up/down resistors for a specified pin.

Parameters:

    $pin

Mandatory: The wiringPi number representation of the GPIO pin.

    $direction

Mandatory: C<2> for UP, C<1> for DOWN and C<0> to disable the resistor.

=head2 pwm_write($pin, $value)

Maps to C<void pwmWrite(int pin, int value)>

Sets the Pulse Width Modulation duty cycle (on-time) of the pin.

Parameters:

    $pin

Mandatory: The wiringPi number representation of the GPIO pin.

    $value

Mandatory: C<0> to C<1023>. C<0> is 0% (off) and C<1023> is 100% (fully on).

=head2 get_alt($pin)

Maps to C<int getAlt(int pin)>

This returns the current mode of the pin (using C<getAlt()> C call). Modes are
INPUT C<0>, OUTPUT C<1>, PWM C<2> and CLOCK C<3>.

Parameters:
    
    $pin

Mandatory: The wiringPi number representation of the GPIO pin.

=head1 BOARD METHODS

=head2 board_rev()

Maps to C<int piBoardRev()>

Returns the Raspberry Pi board's revision.

=head2 wpi_to_gpio($pin_num)

Maps to C<int wpiPinToGpio(int pin)>

Converts a C<wiringPi> pin number to the Broadcom (BCM) representation, and
returns it.

Parameters:

    $pin_num

Mandatory: The C<wiringPi> representation of a pin number.        

=head2 phys_to_gpio($pin_num)

Maps to C<int physPinToGpio(int pin)>

Converts the pin number on the physical board to the Broadcom (BCM)
representation, and returns it.

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

=head2 pwm_set_range($range);

Maps to C<void pwmSetRange(int range)>

Sets the range register of the Pulse Width Modulation (PWM) functionality. It
defaults to C<1024> (C<0-1023>).

Parameters:

    $range

Mandatory: An integer between C<0> and C<1023>.

=head1 LCD METHODS

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
handle (file descriptor) of the device. The return is supposed to be constant,
so DON'T change it.

Parameters:

    %args = (
        rows => $num,       # number of rows. eg: 16 or 20
        cols => $num,       # number of columns. eg: 2 or 4
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

Mandatory: The file descriptor integer returned by C<lcd_init()>.=head2 lcd_clear($fd)

    $state

Mandatory: C<0> to turn the cursor off, C<1> for on.

=head2 lcd_cursor_blink($fd, $state)

Maps to C<void lcdCursorBlink(int fd, int state)>

Allows you to enable/disable a blinking cursor.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.=head2 lcd_clear($fd)

    $state

Mandatory: C<0> to stop blinking, C<1> to enable.

=head2 lcd_send_cmd($fd, $command)

Maps to C<void lcdSendCommand(int fd, char command)>

Sends any arbitrary command to the LCD.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.=head2 lcd_clear($fd)

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

Maps to C<void lcdCharDef(int fd, unsigned char data [8])>

This allows you to re-define one of the 8 user-definable characters in the
display. The data array is 8 bytes which represent the character from the
top-line to the bottom line. Note that the characters are actually 5×8, so
only the lower 5 bits are used. The index is from 0 to 7 and you can
subsequently print the character defined using the lcdPutchar() call.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

    $index

Mandatory: Index of the display character. Values are C<0-7>.

    $data

Mandatory: See above description.

=head2 lcd_put_char($fd, $char)

Maps to C<void lcdPutChar(int fd, unsigned char data)>

Writes a single ASCII character to the LCD display, at the current cursor
position.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

    $char

Mandatory: A single ASCII character.

=head2 lcd_puts($fd, $string)

Maps to C<void lcdPuts(int fd, char *string)>

Writes a string to the LCD display, at the current cursor position.

Parameters:

    $fd

Mandatory: The file descriptor integer returned by C<lcd_init()>.

    $string

Mandatory: A string to display.

=head1 AUTHOR

Steve Bertrand, E<lt>steveb@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Steve Bertrand

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.18.2 or,
at your option, any later version of Perl 5 you may have available.
