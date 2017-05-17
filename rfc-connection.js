/*
 * ABAP Web Proxy
 * https://github.com/koemaeda/abap-web-proxy
 *
 * Copyright (c) 2017 Guilherme Maeda
 * Licensed under the MIT license.
 */
"use strict";

var util = require('util'),
    http = require('http'),
    rfc = require('node-rfc');

var config = require('./config.json');

/**
 * RFC persistent connection class
 */
function Connection() {
  // Initialize properties
  this.status = {
    connecting: false,
    connected: false,
    activeCalls: 0,
    expiry: 0 // force immediate connection
  };

  // Initialize the NW RFC client
  this.client = new rfc.Client(config.rfc);

  // Setup monitor to keep the RFC connection alive
  setInterval(() => {
    this.checkConnection();
  }, config.rfc.checkInterval*1000);

  // Connect!
  console.log('(RFC Connection) Instance created - Client library version:', this.getClientVersion());
  this.checkConnection();
}

Connection.prototype.getClientVersion = function() {
  return this.client.getVersion();
};

Connection.prototype.checkConnection = function() {
  // Check if we should really bother the client connection
  if (this.status.connecting)
    return console.log('(RFC Connection.checkConnection) Still connecting...');
  if (this.status.activeCalls > 0) // see https://github.com/SAP/node-rfc/issues/25
    return console.log('(RFC Connection.checkConnection) Client is busy right now');

  if ( // Check if it must reconnect
    (! this.client.isAlive()) ||                // Check if client closed the connection (maybe because of an error)
    ((new Date()/1000) > this.status.expiry) || // Check if the connection is expired
    (! this.client.ping())                      // Check if it responds to ping
  ) {
    this.client.close();
    this.status.connected = false;
    this.status.connecting = true;

    console.log('(RFC Connection.checkConnection) Connecting to SAP system...');
    var conn = this;
    this.client.connect(function(error) {
      if (error) {
        conn.status.connecting = false;
        conn.status.connected = false;
        return console.error('(RFC Connection.checkConnection) Could not connect to SAP system', error);
      }

      // Success!
      conn.status.connecting = false;
      conn.status.connected = true;
      conn.status.expiry = (new Date()/1000) + config.rfc.maxIdleTime;
      console.log('(RFC Connection.checkConnection) Connected to SAP system');
    });
  }
};

/**
 * Returns a promise that resolves when the RFC connection is online
 */
Connection.prototype.whenConnected = function() {
  return new Promise((resolve, reject) => {
    if (this.status.connected)
      return resolve(true);

    this.checkConnection();

    // Wait unti the RFC client is connected
    var timeOut = (new Date()/1000) + config.rfc.waitTimeout;
    var interval = setInterval(() => {
      if (this.status.connected) {
        clearInterval(interval);
        resolve(true);
      }

      if ((new Date()/1000) > timeOut) {
        clearInterval(interval);
        reject('Timeout waiting for an RFC connection');
      }
    }, 100);
  });
};

/**
 * Handle an HTTP proxy request
 * @param http.IncomingMessage request
 * @param Buffer postData
 * @param http.ServerResponse response
 * @param function finish
 */
Connection.prototype.handleRequest = function(request, postData, response, finish) {
  var requestHeaders = new Array();
  for (var i=0; i<request.rawHeaders.length; i+=2)
    requestHeaders.push({ NAME: request.rawHeaders[i], VALUE: request.rawHeaders[i+1] });

  // Dispatch request to be handled by the ABAP system
  this.whenConnected().then(() => {
    this.status.activeCalls++;
    this.client.invoke('ZWEBPROXY_HANDLE_REQUEST', {
      METHOD: request.method,
      URI: request.url,
      REQUEST_HEADERS: requestHeaders,
      POST_DATA_B64: postData.toString('base64'),
      HTTP_VERSION_MAJOR: request.httpVersionMajor,
      HTTP_VERSION_MINOR: request.httpVersionMinor,
      PROXY_HOST: config.proxy.host,
      PROXY_PORT: config.proxy.port,
      PROXY_USERNAME: config.proxy.username,
      PROXY_PASSWORD: config.proxy.password
    }, (error, rfcRes) => {
      this.status.activeCalls--;
      if (error) {
        console.error('(RFC Connection.handleRequest) Error invoking ZWEBPROXY_HANDLE_REQUEST:', error);
        response.writeHead(503, { 'Retry-After': '60' });
        response.write(error.toString());
        return response.end();
      }
      this.status.expiry = (new Date()/1000) + config.rfc.maxIdleTime;

      // Return the HTTP response to the browser
      rfcRes.RESPONSE_HEADERS.forEach((header) => {
        response.setHeader(header.NAME, header.VALUE);
      });
      response.writeHead(rfcRes.CODE, rfcRes.MESSAGE);

      var base64 = '';
      rfcRes.DATA_B64.forEach((line) => { base64 += line.LINE; });
      response.write(Buffer.from(base64, 'base64'));
      response.end();

      finish();
    });
  }).catch((error) => {
    console.error('(RFC Connection.handleRequest) Error waiting for RFC connection:', error);
    response.writeHead(503, { 'Retry-After': '60' });
    response.write(error.toString());
    return response.end();
  });
};


module.exports = { Connection };
