# Slipstream DNS Tunnel

Slipstream creates a DNS tunnel between a client inside a restricted network and a remote public server.

It allows forwarding SSH or other TCP services over DNS traffic.

This makes it possible to access a remote server even when normal outbound connections (like TCP 22) are blocked, but DNS traffic (UDP 53) is still allowed.

---

# How It Works

Slipstream runs two components:

- slipstream-server → runs on a public server
- slipstream-client → runs inside the restricted network

Traffic flow:

SSH Client
  ->
127.0.0.1:7000 (Slipstream Client)
  ->
DNS Tunnel (UDP 53)
  ->
Slipstream Server
  ->
127.0.0.1:22 (Server SSH)

You are effectively running SSH over DNS.

---

# Deployment Modes

Before starting installation, determine whether you have direct SSH access (TCP port 22) to the server.

Slipstream supports two deployment modes:

---

## 1) Integrated Deployment (Recommended)

Use this method if:

- The client machine CAN connect to the server via SSH (TCP port 22 reachable).
- You have SSH credentials for the server.

In this mode:

- You run a single deployment script from the client.
- The script connects to the server via SSH.
- It installs and configures both server and client automatically.

Advantages:

- Fully automated
- No manual coordination
- Fewer configuration mismatches
- Faster setup

If SSH connectivity exists, this is the preferred method.

---

## 2) Split Deployment (When SSH Is NOT Available)

Use this method if:

- Outbound TCP 22 is blocked
- The server is unreachable on SSH from the client network
- You do not have SSH credentials
- Network policy blocks SSH traffic

In this mode:

- A server administrator runs the server setup script directly on the public server.
- The client operator runs the client setup script locally.
- No SSH connection from client to server is required during installation.

This method is specifically designed for restricted network environments.

---

# Requirements

## Server (Public / Outside Network)

- Linux (Ubuntu/Debian recommended)
- Root or sudo access
- UDP port 53 open (or chosen DNS port)
- Internet access for dependency installation
- A domain name (recommended)

## Client (Restricted Network)

- Linux
- sudo access
- Internet access
- Ability to send UDP traffic to SERVER_IP:DNS_PORT

---

# Split Deployment Instructions

If using Split Deployment:

---

## Server-Side Setup (Run by Server Administrator)

The server administrator must:

1) Run the server setup script directly on the server:

chmod +x server-setup.sh
DOMAIN=mytunnel.example DNS_LISTEN_PORT=53 TARGET_ADDRESS=127.0.0.1:22 ./server-setup.sh

This will:

- Install dependencies + Rust
- Build slipstream-server
- Generate TLS certificate and key
- Create systemd service
- Start slipstream-server
- Bind to UDP port 53

2) Verify the service:

systemctl status slipstream-server

3) Verify UDP port is listening:

ss -lunp | grep :53

4) Ensure firewall allows UDP 53:
- ufw
- iptables
- cloud provider security groups

If UDP 53 is blocked, the tunnel will not function.

---

## Values the Server Admin Must Provide

The client operator needs:

- SERVER_IP
- DNS_LISTEN_PORT
- DOMAIN
- TARGET_ADDRESS (usually 127.0.0.1:22)

Example:

SERVER_IP=203.0.113.10
DNS_LISTEN_PORT=53
DOMAIN=mytunnel.example
TARGET_ADDRESS=127.0.0.1:22

---

## Client-Side Setup (Inside Restricted Network)

After receiving server values:

SERVER_IP=203.0.113.10 DOMAIN=mytunnel.example DNS_LISTEN_PORT=53 CLIENT_TCP_PORT=7000 ./client-setup.sh

This will:

- Build slipstream-client
- Create and start systemd service
- Open local TCP listener (127.0.0.1:7000)

---

# Connecting Through the Tunnel

Once client is running:

ssh -p 7000 root@127.0.0.1

Traffic path:

Local SSH
  ->
127.0.0.1:7000
  ->
slipstream-client
  ->
UDP 53 DNS tunnel
  ->
slipstream-server
  ->
127.0.0.1:22 (server SSH)

---

# Verifying Services

## On Client

systemctl status slipstream-client
ss -ntlp | grep 7000

## On Server

systemctl status slipstream-server
ss -lunp | grep :53

---

# Troubleshooting

Check logs:

journalctl -u slipstream-client -n 100
journalctl -u slipstream-server -n 100

Ensure:

- UDP port 53 is open on the server
- Client can reach SERVER_IP:DNS_PORT via UDP
- Same DOMAIN is configured on both sides
- SSH service is running on server (if forwarding to 127.0.0.1:22)

---

# Technical Limitations

- Split deployment is required only if SSH (TCP 22) from client to server is unavailable.
- The DNS tunnel requires outbound UDP from client to SERVER_IP:DNS_PORT.
- Some restrictive networks allow DNS only to approved resolvers.
- If UDP 53 to your server is blocked, the tunnel will not work.
- Using public domains (e.g., google.com) is not recommended.

---

# Important Notes

- Always use the same DOMAIN on both client and server.
- Ensure firewall rules allow inbound UDP on the server.
- Integrated deployment is simpler when SSH access exists.
- Split deployment exists for restricted environments.
