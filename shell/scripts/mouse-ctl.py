#!/usr/bin/env python3
"""Minimal Wayland/KDE virtual mouse controller using Linux /dev/uinput (no external deps)."""
import ctypes
import fcntl
import os
import struct
import sys
import time

# Linux input constants
UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_SET_ABSBIT = 0x40045567
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502

EV_SYN = 0x00
EV_KEY = 0x01
EV_ABS = 0x03
SYN_REPORT = 0x00

BTN_LEFT = 0x110
BTN_RIGHT = 0x111
ABS_X = 0x00
ABS_Y = 0x01
BUS_USB = 0x03

# struct uinput_abs_setup / legacy uinput_user_dev (80s+4+4+4+4 + 64*4*4 = 1116 bytes)
class UInputUserDev(ctypes.Structure):
    _fields_ = [
        ("name", ctypes.c_char * 80),
        ("id_bustype", ctypes.c_uint16),
        ("id_vendor", ctypes.c_uint16),
        ("id_product", ctypes.c_uint16),
        ("id_version", ctypes.c_uint16),
        ("ff_effects_max", ctypes.c_uint32),
        ("absmax", ctypes.c_int32 * 64),
        ("absmin", ctypes.c_int32 * 64),
        ("absfuzz", ctypes.c_int32 * 64),
        ("absflat", ctypes.c_int32 * 64),
    ]

def emit(fd, etype, code, val):
    sec = int(time.time())
    usec = int((time.time() - sec) * 1_000_000)
    os.write(fd, struct.pack("llHHi", sec, usec, etype, code, val))

def main():
    if len(sys.argv) < 4:
        print("Usage: mouse-ctl.py <move|click|rightclick> <x> <y> [screen_w screen_h]")
        sys.exit(1)

    action = sys.argv[1]
    x = int(float(sys.argv[2]))
    y = int(float(sys.argv[3]))
    sw = int(sys.argv[4]) if len(sys.argv) > 4 else 1920
    sh = int(sys.argv[5]) if len(sys.argv) > 5 else 1080

    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    try:
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_LEFT)
        fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_RIGHT)
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_ABS)
        fcntl.ioctl(fd, UI_SET_ABSBIT, ABS_X)
        fcntl.ioctl(fd, UI_SET_ABSBIT, ABS_Y)

        udev = UInputUserDev()
        udev.name = b"paithosh-virtual-mouse"
        udev.id_bustype = BUS_USB
        udev.id_vendor = 0x1234
        udev.id_product = 0x5678
        udev.id_version = 1
        udev.absmin[ABS_X] = 0
        udev.absmax[ABS_X] = sw
        udev.absmin[ABS_Y] = 0
        udev.absmax[ABS_Y] = sh

        os.write(fd, bytes(udev))
        fcntl.ioctl(fd, UI_DEV_CREATE)
        time.sleep(0.25)

        emit(fd, EV_ABS, ABS_X, x)
        emit(fd, EV_ABS, ABS_Y, y)
        emit(fd, EV_SYN, SYN_REPORT, 0)
        time.sleep(0.08)

        if action == "click":
            emit(fd, EV_KEY, BTN_LEFT, 1)
            emit(fd, EV_SYN, SYN_REPORT, 0)
            time.sleep(0.05)
            emit(fd, EV_KEY, BTN_LEFT, 0)
            emit(fd, EV_SYN, SYN_REPORT, 0)
        elif action == "rightclick":
            emit(fd, EV_KEY, BTN_RIGHT, 1)
            emit(fd, EV_SYN, SYN_REPORT, 0)
            time.sleep(0.05)
            emit(fd, EV_KEY, BTN_RIGHT, 0)
            emit(fd, EV_SYN, SYN_REPORT, 0)

        time.sleep(0.15)
        fcntl.ioctl(fd, UI_DEV_DESTROY)
    finally:
        os.close(fd)

if __name__ == "__main__":
    main()
