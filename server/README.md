# Zone Royale — Multiplayer Server

Authoritative WebSocket arena for Zone Royale. Dart, no framework. Runs the
match simulation (movement, bullets, hits, kills) at 20 Hz and broadcasts
snapshots to every connected client. Supports **custom rooms**: clients that
send the same room code share a match; an empty code lands in `PUBLIC`.

## Protocol (JSON over WebSocket)

Client → server:
- `{"type":"join","name":"Ava","room":"NIGHT"}`  — first message; binds you to a room
- `{"type":"input","mx":0.4,"my":-1,"aim":1.57,"fire":true}` — sent ~30 Hz

Server → client:
- `{"type":"welcome","id":7,"world":3200}`
- `{"type":"state","players":[{id,x,y,aim,hp,alive,kills,name}],"bullets":[{x,y}]}`

## Run locally (free LAN play)

```bash
cd server
dart pub get
dart run bin/server.dart
```

It prints the port (default 8080). Find your PC's LAN IP (`ipconfig` on
Windows) and, from the phone on the **same Wi‑Fi**, connect the app to
`ws://<PC-IP>:8080`. Allow Dart through the Windows firewall if prompted.

Set a custom port with the `PORT` env var: `PORT=9000 dart run bin/server.dart`.

## Deploy to the internet — Render.com (free)

The repo ships a `Dockerfile` (here) and a `render.yaml` (repo root). Push to
GitHub, then on Render: **New + → Blueprint → pick the repo**. Render builds the
image and gives you a public URL. In the app enter `wss://<your-app>.onrender.com`.

The free instance sleeps after ~15 min idle (first connect after sleep takes a
few seconds to wake).
