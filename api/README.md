# FCGCPA API

This is the only web2 service. Deploy this process on Railway. Do not deploy the landing site, Couch Potato, or the chain as their own services.

The downloaded apps are a web browser with the Forever Couch Gang skin. They open Twitch, YouTube, and the other sites through this front door (`GET /connect`). The app does the mining itself with Proof of Rot. This API does not mine and it does not run a mining network.

The chain address is `forevercouchgang.blockchain`. Each downloaded app is its own node. The app mines inside itself with Proof of Rot and then `POST /block` here. There is no mining network. `POST /mine` is refused. Payments stay off.

`GET /health` and `GET /info` describe that split. `GET /chain` returns blocks this API has accepted. `POST /block` accepts `{"text": ...}`; the server computes `index`, `previous`, and `proof`. Client-supplied `previous`/`proof` must match. Authorization for `POST /block` is out of scope for Phase 0.

Railway sets `PORT`. `listen` uses that port and binds all interfaces when `PORT` is set. On a laptop, with `PORT` unset, it binds `127.0.0.1:8080`.

```text
dotnet run -c Release -- api/fcgcpa.vire
```

If `FCG_API_TOKEN` is set, every path except `/health` requires header `X-FCG-Token`. The process never prints the token.

Do not use ports 7099 or 8778.
