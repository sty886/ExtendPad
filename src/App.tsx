import { useEffect, useRef, useState } from "react"
import { AnimatePresence, motion } from "motion/react"
import TextRotate from "./components/TextRotate"

const HERO_WORDS = [
  "Android tablet",
  "5K iMac",
  "spare MacBook",
  "Android phone",
  "foldable",
  "Android",
]

export default function App() {
  const [starCount, setStarCount] = useState<string | null>(null)
  // Show the brand icon in the navbar only once the big hero logo has
  // scrolled up behind the sticky nav — it "hands off" from hero to navbar.
  const heroLogoRef = useRef<HTMLImageElement>(null)
  const [showNavLogo, setShowNavLogo] = useState(false)

  useEffect(() => {
    const el = heroLogoRef.current
    if (!el || typeof IntersectionObserver === "undefined") return
    const io = new IntersectionObserver(
      ([entry]) => setShowNavLogo(!entry.isIntersecting),
      // 60px = navbar height, so the handoff fires as the logo slips under it.
      { rootMargin: "-60px 0px 0px 0px", threshold: 0 }
    )
    io.observe(el)
    return () => io.disconnect()
  }, [])

  // Progressive enhancement: live GitHub star count.
  // Fails silent (offline / rate-limited) — the page works without it.
  useEffect(() => {
    fetch("https://api.github.com/repos/raiseCatError/MeowDisplay", {
      headers: { Accept: "application/vnd.github+json" },
    })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (data && typeof data.stargazers_count === "number") {
          setStarCount(data.stargazers_count.toLocaleString())
        }
      })
      .catch(() => {})
  }, [])

  // Scroll-spy: keep the URL fragment in sync with the section at the top of
  // the viewport so any section is directly shareable. replaceState avoids
  // both a scroll jump and flooding the back button with history entries.
  useEffect(() => {
    const sections = Array.from(document.querySelectorAll("section"))
    if (!sections.length) return
    let raf = 0
    const sync = () => {
      raf = 0
      // Trigger line just below the 60px sticky nav.
      const line = 72
      let current = ""
      for (const s of sections) {
        if (s.getBoundingClientRect().top <= line) current = s.id
      }
      const hash = current ? `#${current}` : ""
      if (hash !== window.location.hash) {
        // Empty hash → drop the fragment entirely (keeps the base path/query).
        const url = hash || window.location.pathname + window.location.search
        window.history.replaceState(null, "", url)
      }
    }
    const onScroll = () => {
      if (!raf) raf = requestAnimationFrame(sync)
    }
    sync()
    window.addEventListener("scroll", onScroll, { passive: true })
    return () => {
      window.removeEventListener("scroll", onScroll)
      if (raf) cancelAnimationFrame(raf)
    }
  }, [])

  return (
    <>
      <nav>
        <div className="wrap">
          <a className="brand" href="./">
            <AnimatePresence mode="popLayout" initial={false}>
              {showNavLogo && (
                <motion.img
                  key="nav-logo"
                  className="nav-logo"
                  src="logo.png"
                  alt=""
                  initial={{ opacity: 0, scale: 0 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0 }}
                  transition={{ type: "spring", damping: 16, stiffness: 340 }}
                />
              )}
            </AnimatePresence>
            <motion.span
              layout
              transition={{ type: "spring", damping: 22, stiffness: 340 }}
            >
              MeowDisplay
            </motion.span>
          </a>
          <div className="links">
            <a href="#features">Features</a>
            <a href="#why">Compare</a>
            <a href="#faq">FAQ</a>
            <a href="#compatible">Other platforms</a>
            <a href="#contribute">Contribute</a>
            <a
              className="gh"
              href="https://github.com/raiseCatError/MeowDisplay"
              title="Star MeowDisplay on GitHub"
            >
              <svg className="gh-logo" viewBox="0 0 16 16" aria-hidden="true">
                <path
                  fillRule="evenodd"
                  d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"
                />
              </svg>
              {starCount && (
                <span className="gh-stars">
                  <span>{starCount}</span>
                </span>
              )}
            </a>
          </div>
        </div>
      </nav>

      <section>
        <div className="wrap hero">
          <img ref={heroLogoRef} className="hero-logo" src="logo.png" alt="MeowDisplay" width="160" height="160" />
          <p className="eyebrow">Free &amp; open source</p>
          <h1>
            <span className="l1">
              Use your{" "}
              <TextRotate
                as="span"
                texts={HERO_WORDS}
                mainClassName="rotator-pill"
                splitLevelClassName="rotator-line"
                staggerFrom="last"
                staggerDuration={0.025}
                rotationInterval={2200}
                transition={{ type: "spring", damping: 30, stiffness: 400 }}
                initial={{ y: "100%", opacity: 0 }}
                animate={{ y: 0, opacity: 1 }}
                exit={{ y: "-120%", opacity: 0 }}
              />
            </span>
            <span className="l2">as your Mac's <span className="u">second monitor</span>.</span>
          </h1>
          <p className="tagline">
            A free, open-source alternative to Apple Sidecar, Duet Display and Luna Display.
            Use an Android device or another Mac as a second screen for your Mac,
            with touch, mouse and keyboard input routed back, locally over USB/WiFi or
            remotely through a private network like Tailscale. No subscription. No dongle.
            No MeowDisplay-hosted account or relay.
          </p>
          <p className="meta">macOS 14+ &nbsp;·&nbsp; Android 10+ &nbsp;·&nbsp; Receiver Mac 12+ &nbsp;·&nbsp; GPL-3.0</p>
          <p className="meta">Supported receivers: <strong>Android and Mac.</strong></p>
        </div>
      </section>

      <section className="downloads-sec">
        <div className="wrap">
          <p className="needs-both">
            MeowDisplay is <strong>two apps that work together</strong> — the <strong>Sender</strong> on your Mac and a <strong>Receiver</strong> on the device you want to use as a display. Public prebuilt downloads aren't live yet — build from source today.
          </p>
          <div className="download-group sender-group">
            <h2 className="download-role">Sender</h2>
            <p className="download-group-intro">Install this on the Mac whose desktop you want to extend or mirror.</p>
            <div className="download-options sender-download">
              <div className="download-option">
                <div className="platform">macOS</div>
                <p className="dl-sub">Captures a virtual display and streams it. Build from source today — a signed, notarized direct download is planned.</p>
                <a className="btn primary" href="https://github.com/raiseCatError/MeowDisplay#getting-started">
                  Build from Source
                </a>
                <p className="note">
                  <a href="https://github.com/raiseCatError/MeowDisplay">View on GitHub ↗</a>
                </p>
              </div>
            </div>
          </div>

          <div className="download-group receiver-group">
            <h2 className="download-role">Receiver</h2>
            <p className="download-group-intro">Install one on the device you want to use as your extra display.</p>
            <div className="download-options receiver-downloads">
              <div className="download-option">
                <div className="platform">Android</div>
                <p className="dl-sub">The receiver app for Android phones, tablets and foldables running Android 10 or later.</p>
                <a className="btn primary" href="https://github.com/raiseCatError/MeowDisplay/tree/main/apps/android">
                  Build from Source
                </a>
              </div>
              <div className="download-option">
                <div className="platform">macOS</div>
                <p className="dl-sub">
                  Got a spare <em>Mac</em> to use as the display? The separate <strong>MeowDisplay Receiver</strong> app
                  turns an older Mac into a second display — runs on macOS&nbsp;12+, so older Macs qualify. Build from source today.
                </p>
                <a className="btn primary" href="https://github.com/raiseCatError/MeowDisplay#getting-started">
                  Build from Source
                </a>
              </div>
            </div>
          </div>

          <p className="note" style={{ marginTop: "16px" }}>
            Setup, signing, permissions, and pairing: see the{" "}
            <a href="https://github.com/raiseCatError/MeowDisplay/blob/main/docs/SETUP.md">Setup Guide ↗</a>.
            Want to see what's coming? Check the{" "}
            <a href="https://github.com/raiseCatError/MeowDisplay#roadmap">Roadmap ↗</a>.
          </p>
        </div>
      </section>

      {/* No "Demo" section: the only existing demo videos are upstream
          OpenDisplay's own recordings (a different developer's product),
          so showing them here as MeowDisplay footage would misattribute
          them. Re-add once MeowDisplay-branded demo footage exists. */}

      <section id="features">
        <div className="wrap sec">
          <p className="eyebrow">Features</p>
          <h2>A true extended display, the way it should be.</h2>
          <div className="fgrid">
            <div className="fcell"><span className="n">001</span><h3>No account, ever</h3><p>No sign-up, no email, no login. Pair your own Android devices and Macs directly, without a hosted account.</p></div>
            <div className="fcell"><span className="n">002</span><h3>Low-latency pipeline</h3><p>Up to 60 FPS over USB. Hardware H.264 (VideoToolbox real-time mode), TCP_NODELAY, and frame-dropping backpressure with instant keyframe recovery keep it responsive.</p></div>
            <div className="fcell"><span className="n">003</span><h3>More than one receiver</h3><p>Connect Android devices and Macs, each with its own display mode. Arrange them in System Settings like real monitors.</p></div>
            <div className="fcell"><span className="n">004</span><h3>Retina sharp</h3><p>Native Retina resolution — the virtual display matches your device panel pixel-for-pixel at HiDPI (@2x), so text looks exactly like it should.</p></div>
            <div className="fcell"><span className="n">005</span><h3>USB-wired, lowest latency</h3><p>Android uses an authorized ADB tunnel over a data cable, with the same authenticated and encrypted session.</p></div>
            <div className="fcell"><span className="n">006</span><h3>WiFi, zero config</h3><p>Receivers advertise themselves with Bonjour; pick one from the device list. No IP addresses to type.</p></div>
            <div className="fcell"><span className="n">007</span><h3>Touch &amp; scroll</h3><p>Tap to click, drag to drag, two-finger pan to scroll. A tiny touchscreen for your Mac.</p></div>
            <div className="fcell"><span className="n">008</span><h3>Portrait mode</h3><p>Rotate the phone and the virtual display rebuilds as a vertical monitor — perfect for chat, logs, or docs.</p></div>
            <div className="fcell"><span className="n">009</span><h3>Private by design</h3><p>One direct TCP connection between your devices. No servers, no accounts, no telemetry. Read the code.</p></div>
            <div className="fcell"><span className="n">010</span><h3>A spare Mac as a display</h3><p>Install the small <em>MeowDisplay Receiver</em> app (macOS 12+) on an old Mac and another Mac extends onto it — a real Retina extended display, over WiFi or a Thunderbolt or Ethernet cable. An old MacBook becomes a second monitor.</p></div>
          </div>
        </div>
      </section>

      <section id="why">
        <div className="wrap sec">
          <p className="eyebrow">Why MeowDisplay</p>
          <h2>The device you already own becomes a real additional display.</h2>
          <div className="compare">
            <div className="row">
              <div className="name"><a href="https://support.apple.com/en-us/HT210380">Apple Sidecar</a></div>
              <p>Free, but iPad-only, requires both devices on the same Apple&nbsp;ID, and only on
              blessed hardware pairs. iPhones need not apply.</p>
            </div>
            <div className="row">
              <div className="name"><a href="https://www.duetdisplay.com/">Duet Display</a></div>
              <p>Pioneered the idea — now behind a subscription.</p>
            </div>
            <div className="row">
              <div className="name"><a href="https://astropad.com/product/lunadisplay/">Luna Display</a></div>
              <p>Great latency, but you're buying a hardware dongle.</p>
            </div>
            <div className="row highlight">
              <div className="name">MeowDisplay</div>
              <p>Free, open source, auditable. The device you already own becomes a real additional
              display. If you were about to build your own — contribute here instead.</p>
            </div>
          </div>

          <h3 className="tbl-head">How it stacks up</h3>
          <div className="tbl-scroll">
            <table>
              <thead>
                <tr><th></th><th className="os">MeowDisplay</th><th>Apple Sidecar</th><th>Duet</th><th>Luna</th></tr>
              </thead>
              <tbody>
                <tr><td>Price</td><td className="mark-yes os">Free &amp; open source</td><td>Free</td><td className="mark-no">Subscription</td><td className="mark-no">$$$ + dongle</td></tr>
                <tr><td>Android as display</td><td className="mark-yes os">✓</td><td className="mark-no">✕</td><td className="mark-yes">✓</td><td className="mark-yes">✓</td></tr>
                <tr><td>Mac as display</td><td className="mark-yes os">✓</td><td className="mark-no">✕</td><td className="mark-yes">✓</td><td className="mark-yes">✓</td></tr>
                <tr><td>Different Apple IDs</td><td className="mark-yes os">✓</td><td className="mark-no">✕</td><td className="mark-yes">✓</td><td className="mark-yes">✓</td></tr>
                <tr><td>No account / sign-up</td><td className="mark-yes os">✓</td><td>Apple&nbsp;ID</td><td className="mark-no">✕</td><td>—</td></tr>
                <tr><td>Wired USB</td><td className="mark-yes os">✓</td><td className="mark-yes">✓</td><td className="mark-yes">✓</td><td className="mark-no">✕</td></tr>
                <tr><td>Open source</td><td className="mark-yes os">✓</td><td>—</td><td className="mark-no">✕</td><td className="mark-no">✕</td></tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <section id="faq">
        <div className="wrap sec">
          <p className="eyebrow">FAQ</p>
          <h2>Questions, answered.</h2>
          <div className="faq">
            <details>
              <summary>How does it actually work?</summary>
              <p>The Mac creates a virtual display with the private <code>CGVirtualDisplay</code> API
              (the same technique used by BetterDisplay and DeskPad), captures it with ScreenCaptureKit,
              hardware-encodes H.264 with VideoToolbox, and streams it over a secured connection —
              through an authorized Android ADB tunnel, or over WiFi. The Android or Mac receiver
              decodes and renders the picture and sends input back to the Mac.</p>
            </details>
            <details>
              <summary>Why do I see the purple screen-recording indicator on my Mac?</summary>
              <p>macOS shows that privacy indicator for <em>every</em> app that captures the screen —
              Duet, Luna, OBS and Zoom included. Apple Sidecar avoids it only because it's built into
              the OS. It's a feature, not a bug: you always know a capture is running.</p>
            </details>
            <details>
              <summary>WiFi mode can't find my Android device — why?</summary>
              <p>Both devices must be on the same WiFi, and the ExtendPad receiver must be open.
              Check macOS Local Network permission and the local firewall on the Mac. For a cable,
              enable USB debugging and authorize the Mac before using the ADB tunnel.</p>
            </details>
            <details>
              <summary>Can I use it away from home, not just on the same WiFi?</summary>
              <p>Yes — Remote Access lets you connect to a paired Mac through any reachable address,
              such as a <a href="https://tailscale.com">Tailscale</a> endpoint. Tailscale (or an
              equivalent private network) is only used for reachability, not authentication — the
              actual trust still comes from the same pinned, encrypted session established during
              pairing. There's no MeowDisplay-hosted account or relay involved. One honest limitation:
              waking a sleeping Mac remotely over Tailscale isn't solved yet (Wake-on-LAN is a
              local-network broadcast) — see the{" "}
              <a href="https://github.com/raiseCatError/MeowDisplay#roadmap">roadmap</a>.</p>
            </details>
            <details>
              <summary>Can another Mac be the display?</summary>
              <p>Yes. Mac-to-Mac receiving is implemented, with physical two-Mac verification still limited.
              Install <em>MeowDisplay Receiver</em>, a separate small app built from the same source tree, on
              the spare Mac. It needs only macOS 12 Monterey or newer (the sending Mac needs 14), so Macs
              from around 2015 onward qualify. It appears on the sending Mac like a phone would and
              becomes a real extended Retina display. WiFi works out of the box. For a cable, use a
              <em>Thunderbolt or USB4</em> cable (macOS sets up a Thunderbolt Bridge network between
              the two), Ethernet, or — on recent macOS on both Macs — a plain USB-C data cable (approve
              the "allow accessory" prompt on each Mac). The sender moves the session onto the cable
              automatically, even one plugged in mid-session. Keyboard and mouse
              input from the receiving Mac is a follow-up.</p>
            </details>
            <details>
              <summary>Is any of my screen data sent to a server?</summary>
              <p>No. One direct TCP connection between your Mac and your device. No accounts, no
              analytics, no cloud. The full story — what the apps store locally, which permissions they
              use and why, and the one current caveat about unencrypted WiFi transport — is on the{" "}
              <a href="privacy.html">privacy page</a>.</p>
            </details>
            <details>
              <summary>What's the license? Can I fork it or use it commercially?</summary>
              <p>MeowDisplay is licensed under{" "}
              <a href="https://github.com/raiseCatError/MeowDisplay/blob/main/LICENSE">GPL-3.0</a>, the
              same license as the upstream OpenDisplay project it's built on. You can
              use, study, and adapt it freely — including commercially. If you distribute a modified
              version, it must remain open source under the same license with the original attribution
              intact, so improvements flow back to everyone instead of into closed forks. (Upstream
              releases up to v0.4.x were MIT-licensed and remain available under those terms.)</p>
            </details>
          </div>
        </div>
      </section>

      <section id="compatible">
        <div className="wrap sec">
          <p className="eyebrow">Compatible apps</p>
          <h2>More Android clients.</h2>
          <p className="compat-lead">
            ExtendPad includes a native Android receiver. These community projects implement the
            related OpenDisplay protocol and may suit other Android setups.
          </p>
          <div className="compat">
            <a className="compat-item" href="https://github.com/gprot42/android-opendisplay">
              <span className="compat-role">Android receiver</span>
              <span className="compat-repo">gprot42/android-opendisplay ↗</span>
              <p>GrapheneOS receiver for de-Googled Pixel phones and tablets. Android 8.0+.</p>
            </a>
            <a className="compat-item" href="https://github.com/josepacelli/opendisplay-android">
              <span className="compat-role">Android receiver</span>
              <span className="compat-repo">josepacelli/opendisplay-android ↗</span>
              <p>Android receiver that works with an unmodified Mac app. Android 8.0+.</p>
            </a>
          </div>
          <p className="compat-note">
            These are community projects, not ExtendPad builds. They are maintained and supported
            in their own repositories.
          </p>
        </div>
      </section>

      <section id="contribute">
        <div className="wrap sec">
          <p className="eyebrow">Contribute</p>
          <h2>Open source, and built in the open.</h2>
          <p style={{ color: "var(--muted)", maxWidth: "72ch", marginTop: "8px" }}>
            MeowDisplay is GPL-3.0 and developed entirely on GitHub — the whole stack, from Mac
            capture and encoding to the Android and Mac receivers, is yours to read, build, and improve.
            Bug reports, feature ideas, and pull requests are all welcome. Build-and-run instructions
            live in the README.
          </p>
          <div className="btn-row">
            <a className="btn primary" href="https://github.com/raiseCatError/MeowDisplay">View on GitHub ↗</a>
            <a className="btn ghost" href="https://github.com/raiseCatError/MeowDisplay/issues">Open an issue ↗</a>
          </div>
          <p className="sub">
            New here? Start with the{" "}
            <a href="https://github.com/raiseCatError/MeowDisplay#quick-start">README quick-start</a>{" "}
            to build both apps, or browse the{" "}
            <a href="https://github.com/raiseCatError/MeowDisplay/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22">good first issues</a>.
          </p>
        </div>
      </section>

      <footer>
        <div className="wrap">
          <div className="links">
            <a href="https://github.com/raiseCatError/MeowDisplay">GitHub</a>
            <a href="https://github.com/raiseCatError/MeowDisplay/releases/latest">Releases</a>
            <a href="https://github.com/raiseCatError/MeowDisplay/issues">Issues</a>
            <a href="privacy.html">Privacy</a>
            <a href="https://github.com/raiseCatError/MeowDisplay/blob/main/LICENSE">GPL-3.0 License</a>
          </div>
          <p className="fine">MeowDisplay — use Android or another Mac as a second monitor for your Mac. Free forever.</p>
        </div>
      </footer>
    </>
  )
}
