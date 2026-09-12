const http = require('http');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');
const root = path.join(__dirname, 'public');
const players = new Map();
const server = http.createServer((req, res) => {
  const file = req.url === '/' ? 'index.html' : req.url.replace(/^\//, '');
  const target = path.normalize(path.join(root, file));
  if (!target.startsWith(root) || !fs.existsSync(target)) { res.writeHead(404); return res.end('Not found'); }
  res.writeHead(200, {'Content-Type': target.endsWith('.js') ? 'text/javascript' : target.endsWith('.html') ? 'text/html' : 'model/gltf-binary'});
  fs.createReadStream(target).pipe(res);
});
const wss = new WebSocket.Server({ server });
function send(ws, data) { if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(data)); }
function broadcast(data, except) { for (const peer of wss.clients) if (peer !== except) send(peer, data); }
wss.on('connection', ws => {
  const id = Math.random().toString(36).slice(2, 9);
  const player = { id, name: 'Player', x: 0, y: 0, z: 1.7, yaw: 0 };
  players.set(id, player); send(ws, { type:'welcome', id, players:[...players.values()] }); broadcast({type:'joined', player}, ws);
  ws.on('message', raw => { try {
    const msg=JSON.parse(raw); if(msg.type==='state') { Object.assign(player, {x:+msg.x||0,y:+msg.y||0,z:+msg.z||1.7,yaw:+msg.yaw||0,name:String(msg.name||'Player').slice(0,16)}); broadcast({type:'state', player},ws); }
    if(msg.type==='fire') broadcast({type:'fire', id, ...msg},ws); // deliberately no hitpoints or damage
  } catch {} });
  ws.on('close', () => { players.delete(id); broadcast({type:'left', id}); });
});
server.listen(8080, '0.0.0.0', () => console.log('Netshooter lobby: http://<LAN-IP>:8080'));
