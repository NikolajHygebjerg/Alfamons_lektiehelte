# Oplæsning i matematik-tutor

**Vigtigt:** I `pubspec.yaml` skal `assets/matematiktutor/` stå eksplicit under `flutter: assets:` (undermapper tælles ikke med i `assets/` alene). Efter nye/ændrede lydfiler: `flutter pub get`, stopp appen helt og kør en **ny build** — **ikke** hot reload.

**Hvis opdaterede mp3 stadig lyder som gamle filer**

1. **Tjek at du kører den rigtige mål-platform** (fra projektroden):  
   `flutter devices` — til **macOS-skrivebord** skal du bruge **`flutter run -d macos`**.  
   Kører du bare `flutter run`, kan Flutter vælge **Chrome**, **iOS-simulator** eller en **telefon** — så ser du en anden build end den du tror.

2. **Afslut appen helt** (Cmd+Q på macOS-appen, ikke kun luk vinduet). En kørende Debug-build kan låse eller forvirre, hvis du genstarter for hurtigt.

3. **Hård oprydning** (macOS-desktop), kør én blok i terminalen fra projektets rodmappe (`alfamon_flutter`):

```bash
killall alfamon_flutter 2>/dev/null || true
flutter clean
rm -rf build macos/Flutter/ephemeral
flutter pub get
flutter run -d macos
```

   (`macos/Flutter/ephemeral` genskabes ved næste build og fjerner nogle Xcode/Flutter-cacher.)

4. **Tjek at de nye filer faktisk er i bundtet** (efter en build):  
   `find build/macos -path '*flutter_assets*matematiktutor*' -name '*.mp3' | head`

5. På **telefon/simulator**: **afinstaller appen** og kør `flutter run` igen. På **iOS** desuden gerne **Product → Clean Build Folder** i Xcode.

Asset-listen kommer fra `pubspec.yaml` og kopieres ind i `.app` ved **fuld build**; **hot reload** (`r`) opdaterer **ikke** assets — brug **genstart af appen** (Stop + `flutter run`, eller `R` i terminalen hvor det understøttes).

## 1. Første skærm — filnavne fra sætningen

Funktionen `mathTutorAudioFilenameSlug()` i `lib/utils/math_tutor_lesson.dart` laver filnavn:

- Hele den talte sætning → **små bogstaver**, **æ→ae**, **ø→oe**, **å→aa**, tegn og komma fjernes, **ord adskilles med `_`**, endelse **`.mp3`** i `assets/matematiktutor/`.

Appen prøver **først** det genererede slug, derefter **gamle korte navne** (fx `1_1`, `11`, `m_14`, `Plus.mp3`).

### Faste intro-sætninger → forventede slugs

| Sætning (som i koden) | Slug (`.mp3`) |
|------------------------|----------------|
| Opgaven er | `opgaven_er` |
| Det første tal er | `det_foerste_tal_er` |
| Det andet tal er | `det_andet_tal_er` |
| Kan du selv … trykke videre. | `kan_du_selv_regne_ud_hvad_svaret_er_skal_du_skrive_det_i_feltet_herunder_hvis_ikke_kan_du_trykke_videre` (konstant `kIntroKanDuSelvAudioBasename`) |
| Svaret er (minus) | `svaret_er` |
| Plus / Minus (ét ord) | `plus` / `minus` (fallback: `Plus` / `Minus`) |

### Tal

`0`–`20`, `30`, `40`, … `90`, og **`100`** eller `1_100` for hundred.

Tal som **21** afspilles som **`en`** + pause + **`20`** (to filer), ikke `1.mp3`, med mindre `en.mp3` mangler.

Sammensatte tal **21–99** (fx **25** → fem + tyve): **`og.mp3`** indsættes i én **sammenhængende** afspilning (gapless concat), uden ekstra kunstig pause og uden at skifte afspiller mellem hvert klip — mindre «hak» end før. Mangler `og.mp3`, afspilles kun ener- og tier-delen uden ordet *og*.

### Møntbeskrivelse (per tal)

Teksten i koden (TTS-fallback) bruger **«på ti»** og **ordtal for tier** (to, tre, …, ni), så den matcher indtalen i klippene.

- **11–19 (foretrukket):** I intro: **`det_foerste_tal_er`** / **`det_andet_tal_er`** + heltal (`18.mp3`), derefter **`det_svarer_til_en_guldmoent_paa_ti_og`** → ener-ciffer (`8.mp3`) → **`guldmoenter_paa_en`** (fallback **`enere`**).  
  Ellers ældre opdeling: `det_svarer_til` → `en`/`1` → `guldmoent` … / slug / `m_*` / TTS.
- **10** (én guldmønt, ingen enere): `det_er_en_guldmoent_paa_ti` (matcher også slug af *Det er en guldmønt på ti.*).
- **20, 30, … 80** (kun tier): `det_svarer_til_to_guldmoenter_paa_ti`, `det_svarer_til_tre_guldmoenter_paa_ti`, … `det_svarer_til_otte_guldmoenter_paa_ti`.
- **21–89 med tier 2–8 og enere:** samme åbningsklip som ved «kun tier», derefter valgfri `guldmoenter_paa_en` når der er **én** en, så ener-ciffer og `enere`.
- **Øvrige** (fx tier 9): slug / `m_*.mp3` / TTS.

Appen forsøger også **`fil.mp3.mp3`** (dobbelt endelse) og **`…_og .mp3`** (mellemrum før punktum), hvis standardnavnet mangler — men **ret gerne filnavnene** til ét `.mp3` og uden mellemrum, så undgår du forvirring.

---

## 2. Guidet trin

Strengene afspilles som **lydfiler** når de findes i `assets/matematiktutor/` (slug eller alias nedenfor); ellers **TTS**.

| Sætning (som i appen) | Primær slug / fil | Ekstra alias prøves først |
|------------------------|-------------------|---------------------------|
| Hvor mange enere er der **ialt**, når du lægger …? | `hvor_mange_enere_er_der_ialt_naar_du_lae_gger_de_to_tal_sammen` | `hvor_mange_enere_er_der_i_alt_naar_du_lae_gger_de_to_tal_sammen` |
| Hvor mange tiere er der? | `hvor_mange_tiere_er_der` | `hvor_mange_tiere` |
| Nej det er ikke rigtigt, prøv igen. | `nej_det_er_ikke_rigtigt_proev_igen` | (samme som eksplicit alias) |

**Godt det giver altså [svar]:** `godt_det_giver_altsaa` + talsprog — eller ét klip for hele sætningen (slug af *Godt det giver altså 42.* osv.).

**Mente (ene-sum 10–18):**

| Sum | Kæde (efter hinanden) |
|-----|------------------------|
| **12–18** | `det_giver` → tal (12…18) → `vi_gemmer_de` → ener-ciffer → `enere` → `og_har_10_som_vi_lae_gger_til_tierne` |
| **10** | `det_giver` → `10` → `vi_har_10_som_vi_lae_gger_til_tierne` |
| **11** | `det_giver` → `11` → `vi_gemmer_en_en` → `og_har_10_som_vi_lae_gger_til_tierne` |

Mangler en del i kæden, prøves **ét klip** for hele åbningssætningen (slug), ellers TTS.

**Skriv-ciffer + ok:** `skriv` → ciffer → `og_tryk_ok` (eller slug af *og tryk ok.*); mangler `og_tryk_ok`, afspilles `skriv` + ciffer og evt. TTS til *og tryk ok.*

---

## 3. Ikke-oplæst UI

Kun skærmtekst — ikke lydfiler.
