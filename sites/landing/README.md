# Forever Couch Gang landing

Static port of the public home. Generate it from the repo root:

```text
dotnet run -c Release -- sites/landing/site.vire
```

`listen` serves `{program folder}/site` for GET and HEAD of an allowlisted extension. It does not list directories, follow links, or return `.vire` source. There is no key in the URL. The program folder is the directory of the `.vire` file you pass.

This file lives in `sites/landing`, and `write` may only create files under `data/` or `site/` there (`..` is refused). A run therefore writes:

- `sites/landing/site/index.html`
- `sites/landing/site/site.css`

`index.html` links `site.css` in that same folder. Repo-root `dotnet run -c Release -- serve.vire` serves `site/` at the repo root, which is a different folder from `sites/landing/site`. Do not start the listener from this page.
