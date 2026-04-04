(function () {
    "use strict";

    var API_BASE = "/api/it/tickets";

    var els = {
        // List view
        listView: document.getElementById("listView"),
        form: document.getElementById("filters"),
        filterStatus: document.getElementById("filterStatus"),
        filterCategory: document.getElementById("filterCategory"),
        filterSubmittedBy: document.getElementById("filterSubmittedBy"),
        filterAssignedTo: document.getElementById("filterAssignedTo"),
        status: document.getElementById("status"),
        tbody: document.getElementById("tbody"),
        resetBtn: document.getElementById("resetBtn"),
        newTicketBtn: document.getElementById("newTicketBtn"),
        // Detail view
        detailView: document.getElementById("detailView"),
        backBtn: document.getElementById("backBtn"),
        ticketDetail: document.getElementById("ticketDetail"),
        // Modal
        modalOverlay: document.getElementById("modalOverlay"),
        modalClose: document.getElementById("modalClose"),
        modalCancel: document.getElementById("modalCancel"),
        newTicketForm: document.getElementById("newTicketForm"),
        ntTitle: document.getElementById("ntTitle"),
        ntDescription: document.getElementById("ntDescription"),
        ntCategory: document.getElementById("ntCategory"),
        ntPriority: document.getElementById("ntPriority"),
        ntName: document.getElementById("ntName"),
        ntEmail: document.getElementById("ntEmail"),
    };

    // ── Helpers ────────────────────────────────────────────────────

    function esc(value) {
        if (value == null) return "";
        return String(value);
    }

    function formatDate(value) {
        if (!value) return "";
        var d = new Date(value);
        if (isNaN(d.getTime())) return String(value);
        return d.toLocaleDateString() + " " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
    }

    function setStatus(message, isError) {
        els.status.textContent = message;
        els.status.classList.toggle("error", Boolean(isError));
    }

    function statusLabel(s) {
        if (!s) return "";
        return s.replace(/_/g, " ");
    }

    async function postJSON(url, body) {
        var res = await fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
        });
        return res.json();
    }

    // ── List View ─────────────────────────────────────────────────

    function renderRows(tickets) {
        els.tbody.replaceChildren();
        if (tickets.length === 0) {
            var tr = document.createElement("tr");
            tr.className = "empty-row";
            var td = document.createElement("td");
            td.colSpan = 7;
            td.textContent = "No tickets match the current filters.";
            tr.appendChild(td);
            els.tbody.appendChild(tr);
            return;
        }

        for (var i = 0; i < tickets.length; i++) {
            var t = tickets[i];
            var tr = document.createElement("tr");
            tr.className = "ticket-row";

            var tdNum = document.createElement("td");
            tdNum.textContent = esc(t.ticketNumber);

            var tdTitle = document.createElement("td");
            tdTitle.textContent = esc(t.title);

            var tdCat = document.createElement("td");
            var catBadge = document.createElement("span");
            catBadge.className = "badge category";
            catBadge.textContent = esc(t.category);
            tdCat.appendChild(catBadge);

            var tdPri = document.createElement("td");
            var priBadge = document.createElement("span");
            priBadge.className = "badge priority-" + (t.priority || "").toLowerCase();
            priBadge.textContent = esc(t.priority);
            tdPri.appendChild(priBadge);

            var tdStatus = document.createElement("td");
            var stBadge = document.createElement("span");
            stBadge.className = "badge status-" + (t.status || "").toLowerCase();
            stBadge.textContent = statusLabel(t.status);
            tdStatus.appendChild(stBadge);

            var tdBy = document.createElement("td");
            tdBy.textContent = esc(t.submittedBy);

            var tdAssign = document.createElement("td");
            tdAssign.textContent = esc(t.assignedTo) || "\u2014";

            tr.appendChild(tdNum);
            tr.appendChild(tdTitle);
            tr.appendChild(tdCat);
            tr.appendChild(tdPri);
            tr.appendChild(tdStatus);
            tr.appendChild(tdBy);
            tr.appendChild(tdAssign);

            (function (ticket) {
                tr.addEventListener("click", function () {
                    showDetail(ticket.ticketNumber);
                });
            })(t);

            els.tbody.appendChild(tr);
        }
    }

    async function runSearch(ev) {
        if (ev) ev.preventDefault();
        setStatus("Loading\u2026", false);

        var body = {};
        var st = els.filterStatus.value;
        var cat = els.filterCategory.value;
        var submittedBy = els.filterSubmittedBy.value.trim();
        var assignedTo = els.filterAssignedTo.value.trim();
        if (st) body.status = st;
        if (cat) body.category = cat;
        if (submittedBy) body.submittedBy = submittedBy;
        if (assignedTo) body.assignedTo = assignedTo;

        try {
            var result = await postJSON(API_BASE + "/list", body);
            if (!result.success) throw new Error(result.message);
            var tickets = result.data || [];
            var msg = tickets.length === 1 ? "1 ticket" : tickets.length + " tickets";
            setStatus(msg + ".", false);
            renderRows(tickets);
        } catch (e) {
            setStatus("Failed to load tickets: " + e.message, true);
            els.tbody.replaceChildren();
        }
    }

    function resetForm() {
        els.form.reset();
        setStatus("", false);
        els.tbody.replaceChildren();
        runSearch();
    }

    // ── Detail View ───────────────────────────────────────────────

    async function showDetail(ticketNumber) {
        els.listView.classList.add("hidden");
        els.detailView.classList.remove("hidden");
        els.ticketDetail.textContent = "Loading\u2026";

        try {
            var result = await postJSON(API_BASE + "/details", { ticketNumber: ticketNumber });
            if (!result.success) throw new Error(result.message);
            renderDetail(result.data);
        } catch (e) {
            els.ticketDetail.textContent = "Error: " + e.message;
        }
    }

    function renderDetail(data) {
        var ticket = data.ticket;
        var comments = data.comments || [];

        els.ticketDetail.innerHTML = "";

        // Header
        var header = document.createElement("div");
        header.className = "ticket-header";
        var headerLeft = document.createElement("div");
        var h2 = document.createElement("h2");
        h2.textContent = esc(ticket.ticketNumber) + " \u2014 " + esc(ticket.title);
        headerLeft.appendChild(h2);
        var meta = document.createElement("div");
        meta.className = "ticket-meta";
        meta.textContent = "Submitted by " + esc(ticket.submittedBy) + " on " + formatDate(ticket.createdAt);
        headerLeft.appendChild(meta);

        var badges = document.createElement("div");
        badges.className = "ticket-badges";
        var stBadge = document.createElement("span");
        stBadge.className = "badge status-" + (ticket.status || "").toLowerCase();
        stBadge.textContent = statusLabel(ticket.status);
        var priBadge = document.createElement("span");
        priBadge.className = "badge priority-" + (ticket.priority || "").toLowerCase();
        priBadge.textContent = esc(ticket.priority);
        var catBadge = document.createElement("span");
        catBadge.className = "badge category";
        catBadge.textContent = esc(ticket.category);
        badges.appendChild(stBadge);
        badges.appendChild(priBadge);
        badges.appendChild(catBadge);

        header.appendChild(headerLeft);
        header.appendChild(badges);
        els.ticketDetail.appendChild(header);

        // Info section
        var infoSection = document.createElement("div");
        infoSection.className = "detail-section";
        var infoH3 = document.createElement("h3");
        infoH3.textContent = "Details";
        infoSection.appendChild(infoH3);
        var dl = document.createElement("dl");
        dl.className = "detail-fields";
        addField(dl, "Email", ticket.submittedByEmail);
        addField(dl, "Assigned To", ticket.assignedTo || "Unassigned");
        addField(dl, "Created", formatDate(ticket.createdAt));
        if (ticket.updatedAt) addField(dl, "Updated", formatDate(ticket.updatedAt));
        if (ticket.resolvedAt) addField(dl, "Resolved", formatDate(ticket.resolvedAt));
        infoSection.appendChild(dl);
        els.ticketDetail.appendChild(infoSection);

        // Description
        if (ticket.description) {
            var descSection = document.createElement("div");
            descSection.className = "detail-section";
            var descH3 = document.createElement("h3");
            descH3.textContent = "Description";
            descSection.appendChild(descH3);
            var descP = document.createElement("div");
            descP.className = "description-text";
            descP.textContent = ticket.description;
            descSection.appendChild(descP);
            els.ticketDetail.appendChild(descSection);
        }

        // Comments
        var commSection = document.createElement("div");
        commSection.className = "detail-section";
        var commH3 = document.createElement("h3");
        commH3.textContent = "Comments (" + comments.length + ")";
        commSection.appendChild(commH3);

        if (comments.length === 0) {
            var noComm = document.createElement("p");
            noComm.className = "no-comments";
            noComm.textContent = "No comments yet.";
            commSection.appendChild(noComm);
        } else {
            var ul = document.createElement("ul");
            ul.className = "comment-list";
            for (var i = 0; i < comments.length; i++) {
                var c = comments[i];
                var li = document.createElement("li");
                li.className = "comment-item";
                var authorSpan = document.createElement("span");
                authorSpan.className = "comment-author";
                authorSpan.textContent = esc(c.author);
                var dateSpan = document.createElement("span");
                dateSpan.className = "comment-date";
                dateSpan.textContent = formatDate(c.createdAt);
                var bodyDiv = document.createElement("div");
                bodyDiv.className = "comment-body";
                bodyDiv.textContent = esc(c.body);
                li.appendChild(authorSpan);
                li.appendChild(dateSpan);
                li.appendChild(bodyDiv);
                ul.appendChild(li);
            }
            commSection.appendChild(ul);
        }
        els.ticketDetail.appendChild(commSection);

        // Action forms
        var actions = document.createElement("div");
        actions.className = "action-forms";

        // Assign form
        var assignCard = document.createElement("div");
        assignCard.className = "action-card";
        assignCard.innerHTML =
            '<h4>Assign Ticket</h4>' +
            '<div class="field"><span class="label">Assign To</span>' +
            '<input type="text" id="assignTo" placeholder="IT staff name" value="' + esc(ticket.assignedTo) + '"></div>' +
            '<button type="button" class="btn primary" id="assignBtn">Assign</button>';
        actions.appendChild(assignCard);

        // Update status form
        var statusCard = document.createElement("div");
        statusCard.className = "action-card";
        statusCard.innerHTML =
            '<h4>Update Status</h4>' +
            '<div class="field"><span class="label">New Status</span>' +
            '<select id="newStatus">' +
            '<option value="OPEN"' + (ticket.status === "OPEN" ? " selected" : "") + '>Open</option>' +
            '<option value="IN_PROGRESS"' + (ticket.status === "IN_PROGRESS" ? " selected" : "") + '>In Progress</option>' +
            '<option value="WAITING_ON_USER"' + (ticket.status === "WAITING_ON_USER" ? " selected" : "") + '>Waiting on User</option>' +
            '<option value="RESOLVED"' + (ticket.status === "RESOLVED" ? " selected" : "") + '>Resolved</option>' +
            '<option value="CLOSED"' + (ticket.status === "CLOSED" ? " selected" : "") + '>Closed</option>' +
            '</select></div>' +
            '<div class="field"><span class="label">Resolution Note</span>' +
            '<input type="text" id="resolutionNote" placeholder="Optional"></div>' +
            '<button type="button" class="btn primary" id="statusBtn">Update</button>';
        actions.appendChild(statusCard);

        // Add comment form
        var commentCard = document.createElement("div");
        commentCard.className = "action-card";
        commentCard.innerHTML =
            '<h4>Add Comment</h4>' +
            '<div class="field"><span class="label">Author</span>' +
            '<input type="text" id="commentAuthor" placeholder="Your name"></div>' +
            '<div class="field"><span class="label">Comment</span>' +
            '<textarea id="commentBody" rows="2" placeholder="Write a comment..."></textarea></div>' +
            '<button type="button" class="btn primary" id="commentBtn">Add Comment</button>';
        actions.appendChild(commentCard);

        els.ticketDetail.appendChild(actions);

        // Wire up action buttons
        var ticketNumber = ticket.ticketNumber;

        document.getElementById("assignBtn").addEventListener("click", async function () {
            var assignTo = document.getElementById("assignTo").value.trim();
            if (!assignTo) return;
            try {
                var res = await postJSON(API_BASE + "/assign", { ticketNumber: ticketNumber, assignedTo: assignTo });
                if (!res.success) throw new Error(res.message);
                showDetail(ticketNumber);
            } catch (e) {
                alert("Error: " + e.message);
            }
        });

        document.getElementById("statusBtn").addEventListener("click", async function () {
            var newSt = document.getElementById("newStatus").value;
            var resNote = document.getElementById("resolutionNote").value.trim();
            var body = { ticketNumber: ticketNumber, status: newSt };
            if (resNote) body.resolution = resNote;
            try {
                var res = await postJSON(API_BASE + "/update-status", body);
                if (!res.success) throw new Error(res.message);
                showDetail(ticketNumber);
            } catch (e) {
                alert("Error: " + e.message);
            }
        });

        document.getElementById("commentBtn").addEventListener("click", async function () {
            var author = document.getElementById("commentAuthor").value.trim();
            var body = document.getElementById("commentBody").value.trim();
            if (!author || !body) return;
            try {
                var res = await postJSON(API_BASE + "/comment", { ticketNumber: ticketNumber, author: author, body: body });
                if (!res.success) throw new Error(res.message);
                showDetail(ticketNumber);
            } catch (e) {
                alert("Error: " + e.message);
            }
        });
    }

    function addField(dl, label, value) {
        var dt = document.createElement("dt");
        dt.textContent = label;
        var dd = document.createElement("dd");
        dd.textContent = esc(value);
        dl.appendChild(dt);
        dl.appendChild(dd);
    }

    function goBack() {
        els.detailView.classList.add("hidden");
        els.listView.classList.remove("hidden");
        runSearch();
    }

    // ── New Ticket Modal ──────────────────────────────────────────

    function openModal() {
        els.modalOverlay.classList.remove("hidden");
    }

    function closeModal() {
        els.modalOverlay.classList.add("hidden");
        els.newTicketForm.reset();
    }

    async function submitNewTicket(ev) {
        ev.preventDefault();
        var title = els.ntTitle.value.trim();
        var description = els.ntDescription.value.trim();
        var category = els.ntCategory.value;
        var priority = els.ntPriority.value;
        var name = els.ntName.value.trim();
        var email = els.ntEmail.value.trim();

        if (!title || !name || !email) {
            alert("Please fill in all required fields.");
            return;
        }

        try {
            var res = await postJSON(API_BASE + "/submit", {
                title: title,
                description: description,
                category: category,
                priority: priority,
                submittedBy: name,
                submittedByEmail: email,
            });
            if (!res.success) throw new Error(res.message);
            closeModal();
            runSearch();
            setStatus("Ticket " + res.data.ticketNumber + " submitted successfully.", false);
        } catch (e) {
            alert("Error submitting ticket: " + e.message);
        }
    }

    // ── Init ──────────────────────────────────────────────────────

    els.form.addEventListener("submit", runSearch);
    els.resetBtn.addEventListener("click", resetForm);
    els.backBtn.addEventListener("click", goBack);
    els.newTicketBtn.addEventListener("click", openModal);
    els.modalClose.addEventListener("click", closeModal);
    els.modalCancel.addEventListener("click", closeModal);
    els.newTicketForm.addEventListener("submit", submitNewTicket);

    els.modalOverlay.addEventListener("click", function (e) {
        if (e.target === els.modalOverlay) closeModal();
    });

    // Check URL params for deep linking
    var urlParams = new URLSearchParams(window.location.search);
    var targetTicket = urlParams.get("ticket");

    if (targetTicket) {
        showDetail(targetTicket);
    } else {
        runSearch();
    }
})();
