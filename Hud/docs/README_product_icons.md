# Visuels des composants dans le HUD

Dans la notecard de définition de tout Component (ingrédient ou conteneur) :

```text
icon=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

ou :

```text
icon=Nom exact de la texture
```

Un UUID valide est transmis directement, en minuscules. Un nom est résolu par
`llGetInventoryKey()` après vérification du type `INVENTORY_TEXTURE` dans la prim
du script Component. La texture doit être copy/modify/transfer pour que la fonction
renvoie son UUID. Le HUD n'a pas besoin de posséder cette texture.
Champ absent, vide, nom introuvable, mauvais type ou permissions insuffisantes :
aucune icône spécifique n'est annoncée et le renderer utilise son secours actuel
(case 12 de l'atlas sur P0/P3, puis DEFAULT_ICON si l'atlas manque ; DEFAULT_ICON sur P1).
Un UUID syntaxiquement valide est transmis sans contrôle de disponibilité de l'asset.

Le conteneur conserve sa propre référence `icon` après CONFIG/remplissage. Le nom
ou UUID brut est sauvegardé dans `rz_icon` ; la notecard présente reste prioritaire,
y compris si son champ icon est supprimé ou vidé. Une modification d'inventaire
déclenche le reset déjà présent dans Component, puis une nouvelle lecture.

## Messages et compatibilité

Le protocole reste 5. L'UUID est un champ optionnel final :

```text
HERE|key|name|qty|use|life|taxonomy|stage|propsPacked|5|eff|mesh|organ[|iconUUID]
BLANK|key|capacity[|iconUUID]
```

Sans icône valide, le message conserve son format d'origine (13 ou 3 champs).
`organ` reste à l'index 12 ; `iconUUID` est à l'index 13 de HERE et 3 de BLANK.
MC_Scan et son relais conservent déjà les messages complets : aucune modification
n'est nécessaire dans ces scripts. Workshop_HUD et Workshop_Output acceptent
les deux longueurs, sans changement des calculs ou du message CONFIG.

Les vues gardent leurs 18 champs : page, total, puis quatre fois
`[nom, quantité, icône, occupé]`. P0 Nearby/Selected et P1 lisent désormais l'index
13 au lieu de confondre l'icône avec organ. Toutes les faces du renderer P1 sont
alignées sur la face 1, comme les renderers P0/P3. Son garde existant sur la présence
de P1_Table1 est conservé ; ce changement ne crée aucune prim dans le HUD.

P3 regroupe par nom d'objet et UUID d'icône résolu (chaîne vide pour le secours).
Même nom et même icône : un compteur commun. Icônes différentes : lignes distinctes.
Les lignes de transfert restent `[UUID individuel, nom, capacité]`. La sélection
reste limitée à un groupe à la fois ; sélectionner un autre couple nom/icône la
remplace. Seuls les UUID effectivement sélectionnés sont transférés.
Le septième champ du record `mc:p3:selection` conserve les icônes des UUID
sélectionnés. Les anciens records de quatre ou six champs restent acceptés
avec secours, puis récupération des icônes au prochain scan terminé.

## Installation et vérification

Mettre à jour ensemble : Component.lsl ; MC_Nearby_Controller.lsl,
MC_Selected_Controller.lsl, MC_P1_Controller.lsl, MC_P3_Controller.lsl,
MC_Render_P1.lsl ; Workshop_HUD.lsl et Workshop_Output.lsl.
Les renderers P0/P3 et MC_Scan existants sont compatibles sans changement.

Lancer `Hud/tests/run_product_icon_checks.ps1` : analyse syntaxe/types et tests
sur les AST des scripts réels, avec services d'inventaire et d'affichage simulés.
Ces tests ne remplacent pas une compilation et une vérification dans Second Life.

Dans Second Life, vérifier sur la face 1 :

1. Afficher un ingrédient avec UUID, puis avec nom de texture full-perm.
2. Tester un ancien composant, icon vide, nom absent et texture sans full-perm.
3. Passer d'une page pleine à une page partielle : chaque ligne garde son icône,
   et les lignes inoccupées masquent icône/quantité et effacent leur nom.
4. Réutiliser une ligne passée par spécifique → secours → vide → spécifique :
   UV complets et alpha 1 doivent être rétablis pour un visuel spécifique.
5. En P3, découvrir des conteneurs de même nom avec deux icônes différentes,
   vérifier deux lignes et leurs compteurs, sélectionner/remplir et vérifier
   l'icône conservée. Après reset/Refresh, vérifier sélection et transfert.
