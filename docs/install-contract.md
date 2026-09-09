# What is the “install contract”?

In this project, **contract** does not mean a legal document. It means an **agreed interface** between you (vendor) and Halden (customer): fixed inputs, fixed steps, and fixed pass/fail checks so both sides know when an install is correct — without you needing access to their cluster.

Think of it like an API spec, but for deployment.

## The problem BYOC creates

In a normal SaaS deploy, you own the cluster and run CD yourself.

In **Bring Your Own Cloud**, Halden owns:

- The Kubernetes cluster (GKE, on-prem, etc.)
- The private container registry
- TLS certificates and DNS
- Kyverno / network policies (possibly adapted from your manifests)
- Their change window and approval process

You cannot “CD into prod” for them. You ship **artifacts + rules for how to use them**. That artifact + rules bundle is the **install contract**.

## The three parts of the contract

```
┌─────────────────────────────────────────────────────────────┐
│  1. INPUTS — what the customer must provide                 │
│     global.registry, publicUrl, secrets, ingress class      │
├─────────────────────────────────────────────────────────────┤
│  2. PROCEDURE — ordered steps both sides expect             │
│     mirror images → preflight → helm install → smoke test   │
├─────────────────────────────────────────────────────────────┤
│  3. ACCEPTANCE — objective pass/fail                        │
│     preflight exits 0, smoke-test exits 0, checklist signed │
└─────────────────────────────────────────────────────────────┘
```

### 1. Inputs (required values)

Documented in `values-customer.example.yaml` and [customer-install.md](customer-install.md).

| Input | Why it matters |
|-------|----------------|
| `global.registry` | All images must pull from Halden’s private registry |
| `publicUrl` | Cap UI + desktop app need the correct external URL |
| `s3PublicUrl` | Uploads go to Minio at this URL |
| `secrets.*` | Auth, DB, encryption — must not use dev defaults in prod |

If inputs are wrong, install may succeed but the app will not work. The contract says **which fields are mandatory**.

### 2. Procedure (scripts)

| Script | Contract role |
|--------|----------------|
| `scripts/preflight.sh` | **Precondition gate** — registry reachable, images present, (optional) cage policies exist |
| `scripts/install.sh` | **Install procedure** — helm upgrade with correct values and timeouts |
| `scripts/smoke-test.sh` | **Post-install verification** — runs the smoke test suite |

Halden runs these in **their** environment. You run the same scripts on the **reference cage** to prove they work before shipping.

`PREFLIGHT_PROFILE` adapts the contract to context:

| Profile | Use when |
|---------|----------|
| `cage` (default) | Reference kind cage — checks egress proxy, kind cluster |
| `byoc` | Customer cluster — checks registry + images only; uses their kubectl context |

### 3. Acceptance (tests + checklist)

| Check | What “pass” means |
|-------|-------------------|
| `tests/smoke/*` | `/login` returns 200, Cap pods ready, Minio healthy |
| `tests/e2e/10-airgap.sh` | Reference cage only — Cap serves with egress fully denied |
| `proof/security-checklist.md` | Human sign-off on controls |
| `scripts/verify-proof.sh` | Proof files exist before you cut a release |

**Smoke pass = “install is good enough to hand to users.”**  
**E2e + proof = “the security pattern works on the reference cage.”**

## What the contract is NOT

| In scope | Out of scope |
|----------|--------------|
| Helm chart installs on Kubernetes 1.28+ | Halden’s exact GKE node pool sizing |
| Images from customer’s registry | You mirroring into their registry for them |
| Scripts pass on reference cage | GHA deploying to Halden prod |
| Policy manifests as examples | Halden’s SOC2 audit (they own prod evidence) |

## Vendor vs customer responsibilities

| Responsibility | Vendor (you) | Customer (Halden) |
|----------------|--------------|-------------------|
| Helm chart quality | ✅ | |
| Reference proof (airgap log) | ✅ | |
| Release bundle + checksum | ✅ | |
| Mirror images to their registry | | ✅ |
| Set values / secrets | | ✅ |
| Apply policies in their cluster | | ✅ |
| Run preflight + smoke in their lab | | ✅ |
| Prod sign-off | | ✅ |

## Where this lives in the repo

```
values-customer.example.yaml   ← input template
scripts/preflight.sh           ← precondition gate
scripts/install.sh             ← install procedure
scripts/smoke-test.sh          ← acceptance entrypoint
tests/smoke/                   ← automated acceptance criteria
proof/security-checklist.md    ← manual acceptance criteria
docs/customer-install.md       ← full handoff guide for Halden
```

## One-line summary

> **The install contract is: “Give us these values, run these scripts in this order; if smoke tests pass, the install meets spec.”**

That is what makes BYOC auditable without shared cluster access.

## Related

- [Release process](release.md) — how you package and tag the bundle
- [Customer install guide](customer-install.md) — step-by-step for Halden
