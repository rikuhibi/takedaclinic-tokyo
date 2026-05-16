(function () {
  const SERVICE_PATHS = new Map([
    ["/kenshin.html", "健康診断・検査"],
    ["/vaccination.html", "予防接種"],
  ]);

  function cleanText(value) {
    return (value || "").replace(/\s+/g, " ").trim().slice(0, 120);
  }

  function emit(eventName, params) {
    const payload = {
      event_category: params.event_category,
      event_label: params.event_label,
      link_url: params.link_url,
      link_text: params.link_text,
      page_path: window.location.pathname,
      transport_type: "beacon",
    };

    if (typeof window.gtag === "function") {
      window.gtag("event", eventName, payload);
      return;
    }

    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push({
      event: eventName,
      ...payload,
    });
  }

  function classifyLink(link) {
    const rawHref = link.getAttribute("href") || "";
    const url = new URL(link.href, window.location.href);
    const linkText = cleanText(link.textContent);
    const base = {
      link_url: url.href,
      link_text: linkText,
    };

    if (rawHref.startsWith("tel:")) {
      return {
        eventName: "phone_click",
        params: {
          ...base,
          event_category: "contact",
          event_label: linkText || "電話",
        },
      };
    }

    if (url.hostname.includes("google.") && url.pathname.includes("/maps")) {
      return {
        eventName: "map_click",
        params: {
          ...base,
          event_category: "access",
          event_label: linkText || "地図",
        },
      };
    }

    if (url.origin === window.location.origin && url.hash === "#access") {
      return {
        eventName: "access_anchor_click",
        params: {
          ...base,
          event_category: "access",
          event_label: linkText || "アクセス",
        },
      };
    }

    if (url.origin === window.location.origin && SERVICE_PATHS.has(url.pathname)) {
      return {
        eventName: "medical_detail_click",
        params: {
          ...base,
          event_category: "medical",
          event_label: SERVICE_PATHS.get(url.pathname),
        },
      };
    }

    return null;
  }

  document.addEventListener(
    "click",
    function (event) {
      const link = event.target.closest("a");
      if (!link) return;

      const classified = classifyLink(link);
      if (!classified) return;

      emit(classified.eventName, classified.params);
    },
    { capture: true },
  );
})();
