# Preuves J5 — PostgreSQL cloud (Neon) (26/11/2026)

| Fichier | Ce qu'il prouve |
|---|---|
| `1-neon-schema-3-tables.png` | Schéma initialisé dans Neon (`init.sql` exécuté une fois) : tables `users`, `quiz_results`, `answers` |
| `2-neon-donnees-ecrites-par-azure.png` | Inscription + quiz faits sur l'URL Azure → ligne présente dans Neon (score 4/20) |
| `3-restart-et-secrets-azure.png` | Redémarrage de la révision backend ; secrets listés **par nom uniquement** (`database-url`, …) ; `DATABASE_URL` référencée en `secretRef` |
| `4-persistance-apres-restart.txt` | Après redémarrage, l'API admin renvoie toujours le résultat enregistré avant |

Aucune chaîne de connexion, aucun mot de passe ni jeton n'apparaît dans ces preuves.
