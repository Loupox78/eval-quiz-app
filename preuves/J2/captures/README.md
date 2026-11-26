# Captures J2 — Trivy avant / après (26/11/2026, macOS, Trivy installé via `brew install trivy`)

Image « avant » reconstruite à partir du Dockerfile backend de J1 (commit `616e223`) :
```bash
git show 616e223:backend/Dockerfile | docker build -f - -t quiz-backend:avant ./backend
docker compose build      # images "après" : quiz-backend:local, quiz-frontend:local
```

| Capture | Commande | Ce qu'elle prouve |
|---|---|---|
| `1-avant-backend-high-critical.png` | `trivy image -q --scanners vuln --severity HIGH,CRITICAL quiz-backend:avant \| grep -E "Total\|CRITICAL"` | Image J1 : 7 HIGH (Alpine) + 21 HIGH et **1 CRITICAL** (`tar` CVE-2026-59873, embarqué par npm) |
| `2-comparaison-avant-apres.png` | `trivy image -q --scanners vuln --severity HIGH,CRITICAL --format json <image> \| grep -c '"Severity"'` | 29 failles HIGH/CRITICAL avant → **0** pour le backend et le frontend après correction |
| `3-controle-bloquant-exit-code.png` | `trivy image -q --scanners vuln --severity CRITICAL --exit-code 1 --format json <image> > /dev/null; echo $?` | Règle de la CI : l'image avant **échoue** (code 1), l'image corrigée **passe** (code 0) |

Rapports Trivy complets : `../avant/` et `../apres/`. Analyse et justifications : `docs-groupe/J2-securite-trivy.md`.
