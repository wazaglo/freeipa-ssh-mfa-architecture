#!/bin/bash
set -e

# Start sshd
/usr/sbin/sshd

# Start systemd as PID 1 for proper service management
exec /usr/sbin/init
