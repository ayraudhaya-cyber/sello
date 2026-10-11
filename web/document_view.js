/**
 * Plain HTML invoice for /d/<token> on iPhone.
 * No canvas, WebGL, or Wasm — those trip Safari’s privacy banner.
 */
(function () {
  "use strict";

  var pub = window.selloPublic || {};

  function esc(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function tokenFromPath() {
    var path = location.pathname || "";
    var marker = "/d/";
    var at = path.indexOf(marker);
    if (at < 0) return "";
    var raw = path.slice(at + marker.length).split("/")[0];
    try {
      return decodeURIComponent(raw).trim();
    } catch (_) {
      return raw.trim();
    }
  }

  function money(doc, value) {
    var code = String(doc.currency || "USD").toUpperCase();
    var symbol =
      code === "LKR"
        ? "Rs "
        : code === "EUR"
          ? "€"
          : code === "GBP"
            ? "£"
            : code === "INR"
              ? "₹"
              : code === "JPY"
                ? "¥"
                : "$";
    var amount = Number(value || 0);
    var formatted = Math.abs(amount).toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
    return symbol + formatted;
  }

  function dateLabel(value) {
    if (!value) return "";
    var parsed = new Date(value);
    if (isNaN(parsed.getTime())) return "";
    var months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return (
      parsed.getDate() +
      " " +
      months[parsed.getMonth()] +
      " " +
      parsed.getFullYear()
    );
  }

  function lineDiscount(line) {
    var value = Number(line.discount || 0);
    if (!(value > 0)) return 0;
    var gross = Number(line.quantity || 0) * Number(line.unit_price || 0);
    if (line.discount_type === "percentage") {
      var amount = (gross * value) / 100;
      return amount > gross ? gross : amount;
    }
    return value > gross ? gross : value;
  }

  function lineTitle(line) {
    var name = line.name || "Item";
    var label = (line.variant_label || "").trim();
    if (!label || label.toLowerCase() === "default") return name;
    return name + " · " + label;
  }

  function show(html) {
    document.title = "Invoice";
    var meta = document.createElement("meta");
    meta.name = "viewport";
    meta.content = "width=device-width, initial-scale=1";
    document.head.appendChild(meta);
    var style = document.createElement("style");
    style.textContent =
      "html,body{margin:0;background:#fff;color:#111;font:15px/1.4 -apple-system,BlinkMacSystemFont,sans-serif}" +
      ".sheet{max-width:720px;margin:0 auto;padding:20px 16px 40px}" +
      ".top{display:flex;justify-content:space-between;gap:16px;align-items:flex-start}" +
      ".logo{max-width:140px;max-height:48px;object-fit:contain}" +
      "h1{font-size:18px;margin:0 0 4px}" +
      ".muted{color:#444;font-size:13px;margin:0}" +
      ".kind{text-align:right}" +
      ".kind strong{font-size:18px;letter-spacing:.04em}" +
      "table{width:100%;border-collapse:collapse;margin-top:16px}" +
      "th,td{border-bottom:1px solid #ddd;padding:8px 4px;text-align:left;vertical-align:top}" +
      "th{font-size:12px;color:#333}" +
      ".num,.amt{text-align:right;white-space:nowrap}" +
      ".totals{margin-top:12px;margin-left:auto;width:min(240px,100%)}" +
      ".totals div{display:flex;justify-content:space-between;gap:12px;padding:3px 0}" +
      ".grand{font-weight:700;border-top:1px solid #111;margin-top:4px;padding-top:6px}" +
      ".terms{margin-top:20px;font-size:12px;color:#333;white-space:pre-wrap}" +
      ".tag{margin-top:16px;text-align:center;font-size:12px;color:#333}" +
      ".miss{padding:48px 20px;text-align:center}" +
      "button{margin-top:18px;border:1px solid #ccc;background:#fff;border-radius:8px;padding:8px 14px;font:inherit}" +
      "@media print{button{display:none}}";
    document.head.appendChild(style);
    document.body.innerHTML = '<main class="sheet">' + html + "</main>";
  }

  function missing() {
    show(
      '<div class="miss"><h1>Document not available</h1><p class="muted">This link is invalid, expired, or is not shared with you.</p></div>',
    );
  }

  function renderOrder(doc) {
    var lines = Array.isArray(doc.lines) ? doc.lines : [];
    var rows = lines
      .map(function (line, index) {
        var off = lineDiscount(line);
        return (
          "<tr><td>" +
          (index + 1) +
          "</td><td>" +
          esc(lineTitle(line)) +
          "</td><td class=\"num\">" +
          esc(line.quantity) +
          "</td><td class=\"num\">" +
          esc(money(doc, line.unit_price)) +
          "</td><td class=\"num\">" +
          (off > 0 ? esc(money(doc, off)) : "") +
          "</td><td class=\"amt\">" +
          esc(money(doc, line.line_total)) +
          "</td></tr>"
        );
      })
      .join("");
    var rep = (doc.sales_rep_name || "").trim();
    var phone = (doc.sales_rep_phone || "").trim();
    var repLine = "";
    if (rep && phone) repLine = "Sales Rep: " + rep + " (" + phone + ")";
    else if (rep) repLine = "Sales Rep: " + rep;
    else if (phone) repLine = "Sales Rep: " + phone;

    var contact = [doc.document_address, doc.document_phone, doc.document_email]
      .filter(Boolean)
      .join(" · ");
    var logo = doc.document_logo_url || doc.logo_url;
    var discount = Number(doc.discount_amount || 0);
    var tax = Number(doc.tax_amount || 0);
    var when = dateLabel(doc.ordered_at || doc.completed_at);

    show(
      '<div class="top"><div>' +
        (logo ? '<img class="logo" alt="" src="' + esc(logo) + '">' : "") +
        "<h1>" +
        esc(doc.company_name || "") +
        "</h1>" +
        (contact ? '<p class="muted">' + esc(contact) + "</p>" : "") +
        "</div><div class=\"kind\"><strong>INVOICE</strong><p class=\"muted\">" +
        esc(doc.order_number || "") +
        "</p>" +
        (when ? '<p class="muted">' + esc(when) + "</p>" : "") +
        "</div></div>" +
        "<h2 style=\"font-size:13px;margin:18px 0 4px\">Bill to</h2>" +
        "<div><strong>" +
        esc(doc.customer_name || "") +
        "</strong></div>" +
        (doc.customer_phone
          ? '<div class="muted">' + esc(doc.customer_phone) + "</div>"
          : "") +
        (doc.customer_address
          ? '<div class="muted">' + esc(doc.customer_address) + "</div>"
          : "") +
        (repLine ? '<p><strong>' + esc(repLine) + "</strong></p>" : "") +
        "<table><thead><tr><th>#</th><th>Description</th><th class=\"num\">Qty</th><th class=\"num\">Rate</th><th class=\"num\">Discount</th><th class=\"amt\">Amount</th></tr></thead><tbody>" +
        rows +
        "</tbody></table>" +
        '<div class="totals"><div><span>Subtotal</span><span>' +
        esc(money(doc, doc.subtotal)) +
        "</span></div>" +
        (discount > 0
          ? "<div><span>Discount</span><span>- " +
            esc(money(doc, discount)) +
            "</span></div>"
          : "") +
        (tax > 0
          ? "<div><span>Tax</span><span>" + esc(money(doc, tax)) + "</span></div>"
          : "") +
        '<div class="grand"><span>Total</span><span>' +
        esc(money(doc, doc.total)) +
        "</span></div></div>" +
        (doc.document_terms
          ? '<div class="terms">' + esc(doc.document_terms) + "</div>"
          : "") +
        (doc.document_tagline
          ? '<div class="tag">' + esc(doc.document_tagline) + "</div>"
          : "") +
        '<button type="button" onclick="window.print()">Print / Save PDF</button>',
    );
  }

  function renderPayment(doc) {
    var when = dateLabel(doc.received_at);
    show(
      "<h1>" +
        esc(doc.company_name || "") +
        "</h1><p class=\"kind\"><strong>" +
        (doc.purpose === "receipt" ? "RECEIPT" : "COLLECTION") +
        "</strong></p><p>" +
        esc(doc.payment_number || "") +
        "</p>" +
        (when ? "<p>" + esc(when) + "</p>" : "") +
        "<p><strong>" +
        esc(doc.customer_name || "") +
        "</strong></p><p class=\"grand\">" +
        esc(money(doc, doc.amount)) +
        "</p>",
    );
  }

  var token = tokenFromPath();
  if (!token || !pub.url || !pub.key) {
    missing();
    return;
  }

  var root = String(pub.url).replace(/\/$/, "");
  fetch(root + "/rest/v1/rpc/get_public_document_by_token", {
    method: "POST",
    headers: {
      apikey: pub.key,
      Authorization: "Bearer " + pub.key,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_token: token }),
  })
    .then(function (response) {
      if (!response.ok) throw new Error("unavailable");
      return response.json();
    })
    .then(function (doc) {
      if (!doc || typeof doc !== "object") {
        missing();
        return;
      }
      if (doc.purpose === "collection_acknowledgement" || doc.purpose === "receipt") {
        renderPayment(doc);
        return;
      }
      renderOrder(doc);
    })
    .catch(function () {
      missing();
    });
})();
