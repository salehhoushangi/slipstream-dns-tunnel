# Slipstream DNS Tunnel – Quick Setup Guide

Slipstream creates a DNS tunnel between a **client (restricted network)** and a **remote server**, allowing you to forward SSH (or other TCP services) over DNS.

---

## What You Need

### On the Server (outside / public)

- Linux (Ubuntu/Debian recommended)
- SSH access
- UDP port 53 open in the firewall

### On the Client (inside restricted network)

- Linux
- `sudo` access
- Internet connection

---

## Quick Setup

Run everything **from the client machine**:

```bash
chmod +x slipstream-deploy.sh
./slipstream-deploy.sh
