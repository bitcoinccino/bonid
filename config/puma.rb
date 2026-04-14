# Puma configuration — optimized for election-day throughput.
#
# Production layout (per server):
#   4 workers × 8 threads = 32 concurrent requests
#   2–3 servers behind ALB = 64–96 concurrent requests
#   At ~5–10ms per vote: ~3,000–5,000 votes/sec capacity
#
# Development:
#   Single process, 3 threads (avoids ngrok/reload issues)
#
# Env vars:
#   WEB_CONCURRENCY=4    (workers — set to CPU cores)
#   RAILS_MAX_THREADS=8  (threads per worker)
#   PORT=3000             (HTTP listen port)

# ── Threads ──
# Min/max thread pool per worker.
# Higher max = more throughput for I/O-bound requests (DB, Redis).
# Keep min ≥ 3 so cold workers don't starve under sudden load.
max_threads = ENV.fetch("RAILS_MAX_THREADS", 3).to_i
min_threads = ENV.fetch("RAILS_MIN_THREADS", max_threads).to_i
threads min_threads, max_threads

# ── Port ──
port ENV.fetch("PORT", 3000)

# ── Workers (Production Only) ──
# Fork multiple OS processes for true parallelism (bypasses GVL).
# Each worker gets its own thread pool + DB connection pool.
# Rule of thumb: WEB_CONCURRENCY = number of CPU cores.
if ENV["RAILS_ENV"] == "production" || ENV["WEB_CONCURRENCY"].to_i > 0
  workers ENV.fetch("WEB_CONCURRENCY", 2).to_i

  # Preload app for faster worker boot + copy-on-write memory savings.
  preload_app!

  # Re-establish DB connections in forked workers.
  on_worker_boot do
    ActiveRecord::Base.establish_connection
  end
end

# ── Plugins ──
# Allow restart via `bin/rails restart`
plugin :tmp_restart

# Run Solid Queue supervisor inside Puma for single-server deployments
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# ── PID File ──
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
