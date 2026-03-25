// app/javascript/visual/matrix_mesh.js

(() => {
  const canvas = document.getElementById("meshCanvas")
  if (!canvas) return

  const ctx = canvas.getContext("2d")
  let width = 0
  let height = 0
  let dpr = window.devicePixelRatio || 1
  let nodes = []
  let lastFrame = 0

  const FPS = 30
  const FRAME_TIME = 1000 / FPS
  const NODE_COUNT = 60

  function resize() {
    width = canvas.offsetWidth
    height = canvas.offsetHeight

    canvas.width = Math.floor(width * dpr)
    canvas.height = Math.floor(height * dpr)
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)

    generateNodes()
  }

  function generateNodes() {
    nodes = Array.from({ length: NODE_COUNT }, () => ({
      x: Math.random() * width,
      y: Math.random() * height,
      vx: (Math.random() - 0.5) * 0.35,
      vy: (Math.random() - 0.5) * 0.35
    }))
  }

  resize()
  window.addEventListener("resize", resize)

  let visible = true

  const observer = new IntersectionObserver(entries => {
    visible = entries[0].isIntersecting
  })

  observer.observe(canvas)

  function draw(ts) {
    if (!visible) {
      requestAnimationFrame(draw)
      return
    }

    if (ts - lastFrame < FRAME_TIME) {
      requestAnimationFrame(draw)
      return
    }

    lastFrame = ts
    ctx.clearRect(0, 0, width, height)

    for (let i = 0; i < nodes.length; i++) {
      const n = nodes[i]

      n.x += n.vx
      n.y += n.vy

      if (n.x <= 0 || n.x >= width) n.vx *= -1
      if (n.y <= 0 || n.y >= height) n.vy *= -1

      ctx.fillStyle = "rgba(0,255,255,0.35)"
      ctx.beginPath()
      ctx.arc(n.x, n.y, 1.3, 0, Math.PI * 2)
      ctx.fill()
    }

    requestAnimationFrame(draw)
  }

  requestAnimationFrame(draw)
})()
