# Couch Potato shell

Static night-city home for Forever Couch Gang. The page is HTML and CSS written by Vire. It is not a React app.

From `D:\_scratch\vire`:

```text
dotnet run -c Release -- sites/cpa/app.vire
```

Vire sandboxes that program to `sites/cpa` and only writes files under `site/` or `data/`. A path such as `sites/cpa/index.html` is outside that sandbox (`..` is refused too). The run says so, then writes:

- `sites/cpa/site/index.html`
- `sites/cpa/site/app.css`

Open `sites/cpa/site/index.html` in a browser. The stylesheet is `app.css` next to it.
