---
name: generate-images
description: Generate product catalog images using OpenAI image generation API
argument-hint: "[sku <SKU> | theme <THEME> | all] [--dry-run] [--skip-existing]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Generate Product Catalog Images

Generate catalog-quality product images via OpenAI's image generation API using the script at `fantaco-product-main/tools/generate_images.py`.

## Step 1: Ensure the Python virtual environment exists

Check if the venv already exists; if not, create it and install dependencies:

```bash
cd fantaco-product-main/tools
if [ ! -f .venv/bin/activate ]; then
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -r requirements.txt
else
  source .venv/bin/activate
fi
```

Report whether the venv was freshly created or already existed.

## Step 2: Determine the generation target

Parse `$ARGUMENTS` for the target mode:

- `sku <SKU>` — generate image for a single product SKU (e.g. `sku KB-MECH-001`)
- `theme <THEME>` — generate images for all products in a theme (e.g. `theme enchanted_forest`)
- `all` — generate images for the entire catalog
- `--dry-run` and `--skip-existing` may appear alongside any of the above

**If `$ARGUMENTS` is empty or does not match any of the above**, prompt the user:

Use `AskUserQuestion` to ask: "What would you like to generate images for?"

Options:
1. **Single product** — "Generate an image for one specific product SKU"
2. **Theme** — "Generate images for all products in a theme"
3. **All products** — "Generate images for the entire catalog (77 products)"

**If the user chose "Single product"**, ask them to type the SKU. Provide examples: `KB-MECH-001`, `IPOD-FIX-HDOOR`, `LAMP-RET-001`.

**If the user chose "Theme"**, use `AskUserQuestion` to ask which theme:
1. **Enchanted Forest** — "Mossy greens, fairy lights, natural wood"
2. **Interstellar Spaceship** — "Brushed metal, blue accent lighting, starfield"
3. **Speakeasy 1920s** — "Art Deco, brass fixtures, warm amber lighting"
4. **Zen Garden** — "Bamboo, smooth stones, raked sand, soft natural light"

Map the selection to: `enchanted_forest`, `interstellar_spaceship`, `speakeasy_1920s`, or `zen_garden`.

## Step 3: Check for `--dry-run`

If `--dry-run` was NOT specified in `$ARGUMENTS`, use `AskUserQuestion` to ask:

"Do you want a dry run first (shows prompts without calling OpenAI) or generate images for real?"

Options:
1. **Dry run** — "Preview the prompts that will be sent to OpenAI, no images generated"
2. **Generate for real** — "Call the OpenAI API and save images to generated-images/"

## Step 4: Obtain the OpenAI API key (skip if dry run)

If this is NOT a dry run, check whether the key is already set:

```bash
echo "${OPENAI_API_KEY:+SET}"
```

If the key is not set, use `AskUserQuestion` to ask:

"Please paste your OpenAI API key (starts with `sk-`). It will only be used for this session."

Then export it:

```bash
export OPENAI_API_KEY="<user-provided-key>"
```

## Step 5: Verify the product API is reachable

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8083/api/products
```

- If HTTP 200, proceed.
- If the service is not reachable, report: "The product API at http://localhost:8083 is not reachable. Is the Spring Boot service running?" and **stop**.

## Step 6: Run the script

Build the command from the selections made above:

```bash
cd fantaco-product-main/tools
source .venv/bin/activate
```

Then run one of:

```bash
# Single SKU
python generate_images.py --sku <SKU> [--dry-run] [--skip-existing]

# Theme
python generate_images.py --theme <theme> [--dry-run] [--skip-existing]

# All
python generate_images.py --all [--dry-run] [--skip-existing]
```

Add `--skip-existing` if it was in `$ARGUMENTS` or if the user is generating for real and images already exist.

Show the full command to the user before running it.

## Step 7: Report results

After the script completes:

1. Show the summary output from the script (generated / skipped / failed counts).
2. If images were generated (not dry run), list the files:

```bash
ls -lh fantaco-product-main/generated-images/*.png 2>/dev/null | head -20
```

3. If this was a dry run, ask if the user wants to proceed with real generation:
   - If yes, go back to Step 4 (to get the API key if needed) and re-run without `--dry-run`.
   - If no, done.
