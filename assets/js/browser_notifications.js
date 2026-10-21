// Permission transitions are declared by Foreman.NotificationPermission.
const ledgerKey = "foreman:notifications:v1"
const kindLabels = {decision: "Decision", push: "Push", open_pr: "Open PR", merge: "Merge", session_waiting: "Session waiting"}

// Web Locks serializes all same-origin tabs, including background tabs. A durable
// ledger survives navigation/reconnect and avoids heartbeat/election expiry races.
async function deliver(requests) {
  if (!navigator.locks || typeof Notification === "undefined") return
  await navigator.locks.request(ledgerKey, () => {
    const stored = localStorage.getItem(ledgerKey)
    const ledger = stored ? JSON.parse(stored) : {seen: {}}
    for (const request of requests) {
      if (ledger.seen[request.id]) continue
      // Claim durably before the OS side effect; if storage is unavailable, fail
      // closed rather than duplicating a toast on every reconciliation tick.
      ledger.seen[request.id] = true
      localStorage.setItem(ledgerKey, JSON.stringify(ledger))
      // First visit establishes a baseline, rather than toasting the old inbox.
      if (stored && Notification.permission === "granted") {
        let notification
        try {
          notification = new Notification(request.title || `${kindLabels[request.kind] || request.kind} · ${request.ticket}`, {
            body: request.body || "",
            tag: `foreman-request-${request.id}`
          })
        } catch (error) {
          delete ledger.seen[request.id]
          localStorage.setItem(ledgerKey, JSON.stringify(ledger))
          throw error
        }
        notification.onclick = () => {
          window.focus()
          document.querySelector("#needs-you-link")?.click()
          notification.close()
        }
      }
    }
    // Persist an empty baseline too.
    if (!stored) localStorage.setItem(ledgerKey, JSON.stringify(ledger))
  })
}
export const BrowserNotifications = {
  mounted() {
    this.machine = JSON.parse(this.el.dataset.machine)
    this.state = "unavailable"
    this.button = this.el.querySelector("button")
    this.observe = () => this.transition(
      typeof Notification !== "undefined" && navigator.locks ? Notification.permission : "unavailable"
    )
    this.click = () => this.transition("click")
    this.button.addEventListener("click", this.click)
    window.addEventListener("focus", this.observe)
    this.observe()
    this.handleEvent("notification_snapshot", ({requests}) => this.receive(requests))
    this.pushEvent("notification_sync", {}, ({requests}) => this.receive(requests))
    // Permission changes in browser settings need no reload or server round trip.
    navigator.permissions?.query({name: "notifications"}).then(status => {
      if (this.disposed) return
      this.permissionStatus = status
      status.addEventListener("change", this.observe)
    }).catch(() => {})
  },
  receive(requests) {
    this.observe()
    // Storage/lock/Notification failures must never affect the in-app inbox.
    deliver(requests).catch(() => {})
  },
  reconnected() {
    this.pushEvent("notification_sync", {}, ({requests}) => this.receive(requests))
  },
  transition(event) {
    const next = this.machine[this.state][event]
    this.state = next.state
    this.button.hidden = this.state !== "default"
    this.el.hidden = this.button.hidden
    if (next.prompt) {
      // Must stay synchronous with the user's gesture, not a server round trip.
      const settled = () => this.transition(Notification.permission === "default" ? "dismissed" : Notification.permission)
      Notification.requestPermission().then(settled, settled)
    }
  },
  destroyed() {
    this.disposed = true
    this.permissionStatus?.removeEventListener("change", this.observe)
    this.button.removeEventListener("click", this.click)
    window.removeEventListener("focus", this.observe)
  }
}
