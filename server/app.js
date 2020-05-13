const http = require('http');
const fs = require('fs');

const http_server = http.createServer((req, res) => {
  if (req.method === 'POST') {
    const stream = fs.createWriteStream('/tmp/data.json', {flags: 'a'});
    req.on('data', chunk => {
      stream.write(chunk);
    });
    req.on('end', () => {
      stream.write('\n');
      stream.end();
      res.end('ok');
    });
  }
});

http_server.listen(8081);
