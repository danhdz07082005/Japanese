// PyTunnel Studio - Cyber-Tunnel HUD Frontend Controller
(() => {
    "use strict";

    let csrfToken = "";
    let lang = localStorage.getItem("pytunnel_lang") || "vi";
    let isLight = localStorage.getItem("pytunnel_theme") === "light";
    let i18nCatalog = {};
    let tunnels = [];
    let activePort = null;
    let selectedMode = "protected"; // "protected" | "public"
    let pollTimer = null;
    let trafficTimer = null;

    // DOM Elements
    const dom = {
        html: document.documentElement,
        targetInput: document.getElementById("target-input"),
        btnSubmitLaunch: document.getElementById("btn-submit-launch"),
        btnModeProtected: document.getElementById("btn-mode-protected"),
        btnModePublic: document.getElementById("btn-mode-public"),
        parseFeedback: document.getElementById("parse-feedback"),
        feedbackText: document.getElementById("feedback-text"),
        tunnelsGrid: document.getElementById("tunnels-grid"),
        tunnelCountPill: document.getElementById("tunnel-count-pill"),
        engineStatusText: document.getElementById("engine-status-text"),
        btnKillAll: document.getElementById("btn-kill-all"),
        btnExitApp: document.getElementById("btn-exit-app"),
        btnToggleLang: document.getElementById("btn-toggle-lang"),
        langLabel: document.getElementById("lang-label"),
        btnToggleTheme: document.getElementById("btn-toggle-theme"),
        themeIcon: document.getElementById("theme-icon"),
        launcherForm: document.getElementById("launcher-form"),
        // Drawer
        drawerBackdrop: document.getElementById("drawer-backdrop"),
        drawerPanel: document.getElementById("drawer-panel"),
        drawerTitle: document.getElementById("drawer-title"),
        drawerOrigin: document.getElementById("drawer-origin"),
        drawerLinkUrl: document.getElementById("drawer-link-url"),
        btnCopyDrawerLink: document.getElementById("btn-copy-drawer-link"),
        btnOpenDrawerLink: document.getElementById("btn-open-drawer-link"),
        drawerQrImg: document.getElementById("drawer-qr-img"),
        btnCopyQrLink: document.getElementById("btn-copy-qr-link"),
        drawerShortInput: document.getElementById("drawer-short-input"),
        btnCreateShort: document.getElementById("btn-create-short"),
        drawerShortResult: document.getElementById("drawer-short-result"),
        drawerShortUrl: document.getElementById("drawer-short-url"),
        btnCopyShortUrl: document.getElementById("btn-copy-short-url"),
        btnOpenShortUrl: document.getElementById("btn-open-short-url"),
        drawerMetricReq: document.getElementById("drawer-metric-req"),
        drawerMetricOnline: document.getElementById("drawer-metric-online"),
        drawerMetricUptime: document.getElementById("drawer-metric-uptime"),
        drawerMetricBlocked: document.getElementById("drawer-metric-blocked"),
        drawerPid: document.getElementById("drawer-pid"),
        drawerProxyPort: document.getElementById("drawer-proxy-port"),
        drawerJobStatus: document.getElementById("drawer-job-status"),
        trafficTbody: document.getElementById("traffic-tbody"),
        btnRefreshTraffic: document.getElementById("btn-refresh-traffic"),
        btnDrawerStop: document.getElementById("btn-drawer-stop"),
        btnDrawerClose: document.getElementById("btn-drawer-close"),
        drawerTabBtns: document.querySelectorAll(".drawer-tab-btn"),
        drawerTabContents: document.querySelectorAll(".drawer-tab-content"),
        btnSwitchProtected: document.getElementById("btn-switch-protected"),
        btnSwitchPublic: document.getElementById("btn-switch-public"),
        drawerDisplayCode: document.getElementById("drawer-display-code"),
        btnCopyDrawerCode: document.getElementById("btn-copy-drawer-code"),
        btnRotateKeep: document.getElementById("btn-rotate-keep"),
        btnRotateKick: document.getElementById("btn-rotate-kick"),
        drawerCodeSection: document.getElementById("drawer-code-section"),
        // Modal
        modalBackdrop: document.getElementById("modal-backdrop"),
        modalTitle: document.getElementById("modal-title"),
        modalBody: document.getElementById("modal-body"),
        modalActions: document.getElementById("modal-actions"),
        toastContainer: document.getElementById("toast-container"),
    };

    function t(key, params = {}) {
        const dict = (i18nCatalog[lang] || i18nCatalog["vi"] || {});
        let template = dict[key] || key;
        for (const [k, v] of Object.entries(params)) {
            template = template.replaceAll(`{${k}}`, v);
        }
        return template;
    }

    function escapeHtml(str) {
        if (!str) return "";
        return String(str)
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;")
            .replaceAll("'", "&#39;");
    }

    function applyI18n() {
        dom.html.setAttribute("lang", lang);
        dom.langLabel.textContent = lang.toUpperCase();
        document.querySelectorAll("[data-i18n]").forEach(el => {
            const key = el.getAttribute("data-i18n");
            el.textContent = t(key);
        });
        document.querySelectorAll("[data-i18n-title]").forEach(el => {
            const key = el.getAttribute("data-i18n-title");
            el.setAttribute("title", t(key));
        });
        document.querySelectorAll("[data-i18n-placeholder]").forEach(el => {
            const key = el.getAttribute("data-i18n-placeholder");
            el.setAttribute("placeholder", t(key));
        });
        dom.targetInput.placeholder = t("launch.placeholder");
        updateEngineStatus();
        renderTunnels();
        if (activePort) updateDrawerContent();
    }

    function applyTheme() {
        if (isLight) {
            dom.html.classList.add("light");
            dom.themeIcon.innerHTML = '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>';
        } else {
            dom.html.classList.remove("light");
            dom.themeIcon.innerHTML = '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>';
        }
    }

    function showToast(msg) {
        const item = document.createElement("div");
        item.className = "toast";
        item.textContent = msg;
        dom.toastContainer.appendChild(item);
        setTimeout(() => {
            item.style.opacity = "0";
            item.style.transition = "opacity 0.3s";
            setTimeout(() => item.remove(), 300);
        }, 2500);
    }

    function copyToClipboard(text) {
        if (!text || text === "-") return;
        navigator.clipboard.writeText(text).then(() => {
            showToast(`${t("toast.copied")}: ${text}`);
        });
    }

    // Modal Helpers
    function closeModal() {
        dom.modalBackdrop.classList.remove("open");
        dom.modalActions.innerHTML = "";
    }

    function showModal(title, body, buttons) {
        dom.modalTitle.textContent = title;
        dom.modalBody.textContent = body;
        dom.modalActions.innerHTML = "";

        buttons.forEach(btnConfig => {
            const b = document.createElement("button");
            b.className = `btn ${btnConfig.danger ? "btn-danger" : (btnConfig.primary ? "btn-primary" : "")}`;
            b.textContent = btnConfig.text;
            b.onclick = () => {
                closeModal();
                if (btnConfig.action) btnConfig.action();
            };
            dom.modalActions.appendChild(b);
        });

        dom.modalBackdrop.classList.add("open");
    }

    let isInitialized = false;

    // API Calls
    async function api(path, options = {}, silentFail = false) {
        const headers = {
            "Accept": "application/json",
            "Accept-Language": lang,
            ...(options.headers || {})
        };
        if (options.method && options.method !== "GET") {
            headers["Content-Type"] = "application/json";
            headers["X-PyTunnel-Token"] = csrfToken;
        }

        try {
            const resp = await fetch(path, { ...options, headers });
            const data = await resp.json().catch(() => ({}));
            if (!resp.ok) {
                const msg = data.message || t(data.error_code || "error.internal");
                throw new Error(msg);
            }
            return data;
        } catch (err) {
            if (err.name === "TypeError" && !silentFail && isInitialized) {
                showToast(t("toast.network_error"));
            }
            throw err;
        }
    }

    function playLiquidHello(durationMs = 1800) {
        const screen = document.getElementById("liquid-hello-screen");
        if (!screen) return;

        const progress = document.getElementById("hello-progress");
        const timerText = document.getElementById("hello-timer");
        const btnSkip = document.getElementById("btn-skip-hello");

        screen.classList.remove("hidden", "fade-out");
        let finished = false;
        const startTime = performance.now();

        const finish = () => {
            if (finished) return;
            finished = true;
            window.removeEventListener("keydown", onKeyDown);
            screen.classList.add("fade-out");
            setTimeout(() => {
                screen.classList.add("hidden");
            }, 350);
        };

        const onKeyDown = (e) => {
            if (e.key === "Escape") finish();
        };
        window.addEventListener("keydown", onKeyDown);
        if (btnSkip) btnSkip.onclick = finish;

        const updateHUD = () => {
            if (finished) return;
            const elapsed = performance.now() - startTime;
            const pct = Math.min(100, Math.floor((elapsed / durationMs) * 100));
            const remaining = Math.max(0, ((durationMs - elapsed) / 1000)).toFixed(1);

            if (progress) progress.style.width = `${pct}%`;
            if (timerText) timerText.textContent = `${remaining}s`;

            if (elapsed >= durationMs) {
                finish();
            } else {
                requestAnimationFrame(updateHUD);
            }
        };
        requestAnimationFrame(updateHUD);
    }

    function playLiquidGoodbye(durationMs = 1800, onComplete) {
        const screen = document.getElementById("liquid-goodbye-screen");
        if (!screen) {
            if (onComplete) onComplete();
            return;
        }

        const progress = document.getElementById("goodbye-progress");
        const timerText = document.getElementById("goodbye-timer");
        const finalBox = document.getElementById("goodbye-final-box");

        screen.classList.remove("hidden", "fade-out");
        if (finalBox) finalBox.style.display = "none";

        let finished = false;
        const startTime = performance.now();

        const updateHUD = () => {
            if (finished) return;
            const elapsed = performance.now() - startTime;
            const pct = Math.min(100, Math.floor((elapsed / durationMs) * 100));
            const remaining = Math.max(0, ((durationMs - elapsed) / 1000)).toFixed(1);

            if (progress) progress.style.width = `${pct}%`;
            if (timerText) timerText.textContent = `${remaining}s`;

            if (elapsed >= durationMs) {
                finished = true;
                if (finalBox) {
                    finalBox.style.display = "block";
                    finalBox.style.animation = "fadeIn 0.3s ease";
                }
                if (onComplete) onComplete();
            } else {
                requestAnimationFrame(updateHUD);
            }
        };
        requestAnimationFrame(updateHUD);
    }

    // Initial Bootstrap with Graceful Startup
    async function init() {
        applyTheme();
        bindEvents();
        playLiquidHello(1800);

        // Load data in background during the 1.8s liquid loading buffer
        let bootSuccess = false;
        for (let attempt = 1; attempt <= 4; attempt++) {
            try {
                const [status, catalog] = await Promise.all([
                    api("/api/status", {}, true),
                    api("/api/i18n", {}, true),
                ]);
                csrfToken = status.csrf_token;
                i18nCatalog = catalog;
                updateEngineStatus(status.engine);
                applyI18n();
                await refreshTunnels();
                bootSuccess = true;
                isInitialized = true;
                break;
            } catch (e) {
                // If server is binding socket, wait 200ms and retry
                await new Promise(r => setTimeout(r, 200));
            }
        }

        if (!bootSuccess) {
            showToast(t("toast.network_error"));
        }

        // Background polling
        pollTimer = setInterval(() => {
            if (!document.hidden && isInitialized) refreshTunnels();
        }, 3000);

        // Continuous Heartbeat: keeps PyTunnel alive while dashboard tab is open
        const sendHeartbeat = () => {
            if (csrfToken) {
                fetch("/api/heartbeat", {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        "x-pytunnel-token": csrfToken,
                    },
                    keepalive: true,
                }).catch(() => {});
            }
        };
        sendHeartbeat();
        setInterval(sendHeartbeat, 5000);
        document.addEventListener("visibilitychange", () => {
            if (document.visibilityState === "visible") sendHeartbeat();
        });
    }

    function updateEngineStatus(engineInfo) {
        if (!engineInfo) return;
        if (engineInfo.downloading) {
            dom.engineStatusText.textContent = t("engine.downloading", { percent: engineInfo.percent });
        } else if (engineInfo.ready) {
            dom.engineStatusText.textContent = t("engine.ready", { version: engineInfo.version });
        } else {
            dom.engineStatusText.textContent = t("engine.missing");
        }
    }

    // Input Parsing & Validation
    let parseTimeout = null;
    function handleTargetInput() {
        clearTimeout(parseTimeout);
        const val = dom.targetInput.value.trim();
        if (!val) {
            dom.targetInput.classList.remove("invalid");
            dom.feedbackText.textContent = "";
            dom.btnSubmitLaunch.disabled = true;
            return;
        }

        parseTimeout = setTimeout(async () => {
            try {
                const res = await api("/api/parse", {
                    method: "POST",
                    body: JSON.stringify({ raw_input: val })
                });
                if (res.valid) {
                    dom.targetInput.classList.remove("invalid");
                    dom.parseFeedback.className = "feedback-bar";
                    dom.feedbackText.textContent = res.description;
                    dom.btnSubmitLaunch.disabled = false;
                } else {
                    dom.targetInput.classList.add("invalid");
                    dom.parseFeedback.className = "feedback-bar err";
                    dom.feedbackText.textContent = res.description;
                    dom.btnSubmitLaunch.disabled = true;
                }
            } catch (e) {
                // Keep current state
            }
        }, 200);
    }

    async function handleLaunchSubmit(e) {
        e.preventDefault();
        const inputVal = dom.targetInput.value.trim();
        if (!inputVal) return;

        dom.btnSubmitLaunch.disabled = true;
        const originalText = dom.btnSubmitLaunch.querySelector("span").textContent;
        dom.btnSubmitLaunch.querySelector("span").textContent = t("launch.submitting");

        try {
            const tunnel = await api("/api/tunnels", {
                method: "POST",
                body: JSON.stringify({
                    target_input: inputVal,
                    is_public: selectedMode === "public"
                })
            });
            showToast(t("toast.tunnel_online", { port: tunnel.port }));
            dom.targetInput.value = "";
            dom.feedbackText.textContent = "";
            await refreshTunnels();
            openDrawer(tunnel.port);
        } catch (err) {
            showToast(err.message);
        } finally {
            dom.btnSubmitLaunch.disabled = false;
            dom.btnSubmitLaunch.querySelector("span").textContent = originalText;
        }
    }

    async function refreshTunnels() {
        try {
            tunnels = await api("/api/tunnels");
            renderTunnels();
            if (activePort) {
                const cur = tunnels.find(x => x.port === activePort);
                if (cur) updateDrawerContent(cur);
            }
        } catch (err) {
            // Handled
        }
    }

    function renderTunnels() {
        dom.tunnelCountPill.textContent = t("list.count", { count: tunnels.length });

        if (tunnels.length === 0) {
            dom.tunnelsGrid.innerHTML = `
                <div class="empty-hero">
                    <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="margin-bottom:0.75rem; opacity:0.6;"><circle cx="12" cy="12" r="10"/><path d="m4.93 4.93 4.24 4.24"/><path d="m14.83 9.17 4.24-4.24"/><path d="m14.83 14.83 4.24 4.24"/><path d="m9.17 14.83-4.24 4.24"/></svg>
                    <p style="font-size:0.875rem;">${escapeHtml(t("list.empty"))}</p>
                </div>
            `;
            return;
        }

        dom.tunnelsGrid.innerHTML = tunnels.map(tun => {
            const isStarting = tun.state === "STARTING";
            const shareUrl = tun.full_tunnel_url || "";
            const modeClass = tun.is_public ? "public" : "protected";
            const modeText = tun.is_public ? t("mode.public") : `${t("card.access_code")}: ${escapeHtml(tun.access_code)}`;
            const uptime = formatUptime(tun.uptime_seconds);

            return `
                <article class="tunnel-card ${isStarting ? 'starting' : ''}" data-port="${tun.port}">
                    <div class="tunnel-card-header">
                        <div class="tunnel-card-title">
                            <span class="port-badge">PORT ${tun.port}</span>
                            <span class="mode-badge ${modeClass}">${modeText}</span>
                        </div>
                        <span style="font-size:0.75rem; color:var(--text-muted);">${escapeHtml(t(`state.${tun.state}`))}${isStarting ? '…' : ''}</span>
                    </div>

                    <div class="link-box">
                        <a href="${escapeHtml(shareUrl)}" target="_blank" class="link-url">
                            ${shareUrl ? escapeHtml(shareUrl) : escapeHtml(t("card.waiting_url"))}
                        </a>
                        <div class="link-actions">
                            <button class="btn btn-icon-sm copy-btn" data-url="${escapeHtml(shareUrl)}" title="${escapeHtml(t("action.copy"))}">
                                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>
                            </button>
                        </div>
                    </div>

                    <div class="metrics-row">
                        <div class="metric-col">
                            <span>${escapeHtml(t("card.requests"))}</span>
                            <strong>${tun.request_count}</strong>
                        </div>
                        <div class="metric-col">
                            <span>${escapeHtml(t("card.online"))}</span>
                            <strong style="color:var(--neon-emerald);">${tun.active_visitors_count}</strong>
                        </div>
                        <div class="metric-col">
                            <span>${escapeHtml(t("card.uptime"))}</span>
                            <strong>${uptime}</strong>
                        </div>
                    </div>
                </article>
            `;
        }).join("");

        // Attach Card Click Events
        dom.tunnelsGrid.querySelectorAll(".tunnel-card").forEach(el => {
            el.addEventListener("click", () => {
                const port = parseInt(el.getAttribute("data-port"), 10);
                openDrawer(port);
            });
        });
        dom.tunnelsGrid.querySelectorAll(".link-url").forEach(el => {
            el.addEventListener("click", (e) => e.stopPropagation());
        });
        dom.tunnelsGrid.querySelectorAll(".copy-btn").forEach(el => {
            el.addEventListener("click", (e) => {
                e.stopPropagation();
                copyToClipboard(el.getAttribute("data-url"));
            });
        });
    }

    function formatUptime(seconds) {
        if (!seconds) return "0s";
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const s = seconds % 60;
        if (h > 0) return `${h}h ${m}m`;
        if (m > 0) return `${m}m ${s}s`;
        return `${s}s`;
    }

    // Drawer Controller
    function openDrawer(port) {
        activePort = port;
        const tun = tunnels.find(x => x.port === port);
        if (!tun) return;

        dom.drawerTitle.textContent = t("drawer.title", { port: tun.port });
        dom.drawerOrigin.textContent = `127.0.0.1:${tun.port}${tun.path || ''}`;
        updateDrawerContent(tun);

        dom.drawerBackdrop.classList.add("open");
        dom.drawerPanel.classList.add("open");

        refreshTrafficLogs();
        clearInterval(trafficTimer);
        trafficTimer = setInterval(() => {
            if (activePort && !document.hidden) refreshTrafficLogs();
        }, 2000);
    }

    function closeDrawer() {
        activePort = null;
        clearInterval(trafficTimer);
        dom.drawerBackdrop.classList.remove("open");
        dom.drawerPanel.classList.remove("open");
    }

    function updateDrawerContent(tun) {
        if (!tun) tun = tunnels.find(x => x.port === activePort);
        if (!tun) return;

        dom.drawerTitle.textContent = t("drawer.title", { port: tun.port });
        dom.drawerLinkUrl.textContent = tun.full_tunnel_url || "-";
        dom.btnOpenDrawerLink.href = tun.full_tunnel_url || "#";
        dom.btnCopyDrawerLink.onclick = () => copyToClipboard(tun.full_tunnel_url);

        // QR Code & Short Link handling
        const bestShareUrl = tun.short_url || tun.full_tunnel_url || "";
        if (bestShareUrl && dom.drawerQrImg) {
            dom.drawerQrImg.src = `https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=${encodeURIComponent(bestShareUrl)}`;
            dom.btnCopyQrLink.onclick = () => copyToClipboard(bestShareUrl);
        }

        if (tun.short_url) {
            dom.drawerShortResult.style.display = "block";
            dom.drawerShortUrl.textContent = tun.short_url;
            dom.btnOpenShortUrl.href = tun.short_url;
            dom.btnCopyShortUrl.onclick = () => copyToClipboard(tun.short_url);
        } else {
            dom.drawerShortResult.style.display = "none";
        }

        dom.drawerMetricReq.textContent = tun.request_count;
        dom.drawerMetricOnline.textContent = tun.active_visitors_count;
        dom.drawerMetricUptime.textContent = formatUptime(tun.uptime_seconds);
        dom.drawerMetricBlocked.textContent = tun.blocked_count;

        dom.drawerPid.textContent = tun.pid || "-";
        dom.drawerProxyPort.textContent = tun.proxy_port || "-";
        dom.drawerJobStatus.textContent = tun.job_object ? t("process.job_on") : t("process.job_off");

        // Security controls
        if (tun.is_public) {
            dom.btnSwitchPublic.className = "btn btn-primary";
            dom.btnSwitchProtected.className = "btn";
            dom.drawerCodeSection.style.display = "none";
        } else {
            dom.btnSwitchPublic.className = "btn";
            dom.btnSwitchProtected.className = "btn btn-primary";
            dom.drawerCodeSection.style.display = "block";
            dom.drawerDisplayCode.textContent = tun.access_code || "----";
        }
    }

    async function refreshTrafficLogs() {
        if (!activePort) return;
        try {
            const data = await api(`/api/tunnels/${activePort}/logs`);
            const logs = data.logs || [];
            if (logs.length === 0) {
                dom.trafficTbody.innerHTML = `<tr><td colspan="6" style="text-align:center; padding:2rem; color:var(--text-subtle);">${escapeHtml(t("traffic.empty"))}</td></tr>`;
                return;
            }

            dom.trafficTbody.innerHTML = logs.map(l => {
                const isErr = l.status >= 400;
                let badgeClass = "auth-badge ok";
                if (l.auth_status === "auth.upstream_error" || l.status >= 500) {
                    badgeClass = "auth-badge error";
                } else if (l.auth_status === "auth.gate" || l.auth_status === "auth.locked" || l.auth_status === "auth.rate_limited" || l.status === 401 || l.status === 403 || l.status === 429) {
                    badgeClass = "auth-badge warn";
                } else if (l.auth_status === "auth.login_fail") {
                    badgeClass = "auth-badge error";
                }
                return `
                    <tr>
                        <td style="color:var(--text-muted);">${escapeHtml(l.time)}</td>
                        <td>${escapeHtml(l.ip)}</td>
                        <td style="font-weight:700;">${escapeHtml(l.method)}</td>
                        <td style="color:${isErr ? 'var(--neon-rose)' : 'var(--neon-emerald)'}; font-weight:700;">${l.status}</td>
                        <td style="color:var(--text-muted);">${l.latency_ms}ms</td>
                        <td><span class="${badgeClass}">${escapeHtml(t(l.auth_status))}</span></td>
                    </tr>
                `;
            }).join("");
        } catch (e) {
            // Ignore
        }
    }

    // Bind Events
    function bindEvents() {
        dom.targetInput.addEventListener("input", handleTargetInput);
        dom.launcherForm.addEventListener("submit", handleLaunchSubmit);

        dom.btnModeProtected.addEventListener("click", () => {
            selectedMode = "protected";
            dom.btnModeProtected.classList.add("active");
            dom.btnModePublic.classList.remove("active");
        });
        dom.btnModePublic.addEventListener("click", () => {
            selectedMode = "public";
            dom.btnModePublic.classList.add("active");
            dom.btnModeProtected.classList.remove("active");
        });

        // Theme & Lang
        dom.btnToggleTheme.addEventListener("click", () => {
            isLight = !isLight;
            localStorage.setItem("pytunnel_theme", isLight ? "light" : "dark");
            applyTheme();
        });
        dom.btnToggleLang.addEventListener("click", () => {
            lang = lang === "vi" ? "en" : "vi";
            localStorage.setItem("pytunnel_lang", lang);
            applyI18n();
            handleTargetInput();
        });

        // Drawer Controls
        dom.btnDrawerClose.addEventListener("click", closeDrawer);
        dom.drawerBackdrop.addEventListener("click", closeDrawer);
        dom.btnRefreshTraffic.addEventListener("click", refreshTrafficLogs);

        if (dom.btnCreateShort) {
            dom.btnCreateShort.addEventListener("click", async () => {
                if (!activePort) return;
                const alias = dom.drawerShortInput.value.trim();
                dom.btnCreateShort.disabled = true;
                try {
                    const res = await api(`/api/tunnels/${activePort}/shorten`, {
                        method: "POST",
                        body: JSON.stringify({ alias })
                    });
                    if (res.status === "ok") {
                        showToast(t("toast.short_created"));
                        await refreshTunnels();
                    } else {
                        const errMsg = res.error_code ? t(`error.shorten_${res.error_code}`) : res.message;
                        showToast(errMsg || t("toast.short_failed", { reason: "Error" }));
                    }
                } catch (err) {
                    showToast(t("toast.short_failed", { reason: err.message }));
                } finally {
                    dom.btnCreateShort.disabled = false;
                }
            });
        }

        dom.drawerTabBtns.forEach(btn => {
            btn.addEventListener("click", () => {
                const tab = btn.getAttribute("data-tab");
                dom.drawerTabBtns.forEach(b => b.classList.remove("active"));
                dom.drawerTabContents.forEach(c => c.style.display = "none");
                btn.classList.add("active");
                document.getElementById(`tab-${tab}`).style.display = "block";
                if (tab === "traffic") refreshTrafficLogs();
            });
        });

        // Mode Switching in Drawer (3-button safe prompt)
        dom.btnSwitchProtected.addEventListener("click", () => {
            const tun = tunnels.find(x => x.port === activePort);
            if (!tun || !tun.is_public) return;

            showModal(
                t("modal.protect.title"),
                t("modal.protect.body"),
                [
                    {
                        text: t("modal.protect.keep"),
                        primary: true,
                        action: async () => {
                            await api(`/api/tunnels/${activePort}/toggle-mode`, {
                                method: "POST",
                                body: JSON.stringify({ is_public: false, keep_sessions: true })
                            });
                            showToast(t("toast.mode_protected_keep"));
                            await refreshTunnels();
                        }
                    },
                    {
                        text: t("modal.protect.kick"),
                        danger: true,
                        action: async () => {
                            await api(`/api/tunnels/${activePort}/toggle-mode`, {
                                method: "POST",
                                body: JSON.stringify({ is_public: false, keep_sessions: false })
                            });
                            showToast(t("toast.mode_protected_kick"));
                            await refreshTunnels();
                        }
                    },
                    {
                        text: t("action.cancel"),
                        action: null
                    }
                ]
            );
        });

        dom.btnSwitchPublic.addEventListener("click", async () => {
            const tun = tunnels.find(x => x.port === activePort);
            if (!tun || tun.is_public) return;

            await api(`/api/tunnels/${activePort}/toggle-mode`, {
                method: "POST",
                body: JSON.stringify({ is_public: true, keep_sessions: true })
            });
            showToast(t("toast.mode_public"));
            await refreshTunnels();
        });

        // Rotate Code
        dom.btnCopyDrawerCode.addEventListener("click", () => {
            const tun = tunnels.find(x => x.port === activePort);
            if (tun) copyToClipboard(tun.access_code);
        });

        dom.btnRotateKeep.addEventListener("click", async () => {
            await api(`/api/tunnels/${activePort}/rotate-code`, {
                method: "POST",
                body: JSON.stringify({ revoke_all: false })
            });
            showToast(t("toast.rotated_keep"));
            await refreshTunnels();
        });

        dom.btnRotateKick.addEventListener("click", () => {
            showModal(
                t("modal.rotate_kick.title"),
                t("modal.rotate_kick.body"),
                [
                    {
                        text: t("modal.rotate_kick.title"),
                        danger: true,
                        action: async () => {
                            await api(`/api/tunnels/${activePort}/rotate-code`, {
                                method: "POST",
                                body: JSON.stringify({ revoke_all: true })
                            });
                            showToast(t("toast.rotated_kick"));
                            await refreshTunnels();
                        }
                    },
                    {
                        text: t("action.cancel"),
                        action: null
                    }
                ]
            );
        });

        // Stop Tunnel
        dom.btnDrawerStop.addEventListener("click", () => {
            const port = activePort;
            showModal(
                t("modal.stop.title", { port }),
                t("modal.stop.body"),
                [
                    {
                        text: t("action.stop"),
                        danger: true,
                        action: async () => {
                            await api(`/api/tunnels/${port}/stop`, { method: "POST" });
                            showToast(t("toast.tunnel_stopped", { port }));
                            closeDrawer();
                            await refreshTunnels();
                        }
                    },
                    {
                        text: t("action.cancel"),
                        action: null
                    }
                ]
            );
        });

        // Kill All Tunnels
        dom.btnKillAll.addEventListener("click", () => {
            showModal(
                t("modal.kill_all.title"),
                t("modal.kill_all.body"),
                [
                    {
                        text: t("header.kill_all"),
                        danger: true,
                        action: async () => {
                            const res = await api("/api/kill-all", { method: "POST" });
                            showToast(t("toast.killed_all", { count: res.killed_count }));
                            closeDrawer();
                            await refreshTunnels();
                        }
                    },
                    {
                        text: t("action.cancel"),
                        action: null
                    }
                ]
            );
        });

        if (dom.btnExitApp) {
            dom.btnExitApp.addEventListener("click", () => {
                showModal(
                    t("modal.exit.title"),
                    t("modal.exit.body"),
                    [
                        {
                            text: t("modal.exit.confirm"),
                            danger: true,
                            action: async () => {
                                closeDrawer();
                                if (pollTimer) clearInterval(pollTimer);
                                if (trafficTimer) clearInterval(trafficTimer);

                                playLiquidGoodbye(1800, async () => {
                                    try {
                                        await api("/api/shutdown", { method: "POST" });
                                    } catch (e) {
                                        // Server closes process rapidly
                                    }

                                    // Attempt browser tab closure
                                    setTimeout(() => {
                                        try {
                                            window.close();
                                            window.open("", "_self");
                                            window.close();
                                        } catch (e) {}
                                    }, 400);
                                });
                            }
                        },
                        {
                            text: t("action.cancel"),
                            action: null
                        }
                    ]
                );
            });
        }

        dom.modalBackdrop.addEventListener("click", (e) => {
            if (e.target === dom.modalBackdrop) closeModal();
        });

        initMissionControlTerminal();
    }

    // ==========================================
    // MISSION CONTROL: REALTIME TERMINAL MONITOR
    // ==========================================
    function initMissionControlTerminal() {
        let terminalSourceFilter = "ALL";
        let cachedLogs = [];

        const terminalCard = document.getElementById("cyber-terminal-card");
        const terminalScreen = document.getElementById("terminal-screen");
        const terminalCountBadge = document.getElementById("terminal-count-badge");
        const terminalFpsHud = document.getElementById("terminal-fps-hud");
        const btnClearTerminal = document.getElementById("btn-clear-terminal");
        const btnMaximizeTerminal = document.getElementById("btn-maximize-terminal");
        const iconTerminalSize = document.getElementById("icon-terminal-size");
        const dotTerminalExpand = document.getElementById("dot-terminal-expand");
        const dotTerminalClose = document.getElementById("dot-terminal-close");
        const consoleFilterBtns = document.querySelectorAll(".console-filter-btn");

        function toggleMaximize() {
            if (!terminalCard) return;
            const isMax = terminalCard.classList.toggle("maximized");
            if (btnMaximizeTerminal) {
                btnMaximizeTerminal.title = isMax ? "Thu nhỏ đài quan sát (Esc)" : "Phóng to toàn màn hình";
            }
            if (iconTerminalSize) {
                if (isMax) {
                    iconTerminalSize.innerHTML = `<path d="M4 14h6v6M20 10h-6V4M14 10l7-7M3 21l7-7"/>`;
                } else {
                    iconTerminalSize.innerHTML = `<path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/>`;
                }
            }
            if (terminalScreen) {
                terminalScreen.scrollTop = terminalScreen.scrollHeight;
            }
        }

        if (btnMaximizeTerminal) btnMaximizeTerminal.addEventListener("click", toggleMaximize);
        if (dotTerminalExpand) dotTerminalExpand.addEventListener("click", toggleMaximize);
        if (dotTerminalClose) {
            dotTerminalClose.addEventListener("click", () => {
                if (terminalCard && terminalCard.classList.contains("maximized")) {
                    toggleMaximize();
                }
            });
        }

        document.addEventListener("keydown", (e) => {
            if (e.key === "Escape" && terminalCard && terminalCard.classList.contains("maximized")) {
                toggleMaximize();
            }
        });

        consoleFilterBtns.forEach(btn => {
            btn.addEventListener("click", () => {
                consoleFilterBtns.forEach(b => b.classList.remove("active"));
                btn.classList.add("active");
                terminalSourceFilter = btn.dataset.source;
                renderTerminalLogs();
            });
        });

        if (btnClearTerminal) {
            btnClearTerminal.addEventListener("click", async () => {
                try {
                    await fetch("/api/terminal-logs/clear", { method: "POST" });
                    cachedLogs = [];
                    renderTerminalLogs();
                } catch (e) {}
            });
        }

        async function pollTerminalLogs() {
            try {
                const res = await fetch("/api/terminal-logs");
                if (res.ok) {
                    const data = await res.json();
                    if (data.status === "ok" && Array.isArray(data.logs)) {
                        cachedLogs = data.logs;

                        // Telemetry HUD update for active player FPS
                        if (terminalFpsHud) {
                            const latestFps = [...cachedLogs].reverse().find(l => l.level === "FPS" || (l.message && l.message.includes("FPS:")));
                            if (latestFps) {
                                terminalFpsHud.style.display = "inline-flex";
                                const cleanMsg = latestFps.message.replace(/\[Telemetry\]\s*/i, "").trim();
                                terminalFpsHud.textContent = `🎮 ${cleanMsg}`;
                            }
                        }

                        renderTerminalLogs();
                    }
                }
            } catch (e) {}
        }

        function getTagClass(source, level) {
            if (level === "ERROR" || level === "FAIL") return "tag-error";
            if (level === "FPS") return "tag-fps";
            const s = (source || "").toUpperCase();
            if (s.includes("NET-SERVER")) return "tag-net-server";
            if (s.includes("PVP-SOCKET")) return "tag-pvp-socket";
            if (s.includes("PVP-ENGINE") || s.includes("MATCH")) return "tag-pvp-engine";
            if (s.includes("KUROSHIRO")) return "tag-kuroshiro";
            return "tag-system";
        }

        function renderTerminalLogs() {
            if (!terminalScreen) return;
            const filtered = cachedLogs.filter(log => {
                if (terminalSourceFilter === "ALL") return true;
                if (terminalSourceFilter === "FPS") return log.level === "FPS" || (log.message && log.message.includes("FPS:"));
                return (log.source || "").toUpperCase().includes(terminalSourceFilter);
            });

            if (terminalCountBadge) {
                terminalCountBadge.textContent = `${filtered.length} sự kiện`;
            }

            if (filtered.length === 0) {
                terminalScreen.innerHTML = `<div style="display:flex; align-items:center; justify-content:center; height:100%; min-height:180px; color:var(--text-muted); font-size:0.8125rem; gap:0.6rem;">
                    <span style="display:inline-block; width:8px; height:8px; border-radius:50%; background:var(--neon-emerald); box-shadow:0 0 10px var(--neon-emerald);"></span>
                    Hệ thống sẵn sàng. Đang chờ gói tin hoặc sự kiện từ Game Server...
                </div>`;
                return;
            }

            const isScrolledToBottom = terminalScreen.scrollHeight - terminalScreen.clientHeight <= terminalScreen.scrollTop + 60;

            terminalScreen.innerHTML = filtered.map(log => {
                const tagClass = getTagClass(log.source, log.level);
                return `<div class="terminal-line">
                    <span class="terminal-time">[${escapeHtml(log.time || "")}]</span>
                    <span class="terminal-tag ${tagClass}">${escapeHtml(log.source || "SERVER")}</span>
                    <span class="terminal-msg">${escapeHtml(log.message || "")}</span>
                </div>`;
            }).join("");

            if (isScrolledToBottom) {
                terminalScreen.scrollTop = terminalScreen.scrollHeight;
            }
        }

        setInterval(pollTerminalLogs, 750);
        pollTerminalLogs();
    }


    // Launch
    document.addEventListener("DOMContentLoaded", init);
})();
