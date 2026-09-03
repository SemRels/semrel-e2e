#!/usr/bin/env node
// Minimal local SMTP catcher used by the hook-email scenario -- implements
// just enough of RFC 5321 (EHLO/HELO, MAIL FROM, RCPT TO, DATA, QUIT) to
// accept one plaintext delivery, no STARTTLS/AUTH. Scenarios that use this
// must configure the plugin with SEMREL_PLUGIN_TLS=false. Never talks to
// any real mail server.
//
// Usage: node server.js <port> <messagesLogPath>
// Prints "LISTENING <port>" to stdout once bound.

const net = require('net');
const fs = require('fs');

const port = Number(process.argv[2] || 0);
const logPath = process.argv[3] || './messages.ndjson';

const server = net.createServer((socket) => {
  let buffer = '';
  let mode = 'command'; // 'command' | 'data'
  let session = { from: null, to: [], dataLines: [] };

  socket.write('220 semrel-e2e mock SMTP ready\r\n');

  socket.on('data', (chunk) => {
    buffer += chunk.toString('utf8');
    let idx;
    while ((idx = buffer.indexOf('\r\n')) !== -1) {
      const line = buffer.slice(0, idx);
      buffer = buffer.slice(idx + 2);

      if (mode === 'data') {
        if (line === '.') {
          fs.appendFileSync(
            logPath,
            JSON.stringify({
              time: new Date().toISOString(),
              from: session.from,
              to: session.to,
              body: session.dataLines.join('\n'),
            }) + '\n'
          );
          socket.write('250 OK: message queued\r\n');
          mode = 'command';
          session = { from: null, to: [], dataLines: [] };
        } else {
          session.dataLines.push(line);
        }
        continue;
      }

      const upper = line.toUpperCase();
      if (upper.startsWith('EHLO') || upper.startsWith('HELO')) {
        socket.write('250-semrel-e2e mock SMTP\r\n250 OK\r\n');
      } else if (upper.startsWith('MAIL FROM:')) {
        session.from = line.slice(10).trim();
        socket.write('250 OK\r\n');
      } else if (upper.startsWith('RCPT TO:')) {
        session.to.push(line.slice(8).trim());
        socket.write('250 OK\r\n');
      } else if (upper === 'DATA') {
        mode = 'data';
        socket.write('354 Start mail input; end with <CRLF>.<CRLF>\r\n');
      } else if (upper === 'QUIT') {
        socket.write('221 Bye\r\n');
        socket.end();
      } else if (upper === 'RSET') {
        session = { from: null, to: [], dataLines: [] };
        socket.write('250 OK\r\n');
      } else {
        socket.write('500 command not recognized (mock server)\r\n');
      }
    }
  });

  socket.on('error', () => {});
});

server.listen(port, '127.0.0.1', () => {
  const addr = server.address();
  console.log(`LISTENING ${addr.port}`);
});
