(function () {
    "use strict";

    const API_PRODUCTS = "/api/products";
    const API_THEMES = "/api/products/meta/pod-themes";

    /** API enum token → display label (dropdown and table). */
    const POD_THEME_LABELS = {
        ENCHANTED_FOREST: "Enchanted Forest",
        INTERSTELLAR_SPACESHIP: "Interstellar Spaceship",
        SPEAKEASY_1920S: "1920s Speakeasy",
        ZEN_GARDEN: "Serene Zen Garden",
        CUSTOM: "Custom",
    };

    const POD_THEME_ORDER = [
        "ENCHANTED_FOREST",
        "INTERSTELLAR_SPACESHIP",
        "SPEAKEASY_1920S",
        "ZEN_GARDEN",
        "CUSTOM",
    ];

    function themeLabel(token) {
        if (token == null || token === "") {
            return "";
        }
        return POD_THEME_LABELS[token] || token;
    }

    const els = {
        form: document.getElementById("filters"),
        themeMode: document.getElementById("themeMode"),
        themeSelect: document.getElementById("themeSelect"),
        excludeUniversal: document.getElementById("excludeUniversal"),
        excludeUniversalRow: document.getElementById("excludeUniversalRow"),
        name: document.getElementById("name"),
        category: document.getElementById("category"),
        manufacturer: document.getElementById("manufacturer"),
        status: document.getElementById("status"),
        tbody: document.getElementById("tbody"),
        resetBtn: document.getElementById("resetBtn"),
    };

    function setStatus(message, isError) {
        els.status.textContent = message;
        els.status.classList.toggle("error", Boolean(isError));
    }

    function syncThemeControls() {
        const mode = els.themeMode.value;
        const applicable = mode === "applicable";
        els.excludeUniversalRow.hidden = !applicable;
        if (!applicable) {
            els.excludeUniversal.checked = false;
        }
    }

    function appendQueryParams(params) {
        const name = els.name.value.trim();
        const category = els.category.value.trim();
        const manufacturer = els.manufacturer.value.trim();
        if (name) {
            params.set("name", name);
        }
        if (category) {
            params.set("category", category);
        }
        if (manufacturer) {
            params.set("manufacturer", manufacturer);
        }
    }

    function isUniversal(product) {
        const themes = product.podThemes;
        return !themes || themes.length === 0;
    }

    function applyClientFilters(products, mode, selectedTheme, excludeUniversal) {
        let out = products;
        if (mode === "universal") {
            out = out.filter(isUniversal);
        }
        if (mode === "applicable" && excludeUniversal && selectedTheme) {
            out = out.filter(
                (p) =>
                    Array.isArray(p.podThemes) &&
                    p.podThemes.includes(selectedTheme)
            );
        }
        return out;
    }

    function formatPrice(value) {
        if (value == null) {
            return "—";
        }
        const n = Number(value);
        if (Number.isNaN(n)) {
            return String(value);
        }
        return n.toLocaleString(undefined, {
            style: "currency",
            currency: "USD",
            minimumFractionDigits: 2,
            maximumFractionDigits: 2,
        });
    }

    function renderThemes(product) {
        const cell = document.createElement("td");
        const wrap = document.createElement("div");
        wrap.className = "themes-cell";

        if (isUniversal(product)) {
            const span = document.createElement("span");
            span.className = "badge universal";
            span.textContent = "Universal";
            wrap.appendChild(span);
        } else {
            for (const t of product.podThemes) {
                const span = document.createElement("span");
                span.className = "badge";
                span.textContent = themeLabel(t);
                span.title = t;
                wrap.appendChild(span);
            }
        }
        cell.appendChild(wrap);
        return cell;
    }

    function renderRows(products) {
        els.tbody.replaceChildren();
        if (products.length === 0) {
            const tr = document.createElement("tr");
            tr.className = "empty-row";
            const td = document.createElement("td");
            td.colSpan = 6;
            td.textContent = "No products match the current filters.";
            tr.appendChild(td);
            els.tbody.appendChild(tr);
            return;
        }

        for (const p of products) {
            const tr = document.createElement("tr");
            const sku = document.createElement("td");
            sku.textContent = p.sku ?? "";
            const name = document.createElement("td");
            name.textContent = p.name ?? "";
            const category = document.createElement("td");
            category.textContent = p.category ?? "";
            const price = document.createElement("td");
            price.className = "num";
            price.textContent = formatPrice(p.price);
            const active = document.createElement("td");
            active.textContent =
                p.isActive === true ? "Yes" : p.isActive === false ? "No" : "—";

            tr.appendChild(sku);
            tr.appendChild(name);
            tr.appendChild(category);
            tr.appendChild(price);
            tr.appendChild(active);
            tr.appendChild(renderThemes(p));
            els.tbody.appendChild(tr);
        }
    }

    async function loadThemes() {
        const res = await fetch(API_THEMES);
        if (!res.ok) {
            throw new Error("Themes request failed: " + res.status);
        }
        const names = await res.json();
        if (!Array.isArray(names)) {
            throw new Error("Unexpected themes response");
        }
        const fromApi = new Set(names);
        const sel = els.themeSelect;
        const keep = sel.querySelector('option[value=""]');
        sel.replaceChildren(keep);
        for (const token of POD_THEME_ORDER) {
            if (!fromApi.has(token)) {
                continue;
            }
            const opt = document.createElement("option");
            opt.value = token;
            opt.textContent = POD_THEME_LABELS[token] || token;
            sel.appendChild(opt);
        }
        for (const n of names) {
            if (POD_THEME_ORDER.includes(n)) {
                continue;
            }
            const opt = document.createElement("option");
            opt.value = n;
            opt.textContent = POD_THEME_LABELS[n] || n;
            sel.appendChild(opt);
        }
    }

    async function runSearch(ev) {
        if (ev) {
            ev.preventDefault();
        }

        const mode = els.themeMode.value;
        const selectedTheme = els.themeSelect.value;
        const excludeUniversal = els.excludeUniversal.checked;

        if (mode === "applicable" && !selectedTheme) {
            setStatus("Choose a pod theme for “Applicable to selected theme”.", true);
            els.tbody.replaceChildren();
            return;
        }

        setStatus("Loading…", false);

        const params = new URLSearchParams();
        appendQueryParams(params);

        if (mode === "applicable") {
            params.set("theme", selectedTheme);
        }

        const url =
            API_PRODUCTS + (params.toString() ? "?" + params.toString() : "");

        let products;
        try {
            const res = await fetch(url);
            if (!res.ok) {
                const text = await res.text();
                throw new Error(
                    res.status + (text ? ": " + text.slice(0, 200) : "")
                );
            }
            products = await res.json();
            if (!Array.isArray(products)) {
                throw new Error("Unexpected products response");
            }
        } catch (e) {
            setStatus("Failed to load products: " + e.message, true);
            els.tbody.replaceChildren();
            return;
        }

        products = applyClientFilters(
            products,
            mode,
            selectedTheme,
            excludeUniversal
        );

        const baseMsg =
            products.length === 1
                ? "1 product"
                : products.length + " products";

        if (mode === "universal") {
            setStatus(baseMsg + " (universal only — no explicit theme tags).", false);
        } else if (mode === "applicable" && excludeUniversal) {
            setStatus(
                baseMsg +
                    " (explicitly tagged with " +
                    themeLabel(selectedTheme) +
                    " only).",
                false
            );
        } else if (mode === "applicable") {
            setStatus(
                baseMsg +
                    " (applicable to " +
                    themeLabel(selectedTheme) +
                    ", including universal SKUs).",
                false
            );
        } else {
            setStatus(baseMsg + ".", false);
        }

        renderRows(products);
    }

    function resetForm() {
        els.form.reset();
        els.themeMode.value = "all";
        syncThemeControls();
        setStatus("", false);
        els.tbody.replaceChildren();
    }

    els.themeMode.addEventListener("change", syncThemeControls);
    els.themeSelect.addEventListener("change", function () {
        if (els.themeSelect.value && els.themeMode.value !== "applicable") {
            els.themeMode.value = "applicable";
            syncThemeControls();
        }
    });
    els.form.addEventListener("submit", runSearch);
    els.resetBtn.addEventListener("click", resetForm);

    loadThemes()
        .then(() => {
            syncThemeControls();
            return runSearch();
        })
        .catch((e) => {
            setStatus("Could not load theme list: " + e.message, true);
        });
})();
