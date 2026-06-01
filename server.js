const http = require("node:http");

const port = process.env.PORT || 3000;

const server = http.createServer((_, res) => {
  res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
  res.end("github-hidden-checks-repro\n");
});

server.listen(port, () => {
  console.log(`listening on ${port}`);
});
