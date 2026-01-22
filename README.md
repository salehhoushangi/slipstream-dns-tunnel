# Slipstream DNS Tunnel

Slipstream creates a DNS tunnel between a client inside a restricted network and a remote public server.  
It allows you to forward SSH or other TCP services over DNS traffic.

This makes it possible to access a remote server even in environments where normal outbound connections are blocked but DNS traffic is still allowed.

---

## How It Works

Slipstream runs two components:

- A **server component** on a public server
- A **client component** inside a restricted network

Traffic flow:

SSH Client ->
127.0.0.1:7000 (Slipstream Client) -> DNS Tunnel (UDP 53) ->Slipstream Server -> 127.0.0.1:22 (Server SSH)
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

All setup is done from the **client machine**.

Make the deploy script executable:

```bash
chmod +x slipstream-deploy.sh

Run the script:

./slipstream-deploy.sh

The script will automatically configure:

    The server (remote machine)

    The client (local machine)

Configuration Prompts Explained

During setup, you will be asked for the following values:

Server public IP
Enter your server’s public IP address.

Server SSH user
Usually root.

Tunnel domain
A domain used for the DNS tunnel.
Both client and server must use the same domain.
Do NOT use public domains like google.com.

Server DNS listen port
Normally 53.

Client TCP listen port
Local port on the client (default: 7000).

Server target-address
For SSH forwarding, use:

127.0.0.1:22

This forwards traffic to the server’s SSH service.
Connecting Through the Tunnel

After successful deployment, the client listens locally on:

127.0.0.1:7000

To connect to your server through the DNS tunnel:

ssh -p 7000 root@127.0.0.1

Use your normal server SSH password or SSH key.
Verifying Services
On the Client

Check client service status:

sudo systemctl status slipstream-client

Check if the local port is listening:

sudo netstat -ntlp | grep 7000

On the Server

Check server service status:

sudo systemctl status slipstream-server

Verify UDP port 53 is listening:

sudo ss -lunp | grep 53

Troubleshooting

Check logs:

journalctl -u slipstream-client -n 100
journalctl -u slipstream-server -n 100

Make sure:

    UDP port 53 is open in the server firewall

    The same tunnel domain is configured on both sides

    SSH is running on the server

    DNS traffic is not being blocked

Important Notes

    Do NOT use public domains like google.com

    Use a domain you control

    Ensure UDP port 53 is open on the server

    Both client and server must use the same tunnel domain
