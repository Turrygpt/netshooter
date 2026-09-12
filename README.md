# Netshooter

Five-floor LAN shooter prototype. Each floor contains an identical 3 × 3 grid of 8 m rooms (45 rooms total). The center connects to side rooms, sides connect to corners, and a gentle ramp in the north room goes to the next floor.

## Run the LAN lobby

1. Install dependencies: `cd web; npm install`
2. Start the host: `npm start`
3. On the host and other machines on the same network, open `http://HOST_LAN_IP:8080`.

The host may need to allow Node.js through the Windows private-network firewall prompt. Use WASD to move, mouse to look, and left-click to fire. Position, facing direction, player join/leave events, and visible shots are synchronized. There are intentionally no hit points, hit detection, or damage.

## Blender source

Run `& 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' --background --python tools/build_house.py` to regenerate the authoring scene and GLB. The resulting source is `art/netshooter_house.blend`; the runtime level asset is `web/public/netshooter_house.glb`.
