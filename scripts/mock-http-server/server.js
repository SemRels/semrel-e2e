#!/usr/bin/env node
// Minimal local mock HTTP endpoint used by scenarios that exercise
// publisher/hook plugins without talking to any real external service.
//
// Every incoming request is appended as one JSON line to REQUESTS_LOG
// (default: ./requests.ndjson next to this script, override with argv[2]),
// then answered with 200 OK. Listens on 127.0.0.1 only.
//
// Usage: node server.js <port> <requestsLogPath>
// Prints "LISTENING <port>" to stdout once bound, so callers can wait on it.

const http = require('http');
const fs = require('fs');

const port = Number(process.argv[2] || 0);
const logPath = process.argv[3] || './requests.ndjson';

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const record = {
      time: new Date().toISOString(),
      method: req.method,
      url: req.url,
      headers: req.headers,
      bodyBase64: body.toString('base64'),
      bodyText: body.toString('utf8'),
    };
    fs.appendFileSync(logPath, JSON.stringify(record) + '\n');
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true }));
  });
});

server.listen(port, '127.0.0.1', () => {
  const addr = server.address();
  console.log(`LISTENING ${addr.port}`);
});
