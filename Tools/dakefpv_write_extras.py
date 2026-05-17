#!/usr/bin/env python3
"""
Write lines to /fs/microsd/etc/extras.txt on a DAKEFPV H743 via MAVLink shell.
Uses NSH append redirection (>>) which works on NuttX littlefs.

Usage:
  python3 dakefpv_write_extras.py [port] [line1] [line2] ...

Example:
  python3 dakefpv_write_extras.py /dev/ttyACM0 "ist8310 -X -b 2 -a 0x0C start"

From QGroundControl MAVLink Console, run directly:
  echo "ist8310 -X -b 2 -a 0x0C start" >> /fs/microsd/etc/extras.txt
"""

import sys, time
import pymavlink.mavutil as mavutil
from pymavlink.mavutil import mavlink

PORT  = sys.argv[1] if len(sys.argv) > 1 else '/dev/serial/by-id/usb-DakeFPV_DAKEFPVH743_0-if00'
LINES = sys.argv[2:] if len(sys.argv) > 2 else ['ist8310 -X -b 2 -a 0x0C start']

orig = mavutil.mavfile.post_message
def safe(self, msg):
    try: orig(self, msg)
    except: pass
mavutil.mavfile.post_message = safe

mav = mavutil.mavlink_connection(PORT, baud=2000000)
mav.wait_heartbeat(timeout=15)
print(f'Connected sysid={mav.target_system}')

def shell(cmd):
    data = list((cmd + '\n').encode().ljust(70, b'\x00'))[:70]
    mav.mav.serial_control_send(
        mavlink.SERIAL_CONTROL_DEV_SHELL,
        mavlink.SERIAL_CONTROL_FLAG_EXCLUSIVE | mavlink.SERIAL_CONTROL_FLAG_RESPOND,
        0, 0, len(cmd) + 1, data)
    time.sleep(1.0)
    out = b''
    while True:
        m = mav.recv_match(type='SERIAL_CONTROL', timeout=0.5)
        if not m: break
        out += bytes(m.data[:m.count])
    return out.decode('utf-8', errors='replace')

# Clear existing file and write fresh
shell('rm /fs/microsd/etc/extras.txt')
for line in LINES:
    result = shell(f'echo "{line}" >> /fs/microsd/etc/extras.txt')
    if 'failed' in result.lower() or 'error' in result.lower():
        print(f'ERROR writing line: {line}')
        print(result)
        sys.exit(1)

# Verify
content = shell('cat /fs/microsd/etc/extras.txt')
print('extras.txt content:')
for line in content.split('\n'):
    line = line.strip('\r\x1b[K')
    if line and 'nsh>' not in line:
        print(' ', line)

print('\nReboot the board to apply.')
mav.close()
