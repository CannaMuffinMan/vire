# CouchStation Windows PE (one session)

This Linux VM cannot execute Windows PE. Run the proofs on CouchStation (Canna's Windows PC) only.

Do **not** change Windows Defender. Do **not** reboot. Unset `VIRE_BUDGET` first (do not export `5000000`; that makes `BudgetCapTests.RenamedLoopDoesNotGetCompilerBudget` fail). Never print `FCG_API_TOKEN`.

```powershell
cd <vire-checkout>
git checkout cursor/integration-proof-d4c7
git rev-parse HEAD
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
dotnet build vire.csproj -c Release --nologo
powershell -NoProfile -File tools/couchstation-windows-all.ps1
```

The driver writes `data/couchstation-windows-all.log` with the tip SHA on every proof (`BEGIN`/`PASS`/`FAIL`). It calls the per-PR scripts (`native-net-windows.ps1`, `rebuild-fcgcpa-windows.ps1`, `rebuild-fcgbds-worker-windows.ps1`, json/crypto/pg/pg-tls, fuzz, selfhost gen1=gen2 ×3) plus the #90 PE json-map / parse-array guests.

`tools/rebuild-proxy-windows.ps1` is still a checklist (`exit 1`). The all-script compiles the proxy guest to PE and checks MZ + `ws2_32`; full host-vs-PE proxy modes still need a loopback upstream on that PC.

Until that log exists from CouchStation, **Windows PE is unproven**.
