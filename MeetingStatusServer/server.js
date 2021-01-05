const yargs = require("yargs");

const options = yargs
 .options({"p": { alias: "port", describe: "Port to run the server on", type: "number", default: 8080 }})
 .argv;

const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: options.port });

wss.on('connection', function connection(ws) {
  console.log("Connection Opened");
  ws.on('message', function incoming(data) {
    console.log("Message Received", data);
    wss.clients.forEach(function each(client) {
      if (client !== ws && client.readyState === WebSocket.OPEN) {
        client.send(data);
      }
    });
  });
});