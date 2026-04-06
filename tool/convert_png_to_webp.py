#!/usr/bin/env python3
"""
Batch-konverter PNG i assets/ til WebP og patch Dart-kilde med .webp-stier.

Kræver enten `cwebp` (anbefalet: brew install webp) eller Python-pakken Pillow.

Examples:
  python3 tool/convert_png_to_webp.py                    # lossy q=80, slet PNG
  python3 tool/convert_png_to_webp.py --lossless
  python3 tool/convert_png_to_webp.py --quality 75
  python3 tool/convert_png_to_webp.py --dry-run
  python3 tool/convert_png_to_webp.py --keep-png
  python3 tool/convert_png_to_webp.py --no-patch

Standard ekskluderer assets/nytikon.png (kilde til flutter_launcher_icons).
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path


def find_cwebp() -> str | None:
    return shutil.which("cwebp")


def convert_cwebp(
    src: Path,
    dst: Path,
    *,
    lossless: bool,
    quality: int,
) -> None:
    cmd = ["cwebp", "-quiet"]
    if lossless:
        cmd.append("-lossless")
    else:
        cmd.extend(["-q", str(quality)])
    cmd.extend([str(src), "-o", str(dst)])
    subprocess.run(cmd, check=True)


def convert_pillow(
    src: Path,
    dst: Path,
    *,
    lossless: bool,
    quality: int,
) -> None:
    from PIL import Image  # type: ignore

    img = Image.open(src)
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGBA")
    save_kw = {"format": "WEBP", "method": 6}
    if lossless:
        save_kw["lossless"] = True
    else:
        save_kw["quality"] = quality
    img.save(dst, **save_kw)


def collect_pngs(assets_dir: Path, exclude_names_lower: set[str]) -> list[Path]:
    """Én indgang pr. inode (undgå duplikater ved case-varianter / symlinks på APFS)."""
    seen: set[int] = set()
    out: list[Path] = []
    for p in sorted(assets_dir.rglob("*.png")):
        if p.name.lower() in exclude_names_lower:
            continue
        if p.name == ".DS_Store":
            continue
        try:
            st = p.stat()
        except FileNotFoundError:
            continue
        key = st.st_ino, st.st_dev
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


DART_REPLACE_RE = re.compile(r'(["\'])(assets/[^"\']+?)\.png\1')


def patch_angreb_assets(project_root: Path, *, dry_run: bool) -> bool:
    """Opdater lib/utils/angreb_assets.dart return-sætninger til .webp (skabelon med $base$stage)."""
    path = project_root / "lib/utils/angreb_assets.dart"
    if not path.is_file():
        return False
    text = path.read_text(encoding="utf-8")
    t2 = text.replace(
        "return 'assets/Deedooangreb4.png';",
        "return 'assets/Deedooangreb4.webp';",
    )
    t2 = t2.replace(
        "return 'assets/$base$stage.png';",
        "return 'assets/$base$stage.webp';",
    )
    if t2 == text:
        return False
    if not dry_run:
        path.write_text(t2, encoding="utf-8")
    return True


def patch_dart_sources(project_root: Path, dry_run: bool) -> list[Path]:
    """Erstat 'assets/foo.png' med 'assets/foo.webp' når .webp findes."""
    changed: list[Path] = []
    dirs = [project_root / "lib", project_root / "packages"]
    for base in dirs:
        if not base.is_dir():
            continue
        for dart in base.rglob("*.dart"):
            text = dart.read_text(encoding="utf-8")

            def sub(m: re.Match[str]) -> str:
                q, stem = m.group(1), m.group(2)
                rel = f"{stem}.webp"
                if (project_root / rel).is_file():
                    return f"{q}{rel}{q}"
                return m.group(0)

            new_text = DART_REPLACE_RE.sub(sub, text)
            if new_text != text:
                if not dry_run:
                    dart.write_text(new_text, encoding="utf-8")
                changed.append(dart)
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--assets-dir",
        type=Path,
        default=None,
        help="Mappe med PNG (standard: <repo>/assets)",
    )
    parser.add_argument("--lossless", action="store_true", help="Lossless WebP")
    parser.add_argument(
        "--quality",
        type=int,
        default=80,
        help="Loss JPEG-lignende kvalitet 0–100 (kun lossy, standard: 80)",
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--keep-png",
        action="store_true",
        help="Behold .png efter konvertering (fylder dobbelt indtil du sletter manuelt)",
    )
    parser.add_argument("--no-patch", action="store_true", help="Hop Dart-patch over")
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        help="Filnavn at springe over (kan gentages). Standard: nytikon.png",
    )
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent
    assets_dir = args.assets_dir or (project_root / "assets")
    if not assets_dir.is_dir():
        print(f"Mangler mappe: {assets_dir}", file=sys.stderr)
        return 1

    exclude = {"nytikon.png", *[e.lower() for e in args.exclude]}
    pngs = collect_pngs(assets_dir, exclude)
    if not pngs:
        print("Ingen PNG at konvertere (efter excludes).")
        return 0

    cwebp = find_cwebp()
    if not cwebp:
        try:
            import PIL  # noqa: F401
        except ImportError:
            print(
                "Installér libwebp (cwebp) eller Pillow:\n"
                "  brew install webp\n"
                "  pip install Pillow",
                file=sys.stderr,
            )
            return 1

    mode = "lossless" if args.lossless else f"lossy q={args.quality}"
    print(f"Konverterer {len(pngs)} PNG → WebP ({mode}) i {assets_dir}", flush=True)
    if args.dry_run:
        for p in pngs[:20]:
            print(f"  [dry-run] {p.relative_to(project_root)}", flush=True)
        if len(pngs) > 20:
            print(f"  ... og {len(pngs) - 20} flere", flush=True)
        print("[dry-run] stop før skrivning", flush=True)
        return 0

    for png in pngs:
        webp = png.with_suffix(".webp")
        if not png.is_file():
            if webp.is_file():
                print(
                    f"  allerede konverteret (spring over): {webp.relative_to(project_root)}",
                    flush=True,
                )
            else:
                print(f"  ADVARSEL: mangler {png.relative_to(project_root)}", flush=True)
            continue
        try:
            if cwebp:
                convert_cwebp(png, webp, lossless=args.lossless, quality=args.quality)
            else:
                convert_pillow(png, webp, lossless=args.lossless, quality=args.quality)
        except Exception as e:
            print(f"FEJL {png}: {e}", file=sys.stderr, flush=True)
            return 1
        rel = webp.relative_to(project_root)
        print(f"  OK {rel}", flush=True)
        if not args.keep_png:
            try:
                png.unlink(missing_ok=True)
            except TypeError:
                # Python < 3.8
                if png.is_file():
                    png.unlink()

    if not args.no_patch:
        patched = patch_dart_sources(project_root, dry_run=False)
        if patch_angreb_assets(project_root, dry_run=False):
            print("  lib/utils/angreb_assets.dart → .webp return paths", flush=True)
        if patched:
            print("Dart opdateret:", flush=True)
            for p in patched:
                print(f"  {p.relative_to(project_root)}", flush=True)
        else:
            print(
                "Ingen øvrige Dart-strenge med 'assets/...png' at erstatte (OK hvis kun skabeloner).",
                flush=True,
            )

    print("Færdig.", flush=True)
    if args.keep_png:
        print("Bemærk: --keep-png — fjern .png manuelt når du har verificeret WebP.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
