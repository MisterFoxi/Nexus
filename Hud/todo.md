# TODO — MC_Workshop_Link (endpoint MCW côté HUD)

Revue du 2026-11-04. Le protocole d'échange HUD ⇄ bench est cohérent de
bout en bout (enveloppes, compte de champs, indices, idempotence, ACK/retry,
discipline « ne jamais rejouer une commande radio »). Rien à corriger sur le
fil lui-même. Les points ci-dessous concernent la **généricité** (objectif :
un seul fichier transport réutilisé par les 5 HUDs de production, à
`HUD_KIND` près) et la robustesse du mode dégradé.

## 1. Bloquant généricité — retirer la connaissance du `cutting_board`

Seule branche de tout le script qui teste une valeur de `kind` en dur :

- `state_entry` : `if (HUD_KIND == "cutting_board") gKeep = FALSE;`
- `listen` / OFFER : idem
- `choose` : `if (choice == "KEEP" && (!gKeep || HUD_KIND == "cutting_board"))`

Le bench annonce déjà `gKeep` dans l'`OFFER` (`fields[7]`). Le client ne
devrait qu'honorer ce flag, pas le ré-dériver et écraser l'annonce serveur.

→ Supprimer les trois overrides `HUD_KIND == "cutting_board"`.
→ Laisser `!gKeep` seul décider dans `choose`.
→ La règle « ici on ne garde pas » revient à la config de la station
  (le cutting_board doit livrer `keep = 0` dans sa `bench_config`).

Effet : `MC_Workshop_Link.lsl` devient mono-source, identique pour les 5
HUDs — seule la ligne `HUD_KIND = "..."` change par build.

## 2. Robustesse — notifier le mode dégradé des attentes radio

`WAIT_BEGIN` / `WAIT_ROW` / `WAIT_RESULT` / `WAIT_TRANSFER` n'ont pas de
reprise auto (choix assumé : ne rien rejouer). Mais la seule notification au
deadline est un `llOwnerSay` unique, puis `gDeadline = 0` → plus aucun rappel.
Si un ACK se perd, le joueur reste bloqué sans savoir qu'il doit cliquer
`RETRY`.

→ Rappel périodique au timer tant qu'on est en `WAIT_*` avec `gWire != ""`,
  ou état visible « action requise : Retry ». Ne rien re-whisperer
  automatiquement (garder la discipline actuelle).

## 3. À vérifier (pas tranché en revue)

- Bornes de chaleur en dur `0..30` dans le parseur de geste : acceptable si
  le parseur est spécifique au HUD « cuire ». À confirmer selon que le geste
  est partagé ou non entre productions.
- Côté bench (hors de ce dépôt) : phase `OUTPUT`/`SETTLING`/`PRODUCT` de
  `Workshop.lsl` sans watchdog, contrairement à `EVALUATING` et au `BEGIN`
  en attente — stall possible sans message owner si `Output` reste muet.
  (Noté ici pour mémoire ; action côté repo Workshop.)
