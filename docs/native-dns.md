# Native DNS stub

Linux ELF and Windows PE share one packet codec (`src/rt-dns.vire`).

## Linux

- UDP A/AAAA query, max 512 bytes, 3s wait (`poll` then `recv`)
- Reads `/etc/resolv.conf` (`nameserver`) and `/etc/hosts` with `open(2)` (`O_RDONLY|O_NOFOLLOW|O_CLOEXEC`). Guest `CreateFileA` still rejects absolute paths.
- Fixture: `data/vire-dns` containing `127.0.0.1 PORT` (sandbox-relative). Tests bind a loopback UDP server to that port.
- Name compression: at most 16 pointer hops; every length and `rdlength` is checked against the received size before a read.

## Windows PE (CouchStation)

No new imports. Connected UDP uses the existing ws2 allowlist: `socket`, `bind`, `connect`, `send`, `recv`, `closesocket`, `setsockopt`, `GetTickCount`.

| Need | Plan |
| --- | --- |
| Packet codec | Same `dns_skip` / `dns_parse` / `dns_build` as ELF |
| Hosts | `CreateFileA` of `C:\Windows\System32\drivers\etc\hosts` (follow-up: parked path; this change uses `data/vire-dns` + `127.0.0.1:53`) |
| Nameservers | `GetAdaptersAddresses` (`iphlpapi`) would be a new DLL/IAT entry. Until that allowlist grows, PE uses `data/vire-dns` or `127.0.0.1:53` so the loopback fake DNS fixture works |
| Timeout | `setsockopt(SO_RCVTIMEO)` (already imported) |
| ID / port | `GetTickCount` xor `rdtsc`; `bind` port 0 |

Prove on CouchStation:

```powershell
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
dotnet build vire.csproj -c Release --nologo
powershell -NoProfile -File tools/native-dns-windows.ps1
```
