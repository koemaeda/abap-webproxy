# ABAP Web Proxy

<b>A Squid-like HTTP proxy that routes your HTTP trafic through an ABAP server</b>

It is useful for accessing internal/intranet websites when all you have is a limited VPN connection or a saprouter access.

```
 /---------\                     /----------\                 /--------\                    /------\
|  Browser  |   HTTP request    |   Node.js  |   RFC call    |   ABAP   |   HTTP request   |  Web   |
|           | ----------------> |   script   | ------------> |  server  | ---------------> | Server |
 \---------/                     \----------/                 \--------/                    \------/
 ```

Node.js version: 6 or higher

ABAP Version: 731 or higher

## Installation

### 1) Install the SAP NetWeaver RFC SDK library

You will need a valid SAP Service Marketplace user to download this (legally).

Follow the instructions at [the node-rfc package prerequisites](https://github.com/SAP/node-rfc#platforms--prerequisites).

### 2) Install the ABAP code

Use [abapGit](https://github.com/larshp/abapGit) to install the RFC function module and the ABAP class in a development system.

### 3) Run the node.js script

Edit the configuration parameters in the `config.json` file to set the proper SAP credentials.

```
node index.js
```

The script will keep running until it's manually stoped.

The RFC connection is kept opened and is reused for all requests. If the connection is lost, it will keep trying to reconnect.

### 4) Configure your browser to use the new proxy

By default the proxy runs on port 3128 (the same as Squid)

## Configuration

All the configuration is stored in the `config.json` file.

Available parameters:

* http.listenPort - The TCP port used by the inbound proxy
* rfc.user, rfc.passwd, rfc,ashost, rfc.sysnr, rfc.client, rfc.saprouter - Logon parameters used by the NetWeaver RFC library
* rfc.maxIdleTime - Time (in seconds) after which an idle RFC connection will be reconnected
* rfc.checkInterval - Time (in seconds) for checking the status of the RFC connection
* rfc.waitTimeout - Timeout (in seconds) when waiting for an available RFC connection

## Limitations

* The CONNECT method is not supported (I don't think it's possible to keep a stateful TCP client socket in the ABAP server)
* WebSockets are not supported (It might be possible via ABAP Push Channels)
* Transparent SSL is not (yet) supported (this is simple to implement, will probably be done in the future)
* The script uses a single RFC connection, so parallel performance is not great (this could be improved by implementing connection pools and load balancing)
* Base64 is not the most optimized way to exchange binary data through RFC, but is the only way I got it to work properly
