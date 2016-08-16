#include <stdlib.h>
#include <stdint.h>

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <wiringPi.h>
#include <lcd.h>

/*
 * definitions
 */

void registerInterrupt(int pin, int edge, int int_num);
void interruptOne();
void interruptTwo();
static int phys_wpi_map[64];
int physPinToWpi(int wpi_pin);
void callPerlInterrupt();

/*
 * declarations
 */

void registerInterrupt(int pin, int edge, int int_num){
    if (int_num == 1)
        wiringPiISR(pin, edge, &interruptOne);
    if (int_num == 2)
        wiringPiISR(pin, edge, &interruptTwo);
}

void interruptOne(){
    //dSP;
    //PUSHMARK(SP);
    printf("*** interrupt one! ***\n");
    //call_pv("RPi::WiringPi::Interrupt::interrupt_one", G_DISCARD|G_NOARGS);
}

void interruptTwo(){
    dSP;
    PUSHMARK(SP);
    call_pv("RPi::WiringPi::Interrupt::interrupt_two", G_DISCARD|G_NOARGS);
}

int physPinToWpi(int wpi_pin){
    return phys_wpi_map[wpi_pin];
}

void callPerlInterrupt(){
    printf("test");
}

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

/*
    not yet implemented

    # core

    extern void pinModeAlt          (int pin, int mode) ;
    extern int  analogRead          (int pin) ;
    extern void analogWrite         (int pin, int value) ;

    # board

    extern          void setPadDrive         (int group, int value) ;
    extern          void pwmToneWrite        (int pin, int freq) ;
    extern          void digitalWriteByte    (int value) ;
    extern unsigned int  digitalReadByte     (void) ;
    extern          void pwmSetMode          (int mode) ;
    extern          void pwmSetClock         (int divisor) ;
    extern          void gpioClockSet        (int pin, int freq) ;

*/

MODULE = RPi::WiringPi::Core  PACKAGE = RPi::WiringPi::Core

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
digitalWriteByte(value)
    int value

void
pwmWrite(pin, value)
    int pin
    int value

int
getAlt(pin)
    int pin

#
# board
#

int
piBoardRev()

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
    unsigned char *data

void
lcdPutchar(fd, data)
    int fd
    unsigned char data

void lcdPuts(fd, string)
    int fd
    char *string

# custom

int
physPinToWpi(wpi_pin)
    int wpi_pin

void
registerInterrupt(pin, edge, int_num)
    int pin
    int edge
    int int_num

void
interruptOne()

void
interruptTwo()
