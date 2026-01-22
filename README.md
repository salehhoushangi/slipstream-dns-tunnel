# Slipstream DNS Tunnel

Slipstream creates a DNS tunnel between a client inside a restricted network and a remote public server.
It allows forwarding SSH or other TCP services over DNS traffic.

This enables access to a remote server in environments where normal outbound connections are blocked but DNS traffic is still allowed.

---

## How It Works

Slipstream runs two components:

- Server component – runs on a public server
- Client component – runs inside the restricted network

Traffic Flow:

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

## Requirements

### Server (Public / Outside Network)

- Linux (Ubuntu/Debian recommended)
- SSH access
- UDP port 53 open in the firewall
- A domain you control (recommended)

### Client (Restricted Network)

- Linux
- sudo access
- Internet connection

---

## Installation

All setup is performed from the client machine.

1) Make the deploy script executable:

chmod +x slipstream-deploy.sh

2) Run the script:

./slipstream-deploy.sh

The script automatically configures:
- The remote server
- The local client

---

## Configuration Prompts Explained

Server Public IP
Enter the public IP address of your server.

Server SSH User
Usually root.

Tunnel Domain
A domain used for the DNS tunnel.
Both client and server must use the same domain.
Do NOT use public domains like google.com.

Server DNS Listen Port
Normally 53.

Client TCP Listen Port
Local port on the client (default: 7000).

Server Target Address
For SSH forwarding, use:
127.0.0.1:22

This forwards traffic to the server’s SSH service.

---

## Connecting Through the Tunnel

After successful deployment, the client listens on:
127.0.0.1:7000

To connect to your server through the DNS tunnel:

ssh -p 7000 root@127.0.0.1

Use your normal SSH password or SSH key.

---

## Verifying Services

On the Client:

sudo systemctl status slipstream-client
sudo netstat -ntlp | grep 7000

On the Server:

sudo systemctl status slipstream-server
sudo ss -lunp | grep 53

---

## Troubleshooting

Check logs:

journalctl -u slipstream-client -n 100
journalctl -u slipstream-server -n 100

Make sure:
- UDP port 53 is open in the server firewall
- The same tunnel domain is configured on both sides
- SSH is running on the server
- DNS traffic is not being blocked

---

## Important Notes

- Do NOT use public domains like google.com
- Use a domain you control
- Ensure UDP port 53 is open on the server
- Both client and server must use the same tunnel domain
