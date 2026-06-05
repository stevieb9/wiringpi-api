/*
 * API.xs file for WiringPi::API Perl distribution
 *
 * Copyright (c) 2017-2026 by Steve Bertrand
 *
 * This library is free software; you can redistribute it and/or modify it under
 * the same terms as Perl itself, either Perl version 5.18.2 or, at your option,
 * any later version of Perl 5 you may have available.
 *
 */

#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "INLINE.h"

#include "API.h"
#include <wiringPi.h>
#include <wiringPiSPI.h>
#include <lcd.h>
#include <sys/mman.h>
#include <softPwm.h>
#include <softTone.h>
#include <sr595.h>

#define PERL_NO_GET_CONTEXT

char* serialGets(int fd, char* buf, int nbytes){
    int bytes_read = 0;

    while (bytes_read < nbytes){
        int result = read(fd, buf + bytes_read, nbytes - bytes_read);
        
        if (0 >= result){
            if (0 > result){
                exit(-1);
            }
            break;
        }
        bytes_read += result;
    }

    return buf;
}

void spiDataRW(int channel, SV* byte_ref, int len){

     /*
      * Custom wrapper for wiringPiSPIDataRW() as we
      * need to translate an aref into an unsigned char *,
      * and then send back an array containing the bytes
      * read from the device
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
    
    if (wiringPiSPIDataRW(channel, buf, len) < 0){
        croak("failed to write to the SPI bus\n");
    }

    inline_stack_vars;
    inline_stack_reset;

    int x;
    for (x=0; x<len; x++){
        inline_stack_push(sv_2mortal(newSViv(buf[x])));
    } 

    inline_stack_done;
}

// Used for interrupts and threads

PerlInterpreter * mine;

/* Per-pin callback storage so multiple interrupts can coexist. */

#define MAX_PINS 40
static SV *perl_callbacks[MAX_PINS] = { NULL };

/* Event queue for ISR -> dispatcher communication */

#define EVENT_QUEUE_SIZE 256
typedef struct {
    int events[EVENT_QUEUE_SIZE];
    int head;
    int tail;
    int count;
} event_queue_t;

static event_queue_t event_queue = { .head = 0, .tail = 0, .count = 0 };
static pthread_mutex_t event_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t event_cond = PTHREAD_COND_INITIALIZER;
static pthread_t dispatcher_thread;
static int dispatcher_started = 0;
static int dispatcher_shutdown = 0;

static void ISR_enqueue_event(int pin){
    pthread_mutex_lock(&event_mutex);
    if (event_queue.count < EVENT_QUEUE_SIZE) {
        event_queue.events[event_queue.tail] = pin;
        event_queue.tail = (event_queue.tail + 1) % EVENT_QUEUE_SIZE;
        event_queue.count++;
        pthread_cond_signal(&event_cond);
    }
    pthread_mutex_unlock(&event_mutex);
}

static int ISR_dequeue_event(int *pin){
    pthread_mutex_lock(&event_mutex);
    while (event_queue.count == 0 && !dispatcher_shutdown) {
        pthread_cond_wait(&event_cond, &event_mutex);
    }
    if (event_queue.count == 0 && dispatcher_shutdown) {
        pthread_mutex_unlock(&event_mutex);
        return 0;
    }
    *pin = event_queue.events[event_queue.head];
    event_queue.head = (event_queue.head + 1) % EVENT_QUEUE_SIZE;
    event_queue.count--;
    pthread_mutex_unlock(&event_mutex);
    return 1;
}

static void *ISR_dispatcher_main(void *arg){
    int pin;
    PERL_SET_CONTEXT(mine);
    while (ISR_dequeue_event(&pin)){
        if (pin < 0 || pin >= MAX_PINS) continue;

        if (! perl_callbacks[pin]) continue;
        if (! SvROK(perl_callbacks[pin]) || SvTYPE(SvRV(perl_callbacks[pin])) != SVt_PVCV) continue;

        dSP; ENTER; SAVETMPS; PUSHMARK(SP); PUTBACK;
        call_sv(SvRV(perl_callbacks[pin]), G_DISCARD|G_NOARGS);
        FREETMPS; LEAVE;
    }
    return NULL;
}

/* Generate a small wrapper handler for each pin that enqueues the pin */

#define MAKE_HANDLER(n) \
static void interruptHandler_##n(void){ \
    ISR_enqueue_event(n); \
}

/* Apply macro to every pin index to generate handlers and handler table. */

#define APPLY_TO_PINS(m) \
    m(0)  m(1)  m(2)  m(3)  m(4)  m(5)  m(6)  m(7)  \
    m(8)  m(9)  m(10) m(11) m(12) m(13) m(14) m(15) \
    m(16) m(17) m(18) m(19) m(20) m(21) m(22) m(23) \
    m(24) m(25) m(26) m(27) m(28) m(29) m(30) m(31) \
    m(32) m(33) m(34) m(35) m(36) m(37) m(38) m(39)

/* Generate handlers */

APPLY_TO_PINS(MAKE_HANDLER)

/* Array of function pointers to pass to wiringPiISR */

#define HANDLER_PTR(n) interruptHandler_##n,
static void (*interrupt_handlers[MAX_PINS])(void) = { APPLY_TO_PINS(HANDLER_PTR) };

#undef HANDLER_PTR
#undef APPLY_TO_PINS

int setInterrupt(int pin, int edge, SV * callback){
    mine = Perl_get_context();

    if (pin < 0 || pin >= MAX_PINS) {
        croak("pin out of range\n");
    }

    if (! callback || ! SvROK(callback) || SvTYPE(SvRV(callback)) != SVt_PVCV) {
        croak("callback param must be a CODE reference\n");
    }

    if (perl_callbacks[pin]) SvREFCNT_dec(perl_callbacks[pin]);
    perl_callbacks[pin] = callback;
    SvREFCNT_inc(perl_callbacks[pin]);

    /* Start dispatcher once (captures `mine` above). */

    if (! dispatcher_started) {
        dispatcher_shutdown = 0;
        if (pthread_create(&dispatcher_thread, NULL, ISR_dispatcher_main, NULL) == 0) {
            dispatcher_started = 1;
        }
    }

    return wiringPiISR(pin, edge, interrupt_handlers[pin]);
}

static SV *thread_callback_sv = NULL; /* code-ref for thread entry */

int initThread(SV * callback){
    mine = Perl_get_context();

    if (! callback || ! SvROK(callback) || SvTYPE(SvRV(callback)) != SVt_PVCV) {
        croak("callback param must be a CODE reference\n");
    }

    if (thread_callback_sv) SvREFCNT_dec(thread_callback_sv);
    thread_callback_sv = callback;
    SvREFCNT_inc(thread_callback_sv);

    PI_THREAD (myThread){
        PERL_SET_CONTEXT(mine);
        dSP;
        ENTER;
        SAVETMPS;
        PUSHMARK(SP);
        PUTBACK;

        call_sv(SvRV(thread_callback_sv), G_DISCARD|G_NOARGS);

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

MODULE = WiringPi::API  PACKAGE = WiringPi::API PREFIX = XS_

PROTOTYPES: DISABLE

#
# core
#

int
wiringPiSetup()

int
wiringPiSetupGpio()

int
wiringPiSetupPinType(pinType)
    int pinType

int
wiringPiSetupGpioDevice(pinType)
    int pinType

int
wiringPiGpioDeviceGetFd()

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

char *
wiringPiVersion()
    CODE:
        int major;
        int minor;
        char ver[16];
        wiringPiVersion(&major, &minor);
        snprintf(ver, sizeof(ver), "%d.%d", major, minor);
        RETVAL = ver;
    OUTPUT:
        RETVAL

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

void
pwmSetClock(divisor)
    int divisor

void pwmSetMode(mode)
    int mode

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
    unsigned char command

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

# soft tone

int
softToneCreate(pin)
    int pin

void
softToneStop(pin)
    int pin

void
softToneWrite(pin, freq)
    int pin
    int freq

# SR74HC595 shift register

int
sr595Setup(pin_base, num_pins, data_pin, clock_pin, latch_pin)
    int pin_base
    int num_pins
    int data_pin
    int clock_pin
    int latch_pin

void
piLock(keyNum)
    int keyNum

void piUnlock(keyNum)
    int keyNum

# timing / scheduling

void
delay(ms)
    unsigned int ms

void
delayMicroseconds(us)
    unsigned int us

unsigned int
millis()

unsigned int
micros()

uint64_t
piMicros64()

int
piHiPri(pri)
    int pri

# pad drive / pwm tone / gpio clock

void
setPadDrive(group, value)
    int group
    int value

void
setPadDrivePin(pin, value)
    int pin
    int value

void
pwmToneWrite(pin, freq)
    int pin
    int freq

void
gpioClockSet(pin, freq)
    int pin
    int freq

# board / identity

int
wiringPiGlobalMemoryAccess()

int
wiringPiUserLevelAccess()

int
getPinModeAlt(pin)
    int pin

int
piBoard40Pin()

int
piRP1Model()

void
piBoardId()
    PPCODE:
        int model, rev, mem, maker, overVolted;
        piBoardId(&model, &rev, &mem, &maker, &overVolted);
        EXTEND(SP, 5);
        mPUSHi(model);
        mPUSHi(rev);
        mPUSHi(mem);
        mPUSHi(maker);
        mPUSHi(overVolted);

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
    SV * callback

int
initThread(callback)
    SV * callback

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

unsigned int
digitalReadByte()

unsigned int
digitalReadByte2()

void
digitalWriteByte(value)
    int value

void
digitalWriteByte2(value)
    int value

# SPI

int
wiringPiSPISetup(channel, speed)
    int channel
    int speed

void
spiDataRW (channel, byte_ref, len)
	int	channel
	SV *	byte_ref
	int	len
        PREINIT:
        I32* temp;
        PPCODE:
        temp = PL_markstack_ptr++;
        spiDataRW(channel, byte_ref, len);
        if (PL_markstack_ptr != temp) {
          PL_markstack_ptr = temp;
          XSRETURN_EMPTY;
        }
        return;

int
wiringPiSPIGetFd(channel)
    int channel

int
wiringPiSPISetupMode(channel, speed, mode)
    int channel
    int speed
    int mode

int
wiringPiSPIClose(channel)
    int channel

# I2C

int wiringPiI2CSetup (devId)
    int devId

int wiringPiI2CSetupInterface (device, devId)
    char* device
    int devId

int wiringPiI2CRead (fd)
    int fd

int wiringPiI2CReadReg8 (fd, reg)
    int fd
    int reg

int wiringPiI2CReadReg16 (fd, reg)
    int fd
    int reg

int wiringPiI2CWrite (fd, data)
    int fd
    int data

int wiringPiI2CWriteReg8 (fd, reg, data)
     int fd
     int reg
     int data

int wiringPiI2CWriteReg16 (fd, reg, data)
    int fd
    int reg
    int data

void
wiringPiI2CReadBlockData(fd, reg, size)
    int fd
    int reg
    int size
    PREINIT:
        uint8_t buf[256];
        int n, i;
    PPCODE:
        if (size < 0 || size > 255)
            croak("wiringPiI2CReadBlockData: size must be 0-255");
        n = wiringPiI2CReadBlockData(fd, reg, buf, (uint8_t)size);
        if (n < 0)
            croak("wiringPiI2CReadBlockData: read failed");
        EXTEND(SP, n);
        for (i = 0; i < n; i++)
            mPUSHu(buf[i]);

void
wiringPiI2CRawRead(fd, size)
    int fd
    int size
    PREINIT:
        uint8_t buf[256];
        int n, i;
    PPCODE:
        if (size < 0 || size > 255)
            croak("wiringPiI2CRawRead: size must be 0-255");
        n = wiringPiI2CRawRead(fd, buf, (uint8_t)size);
        if (n < 0)
            croak("wiringPiI2CRawRead: read failed");
        EXTEND(SP, n);
        for (i = 0; i < n; i++)
            mPUSHu(buf[i]);

int
wiringPiI2CWriteBlockData(fd, reg, values)
    int fd
    int reg
    SV * values
    PREINIT:
        uint8_t buf[256];
        AV *av;
        int len, i;
        SV **elem;
    CODE:
        if (! SvROK(values) || SvTYPE(SvRV(values)) != SVt_PVAV)
            croak("wiringPiI2CWriteBlockData: values must be an array reference");
        av = (AV *)SvRV(values);
        len = av_len(av) + 1;
        if (len < 0 || len > 255)
            croak("wiringPiI2CWriteBlockData: 0-255 values allowed");
        for (i = 0; i < len; i++) {
            elem = av_fetch(av, i, 0);
            buf[i] = (uint8_t)(elem ? SvUV(*elem) : 0);
        }
        RETVAL = wiringPiI2CWriteBlockData(fd, reg, buf, (uint8_t)len);
    OUTPUT:
        RETVAL

int
wiringPiI2CRawWrite(fd, values)
    int fd
    SV * values
    PREINIT:
        uint8_t buf[256];
        AV *av;
        int len, i;
        SV **elem;
    CODE:
        if (! SvROK(values) || SvTYPE(SvRV(values)) != SVt_PVAV)
            croak("wiringPiI2CRawWrite: values must be an array reference");
        av = (AV *)SvRV(values);
        len = av_len(av) + 1;
        if (len < 0 || len > 255)
            croak("wiringPiI2CRawWrite: 0-255 values allowed");
        for (i = 0; i < len; i++) {
            elem = av_fetch(av, i, 0);
            buf[i] = (uint8_t)(elem ? SvUV(*elem) : 0);
        }
        RETVAL = wiringPiI2CRawWrite(fd, buf, (uint8_t)len);
    OUTPUT:
        RETVAL

# serial interface

int serialOpen (device, baud)
    char* device
    int baud

void serialClose (fd)
    int fd

void serialFlush (fd)
    int fd

void serialPutchar (fd, c)
    int fd
    unsigned char c

void serialPuts (fd, s)
    int fd
    char* s

int serialDataAvail (fd)
    int fd

int serialGetchar (fd)
    int fd

char* serialGets(fd, buf, nbytes)
    int fd
    char* buf
    int nbytes
