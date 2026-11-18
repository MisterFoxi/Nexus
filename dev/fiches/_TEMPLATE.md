# Fiche — <NomScript>

*Fiche de dev & suivi. À dupliquer pour chaque script. Voir `CONVENTIONS.md`.*

---

## Rôle

> Une seule phrase. La responsabilité unique du script. Si tu en écris deux, découpe le script.

## Version courante

`v0.0.0 (AAAA-MM-JJ)` — préproc : `#define SCRIPT_VERSION` / `SCRIPT_DATE`

## Journal

| Version | Date | Changement |
|---|---|---|
| v0.0.0 | AAAA-MM-JJ | création |

## Dépendances

- **Scripts** (mêmes linkset / autres objets) : …
- **Canaux** (whisper/region say) : …
- **Clés LinksetData** lues / écrites : …
- **Include** : `nexus_header.lsl` (bannière + report mémoire)

## Interfaces (messages)

| Sens | Code / verbe | Payload | Déclencheur / effet |
|---|---|---|---|
| in | … | … | … |
| out | … | … | … |

## État & persistance

- Phases possibles : …
- Ce qui est persistant (survit reset/re-rez) : …
- Ce qui est transitoire : …

## Mémoire

- `free` au boot : … o
- min observé sous charge : … o
- notes (listes non bornées, risques) : …

## Points ouverts / dette

> Chaque `// REVIEW:` du code est recopié ici, daté. Rien ne se perd.

- [ ] …
