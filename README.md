# Infrastructure Engineer — Technical Test

This repo contains the answers to all 4 parts of the technical test: Linux observability, Terraform (AWS), CI/CD pipeline design, and incident RCA.

Structure:
```
.
├── README.md                     # Answers to Part 1 & Part 4
├── terraform/                    # Answer to Part 2
│   ├── backend.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── security-groups.tf
│   ├── ec2.tf
│   └── outputs.tf
└── cicd/
    └── pipeline.yml               # Answer to Part 3 (GitHub Actions)
```

---

## 1. Linux Systems Administration & Local Observability

All commands below are verified against Ubuntu 24.04/26.04 LTS and avoid deprecated tooling (`netstat`, `ifconfig`, etc.) in favor of the modern `iproute2`/`procps` toolset.

### 1.1 RAM (total, used, free, cache)

```bash
free -h
```
The relevant numbers sit on the `Mem:` line — `total`, `used`, `free`, `buff/cache`, and `available`. The distinction people usually get wrong is `free` vs `available`: `free` is memory sitting completely idle, while `available` already accounts for cache the kernel can reclaim instantly if an app needs it. So "how much breathing room does this box actually have" is answered by `available`, not `free`.

For a live or short historical view:
```bash
vmstat -s -S M      # one-shot memory summary in MB
vmstat 2 5           # sample every 2s, 5 times — watch the si/so columns (swap in/out)
```
If `si`/`so` in vmstat keep climbing, that's active swapping — a sign of real memory pressure even if `free -h` still looks fine at a glance.

### 1.2 Storage (disk space & I/O throughput)

Capacity:
```bash
df -hT
```
Focus on the `Use%` column per mount point, especially `/` and `/var` (log growth is a very common silent cause of a filled-up partition).

I/O throughput (needs the `sysstat` package, usually preinstalled on Ubuntu server images):
```bash
iostat -xz 1 5
```
The metrics that actually determine disk health:
- `%util` — sustained near 100% means the disk is the bottleneck.
- `await` — average I/O wait time (ms); if it's far above `svctm`, requests are queuing up.
- `r/s`, `w/s`, `rkB/s`, `wkB/s` — actual throughput, compared against a known baseline.

### 1.3 Service health (example: Nginx)

```bash
systemctl status nginx --no-pager
```
What to check: `Active: active (running)` vs `failed`/`activating`, and the `Main PID` (if it keeps changing, the process is crash-looping).

Startup and runtime logs:
```bash
journalctl -u nginx -b --no-pager        # since last boot
journalctl -u nginx --since "15 min ago"  # a specific time window
journalctl -u nginx -f                    # live tail
```

### 1.4 Port usage (who's listening on 80/443)

```bash
ss -tulpn | grep -E ':80|:443'
```
`ss` is used instead of `netstat`, which is deprecated in net-tools and often not even installed by default on modern images. What matters in the output: `LISTEN` state, `Local Address:Port`, and the process name + PID in the last column — that's what confirms the port is actually held by the intended service and not, say, a stale process that never got killed.

---

## 2. Infrastructure as Code (AWS & Terraform)

See the `terraform/` directory for the full configuration.

A few deliberate design choices worth calling out:
- `allowed_ssh_cidr`, `ami_id`, and `key_pair_name` are declared as **required variables with no default value** — they're environment-specific and, in the case of the SSH CIDR, sensitive. They're meant to be supplied at apply time via a `terraform.tfvars` file (kept out of version control) or `TF_VAR_*` environment variables, never hardcoded into the `.tf` files themselves. This is intentional, in line with the requirement that the configuration contain no hardcoded local system values or credentials — it isn't an oversight.
- The remote state backend (S3 bucket + DynamoDB lock table in `backend.tf`) assumes those two resources already exist in the target AWS account. Bootstrapping them is normally a one-time separate step (often done manually or via a small standalone Terraform config) before this configuration's `terraform init` can run.

---

## 4. Live System Incident Triage — Post-Mortem & RCA

### 4.1 Why manual testing passes while production returns 502

The dev team tested directly against `/api/health`, `/api/users`, or `/api/products` on port 3000 — real routes that legitimately return 200 OK. But the ALB never tests those paths. Its Target Group health check is configured against `/`, and the application has no route registered at root. So the two sides were validating two completely different things: the humans were validating business endpoints, the ALB was validating an endpoint that never existed in the first place.

### 4.2 Primary root cause

**A configuration mismatch between the ALB health check path and the application's actual routing.** Specifically:
1. The Target Group health check hits `/` → the app returns 404 (outside the healthy 200–399 range) → the ALB marks that target `unhealthy`.
2. The ALB pulls unhealthy targets out of rotation. If that happens while no other target is currently healthy (or a deregistration/draining cycle overlaps it), an incoming request has no valid backend to route to → **502 Bad Gateway**.
3. This is intermittent because the target flaps: each health check interval repeats the same 404 → unhealthy → re-check → 404 cycle, so there are brief windows where a request slips through fine and windows where it doesn't — exactly the pattern reported.

### 4.3 Structured troubleshooting methodology

1. **Isolate the layer** — confirm first whether the fault is in the app, the container, the host, or the load balancer. Work outward: app on localhost → container networking → host → load balancer.
2. **Check Target Group health status** — pull the per-target health state and reason code.
3. **Replay the exact request the ALB sends** — same method, path, and host header — and compare the response against what the ALB expects.
4. **Correlate logs across layers** — container logs, host logs, ALB access logs — line up by timestamp.
5. **Check metric trends** — does the unhealthy count spike in lockstep with the health check interval (config issue) or does it look random (resource exhaustion)?
6. **Reproduce under control** — curl the exact health check path manually to confirm the hypothesis before touching any configuration.

### 4.4 CLI diagnostics on the host EC2 instance

```bash
# Confirm the container is running and check port mapping
docker ps
docker logs <container_id> --tail 200 -f

# Hit the exact paths the ALB uses, from the host itself
curl -i http://localhost:3000/          # this returns 404
curl -i http://localhost:3000/api/health # this returns 200

# Confirm the process is actually bound to 3000
ss -tlnp | grep 3000

# Rule out host-level resource starvation
top -bn1 | head -20
free -h

# Check for restarts or OOM kills
docker inspect <container_id> --format '{{.State.Status}} {{.State.OOMKilled}} {{.RestartCount}}'
```

### 4.5 AWS components & logs to audit

- **Target Group Health Checks** (Console/CLI): `aws elbv2 describe-target-health --target-group-arn <arn>` — check the `Reason` code per target (`Target.ResponseCodeMismatch` is the giveaway here).
- **CloudWatch ALB metrics**: `HealthyHostCount`, `UnHealthyHostCount`, `HTTPCode_ELB_5XX_Count`, `HTTPCode_Target_4XX_Count`, `TargetResponseTime`.
- **ALB access logs** (if enabled to S3): correlate 502 timestamps against which target was unhealthy at that moment.
- **Target Group attributes**: `HealthCheckPath`, `HealthCheckIntervalSeconds`, `HealthyThresholdCount`, `UnhealthyThresholdCount`.

*(On Azure/GCP: check Backend Health on Azure Application Gateway or the Health Check config on GCP HTTP(S) Load Balancing — same underlying principle: compare the configured health check path against the routes the app actually exposes.)*

### 4.6 Long-term fix

1. **Change the Target Group health check path** from `/` to a route that genuinely exists, ideally `/api/health` — and keep that endpoint lightweight, not dependent on heavy downstream calls (DB, cache), so it doesn't produce false negatives when a dependency is just slow.
2. **Codify this in Terraform** rather than editing it manually in the console, so it can't silently drift again (see `terraform/ec2.tf` — the health check path is already parameterized and documented there).
3. If keeping `/` as the root is preferred instead, add a minimal root route in the app that returns 200 — but option 1 is generally the better call, since `/api/health` can be designed as a more meaningful readiness probe.
4. Align the ALB health check definition with the container-level health check (Docker `HEALTHCHECK` instruction) so "healthy" means the same thing at every layer.

### 4.7 Proactive validation to stop this drift from shipping again

- **Policy-as-code on plan review**: gate the Terraform plan with Conftest/OPA that validates the Target Group's `health_check.path` against the routes actually defined in the app (sourced from an OpenAPI spec, for example).
- **Post-deploy smoke test in the pipeline**: after deploying to staging, have the pipeline curl the ALB endpoint directly (not localhost) using the configured health check path, and fail the build on anything other than 2xx.
- **Canary / blue-green deployment**: new targets must prove healthy before receiving full traffic, so a config mistake doesn't take down all users at once.
- **Synthetic monitoring** (CloudWatch Synthetics / Route53 Health Check) continuously hitting the public endpoint and alerting on any drop in `HealthyHostCount` — catches the issue faster than waiting for a user report.
