(function () {
    "use strict";

    var API_ORDERS = "/api/sales-orders";

    var els = {
        form: document.getElementById("filters"),
        customerName: document.getElementById("customerName"),
        status: document.getElementById("status"),
        statusMsg: document.getElementById("statusMsg"),
        tbody: document.getElementById("tbody"),
        resetBtn: document.getElementById("resetBtn"),
    };

    function setStatus(message, isError) {
        els.statusMsg.textContent = message;
        els.statusMsg.classList.toggle("error", Boolean(isError));
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

    // ── Detail rendering ─────────────────────────────────────────

    function renderLineItems(orderDetails) {
        var section = document.createElement("div");
        section.className = "detail-section";
        var h = document.createElement("h3");
        h.textContent = "Line Items";
        section.appendChild(h);

        if (!orderDetails || orderDetails.length === 0) {
            var p = document.createElement("p");
            p.className = "detail-empty";
            p.textContent = "No line items.";
            section.appendChild(p);
            return section;
        }

        var table = document.createElement("table");
        table.className = "detail-table";
        var thead = document.createElement("thead");
        var headRow = document.createElement("tr");
        var cols = ["Product ID", "Product Name", "Qty", "Unit Price", "Subtotal"];
        for (var i = 0; i < cols.length; i++) {
            var th = document.createElement("th");
            th.textContent = cols[i];
            if (i >= 2) th.className = "num";
            headRow.appendChild(th);
        }
        thead.appendChild(headRow);
        table.appendChild(thead);

        var tbody = document.createElement("tbody");
        for (var j = 0; j < orderDetails.length; j++) {
            var item = orderDetails[j];
            var tr = document.createElement("tr");

            var tdPid = document.createElement("td");
            tdPid.textContent = esc(item.productId);

            var tdName = document.createElement("td");
            tdName.textContent = esc(item.productName);

            var tdQty = document.createElement("td");
            tdQty.className = "num";
            tdQty.textContent = esc(item.quantity);

            var tdPrice = document.createElement("td");
            tdPrice.className = "num";
            tdPrice.textContent = formatCurrency(item.unitPrice);

            var tdSub = document.createElement("td");
            tdSub.className = "num";
            tdSub.textContent = formatCurrency(item.subtotal);

            tr.appendChild(tdPid);
            tr.appendChild(tdName);
            tr.appendChild(tdQty);
            tr.appendChild(tdPrice);
            tr.appendChild(tdSub);
            tbody.appendChild(tr);
        }
        table.appendChild(tbody);
        section.appendChild(table);
        return section;
    }

    function toggleDetail(tr, order) {
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

        var wrap = document.createElement("div");
        wrap.className = "detail-content";

        var overview = document.createElement("div");
        overview.className = "detail-overview";
        var dl = document.createElement("dl");
        dl.className = "detail-fields";
        var fields = [
            ["Customer ID", order.customerId],
            ["Order Date", formatDate(order.orderDate)],
            ["Total", formatCurrency(order.totalAmount)],
        ];
        for (var i = 0; i < fields.length; i++) {
            var dt = document.createElement("dt");
            dt.textContent = fields[i][0];
            var dd = document.createElement("dd");
            dd.textContent = fields[i][1];
            dl.appendChild(dt);
            dl.appendChild(dd);
        }
        overview.appendChild(dl);
        wrap.appendChild(overview);
        wrap.appendChild(renderLineItems(order.orderDetails));

        td.appendChild(wrap);
        detailTr.appendChild(td);
        tr.after(detailTr);
        tr.classList.add("expanded");
    }

    // ── Table rendering ──────────────────────────────────────────

    function renderRows(orders) {
        els.tbody.replaceChildren();
        if (orders.length === 0) {
            var tr = document.createElement("tr");
            tr.className = "empty-row";
            var td = document.createElement("td");
            td.colSpan = 6;
            td.textContent = "No orders match the current filters.";
            tr.appendChild(td);
            els.tbody.appendChild(tr);
            return;
        }

        for (var i = 0; i < orders.length; i++) {
            var o = orders[i];
            var tr = document.createElement("tr");
            tr.className = "order-row";

            var tdOrder = document.createElement("td");
            tdOrder.innerHTML = '<span class="expand-icon">&#x25B6;</span> ' + esc(o.orderNumber);

            var tdCustomer = document.createElement("td");
            tdCustomer.textContent = esc(o.customerName);

            var tdDate = document.createElement("td");
            tdDate.textContent = formatDate(o.orderDate);

            var tdStatus = document.createElement("td");
            if (o.status) {
                var badge = document.createElement("span");
                badge.className = "badge status-" + o.status.toLowerCase();
                badge.textContent = o.status;
                tdStatus.appendChild(badge);
            }

            var tdTotal = document.createElement("td");
            tdTotal.className = "num";
            tdTotal.textContent = formatCurrency(o.totalAmount);

            var tdItems = document.createElement("td");
            tdItems.className = "num";
            tdItems.textContent = o.orderDetails ? o.orderDetails.length : 0;

            tr.appendChild(tdOrder);
            tr.appendChild(tdCustomer);
            tr.appendChild(tdDate);
            tr.appendChild(tdStatus);
            tr.appendChild(tdTotal);
            tr.appendChild(tdItems);

            (function (row, order) {
                row.addEventListener("click", function () {
                    toggleDetail(row, order);
                });
            })(tr, o);

            els.tbody.appendChild(tr);
        }
    }

    // ── Search ───────────────────────────────────────────────────

    async function runSearch(ev) {
        if (ev) ev.preventDefault();

        setStatus("Loading\u2026", false);

        var params = new URLSearchParams();
        var customerName = els.customerName.value.trim();
        var status = els.status.value;
        if (customerName) params.set("customerName", customerName);
        if (status) params.set("status", status);

        var url = API_ORDERS + (params.toString() ? "?" + params.toString() : "");

        try {
            var res = await fetch(url);
            if (!res.ok) {
                var text = await res.text();
                throw new Error(res.status + (text ? ": " + text.slice(0, 200) : ""));
            }
            var orders = await res.json();
            if (!Array.isArray(orders)) {
                throw new Error("Unexpected response format");
            }
        } catch (e) {
            setStatus("Failed to load orders: " + e.message, true);
            els.tbody.replaceChildren();
            return;
        }

        var msg = orders.length === 1 ? "1 order" : orders.length + " orders";
        setStatus(msg + ".", false);
        renderRows(orders);
    }

    function resetForm() {
        els.form.reset();
        setStatus("", false);
        els.tbody.replaceChildren();
        runSearch();
    }

    // ── Init ─────────────────────────────────────────────────────

    els.form.addEventListener("submit", runSearch);
    els.resetBtn.addEventListener("click", resetForm);
    runSearch();
})();
