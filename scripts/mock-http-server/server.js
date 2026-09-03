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
    // Two real plugins decode this response into a typed struct, and they
    // disagree on shape -- so route on the path instead of one-size-fits-all:
    // - provider-gitlab/gitea POST to a path containing "releases" and
    //   require both HTTP 201 (gitlab checks this exactly) and a numeric
    //   `id` (gitea's createReleaseResponse.id is int64).
    // - hook-jira GETs a Jira-style project payload where `id` must be a
    //   STRING (Jira's real API returns numeric-looking string ids).
    // Everything else in this suite (slack/teams/matrix, generic-http
    // publisher) only checks the status is in the 2xx range, so both
    // branches stay compatible with them.
    const isReleaseCall = req.url.includes('releases');
    const status = isReleaseCall ? 201 : 200;
    const responseBody = isReleaseCall
      ? { ok: true, id: 1, url: 'http://127.0.0.1/mock-release/1' }
      : { ok: true, id: '1', key: 'REL', name: 'mock', url: 'http://127.0.0.1/mock/1' };
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(responseBody));
  });
});

server.listen(port, '127.0.0.1', () => {
  const addr = server.address();
  console.log(`LISTENING ${addr.port}`);
});
