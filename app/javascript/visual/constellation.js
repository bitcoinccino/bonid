// ======================================================
// Verifyem Orbit Rings — SOLAR PLANET SMOOTH (no shaking)
// - Uses transform translate3d() only (GPU)
// - No left/top per-frame writes
// - Inner + outer rings rotate (opposite directions)
// ======================================================

class VerifyemOrbitRings {
  constructor(orbitSelector) {
    this.orbitEl = document.querySelector(orbitSelector);
    if (!this.orbitEl) return;

    this.config = {
      innerSpeed: 0.00065,
      outerSpeed: -0.00050,
      innerRadius: 160,
      outerRadius: 240,
      fps: 60
    };

    this.state = {
      hub: null,
      nodes: [],
      innerNodes: [],
      outerNodes: [],
      innerAngle: 0,
      outerAngle: 0,
      animationId: null,
      isPaused: false,
      lastFrameTime: 0,
      reducedMotion: false
    };

    this.init();
  }

  init() {
    this.state.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (this.state.reducedMotion) {
      this.config.innerSpeed *= 0.25;
      this.config.outerSpeed *= 0.25;
    }

    this.state.hub = this.orbitEl.querySelector('[data-role="hub"]');

    const ring = this.orbitEl.querySelector('[data-orbit-ring="main"]');
    this.state.nodes = ring ? Array.from(ring.querySelectorAll('[data-role="node"]')) : [];

    // Split nodes across two rings (alternating)
    this.state.innerNodes = this.state.nodes.filter((_, i) => i % 2 === 0);
    this.state.outerNodes = this.state.nodes.filter((_, i) => i % 2 === 1);

    this.updateResponsiveSizes();
    this.attachEventListeners();
    this.prepareNodes();   // <-- critical for smooth motion
    this.positionHub();
    this.start();
  }

  updateResponsiveSizes() {
    const w = window.innerWidth;

    if (w <= 576) {
      this.config.innerRadius = 105;
      this.config.outerRadius = 150;
    } else if (w <= 992) {
      this.config.innerRadius = 135;
      this.config.outerRadius = 200;
    } else {
      this.config.innerRadius = 160;
      this.config.outerRadius = 240;
    }
  }

  attachEventListeners() {
    let resizeTimeout;
    window.addEventListener("resize", () => {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(() => {
        this.updateResponsiveSizes();
        this.positionHub();
        this.positionAll();
      }, 120);
    });

    document.addEventListener("visibilitychange", () => {
      if (document.hidden) this.pause();
      else this.resume();
    });

    ["turbo:before-cache", "turbo:before-render"].forEach((evt) => {
      document.addEventListener(evt, () => this.destroy(), { once: true });
    });
  }

  // Ensure all orbiting nodes are anchored at center,
  // and we ONLY move them with translate3d().
  prepareNodes() {
    const setBase = (node) => {
      node.style.left = "50%";
      node.style.top = "50%";
      node.style.transform = "translate3d(0px,0px,0)";
      node.style.transformOrigin = "center center";
    };

    this.state.innerNodes.forEach(setBase);
    this.state.outerNodes.forEach(setBase);
  }

  positionHub() {
    if (!this.state.hub) return;
    this.state.hub.style.left = "50%";
    this.state.hub.style.top = "50%";
    this.state.hub.style.transform = "translate(-50%, -50%)";
  }

  // Write transforms only (no rounding = no jitter)
  positionRing(nodes, angle, radius) {
    const count = nodes.length || 1;

    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      const a = angle + (i / count) * Math.PI * 2;

      const x = Math.cos(a) * radius;
      const y = Math.sin(a) * radius;

      // IMPORTANT: include -50%,-50% so the circle is centered on its position
      node.style.transform = `translate3d(calc(-50% + ${x}px), calc(-50% + ${y}px), 0)`;
    }
  }

  positionAll() {
    this.positionRing(this.state.innerNodes, this.state.innerAngle, this.config.innerRadius);
    this.positionRing(this.state.outerNodes, this.state.outerAngle, this.config.outerRadius);
  }

  animate = (timestamp) => {
    if (this.state.isPaused) return;

    const elapsed = timestamp - this.state.lastFrameTime;
    const fpsInterval = 1000 / this.config.fps;

    if (elapsed < fpsInterval) {
      this.state.animationId = requestAnimationFrame(this.animate);
      return;
    }

    this.state.lastFrameTime = timestamp - (elapsed % fpsInterval);

    // pure circular motion (solar planet)
    this.state.innerAngle += this.config.innerSpeed;
    this.state.outerAngle += this.config.outerSpeed;

    this.positionAll();
    this.state.animationId = requestAnimationFrame(this.animate);
  };

  start() {
    if (this.state.animationId) return;
    this.positionAll();
    this.state.animationId = requestAnimationFrame(this.animate);
  }

  pause() {
    if (!this.state) return;
    this.state.isPaused = true;
    if (this.state.animationId) cancelAnimationFrame(this.state.animationId);
    this.state.animationId = null;
  }

  resume() {
    if (!this.state.isPaused) return;
    this.state.isPaused = false;
    this.start();
  }

  destroy() {
    this.pause();
  }
}

// Turbo-safe init
let verifyemOrbit = null;

function initVerifyemOrbit() {
  if (verifyemOrbit) verifyemOrbit.destroy();
  verifyemOrbit = new VerifyemOrbitRings("[data-orbit]");
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initVerifyemOrbit);
} else {
  initVerifyemOrbit();
}

document.addEventListener("turbo:load", initVerifyemOrbit);
document.addEventListener("turbo:render", initVerifyemOrbit);

window.VerifyemOrbitRings = VerifyemOrbitRings;
