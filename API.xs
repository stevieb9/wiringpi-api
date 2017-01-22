#include <stdlib.h>
#include <stdint.h>

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <wiringPi.h>
#include <wiringPiSPI.h>
#include <lcd.h>
#include <softPwm.h>
#include <sr595.h>

#define PERL_NO_GET_CONTEXT

/*
 * definitions
 */

int bmp180Pressure(int pin);
int bmp180Temp(int pin);
int initThread(char * callback);
void interruptHandler();
int physPinToWpi(int wpi_pin);
static int phys_wpi_map[64];
int setInterrupt(int pin, int edge, char * callback);

/*
 * declarations
 */

static int phys_wpi_map[64] =
{
  -1, // pin 0 doesn't exist
  -1, -1,
   8, -1,
   9, -1,
   7, 15,
  -1, 16,
   0,  1,
   2, -1,
   3,  4,
  -1,  5,
  12, -1,
  13,  6,
  14, 10,
  -1, 11,
  30, 31,
  21, -1,
  22, 26,
  23, -1,
  24, 27,
  25, 28,
  -1, 29,
  -1, -1,
  -1, -1,
  -1, -1,
  -1, -1,
  -1, -1,
  17, 18,
  19, 20,
  -1, -1,
  -1, -1,
  -1, -1,
  -1, -1,
  -1
};

int spiDataRW(int channel, SV* byte_ref, int len){

     /*
      * Custom wrapper for wiringPiSPIDataRW() as we
      * need to translate an aref into an unsigned char *
      */ 

    if (channel != 0 && channel != 1){
        croak("channel param must be 0 or 1\n");
    }

    if (! SvROK(byte_ref) || SvTYPE(SvRV(byte_ref)) != SVt_PVAV){
        croak("data param must be an array reference\n");
    }

    AV* bytes = (AV*)SvRV(byte_ref);

    int num_bytes = av_len(bytes) + 1;

    if (len != num_bytes){
        croak("len param doesn't match element count in data\n");
    }

    unsigned char buf[num_bytes];

    int i;

    for (i=0; i<len; i++){
        SV** elem = av_fetch(bytes, i, 0);

        int elem_int = (int)SvNV(*elem);
        
        if (elem_int < 0 || elem_int > 255){
            printf("byte %d in data param out of range: (%d)\n", i, elem_int);
            exit(1);
        }

        buf[i] = (unsigned char)SvNV(*elem);
    }
    
    /*  int x;
     *  for (x=0; x<len; x++){
     *      printf("%d\n", buf[x]);
     *  }
     */
      
    int bus_opened;
     
    if (bus_opened = (wiringPiSPIDataRW(channel, buf, len) < 0)){
        croak("failed to write to the SPI bus\n");
    }

    return bus_opened;
}

char * perl_callback; // dynamically set perl callback for interrupt handler
PerlInterpreter * mine;
int first_call = 1;

void interruptHandler(){
    PERL_SET_CONTEXT(mine);

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    PUTBACK;

    // for some reason, the very first interrupt always calls the handler
    // twice. This code skips the very first erroneous call

    if (first_call == 0){
        call_pv(perl_callback, G_DISCARD|G_NOARGS);
    }
    else
        first_call = 0;

    FREETMPS;
    LEAVE;
}

int setInterrupt(int pin, int edge, char * callback){
    mine = Perl_get_context();
    perl_callback = callback;
    int interrupt = wiringPiISR(pin, edge, &interruptHandler);
    return interrupt;
}

int initThread(char * callback){
    mine = Perl_get_context();

    PI_THREAD (myThread){
        dSP;
        ENTER;
        SAVETMPS;
        PUSHMARK(SP);
        PUTBACK;

        call_pv(callback, G_DISCARD|G_NOARGS);

        FREETMPS;
        LEAVE;
    }

    return piThreadCreate(myThread);
}

int physPinToWpi(int wpi_pin){
    return phys_wpi_map[wpi_pin];
}

int bmp180Pressure(int pin){
    return analogRead(pin);
}

int bmp180Temp(int pin){
    return analogRead(pin);
}

/*
    not yet implemented

    extern          void setPadDrive         (int group, int value) ;
    extern          void pwmToneWrite        (int pin, int freq) ;
    extern          void pwmSetMode          (int mode) ;
    extern          void pwmSetClock         (int divisor) ;
    extern          void gpioClockSet        (int pin, int freq) ;

*/

MODULE = WiringPi::API  PACKAGE = WiringPi::API

#
# core
#

int
wiringPiSetup()

int
wiringPiSetupSys()

int
wiringPiSetupGpio()

int wiringPiSetupPhys()

void
pinMode(pin, mode)
    int pin
    int mode

void
pullUpDnControl(pin, pud)
    int pin
    int pud

int
digitalRead(pin)
    int pin

void
digitalWrite(pin, value)
    int pin
    int value

void
pwmWrite(pin, value)
    int pin
    int value

int
getAlt(pin)
    int pin

int
analogRead(pin)
    int pin

void
analogWrite(pin, value)
    int pin
    int value

#
# board
#

int
piGpioLayout()

int 
wpiPinToGpio(wpiPin)
    int wpiPin

int 
physPinToGpio(physPin)
    int physPin

void
pwmSetRange(range)
    unsigned int range

#
# lcd
#

int
lcdInit(rows, cols, bits, rs, strb, d0, d1, d2, d3, d4, d5, d6, d7)
    int rows
    int cols
    int bits
    int rs
    int strb
    int d0
    int d1
    int d2
    int d3
    int d4
    int d5
    int d6
    int d7

void
lcdHome(fd)
    int fd

void
lcdClear(fd)
    int fd

void
lcdDisplay(fd, state)
    int fd
    int state

void
lcdCursor(fd, state)
    int fd
    int state

void
lcdCursorBlink(fd, state)
    int fd
    int state

void
lcdSendCommand(fd, command)
    int fd
    char command

void
lcdPosition(fd, x, y)
    int fd
    int x
    int y

void
lcdCharDef(fd, index, data)
    int fd
    int index
    unsigned char * data

void
lcdPutchar(fd, data)
    int fd
    unsigned char data

void
lcdPuts(fd, string)
    int fd
    char * string

# soft pwm

int
softPwmCreate(pin, value, range)
    int pin
    int value
    int range

void
softPwmWrite(pin, value)
    int pin
    int value

void softPwmStop(pin)
    int pin

# SR74HC595 shift register

int
sr595Setup(pin_base, num_pins, data_pin, clock_pin, latch_pin)
    int pin_base
    int num_pins
    int data_pin
    int clock_pin
    int latch_pin

# threading

#int
#piThreadCreate(callback)
#    char callback

void
piLock(keyNum)
    int keyNum

void piUnlock(keyNum)
    int keyNum

# bmp180 pressure sensor

int
bmp180Setup(pin_base)
    int pin_base

int
bmp180Pressure(pin)
    int pin

int
bmp180Temp(pin)
    int pin

# custom

int
setInterrupt(pin, edge, callback)
    int pin
    int edge
    char * callback

void
interruptHandler()

int
initThread(callback)
    char * callback

int
physPinToWpi(wpi_pin)
    int wpi_pin

int
ads1115Setup(pin_base, addr)
    int pin_base
    int addr

int
pseudoPinsSetup(pin_base)
    int pin_base

void
pinModeAlt(pin, mode)
    int pin
    int mode

int
digitalReadByte()

int
digitalReadByte2()

void
digitalWriteByte(value)
    int value

void
digitalWriteByte2(value)
    int value

int
wiringPiSPISetup(channel, speed)
    int channel
    int speed

int
spiDataRW(channel, data, len)
    # custom wrapper for wiringPiSPIDataRW().
    # We transform an aref into an unsigned char *
    int channel
    SV* data
    int len

#char *
#wiringPiVersion()
