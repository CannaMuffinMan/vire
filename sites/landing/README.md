# Forever Couch Gang landing

Static port of the public home. Generate it from the repo root:

```text
dotnet run -c Release -- sites/landing/site.vire
```

`serve` does not serve the program folder. `serve.vire` is `serve with 8080`. The runner serves `{program folder}/site` on `127.0.0.1` only, prints a key, and stays up until you stop it. The program folder is the directory of the `.vire` file you pass.

This file lives in `sites/landing`, and `write` may only create files under `data/` or `site/` there (`..` is refused). A run therefore writes:

- `sites/landing/site/index.html`
- `sites/landing/site/site.css`

`index.html` links `site.css` in that same folder. Repo-root `dotnet run -c Release -- serve.vire` serves `site/` at the repo root, which is a different folder. Do not start the listener from this page.
