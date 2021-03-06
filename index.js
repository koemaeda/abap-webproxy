/*
 * ABAP Web Proxy
 * https://github.com/koemaeda/abap-web-proxy
 *
 * Copyright (c) 2017 Guilherme Maeda
 * Licensed under the MIT license.
 */
"use strict";

const LIB_VERSION = '1.0.0';

var util = require('util'),
    http = require('http'),
    rfc = require('./rfc-connection');

var config = require('./config.json');

console.log("ABAP Web Proxy", LIB_VERSION, "started!");

// Initialize RFC persistent connection
var conn = new rfc.Connection();

// Initialize HTTP server
var server = http.createServer(function(request, response) {
  console.log('(HTTP Server) Request received:', request.method, request.url);

  // Receive complete request data
  var postDataChunks = [];
  request.on('data', (chunk) => {
    postDataChunks.push(chunk);
  });

  // Complete request received, serve it!
  request.on('end', () => {
    var postData = Buffer.concat(postDataChunks);
    conn.handleRequest(request, postData, response, () => {
      console.log('(HTTP Server) Request served:', request.method, request.url,
        '=>', response.statusCode, response.statusMessage);
    });
  });
});

console.log("HTTP proxy listening on port", config.http.listenPort);
server.listen(config.http.listenPort);
