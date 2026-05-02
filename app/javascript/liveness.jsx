// app/javascript/liveness.jsx
// Separate esbuild entry point — only loaded on the identity submission form page.
// Exports window.BonidLiveness.mount() / .unmount() for the Stimulus controller.

import React, { useState, useEffect, useCallback, useRef } from "react"
import { createRoot } from "react-dom/client"
import { FaceLivenessDetector } from "@aws-amplify/ui-react-liveness"
import { ThemeProvider } from "@aws-amplify/ui-react"
import { Amplify } from "aws-amplify"
import "@aws-amplify/ui-react/styles.css"

// ── Human-Friendly Error Messages ──
// Converts raw AWS / technical errors to user-friendly messages
function friendlyError(raw) {
  if (!raw || typeof raw !== "string") return "Gen yon pwoblèm. Tanpri eseye ankò."

  const lower = raw.toLowerCase()

  if (lower.includes("deserialization") || lower.includes("$response"))
    return "Nou pa t kapab trete verifikasyon an. Tanpri eseye ankò ak pi bon limyè."
  if (lower.includes("session not found") || lower.includes("expired"))
    return "Sesyon ou an ekspire. Tanpri kòmanse yon nouvo verifikasyon."
  if (lower.includes("timeout") || lower.includes("timed out"))
    return "Verifikasyon an pran twòp tan. Tanpri eseye ankò epi pa bouje."
  if (lower.includes("camera") || lower.includes("permission") || lower.includes("notallowederror"))
    return "Aksè kamera obligatwa. Tanpri pèmèt aksè kamera epi eseye ankò."
  if (lower.includes("network") || lower.includes("fetch") || lower.includes("failed to fetch"))
    return "Pwoblèm koneksyon. Tcheke entènèt ou epi eseye ankò."
  if (lower.includes("face") && lower.includes("detect"))
    return "Nou pa t kapab detekte figi ou. Asire ou figi ou nan mitan epi gen bon limyè."
  if (lower.includes("too many"))
    return "Twòp tantativ. Tanpri tann kèk minit anvan ou eseye ankò."
  if (lower.includes("not supported"))
    return "Navigatè ou pa sipòte fonksyon sa a. Tanpri itilize Chrome oswa Safari."
  if (lower.includes("confidence") || lower.includes("threshold"))
    return "Verifikasyon pa rive nan konfyans nesesè a. Eseye ak pi bon limyè epi pa bouje."
  if (lower.includes("constraint") || lower.includes("invalid session"))
    return "Sesyon ou ekspire (limit 3 minit). Peze \"Eseye ankò\" pou kòmanse yon nouvo verifikasyon."

  // If it looks technical (contains error codes, stack traces, etc.), replace entirely
  if (raw.includes("{") || raw.includes("Error:") || raw.length > 120)
    return "Verifikasyon pa t kapab fini. Tanpri eseye ankò."

  return raw
}

// Detect timeout/network errors for low-bandwidth fallback tracking
function isTimeoutOrNetworkError(raw) {
  if (!raw || typeof raw !== "string") return false
  const lower = raw.toLowerCase()
  return lower.includes("timeout") || lower.includes("timed out") ||
         lower.includes("network") || lower.includes("fetch") ||
         lower.includes("failed to fetch") || lower.includes("aborted")
}

// Detect camera permission denied — distinct from "camera not found"
// (hardware) or "camera busy" (another app holds it). When this fires
// the browser will not re-prompt without a manual settings change, so
// "try again" doesn't help. We route the citizen to the manual-selfie
// fallback instead of leaving them stuck on an error screen.
function isCameraPermissionError(raw) {
  if (!raw || typeof raw !== "string") return false
  const lower = raw.toLowerCase()
  return lower.includes("notallowederror") ||
         lower.includes("permission denied") ||
         lower.includes("permissiondenied") ||
         lower.includes("permission_denied") ||
         (lower.includes("camera") && (lower.includes("denied") || lower.includes("blocked") || lower.includes("not allowed"))) ||
         (lower.includes("getusermedia") && lower.includes("denied"))
}

// BonID-themed Amplify theme for FaceLivenessDetector
const bonidTheme = {
  name: "bonid-liveness",
  tokens: {
    colors: {
      brand: {
        primary: {
          10: { value: "#e6eaf5" },
          20: { value: "#b3bfe0" },
          40: { value: "#6680c0" },
          60: { value: "#1a40a0" },
          80: { value: "#00209F" },
          90: { value: "#001a80" },
          100: { value: "#001466" },
        },
      },
    },
    components: {
      button: {
        primary: {
          backgroundColor: { value: "#00209F" },
          _hover: { backgroundColor: { value: "#001a80" } },
          _active: { backgroundColor: { value: "#001466" } },
          borderRadius: { value: "50px" },
          paddingInline: { value: "2rem" },
          fontWeight: { value: "600" },
        },
      },
      heading: {
        color: { value: "#1a1a2e" },
        fontFamily: { value: "'Montserrat', sans-serif" },
        fontWeight: { value: "700" },
      },
    },
    fonts: {
      default: {
        variable: { value: "'Montserrat', sans-serif" },
        static: { value: "'Montserrat', sans-serif" },
      },
    },
    radii: {
      small: { value: "8px" },
      medium: { value: "12px" },
      large: { value: "16px" },
    },
  },
}

// Dark mode variant — uses ThemeProvider tokens so Amplify manages its own
// internal backgrounds/text colors without manual CSS overrides on canvas/video.
const bonidDarkTheme = {
  name: "bonid-liveness-dark",
  tokens: {
    ...bonidTheme.tokens,
    colors: {
      ...bonidTheme.tokens.colors,
      background: {
        primary: { value: "#0a0f1f" },
        secondary: { value: "#111730" },
      },
      font: {
        primary: { value: "#ffffff" },
        secondary: { value: "#d0d4e0" },
      },
    },
    components: {
      ...bonidTheme.tokens.components,
      heading: {
        color: { value: "#ffffff" },
        fontFamily: { value: "'Montserrat', sans-serif" },
        fontWeight: { value: "700" },
      },
    },
  },
}

// ── Centered Icon + Text Layout (reusable) ──
const centeredStyle = {
  display: "flex", flexDirection: "column", alignItems: "center",
  justifyContent: "center", textAlign: "center",
  padding: "clamp(2rem, 6vw, 3rem) 1rem",
  fontFamily: "'Montserrat', sans-serif",
  minHeight: "280px",
  width: "100%",
}

const iconCircle = (bg, iconClass, iconColor) => (
  <div style={{
    width: "60px", height: "60px", borderRadius: "50%",
    background: bg,
    display: "flex", alignItems: "center", justifyContent: "center",
    margin: "0 auto 1rem"
  }}>
    <i className={iconClass} style={{ fontSize: "1.6rem", color: iconColor }}></i>
  </div>
)

// ── Progressive Verifying Screen ──
function VerifyingScreen() {
  const [step, setStep] = useState(0)

  const messages = [
    { icon: "ri-shield-check-line", text: "Yon moman tanpri... N'ap verifye idantite ou." },
    { icon: "ri-user-smile-line", text: "Siksè! Ou se yon moun tout bon." },
    { icon: "ri-scan-2-line", text: "Kounye a, n'ap konpare figi ou ak foto ki sou dokiman an." },
  ]

  useEffect(() => {
    const t1 = setTimeout(() => setStep(1), 2500)  // Show processing for 2.5s
    const t2 = setTimeout(() => setStep(2), 4500)  // Show success for 2s before comparing
    return () => { clearTimeout(t1); clearTimeout(t2) }
  }, [])

  const msg = messages[step]

  return (
    <div style={{ ...centeredStyle, background: "#0a0f1f" }}>
      {iconCircle("rgba(255,255,255,0.08)", msg.icon, "#7b8fff")}
      <div className="spinner-border" role="status" style={{
        width: "1.35rem", height: "1.35rem", borderWidth: "2px",
        color: "#7b8fff"
      }}>
        <span className="visually-hidden">Ap verifye...</span>
      </div>
      <p style={{
        fontSize: "clamp(0.82rem, 2.5vw, 0.9rem)", color: "#ffffff",
        marginTop: "0.85rem", marginBottom: 0, fontWeight: 500,
        transition: "opacity 0.3s ease"
      }}>
        {msg.text}
      </p>
    </div>
  )
}

// ── Success Screen ──
// Bridge state shown after AWS Liveness passes but BEFORE face_compare
// runs. Liveness only confirms "real human face in front of the camera"
// — it does not compare to the ID photo. Claiming "matche ak dokiman"
// here was misleading and contradicted the mismatch error that fires
// 2 seconds later. Now reads as a continuation, not a final verdict.
function SuccessScreen() {
  return (
    <div style={{ ...centeredStyle, background: "#0a0f1f" }}>
      {iconCircle("rgba(123,143,255,0.15)", "ri-loader-4-line spin", "#7b8fff")}
      <p style={{
        fontSize: "clamp(0.9rem, 3vw, 1rem)", fontWeight: 700,
        color: "#ffffff", marginBottom: "0.3rem"
      }}>
        Verifikasyon Figi Fini
      </p>
      <p style={{
        fontSize: "clamp(0.78rem, 2.3vw, 0.85rem)",
        color: "#d0d4e0", margin: 0
      }}>
        N ap konpare figi ou ak foto sou dokiman ou…
      </p>
    </div>
  )
}

// ── Error Screen ──
function ErrorScreen({ message, onRetry }) {
  return (
    <div style={{ ...centeredStyle, background: "#0a0f1f" }}>
      {iconCircle("rgba(220,53,69,0.15)", "ri-error-warning-line", "#f87171")}
      <p style={{
        fontSize: "clamp(0.85rem, 2.5vw, 0.92rem)", fontWeight: 600,
        color: "#ffffff", marginBottom: "0.35rem"
      }}>
        Verifikasyon echwe
      </p>
      <p style={{
        fontSize: "clamp(0.75rem, 2.2vw, 0.82rem)", color: "#d0d4e0",
        lineHeight: 1.5, marginBottom: "1.25rem",
        padding: "0 0.5rem", maxWidth: "340px"
      }}>
        {message}
      </p>
      <button
        type="button"
        className="btn btn-outline-light btn-sm rounded-pill px-4"
        onClick={onRetry}
        style={{
          fontSize: "clamp(0.8rem, 2.5vw, 0.875rem)",
          fontFamily: "'Montserrat', sans-serif", fontWeight: 600
        }}
      >
        <i className="ri-refresh-line me-1"></i> Eseye ankò
      </button>
    </div>
  )
}

// ── Low-Bandwidth Fallback Screen ──
// Shown after 2 consecutive timeout/network failures.
// Lets the citizen take a static selfie instead of the live video challenge.
// Submission is flagged for mandatory admin review.
function LowBandwidthScreen({ csrfToken, onComplete, onRetryNormal, reason = null, manualSelfieUrl = "/citizens/identity_submissions/manual_selfie" }) {
  const [uploading, setUploading] = useState(false)
  const [uploadError, setUploadError] = useState(null)
  const fileInputRef = useRef(null)

  const handleCapture = useCallback(async (e) => {
    const file = e.target.files?.[0]
    if (!file) return

    setUploading(true)
    setUploadError(null)

    try {
      const formData = new FormData()
      formData.append("selfie", file)
      formData.append("low_bandwidth_mode", "true")

      const resp = await fetch(manualSelfieUrl, {
        method: "POST",
        headers: { "X-CSRF-Token": csrfToken },
        credentials: "same-origin",
        body: formData
      })

      const data = await resp.json()
      if (resp.ok && data.blob_signed_id) {
        onComplete({
          passed: true,
          blob_signed_id: data.blob_signed_id,
          manual_selfie: true,
          needs_review: true
        })
      } else {
        setUploadError(data.error || "Telechajman echwe. Tanpri eseye ankò.")
      }
    } catch (err) {
      setUploadError("Erè koneksyon. Tanpri eseye ankò.")
    } finally {
      setUploading(false)
    }
  }, [csrfToken, onComplete])

  // Reason-aware intro copy: same manual-selfie destination, different
  // explanation depending on what tripped us into the fallback. Keeps the
  // citizen oriented instead of seeing a generic "Koneksyon fèb" header
  // when their actual blocker was a denied camera permission.
  const isCameraDenied = reason === "camera_denied"
  const headerIconBg   = isCameraDenied ? "#fee2e2" : "#fff3e6"
  const headerIconName = isCameraDenied ? "ri-camera-off-line" : "ri-wifi-off-line"
  const headerIconColor = isCameraDenied ? "#dc2626" : "#e67e22"
  const headerTitle = isCameraDenied
    ? "Kamera bloke"
    : "Koneksyon fèb"
  const headerSub = isCameraDenied
    ? "Nou pa kapab itilize kamera ou pou verifikasyon dirèk. Pran yon selfi klè olye — yon admin ap verifye li manyèlman."
    : "Koneksyon ou twò dousman pou verifikasyon an dirèk. Pran yon selfi klè olye — yon admin ap verifye li manyèlman."

  return (
    <div style={centeredStyle}>
      {iconCircle(headerIconBg, headerIconName, headerIconColor)}
      <p style={{
        fontSize: "clamp(0.9rem, 3vw, 1rem)", fontWeight: 700,
        color: "#333", marginBottom: "0.3rem"
      }}>
        {headerTitle}
      </p>
      <p style={{
        fontSize: "clamp(0.75rem, 2.2vw, 0.82rem)", color: "#888",
        lineHeight: 1.5, marginBottom: "1.25rem",
        padding: "0 0.5rem", maxWidth: "340px"
      }}>
        {headerSub}
      </p>

      {uploadError && (
        <p style={{ fontSize: "0.8rem", color: "#dc3545", marginBottom: "0.75rem" }}>
          {uploadError}
        </p>
      )}

      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        capture="user"
        style={{ display: "none" }}
        onChange={handleCapture}
      />

      <div style={{ display: "flex", flexDirection: "column", gap: "0.5rem", alignItems: "center" }}>
        <button
          type="button"
          className="btn btn-haitian-blue rounded-pill px-4 fw-bold"
          onClick={() => fileInputRef.current?.click()}
          disabled={uploading}
          style={{
            fontSize: "clamp(0.82rem, 2.5vw, 0.88rem)",
            fontFamily: "'Montserrat', sans-serif",
            padding: "0.55rem 1.5rem"
          }}
        >
          {uploading ? (
            <>
              <span className="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>
              Ap telechaje...
            </>
          ) : (
            <>
              <i className="ri-camera-line me-2"></i>
              Pran Selfi
            </>
          )}
        </button>

        <button
          type="button"
          className="btn btn-outline-secondary btn-sm rounded-pill px-3"
          onClick={onRetryNormal}
          style={{ fontSize: "0.78rem" }}
        >
          <i className="ri-refresh-line me-1"></i> Eseye verifikasyon an dirèk ankò
        </button>
      </div>
    </div>
  )
}

// Inject the GetReady fade-in keyframes once per page load. Inline so the
// liveness bundle stays self-contained — no application.css coupling.
const BONID_GET_READY_STYLES_ID = "bonid-get-ready-styles"
function ensureGetReadyStyles() {
  if (typeof document === "undefined") return
  if (document.getElementById(BONID_GET_READY_STYLES_ID)) return
  const style = document.createElement("style")
  style.id = BONID_GET_READY_STYLES_ID
  style.textContent = `
    @keyframes bonidGetReadyIn {
      from { opacity: 0; transform: translateY(6px); }
      to   { opacity: 1; transform: translateY(0); }
    }
  `
  document.head.appendChild(style)
}

// ── "Get Ready" Pre-Check Screen ──
function GetReadyScreen({ onReady, darkMode = false }) {
  // "warming" phase shows just the icon + a single line for ~700ms before
  // the full panel fades in. This gives the citizen a deliberate, calm
  // hand-off into the prep panel instead of the panel snapping in fully
  // populated the moment the AWS session finishes provisioning.
  const [warming, setWarming] = useState(true)
  useEffect(() => {
    ensureGetReadyStyles()
    const t = setTimeout(() => setWarming(false), 700)
    return () => clearTimeout(t)
  }, [])

  if (warming) {
    const wbg = darkMode ? "#0a0f1f" : "transparent"
    const wIconBg = darkMode ? "rgba(255,255,255,0.08)" : "#e6eaf5"
    const wIconColor = darkMode ? "#7b8fff" : "#00209F"
    const wTextColor = darkMode ? "#ffffff" : "#1a1a2e"
    return (
      <div style={{
        ...centeredStyle,
        background: wbg,
        minHeight: "min(580px, 90vh)",
        animation: "bonidGetReadyIn 0.22s ease-out both"
      }}>
        {iconCircle(wIconBg, "ri-camera-line", wIconColor)}
        <p style={{
          fontSize: "clamp(0.85rem, 2.6vw, 0.92rem)",
          color: wTextColor,
          marginTop: "0.85rem",
          marginBottom: 0,
          fontWeight: 600
        }}>
          Ap prepare verifikasyon ou...
        </p>
      </div>
    )
  }
  const tips = [
    { icon: "ri-sun-line", title: "Limyè ekran 100%", desc: "Mete limyè ekran ou pi wo posib pou pi bon rezilta" },
    { icon: "ri-lightbulb-line", title: "Fè fas ak yon sous limyè", desc: "Chita devan yon fenèt oswa yon lanp — evite limyè dèyè ou" },
    { icon: "ri-glasses-2-line", title: "Retire obstak", desc: "Retire linèt, chapo, oswa mask si posib" },
    { icon: "ri-smartphone-line", title: "Kenbe aparèy la estab", desc: "Kenbe aparèy la nan longè bra, figi ou nan mitan" },
  ]

  const bg = darkMode ? "#0a0f1f" : "transparent"
  const cardBg = darkMode ? "rgba(255,255,255,0.06)" : "#f8f9fc"
  const cardBorder = darkMode ? "1px solid rgba(255,255,255,0.08)" : "1px solid #eef0f6"
  const iconBg = darkMode ? "rgba(255,255,255,0.08)" : "#e6eaf5"
  const titleColor = darkMode ? "#ffffff" : "#1a1a2e"
  const subtitleColor = darkMode ? "#a0a8c0" : "#888"
  const tipTitleColor = darkMode ? "#e0e4f0" : "#333"
  const tipDescColor = darkMode ? "#8890a8" : "#888"

  return (
    <div className="bonid-get-ready" style={{
      fontFamily: "'Montserrat', sans-serif",
      padding: "clamp(1.2rem, 5vw, 2rem) clamp(1rem, 4vw, 1.5rem)",
      background: bg,
      // Reserve the eventual height up-front. The previous loading state has
      // minHeight: 280px; without this, the parent reflows from 280 → ~600px
      // when GetReadyScreen mounts and the citizen sees a visible jump.
      minHeight: "min(580px, 90vh)",
      // Fade in so the swap from the spinner feels intentional rather than
      // a flash. Keyframes are inlined just below the component definition
      // so this file stays self-contained.
      animation: "bonidGetReadyIn 0.28s ease-out both",
      willChange: "opacity, transform"
    }}>
      <div style={{ textAlign: "center", marginBottom: "clamp(1rem, 3vw, 1.5rem)" }}>
        {iconCircle(
          darkMode ? "rgba(255,255,255,0.08)" : "linear-gradient(135deg, #e6eaf5 0%, #d0d8f0 100%)",
          "ri-camera-line",
          darkMode ? "#7b8fff" : "#00209F"
        )}
        <h6 style={{
          fontWeight: 700, fontSize: "clamp(0.95rem, 3vw, 1.05rem)",
          color: titleColor, marginBottom: "0.25rem"
        }}>
          Prepare ou
        </h6>
        <p style={{
          fontSize: "clamp(0.75rem, 2.3vw, 0.82rem)", color: subtitleColor,
          margin: 0, lineHeight: 1.5
        }}>
          Prepare anviwònman ou pou pi bon rezilta
        </p>
      </div>

      <div style={{
        display: "flex", flexDirection: "column",
        gap: "clamp(0.6rem, 2vw, 0.75rem)",
        marginBottom: "clamp(1.2rem, 4vw, 1.75rem)"
      }}>
        {tips.map((tip, i) => (
          <div key={i} style={{
            display: "flex", alignItems: "center", gap: "clamp(0.65rem, 2.5vw, 0.85rem)",
            background: cardBg, borderRadius: "12px",
            padding: "clamp(0.65rem, 2.5vw, 0.85rem) clamp(0.75rem, 2.5vw, 1rem)",
            border: cardBorder
          }}>
            <div style={{
              width: "38px", height: "38px", borderRadius: "50%",
              background: iconBg,
              display: "flex", alignItems: "center", justifyContent: "center",
              flexShrink: 0
            }}>
              <i className={tip.icon} style={{ fontSize: "1rem", color: darkMode ? "#7b8fff" : "#00209F" }}></i>
            </div>
            <div style={{ minWidth: 0 }}>
              <div style={{
                fontSize: "clamp(0.78rem, 2.3vw, 0.84rem)",
                fontWeight: 600, color: tipTitleColor, lineHeight: 1.3
              }}>{tip.title}</div>
              <div style={{
                fontSize: "clamp(0.7rem, 2vw, 0.76rem)",
                color: tipDescColor, lineHeight: 1.4, marginTop: "1px"
              }}>{tip.desc}</div>
            </div>
          </div>
        ))}
      </div>

      <div style={{ textAlign: "center", display: "flex", flexDirection: "column", alignItems: "center", gap: "0.75rem" }}>
        <button
          type="button"
          className="btn btn-haitian-blue rounded-pill px-4 fw-bold"
          onClick={onReady}
          style={{
            fontSize: "clamp(0.85rem, 2.5vw, 0.92rem)",
            fontFamily: "'Montserrat', sans-serif",
            padding: "0.6rem 2rem", width: "100%", maxWidth: "280px"
          }}
        >
          <i className="ri-camera-line me-2"></i>
          Mwen Prè
        </button>
        <button
          type="button"
          onClick={() => {
            const wizard = document.querySelector("[data-controller*='wizard']")
            if (wizard) {
              const evt = new CustomEvent("click")
              const btn = document.createElement("button")
              btn.setAttribute("data-action", "wizard#goToStep")
              btn.setAttribute("data-step", "1")
              wizard.appendChild(btn)
              btn.click()
              btn.remove()
            }
          }}
          style={{
            fontSize: "clamp(0.78rem, 2.3vw, 0.84rem)",
            fontFamily: "'Montserrat', sans-serif",
            fontWeight: 500,
            padding: "0.5rem 1.5rem",
            background: "transparent",
            color: darkMode ? "#6b7280" : "#999",
            border: `1px solid ${darkMode ? "rgba(255,255,255,0.1)" : "#ddd"}`,
            borderRadius: "2rem",
            cursor: "pointer",
            width: "100%", maxWidth: "280px"
          }}
        >
          <i className="ri-arrow-left-line me-1"></i>
          Mwen Poko Pare
        </button>
      </div>

    </div>
  )
}

// ── Rate Limit Exceeded Screen ──
function RateLimitScreen({ resetTime }) {
  const [remaining, setRemaining] = useState(0)

  useEffect(() => {
    const update = () => {
      const left = Math.max(0, Math.ceil((resetTime - Date.now()) / 1000))
      setRemaining(left)
    }
    update()
    const timer = setInterval(update, 1000)
    return () => clearInterval(timer)
  }, [resetTime])

  const minutes = Math.floor(remaining / 60)
  const seconds = remaining % 60

  return (
    <div style={centeredStyle}>
      {iconCircle("#fff3e6", "ri-time-line", "#e67e22")}
      <p style={{
        fontSize: "clamp(0.82rem, 2.5vw, 0.9rem)", fontWeight: 600,
        color: "#333", marginBottom: "0.35rem"
      }}>
        Twòp tantativ
      </p>
      <p style={{
        fontSize: "clamp(0.75rem, 2.2vw, 0.82rem)", color: "#888",
        lineHeight: 1.5, marginBottom: "1rem", padding: "0 0.5rem"
      }}>
        Tanpri tann anvan ou eseye ankò. Sa ede pwoteje sekirite ou.
      </p>
      {remaining > 0 && (
        <div style={{
          display: "inline-flex", alignItems: "center", gap: "0.5rem",
          background: "#f8f9fc", borderRadius: "20px",
          padding: "0.4rem 1rem", border: "1px solid #e8ecf4"
        }}>
          <i className="ri-timer-line" style={{ color: "#00209F", fontSize: "0.95rem" }}></i>
          <span style={{
            fontSize: "clamp(0.82rem, 2.5vw, 0.9rem)",
            fontWeight: 600, color: "#00209F",
            fontVariantNumeric: "tabular-nums"
          }}>
            {minutes}:{seconds.toString().padStart(2, "0")}
          </span>
        </div>
      )}
    </div>
  )
}

// ── Main LivenessCheck Component ──
function LivenessCheck({
  csrfToken, region, identityPoolId, onComplete, onError, attemptTracker, darkMode = false,
  createSessionUrl = "/citizens/identity_submissions/liveness_session",
  resultsUrl = "/citizens/identity_submissions/liveness_results",
  statusUrl = "/citizens/identity_submissions/liveness_status",
  manualSelfieUrl = "/citizens/identity_submissions/manual_selfie"
}) {
  const [sessionId, setSessionId] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [ready, setReady] = useState(false)
  const [verifying, setVerifying] = useState(false)
  const [success, setSuccess] = useState(false)
  const [rateLimited, setRateLimited] = useState(false)
  const [rateLimitResetTime, setRateLimitResetTime] = useState(0)
  const [timeoutCount, setTimeoutCount] = useState(0)
  const [lowBandwidthMode, setLowBandwidthMode] = useState(false)
  const [lowBandwidthReason, setLowBandwidthReason] = useState(null) // "camera_denied" | "slow_connection" | null
  const successTimerRef = useRef(null)
  const sessionCreatingRef = useRef(false)

  // Configure Amplify with Cognito Identity Pool for client-side credentials
  useEffect(() => {
    if (identityPoolId) {
      Amplify.configure({
        Auth: {
          Cognito: {
            identityPoolId: identityPoolId,
            allowGuestAccess: true
          }
        }
      })
    }
  }, [identityPoolId])

  // Cleanup success timer on unmount
  useEffect(() => {
    return () => { if (successTimerRef.current) clearTimeout(successTimerRef.current) }
  }, [])

  // Check rate limit on mount
  const checkRateLimit = useCallback(() => {
    if (!attemptTracker) return false
    const now = Date.now()
    const windowMs = 3 * 60 * 1000
    const maxAttempts = 5

    attemptTracker.attempts = (attemptTracker.attempts || []).filter(t => now - t < windowMs)

    if (attemptTracker.attempts.length >= maxAttempts) {
      const oldestInWindow = Math.min(...attemptTracker.attempts)
      const resetAt = oldestInWindow + windowMs
      setRateLimited(true)
      setRateLimitResetTime(resetAt)

      const timeout = setTimeout(() => {
        setRateLimited(false)
        attemptTracker.attempts = []
      }, resetAt - now)

      return () => clearTimeout(timeout)
    }
    return false
  }, [attemptTracker])

  useEffect(() => { checkRateLimit() }, [checkRateLimit])

  const isRetryRef = useRef(false)

  const createSession = useCallback(async () => {
    // Guard: prevent duplicate session creation during the same lifecycle
    if (sessionCreatingRef.current) return
    sessionCreatingRef.current = true

    setLoading(true)
    setError(null)
    setVerifying(false)
    setSuccess(false)
    try {
      // On retry, send force_new to bypass server-side cache
      // (prevents stale AWS sessions from being reused)
      const url = isRetryRef.current
        ? `${createSessionUrl}?force_new=1`
        : createSessionUrl

      const resp = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
        },
        credentials: "same-origin",
      })
      const data = await resp.json()
      if (!resp.ok) throw new Error(data.error || "Failed to create liveness session")
      setSessionId(data.session_id)
    } catch (err) {
      setError(friendlyError(err.message))
      sessionCreatingRef.current = false  // allow retry on error
    } finally {
      setLoading(false)
    }
  }, [csrfToken, createSessionUrl])

  useEffect(() => { createSession() }, [createSession])

  // Shared result handler — used by both sync fallback and async poll
  const handleResult = useCallback((data) => {
    if (data.passed) {
      if (attemptTracker) attemptTracker.attempts = []
      setVerifying(false)
      setSuccess(true)
      // Include the AWS session ID so consent_liveness_controller can send it to liveness_decide
      const resultWithSession = { ...data, session_id: sessionId }
      // Brief beat (350ms) so the citizen sees "Verifikasyon Figi Fini —
      // n ap konpare…" before the Stimulus controller takes over with its
      // own comparing state. Was 2000ms when the React success screen
      // claimed the ID match was done — too long, and it lied.
      successTimerRef.current = setTimeout(() => onComplete(resultWithSession), 350)
    } else {
      setVerifying(false)
      if (attemptTracker) {
        attemptTracker.attempts = [...(attemptTracker.attempts || []), Date.now()]
      }
      checkRateLimit()
      setError(friendlyError(data.error || "Verifikasyon pa rive nan konfyans nesesè a. Eseye ak pi bon limyè epi pa bouje."))
    }
  }, [attemptTracker, checkRateLimit, onComplete])

  // Async polling: trigger background job, then poll for results.
  // Eliminates the synchronous AWS API call that blocks users for
  // 2–10s on Haiti's slow mobile networks.
  const handleAnalysisComplete = useCallback(async () => {
    setVerifying(true)

    try {
      // Step 1: Trigger async processing — returns immediately
      const triggerResp = await fetch(
        `${resultsUrl}?session_id=${sessionId}`,
        {
          headers: { "X-CSRF-Token": csrfToken },
          credentials: "same-origin",
        }
      )
      const triggerData = await triggerResp.json()

      // Fallback: if server returned a result directly (shouldn't happen, but handle gracefully)
      if (triggerData.status !== "processing") {
        handleResult(triggerData)
        return
      }

      // Step 2: Poll /liveness_status every 2s (max 15 attempts = 30s)
      let attempt = 0
      const poll = async () => {
        attempt++
        try {
          const resp = await fetch(
            `${statusUrl}?session_id=${sessionId}`,
            {
              headers: { "X-CSRF-Token": csrfToken },
              credentials: "same-origin",
            }
          )
          const data = await resp.json()

          if (data.status === "processing") {
            if (attempt >= 15) {
              setVerifying(false)
              setError("Verifikasyon an pran twòp tan. Tanpri tcheke koneksyon ou epi eseye ankò.")
              return
            }
            setTimeout(poll, 2000)
            return
          }

          // Result ready
          handleResult(data)
        } catch (pollErr) {
          // Network error during poll — retry silently (connection may recover)
          if (attempt < 15) {
            setTimeout(poll, 2000)
          } else {
            setVerifying(false)
            setError(friendlyError(pollErr.message))
          }
        }
      }

      poll()
    } catch (err) {
      setVerifying(false)
      setError(friendlyError(err.message))
    }
  }, [sessionId, csrfToken, handleResult])

  const handleError = useCallback((livenessError) => {
    const rawMsg = livenessError?.error?.message || livenessError?.message || "Liveness check failed"
    const friendly = friendlyError(rawMsg)

    setVerifying(false)

    // Camera permission denied — AWS Rekognition can't run at all and
    // "try again" won't re-prompt. Skip directly to the manual-selfie
    // fallback so the citizen has an actual recovery path.
    if (isCameraPermissionError(rawMsg)) {
      setError(null)
      setLowBandwidthReason("camera_denied")
      setLowBandwidthMode(true)
      return
    }

    // Track consecutive timeout/network errors for low-bandwidth fallback
    if (isTimeoutOrNetworkError(rawMsg)) {
      const newCount = timeoutCount + 1
      setTimeoutCount(newCount)
      if (newCount >= 2) {
        // After 2 consecutive timeout failures, offer low-bandwidth mode
        setError(null)
        setLowBandwidthReason("slow_connection")
        setLowBandwidthMode(true)
        return
      }
    } else {
      setTimeoutCount(0) // Reset on non-timeout errors
    }

    setError(friendly)

    if (attemptTracker) {
      attemptTracker.attempts = [...(attemptTracker.attempts || []), Date.now()]
    }
    checkRateLimit()
    // Don't call onError here — error is handled entirely within React.
    // The Stimulus controller only needs to know about success (onComplete).
  }, [attemptTracker, checkRateLimit, timeoutCount])

  const handleRetry = useCallback(() => {
    setError(null)
    setReady(false)
    setVerifying(false)
    setSuccess(false)
    setSessionId(null)
    sessionCreatingRef.current = false  // reset guard for explicit retry
    isRetryRef.current = true           // force fresh AWS session
    createSession()
  }, [createSession])

  // ── Dark mode style helpers ──
  const darkBg = darkMode ? "#0a0f1f" : "transparent"
  const darkText = darkMode ? "#d0d4e0" : "#555"
  const darkTextStrong = darkMode ? "#ffffff" : "#333"
  const darkCardBg = darkMode ? "rgba(255,255,255,0.06)" : "#f8f9fc"
  const darkCardBorder = darkMode ? "1px solid rgba(255,255,255,0.08)" : "1px solid #eef0f6"
  const darkWrap = (children) => darkMode
    ? <div style={{ background: darkBg, minHeight: "100%", flex: 1 }}>{children}</div>
    : children

  // ── Render States ──

  if (rateLimited) return darkWrap(<RateLimitScreen resetTime={rateLimitResetTime} />)
  if (lowBandwidthMode) return darkWrap(
    <LowBandwidthScreen
      csrfToken={csrfToken}
      manualSelfieUrl={manualSelfieUrl}
      reason={lowBandwidthReason}
      onComplete={(data) => {
        setLowBandwidthMode(false)
        setSuccess(true)
        successTimerRef.current = setTimeout(() => onComplete(data), 2000)
      }}
      onRetryNormal={() => {
        setLowBandwidthMode(false)
        setTimeoutCount(0)
        handleRetry()
      }}
    />
  )
  if (success) return darkWrap(<SuccessScreen />)
  if (verifying) return darkWrap(<VerifyingScreen />)

  if (loading) {
    // Respect darkMode so the transition to GetReadyScreen (which honors
    // darkMode) doesn't flash from dark navy → light bg in light mode.
    const loadBg = darkMode ? "#0a0f1f" : "transparent"
    const loadIconBg = darkMode ? "rgba(255,255,255,0.08)" : "#e6eaf5"
    const loadIconColor = darkMode ? "#7b8fff" : "#00209F"
    const loadTextColor = darkMode ? "#ffffff" : "#1a1a2e"
    return (
      <div style={{ ...centeredStyle, background: loadBg }}>
        {iconCircle(loadIconBg, "ri-shield-check-line", loadIconColor)}
        <div className="spinner-border" role="status" style={{
          width: "1.35rem", height: "1.35rem", borderWidth: "2px",
          color: loadIconColor
        }}>
          <span className="visually-hidden">Ap chaje...</span>
        </div>
        <p style={{
          fontSize: "clamp(0.82rem, 2.5vw, 0.88rem)", color: loadTextColor,
          marginTop: "0.85rem", marginBottom: 0, fontWeight: 500
        }}>
          Preparasyon verifikasyon figi...
        </p>
      </div>
    )
  }

  if (error) return darkWrap(<ErrorScreen message={error} onRetry={handleRetry} />)
  if (!sessionId) return null
  if (!ready) {
    return darkWrap(
      <GetReadyScreen
        onReady={() => setReady(true)}
        darkMode={darkMode}
      />
    )
  }

  // ── FaceLivenessDetector (Active Challenge) ──

  // Haitian Creole display text for ALL liveness prompts
  const livenessDisplayText = {
    // Hint text (shown during active check)
    hintCenterFaceText: "Santre figi ou",
    hintCenterFaceInstructionText: "Mete figi ou nan mitan kamera a anvan ou kòmanse.",
    hintMoveCloserText: "Rapwoche ou plis",
    hintMoveFaceFrontOfCameraText: "Mete figi ou devan kamera a",
    hintTooCloseText: "Ou twò pre",
    hintTooFarText: "Ou twò lwen",
    hintHoldFaceForFreshnessText: "Pa bouje",
    hintConnectingText: "Koneksyon...",
    hintVerifyingText: "Verifye...",
    hintCheckCompleteText: "Verifikasyon fini",
    hintMatchIndicatorText: "Kontinye rapwoche ou.",
    hintTooManyFacesText: "Gen twòp figi",
    hintFaceDetectedText: "Figi ou detekte",
    hintFaceOffCenterText: "Figi ou pa nan mitan, santre figi ou.",
    hintCanNotIdentifyText: "Bouje figi ou devan kamera a",
    hintIlluminationTooBrightText: "Twòp limyè",
    hintIlluminationTooDarkText: "Pa ase limyè",
    hintIlluminationNormalText: "Limyè bon",
    // Captions
    goodFitCaptionText: "Bon anfòm!",
    tooFarCaptionText: "Twò lwen",
    // Start screen
    startScreenBeginCheckText: "Kòmanse verifikasyon",
    startScreenHeaderText: "Verifikasyon figi",
    // Camera
    cameraMinSpecificationsHeadingText: "Kamera pa ranpli kondisyon minimòm",
    cameraMinSpecificationsMessageText: "Kamera dwe sipòte omwen 320x240 rezolisyon ak 15 fps.",
    cameraNotFoundHeadingText: "Kamera pa aksesib.",
    cameraNotFoundMessageText: "Verifye ke yon kamera konekte epi pa gen lòt aplikasyon k ap itilize kamera a.",
    waitingCameraPermissionText: "Ap tann pèmisyon kamera ou...",
    a11yVideoLabelText: "Kamera pou verifikasyon",
    cancelLivenessCheckText: "Anile verifikasyon",
    retryCameraPermissionsText: "Eseye ankò",
    recordingIndicatorText: "Anrejistreman",
    // Photosensitivity
    photosensitivityWarningHeadingText: "Avètisman",
    photosensitivityWarningBodyText: "Aparèy sa a ap flache koulè diferan.",
    photosensitivityWarningInfoText: "Kèk moun ka gen kriz lè yo ekspoze ak limyè koulè.",
    photosensitivityWarningLabelText: "Plis enfòmasyon sou fotosansibilite",
    photosensitivyWarningHeadingText: "Avètisman",
    photosensitivyWarningBodyText: "Aparèy sa a ap flache koulè diferan.",
    photosensitivyWarningInfoText: "Kèk moun ka gen kriz lè yo ekspoze ak limyè koulè.",
    photosensitivyWarningLabelText: "Plis enfòmasyon sou fotosansibilite",
    // Errors
    errorLabelText: "Erè",
    connectionTimeoutHeaderText: "Koneksyon ekspire",
    connectionTimeoutMessageText: "Koneksyon an ekspire.",
    timeoutHeaderText: "Tan ekspire",
    timeoutMessageText: "Figi ou pa t rantre nan oval la atan. Eseye ankò.",
    faceDistanceHeaderText: "Mouvman detekte",
    faceDistanceMessageText: "Evite rapwoche ou pandan koneksyon an.",
    multipleFacesHeaderText: "Plizyè figi detekte",
    multipleFacesMessageText: "Asire ke sèlman yon figi devan kamera a.",
    clientHeaderText: "Erè kliyan",
    clientMessageText: "Verifikasyon echwe akòz yon erè kliyan.",
    serverHeaderText: "Erè sèvè",
    serverMessageText: "Pa kapab fini verifikasyon akòz yon pwoblèm sèvè.",
    landscapeHeaderText: "Oryantasyon orizontal pa sipòte",
    landscapeMessageText: "Tounen aparèy ou an vètikal.",
    portraitMessageText: "Kenbe aparèy ou an vètikal pandan verifikasyon an.",
    tryAgainText: "Eseye ankò",
  }

  return (
    <ThemeProvider theme={darkMode ? bonidDarkTheme : bonidTheme}>
      <FaceLivenessDetector
        sessionId={sessionId}
        region={region}
        onAnalysisComplete={handleAnalysisComplete}
        onError={handleError}
        disableStartScreen={true}
        displayText={livenessDisplayText}
        components={{
          PhotosensitiveWarning: () => null,
        }}
      />
    </ThemeProvider>
  )
}

// ── Dark Theme Overrides ──
// Minimal runtime injection — sets CSS custom properties on .bonid-liveness-dark
// as a fallback. Primary dark styling is in _transaction_consents.scss.
const DARK_STYLE_ID = "bonid-liveness-dark-overrides"
const DARK_CSS = `
  .bonid-liveness-dark {
    --amplify-colors-background-primary: #0a0f1f;
    --amplify-colors-background-secondary: #111730;
    --amplify-colors-font-primary: #ffffff;
    --amplify-colors-font-secondary: #d0d4e0;
    --amplify-colors-neutral-100: #1a2040;
    --amplify-colors-primary-80: #00209F;
  }
`

function injectDarkStyles() {
  if (!document.getElementById(DARK_STYLE_ID)) {
    const style = document.createElement("style")
    style.id = DARK_STYLE_ID
    style.textContent = DARK_CSS
    document.head.appendChild(style)
  }
}

// Global mount/unmount API for the Stimulus controller
let root = null

window.BonidLiveness = {
  mount(containerElement, { csrfToken, region, identityPoolId, onComplete, onError, attemptTracker,
                            createSessionUrl, resultsUrl, statusUrl, manualSelfieUrl }) {
    if (root) {
      root.unmount()
    }

    // Detect dark mode: if mount point is inside .consent-liveness-dark or .bonid-liveness-dark
    const darkWrapper = containerElement.closest(".consent-liveness-dark") || containerElement.closest(".bonid-liveness-dark")
    const isDark = !!darkWrapper
    if (isDark) {
      injectDarkStyles()
      darkWrapper.classList.add("bonid-liveness-dark")
    }

    root = createRoot(containerElement)
    root.render(
      <LivenessCheck
        csrfToken={csrfToken}
        region={region}
        identityPoolId={identityPoolId}
        onComplete={onComplete}
        onError={onError}
        attemptTracker={attemptTracker}
        createSessionUrl={createSessionUrl}
        resultsUrl={resultsUrl}
        statusUrl={statusUrl}
        manualSelfieUrl={manualSelfieUrl}
        darkMode={isDark}
      />
    )

  },

  unmount() {
    if (root) {
      root.unmount()
      root = null
    }
  }
}
