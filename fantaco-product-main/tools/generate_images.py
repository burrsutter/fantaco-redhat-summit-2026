#!/usr/bin/env python3
"""Generate product catalog images via OpenAI image generation API.

Fetches product data from the FantaCo Spring Boot service and generates
catalog-quality images using OpenAI's gpt-image-1 (or dall-e-3) model.

Usage:
    python generate_images.py --sku KB-MECH-001
    python generate_images.py --theme enchanted_forest
    python generate_images.py --all
    python generate_images.py --sku KB-MECH-001 --dry-run
"""

import argparse
import base64
import os
import sys
from pathlib import Path

import requests
from openai import OpenAI

VALID_THEMES = [
    "ENCHANTED_FOREST",
    "INTERSTELLAR_SPACESHIP",
    "SPEAKEASY_1920S",
    "ZEN_GARDEN",
]

THEME_STYLES = {
    "ENCHANTED_FOREST": (
        "Color palette hints: mossy greens, warm wood tones, soft golden fairy-light accents"
    ),
    "INTERSTELLAR_SPACESHIP": (
        "Color palette hints: brushed metallic silver, cool blue accent lighting, dark charcoal"
    ),
    "SPEAKEASY_1920S": (
        "Color palette hints: Art Deco gold and brass, warm amber tones, geometric accent details"
    ),
    "ZEN_GARDEN": (
        "Color palette hints: natural bamboo, soft stone grey, muted sand, gentle warm light"
    ),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate product catalog images via OpenAI image generation API."
    )

    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--sku", help="Generate image for a single product SKU")
    target.add_argument(
        "--theme",
        help="Generate images for all products in a theme "
        "(enchanted_forest, interstellar_spaceship, speakeasy_1920s, zen_garden)",
    )
    target.add_argument(
        "--all", action="store_true", help="Generate images for the entire catalog"
    )

    parser.add_argument(
        "--api-url",
        default="http://localhost:8083",
        help="Product API base URL (default: http://localhost:8083)",
    )
    parser.add_argument(
        "--output-dir",
        default=str(Path(__file__).resolve().parent.parent / "generated-images"),
        help="Image output directory (default: ../generated-images)",
    )
    parser.add_argument(
        "--model",
        default="gpt-image-1",
        choices=["gpt-image-1", "dall-e-3"],
        help="OpenAI model (default: gpt-image-1)",
    )
    parser.add_argument(
        "--size",
        default="1024x1024",
        help="Image size (default: 1024x1024)",
    )
    parser.add_argument(
        "--quality",
        default="high",
        help="Image quality (default: high)",
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip generation if image already exists for SKU",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show prompts without calling the OpenAI API",
    )

    return parser.parse_args()


def fetch_product_by_sku(api_url: str, sku: str) -> dict:
    """Fetch a single product by SKU from the product API."""
    url = f"{api_url}/api/products/{sku}"
    try:
        resp = requests.get(url, timeout=10)
    except requests.ConnectionError:
        print(
            f"Error: Cannot connect to {api_url}. "
            "Is the Spring Boot service running?",
            file=sys.stderr,
        )
        sys.exit(1)

    if resp.status_code == 404:
        print(f"Error: SKU '{sku}' not found.", file=sys.stderr)
        sys.exit(1)

    resp.raise_for_status()
    return resp.json()


def fetch_products_by_theme(api_url: str, theme: str) -> list[dict]:
    """Fetch all products for a given theme from the product API."""
    theme_upper = theme.upper()
    if theme_upper not in VALID_THEMES:
        print(
            f"Error: Invalid theme '{theme}'. Valid themes: "
            + ", ".join(t.lower() for t in VALID_THEMES),
            file=sys.stderr,
        )
        sys.exit(1)

    url = f"{api_url}/api/products"
    try:
        resp = requests.get(url, params={"theme": theme_upper}, timeout=10)
    except requests.ConnectionError:
        print(
            f"Error: Cannot connect to {api_url}. "
            "Is the Spring Boot service running?",
            file=sys.stderr,
        )
        sys.exit(1)

    resp.raise_for_status()
    return resp.json()


def fetch_all_products(api_url: str) -> list[dict]:
    """Fetch all products from the product API."""
    url = f"{api_url}/api/products"
    try:
        resp = requests.get(url, timeout=10)
    except requests.ConnectionError:
        print(
            f"Error: Cannot connect to {api_url}. "
            "Is the Spring Boot service running?",
            file=sys.stderr,
        )
        sys.exit(1)

    resp.raise_for_status()
    return resp.json()


def build_prompt(product: dict) -> str:
    """Build an image generation prompt from product data.

    Uses the first sentence of the description (factual specs) and adds
    theme-specific environment styling when the product has themes.
    """
    description = product.get("description", "")
    # Extract first sentence only — skip the FantaCo humor
    first_sentence = description.split(". ")[0].rstrip(".")
    name = product.get("name", "")

    parts = [
        "Professional product catalog photograph.",
        f'Product: "{name}".',
        f"Description: {first_sentence}.",
    ]

    # Add subtle theme color hints (not environmental scenes)
    themes = product.get("podThemes", [])
    if themes:
        primary_theme = themes[0]
        style = THEME_STYLES.get(primary_theme)
        if style:
            parts.append(f"{style}.")

    parts.append(
        "Product-only shot on a clean white background. "
        "Soft studio lighting, centered composition, slight drop shadow. "
        "No environment, no scenery, no people, no text or labels."
    )

    return " ".join(parts)


def generate_image(
    client: OpenAI, prompt: str, model: str, size: str, quality: str
) -> bytes | None:
    """Call OpenAI image generation API and return image bytes."""
    try:
        if model == "gpt-image-1":
            result = client.images.generate(
                model=model,
                prompt=prompt,
                size=size,
                quality=quality,
                n=1,
            )
            b64_data = result.data[0].b64_json
            return base64.b64decode(b64_data)
        else:
            # dall-e-3 returns a URL
            result = client.images.generate(
                model=model,
                prompt=prompt,
                size=size,
                quality=quality if quality in ("standard", "hd") else "standard",
                n=1,
            )
            image_url = result.data[0].url
            resp = requests.get(image_url, timeout=60)
            resp.raise_for_status()
            return resp.content
    except Exception as e:
        error_msg = str(e)
        if "rate_limit" in error_msg.lower() or "429" in error_msg:
            print(f"  Rate limited: {error_msg}")
        elif "content_policy" in error_msg.lower() or "safety" in error_msg.lower():
            print(f"  Content rejected: {error_msg}")
        else:
            print(f"  API error: {error_msg}")
        return None


def process_products(
    products: list[dict], args: argparse.Namespace, client: OpenAI | None
) -> None:
    """Process a list of products: build prompts and generate images."""
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    generated = 0
    skipped = 0
    failed = 0

    for product in products:
        sku = product["sku"]
        name = product["name"]
        image_path = output_dir / f"{sku}.png"

        if args.skip_existing and image_path.exists():
            print(f"[SKIP] {sku} — {name} (image exists)")
            skipped += 1
            continue

        prompt = build_prompt(product)

        if args.dry_run:
            print(f"[DRY RUN] {sku} — {name}")
            print(f"  Prompt: {prompt}")
            print()
            generated += 1
            continue

        print(f"[GENERATING] {sku} — {name}")
        image_bytes = generate_image(client, prompt, args.model, args.size, args.quality)

        if image_bytes:
            image_path.write_bytes(image_bytes)
            size_kb = len(image_bytes) / 1024
            print(f"  Saved: {image_path} ({size_kb:.0f} KB)")
            generated += 1
        else:
            print(f"  FAILED: {sku}")
            failed += 1

    # Summary
    print()
    print("--- Summary ---")
    label = "would generate" if args.dry_run else "generated"
    print(f"  {label.capitalize()}: {generated}")
    if skipped:
        print(f"  Skipped: {skipped}")
    if failed:
        print(f"  Failed: {failed}")
    print(f"  Total: {generated + skipped + failed}")


def main() -> None:
    args = parse_args()

    # Check for API key unless dry run
    if not args.dry_run:
        api_key = os.environ.get("OPENAI_API_KEY")
        if not api_key:
            print(
                "Error: OPENAI_API_KEY environment variable is not set.\n"
                "  export OPENAI_API_KEY=sk-...",
                file=sys.stderr,
            )
            sys.exit(1)
        client = OpenAI(api_key=api_key)
    else:
        client = None

    # Fetch products
    if args.sku:
        product = fetch_product_by_sku(args.api_url, args.sku)
        products = [product]
    elif args.theme:
        products = fetch_products_by_theme(args.api_url, args.theme)
    else:
        products = fetch_all_products(args.api_url)

    if not products:
        print("No products found.")
        sys.exit(0)

    print(f"Found {len(products)} product(s).")
    print(f"Model: {args.model} | Size: {args.size} | Quality: {args.quality}")
    print(f"Output: {args.output_dir}")
    print()

    process_products(products, args, client)


if __name__ == "__main__":
    main()
