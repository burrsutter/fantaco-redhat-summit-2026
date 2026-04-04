(function () {
    "use strict";

    var API_CUSTOMERS = "/api/customers";

    var els = {
        form: document.getElementById("filters"),
        companyName: document.getElementById("companyName"),
        contactName: document.getElementById("contactName"),
        contactEmail: document.getElementById("contactEmail"),
        salesPersonName: document.getElementById("salesPersonName"),
        status: document.getElementById("status"),
        tbody: document.getElementById("tbody"),
        resetBtn: document.getElementById("resetBtn"),
    };

    /** Cache for detail responses keyed by customerId. */
    var detailCache = {};

    function setStatus(message, isError) {
        els.status.textContent = message;
        els.status.classList.toggle("error", Boolean(isError));
    }

    function esc(value) {
        if (value == null) return "";
        return String(value);
    }

    function formatDate(value) {
        if (!value) return "";
        var d = new Date(value);
        if (isNaN(d.getTime())) return String(value);
        return d.toLocaleDateString();
    }

    function formatCurrency(value) {
        if (value == null) return "";
        var n = Number(value);
        if (isNaN(n)) return String(value);
        return n.toLocaleString(undefined, {
            style: "currency",
            currency: "USD",
            minimumFractionDigits: 2,
            maximumFractionDigits: 2,
        });
    }

    // ── Detail rendering helpers ──────────────────────────────────

    function renderDetailSection(title, contentEl) {
        var section = document.createElement("div");
        section.className = "detail-section";
        var h = document.createElement("h3");
        h.textContent = title;
        section.appendChild(h);
        section.appendChild(contentEl);
        return section;
    }

    function renderContacts(contacts) {
        if (!contacts || contacts.length === 0) {
            var p = document.createElement("p");
            p.className = "detail-empty";
            p.textContent = "No contacts on file.";
            return renderDetailSection("Contacts", p);
        }
        var ul = document.createElement("ul");
        ul.className = "detail-list";
        for (var i = 0; i < contacts.length; i++) {
            var c = contacts[i];
            var li = document.createElement("li");
            var parts = [];
            if (c.firstName || c.lastName) parts.push(esc(c.firstName) + " " + esc(c.lastName));
            if (c.title) parts.push(c.title);
            if (c.email) parts.push(c.email);
            if (c.phone) parts.push(c.phone);
            li.textContent = parts.join(" \u2014 ");
            if (c.notes) {
                var note = document.createElement("span");
                note.className = "detail-note";
                note.textContent = " (" + c.notes + ")";
                li.appendChild(note);
            }
            ul.appendChild(li);
        }
        return renderDetailSection("Contacts", ul);
    }

    function renderSalesPersons(salesPersons) {
        if (!salesPersons || salesPersons.length === 0) {
            var p = document.createElement("p");
            p.className = "detail-empty";
            p.textContent = "No sales persons assigned.";
            return renderDetailSection("Sales Persons", p);
        }
        var ul = document.createElement("ul");
        ul.className = "detail-list";
        for (var i = 0; i < salesPersons.length; i++) {
            var sp = salesPersons[i];
            var parts = [];
            if (sp.firstName || sp.lastName) parts.push(esc(sp.firstName) + " " + esc(sp.lastName));
            if (sp.territory) parts.push("Territory: " + sp.territory);
            if (sp.email) parts.push(sp.email);
            if (sp.phone) parts.push(sp.phone);
            var li = document.createElement("li");
            li.textContent = parts.join(" \u2014 ");
            ul.appendChild(li);
        }
        return renderDetailSection("Sales Persons", ul);
    }

    function renderProjects(projects) {
        if (!projects || projects.length === 0) {
            var p = document.createElement("p");
            p.className = "detail-empty";
            p.textContent = "No projects.";
            return renderDetailSection("Projects", p);
        }
        var table = document.createElement("table");
        table.className = "detail-table";
        var thead = document.createElement("thead");
        var headRow = document.createElement("tr");
        var cols = ["Project", "Theme", "Status", "Budget", "Site"];
        for (var i = 0; i < cols.length; i++) {
            var th = document.createElement("th");
            th.textContent = cols[i];
            headRow.appendChild(th);
        }
        thead.appendChild(headRow);
        table.appendChild(thead);

        var tbody = document.createElement("tbody");
        for (var j = 0; j < projects.length; j++) {
            var proj = projects[j];
            var tr = document.createElement("tr");

            var tdName = document.createElement("td");
            tdName.textContent = esc(proj.projectName);
            if (proj.description) tdName.title = proj.description;

            var tdTheme = document.createElement("td");
            if (proj.podTheme) {
                var badge = document.createElement("span");
                badge.className = "badge";
                badge.textContent = proj.podTheme;
                tdTheme.appendChild(badge);
            }

            var tdStatus = document.createElement("td");
            if (proj.status) {
                var statusBadge = document.createElement("span");
                statusBadge.className = "badge status-" + proj.status.toLowerCase();
                statusBadge.textContent = proj.status;
                tdStatus.appendChild(statusBadge);
            }

            var tdBudget = document.createElement("td");
            tdBudget.className = "num";
            tdBudget.textContent = formatCurrency(proj.estimatedBudget);

            var tdSite = document.createElement("td");
            tdSite.textContent = esc(proj.siteAddress);

            tr.appendChild(tdName);
            tr.appendChild(tdTheme);
            tr.appendChild(tdStatus);
            tr.appendChild(tdBudget);
            tr.appendChild(tdSite);
            tbody.appendChild(tr);
        }
        table.appendChild(tbody);
        return renderDetailSection("Projects", table);
    }

    function renderNotes(notes) {
        if (!notes || notes.length === 0) {
            var p = document.createElement("p");
            p.className = "detail-empty";
            p.textContent = "No notes.";
            return renderDetailSection("Notes", p);
        }
        var ul = document.createElement("ul");
        ul.className = "detail-list";
        for (var i = 0; i < notes.length; i++) {
            var n = notes[i];
            var li = document.createElement("li");
            li.textContent = esc(n.noteText);
            if (n.createdAt) {
                var time = document.createElement("span");
                time.className = "detail-note";
                time.textContent = " \u2014 " + formatDate(n.createdAt);
                li.appendChild(time);
            }
            ul.appendChild(li);
        }
        return renderDetailSection("Notes", ul);
    }

    // ── Expand/collapse detail row ────────────────────────────────

    async function toggleDetail(tr, customer) {
        var next = tr.nextElementSibling;
        if (next && next.classList.contains("detail-row")) {
            next.remove();
            tr.classList.remove("expanded");
            return;
        }

        var detailTr = document.createElement("tr");
        detailTr.className = "detail-row";
        var td = document.createElement("td");
        td.colSpan = 6;

        var customerId = customer.customerId;

        if (detailCache[customerId]) {
            buildDetailContent(td, detailCache[customerId]);
        } else {
            td.textContent = "Loading\u2026";
            try {
                var res = await fetch(API_CUSTOMERS + "/" + encodeURIComponent(customerId) + "/detail");
                if (!res.ok) {
                    var errText = await res.text();
                    throw new Error(res.status + (errText ? ": " + errText.slice(0, 200) : ""));
                }
                var detail = await res.json();
                detailCache[customerId] = detail;
                td.textContent = "";
                buildDetailContent(td, detail);
            } catch (e) {
                td.textContent = "Failed to load detail: " + e.message;
                td.classList.add("detail-error");
            }
        }

        detailTr.appendChild(td);
        tr.after(detailTr);
        tr.classList.add("expanded");
    }

    function buildDetailContent(td, detail) {
        var wrap = document.createElement("div");
        wrap.className = "detail-content";

        // Customer overview
        var overview = document.createElement("div");
        overview.className = "detail-overview";
        var fields = [];
        if (detail.contactTitle) fields.push(["Title", detail.contactTitle, false]);
        if (detail.contactEmail) fields.push(["Email", detail.contactEmail, false]);
        if (detail.website) fields.push(["Website", detail.website, true]);
        if (detail.address) {
            var addr = [detail.address, detail.city, detail.region, detail.postalCode, detail.country]
                .filter(Boolean).join(", ");
            fields.push(["Address", addr]);
        }
        if (detail.fax) fields.push(["Fax", detail.fax]);

        if (fields.length > 0) {
            var dl = document.createElement("dl");
            dl.className = "detail-fields";
            for (var i = 0; i < fields.length; i++) {
                var dt = document.createElement("dt");
                dt.textContent = fields[i][0];
                var dd = document.createElement("dd");
                if (fields[i][2]) {
                    var a = document.createElement("a");
                    var href = fields[i][1];
                    if (!/^https?:\/\//i.test(href)) href = "https://" + href;
                    a.href = href;
                    a.target = "_blank";
                    a.rel = "noopener noreferrer";
                    a.textContent = fields[i][1];
                    dd.appendChild(a);
                } else {
                    dd.textContent = fields[i][1];
                }
                dl.appendChild(dt);
                dl.appendChild(dd);
            }
            overview.appendChild(dl);
            wrap.appendChild(overview);
        }

        wrap.appendChild(renderContacts(detail.contacts));
        wrap.appendChild(renderSalesPersons(detail.salesPersons));
        wrap.appendChild(renderProjects(detail.projects));
        wrap.appendChild(renderNotes(detail.notes));

        td.appendChild(wrap);
    }

    // ── Table rendering ───────────────────────────────────────────

    /** Renders table rows. Returns a Map of customerId → { tr, customer }. */
    function renderRows(customers) {
        els.tbody.replaceChildren();
        var rowMap = {};
        if (customers.length === 0) {
            var tr = document.createElement("tr");
            tr.className = "empty-row";
            var td = document.createElement("td");
            td.colSpan = 6;
            td.textContent = "No customers match the current filters.";
            tr.appendChild(td);
            els.tbody.appendChild(tr);
            return rowMap;
        }

        for (var i = 0; i < customers.length; i++) {
            var c = customers[i];
            var tr = document.createElement("tr");
            tr.className = "customer-row";

            var tdId = document.createElement("td");
            tdId.innerHTML = '<span class="expand-icon">&#x25B6;</span> ' + esc(c.customerId);

            var tdCompany = document.createElement("td");
            tdCompany.textContent = esc(c.companyName);

            var tdContact = document.createElement("td");
            tdContact.textContent = esc(c.contactName);

            var tdCity = document.createElement("td");
            tdCity.textContent = esc(c.city);

            var tdCountry = document.createElement("td");
            tdCountry.textContent = esc(c.country);

            var tdPhone = document.createElement("td");
            tdPhone.textContent = esc(c.phone);

            tr.appendChild(tdId);
            tr.appendChild(tdCompany);
            tr.appendChild(tdContact);
            tr.appendChild(tdCity);
            tr.appendChild(tdCountry);
            tr.appendChild(tdPhone);

            (function (row, cust) {
                row.addEventListener("click", function () {
                    toggleDetail(row, cust);
                });
            })(tr, c);

            els.tbody.appendChild(tr);
            rowMap[c.customerId] = { tr: tr, customer: c };
        }
        return rowMap;
    }

    // ── Search ────────────────────────────────────────────────────

    async function runSearch(ev) {
        if (ev) ev.preventDefault();

        setStatus("Loading\u2026", false);

        var params = new URLSearchParams();
        var companyName = els.companyName.value.trim();
        var contactName = els.contactName.value.trim();
        var contactEmail = els.contactEmail.value.trim();
        var salesPersonName = els.salesPersonName.value.trim();
        if (companyName) params.set("companyName", companyName);
        if (contactName) params.set("contactName", contactName);
        if (contactEmail) params.set("contactEmail", contactEmail);
        if (salesPersonName) params.set("salesPersonName", salesPersonName);

        var url = API_CUSTOMERS + (params.toString() ? "?" + params.toString() : "");

        var customers;
        try {
            var res = await fetch(url);
            if (!res.ok) {
                var text = await res.text();
                throw new Error(res.status + (text ? ": " + text.slice(0, 200) : ""));
            }
            customers = await res.json();
            if (!Array.isArray(customers)) {
                throw new Error("Unexpected response format");
            }
        } catch (e) {
            setStatus("Failed to load customers: " + e.message, true);
            els.tbody.replaceChildren();
            return;
        }

        var msg = customers.length === 1 ? "1 customer" : customers.length + " customers";
        setStatus(msg + ".", false);
        return renderRows(customers);
    }

    function resetForm() {
        els.form.reset();
        setStatus("", false);
        els.tbody.replaceChildren();
        detailCache = {};
        runSearch();
    }

    // ── Init ──────────────────────────────────────────────────────

    els.form.addEventListener("submit", runSearch);
    els.resetBtn.addEventListener("click", resetForm);

    var urlParams = new URLSearchParams(window.location.search);
    var targetCustomerId = urlParams.get("customerId");

    runSearch().then(function (rowMap) {
        if (!targetCustomerId || !rowMap) return;
        var entry = rowMap[targetCustomerId];
        if (entry) {
            entry.tr.scrollIntoView({ behavior: "smooth", block: "center" });
            toggleDetail(entry.tr, entry.customer);
        } else {
            setStatus('Customer "' + targetCustomerId + '" not found.', true);
        }
    });
})();
