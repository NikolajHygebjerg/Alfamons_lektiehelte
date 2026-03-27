# Guide: Læg Alfamon (Flutter Web) på din hjemmeside

Denne guide forudsætter, at backend allerede er Supabase (som i projektet), og at du har et domæne med HTTPS.

## 1. Byg web-versionen

Fra projektroden:

```bash
cd alfamon_flutter
flutter pub get
flutter build web --release
```

Resultatet ligger i **`build/web/`**. Det er **statiske filer** (HTML, JS, CSS, assets) – du skal kun uploade/hoste den mappe (eller dens indhold).

### App i en undermappe (fx `www.eksempel.dk/alfamon/`)

Brug så den **rigtige base-href** ved build:

```bash
flutter build web --release --base-href /alfamon/
```

(Tallet/mappen skal matche præcis den URL-sti, brugerne åbner appen på.)

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
