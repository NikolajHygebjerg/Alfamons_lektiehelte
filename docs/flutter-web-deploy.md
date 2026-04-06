# Guide: Læg Alfamon (Flutter Web) på din hjemmeside

Denne guide forudsætter, at backend allerede er Supabase (som i projektet), og at du har et domæne med HTTPS.

## 1. Byg web-versionen (forælder-admin, slank)

Standard **`flutter build web`** bruger **`pubspec.yaml`**, som lister **`assets/`** og **`alfamon_trace`**. Flutter pakker **alle** de filer ind i **`build/web/assets/`** (ofte ~300–400 MB), selv om **web kun kører admin** — det er forventet opførsel.

**Anbefalet:** byg den lette admin-uden-spil-assets-version:

```bash
cd alfamon_flutter
./tool/build_web_admin.sh
```

(vælger midlertidigt **`pubspec_web.yaml`**: ingen rod-`assets/`, ingen `alfamon_trace`-pakke → langt mindre `build/web/assets/`.)

Ved manuel build med fuld app (fx til test):

```bash
flutter pub get
flutter build web --release
```

Resultatet ligger i **`build/web/`**. Det er **statiske filer** (HTML, JS, CSS, evt. assets) – upload **hele** mappens indhold.

**Vedligeholdelse:** når du tilføjer nye **`dependencies`** i **`pubspec.yaml`**, skal typisk **`pubspec_web.yaml`** opdateres tilsvarende (kopier blokken og fjern stadig `alfamon_trace` og `assets`).

### App i en undermappe (fx `www.eksempel.dk/alfamon/`)

Brug så den **rigtige base-href** ved build:

```bash
flutter build web --release --base-href /alfamon/
```

(Tallet/mappen skal matche præcis den URL-sti, brugerne åbner appen på.)

## Hvid skærm efter upload — typiske årsager

1. **Forkert mappe** — Du har uploadet projektets `web/`-mappe (kilde med kun `index.html` + ikoner). Den indeholder **ikke** den kompilerede app (`main.dart.js`, `flutter.js`, `assets/`, `canvaskit/` m.m.).  
   **Løsning:** Kør `flutter build web --release` og upload **alt indhold af `build/web/`**.

2. **404 på scripts** — Åbn **Udviklerværktøj (F12) → Network** og genindlæs. Hvis `main.dart.js` eller `flutter_bootstrap.js` er røde (404), er filerne ikke uploadet eller **`base href`** passer ikke til din URL (fx app i undermappe uden `--base-href /undermappe/`).

3. **Ingen SPA-fallback** — Direkte adgang til `/admin` eller refresh kan give tom side hvis serveren ikke sender `index.html` for ukendte stier. Se afsnit 2 nedenfor.

## 2. Hvad serveren skal kunne (SPA)

Flutter Web er en **single-page app**: alle ruter (fx `/admin`, `/kid/...`) skal stadig servere **`index.html`**, ellers får du 404 ved direkte link eller refresh.

Konfigurer din webserver med **fallback til `index.html`** for ukendte stier (undtagen eksisterende filer som `main.dart.js`, `assets/`, osv.).

Eksempler:

- **nginx** (kort princip): `try_files $uri $uri/ /index.html;` for location der peger på `build/web`.
- **Apache**: typisk `FallbackResource /index.html` i den mappe der serverer web-buildet.
- **Netlify / Vercel / Cloudflare Pages**: brug deres “SPA” / “rewrite all to index.html”-indstilling.

Uden dette virker dybe links og opdatering af siden ofte ikke.

## 3. Læg filerne op

Vælg én model:

**A) Egen server (VPS, shared hosting m. statisk fil-support)**  
Upload indholdet af `build/web/` til dokumentroden eller en undermappe. Sørg for HTTPS (Let’s Encrypt eller hostens certifikat).

**B) Statisk hosting**  
Services som Netlify, Vercel, Cloudflare Pages, GitHub Pages: peg “publish directory” på `build/web` (eller det CI bygger), og aktiver SPA-fallback som ovenfor.

**C) CI**  
Du kan lade GitHub Actions (eller lign.) køre `flutter build web --release` og deploye `build/web` automatisk ved push til `main`.

## 4. Supabase (vigtigt når appen har ny URL)

Når appen har en **fast https-URL**, opdater i **Supabase Dashboard → Authentication → URL Configuration**:

1. **Site URL** – typisk din primære app-URL, fx `https://www.ditdomæne.dk` eller `https://www.ditdomæne.dk/alfamon/` (hvis du bruger undermappe + base-href).
2. **Redirect URLs** – tilføj præcis den origin, appen kører fra, fx:
   - `https://www.ditdomæne.dk`
   - `https://www.ditdomæne.dk/alfamon` (hvis relevant)
   - Behold også **`alfamon://login-callback`** hvis I stadig bruger native app til email-bekræftelse.

I koden bruger web allerede **`Uri.base.origin`** til email-redirect (se `SupabaseConfig.authEmailRedirectTo`). Den skal derfor matche den URL, brugerne åbner i browseren.

## 5. Kort tjekliste før go-live

- [ ] `flutter build web --release` (evt. med `--base-href` hvis undermappe).
- [ ] HTTPS er aktivt på domænet.
- [ ] SPA-fallback til `index.html` er sat op.
- [ ] Supabase **Site URL** og **Redirect URLs** indeholder den nye web-URL.
- [ ] Test: log ind, refresh på `/admin`, dybe links fra bogmærker.

## 6. Begrænsninger på web vs. mobil

Ikke alle mobil-plugins opfører sig ens på web (kamera, notification, vis hardware). Test de vigtigste flows i Chrome/Safari på desktop og mobil.

---

Ved behov kan du supplere med konkret nginx/Apache-snit af din egen serverkonfiguration; strukturen er altid: **servér `build/web` + fallback til `index.html` + HTTPS + Supabase URL’er opdateret**.
