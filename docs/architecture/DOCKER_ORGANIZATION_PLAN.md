# Plan d'Organisation Docker - Lyftium Labs
**Date**: 8 Janvier 2025
**Objectif**: Éliminer les doublons et organiser les configurations Docker

---

## 📋 **État Actuel - Analyse des Fichiers**

### Fichier Principal (À Conserver)
- **`docker/services/docker-compose-production-mev.yml`** (720 lignes)
  - Configuration complète optimisée
  - Contient tous les services : Ethereum, Arbitrum, Avalanche, BSC, Optimism, Polygon, Solana
  - Limites de ressources configurées
  - **STATUT**: ✅ À CONSERVER (Fichier principal)

### Fichiers Redondants Identifiés

#### Niveau 1: Versions Obsolètes (À Supprimer)
1. **`docker/services/docker-compose-optimized.yml`** (114 lignes)
   - Version antérieure de la configuration
   - Remplacé par production-mev.yml
   - **ACTION**: 🗑️ SUPPRIMER

2. **`docker/services/docker-compose-base-fix.yml`** (32 lignes)
   - Configuration de base très limitée
   - Fonctionnalité incluse dans production-mev.yml
   - **ACTION**: 🗑️ SUPPRIMER

3. **`docker/services/docker-compose-missing-chains.yml`** (77 lignes)
   - Configuration partielle
   - Services intégrés dans production-mev.yml
   - **ACTION**: 🗑️ SUPPRIMER

#### Niveau 2: Configurations Spécialisées (À Réviser)
1. **`docker/services/docker-compose-optimism-memory.yml`** (114 lignes)
   - Configuration spécifique Optimism
   - **ACTION**: 📝 VÉRIFIER si utile sinon SUPPRIMER

2. **`docker/services/docker-compose-polygon-memory.yml`** (128 lignes)
   - Configuration spécifique Polygon
   - **ACTION**: 📝 VÉRIFIER si utile sinon SUPPRIMER

3. **`docker/services/docker-compose-solana-optimized.yml`** (58 lignes)
   - Configuration spécifique Solana
   - **ACTION**: 📝 VÉRIFIER si utile sinon SUPPRIMER

#### Niveau 3: Fichiers Blockchain Spécifiques (À Organiser)
1. **`arbitrum/docker-compose-fixed.yml`** (1591 bytes)
   - Version ancienne
   - **ACTION**: 🗑️ SUPPRIMER (remplacé par mev-optimized.yml)

2. **`arbitrum/docker-compose-mev-optimized.yml`** (1856 bytes)
   - Configuration spécialisée Arbitrum
   - **ACTION**: 📂 GARDER comme référence spécialisée

3. **`polygon/docker-compose-mev-optimized.yml`**
   - Configuration spécialisée Polygon
   - **ACTION**: 📂 GARDER comme référence spécialisée

4. **`polygon/docker-compose-simple.yml`**
   - Version simplifiée
   - **ACTION**: 📝 VÉRIFIER redondance

5. **`polygon/docker-compose.yml`**
   - Version de base
   - **ACTION**: 📝 VÉRIFIER redondance

---

## 🎯 **Structure Cible Organisée**

### Répertoire Principal
```
/data/blockchain/nodes/
├── docker/
│   └── services/
│       └── docker-compose-production-mev.yml     # ✅ PRINCIPAL
│
├── configs/                                      # 📂 NOUVEAU
│   ├── arbitrum/
│   │   └── docker-compose-mev-optimized.yml     # Référence spécialisée
│   ├── polygon/
│   │   └── docker-compose-mev-optimized.yml     # Référence spécialisée
│   └── specialized/                              # Configs spécialisées
│       ├── optimism-memory.yml
│       ├── polygon-memory.yml
│       └── solana-optimized.yml
│
└── archive/                                      # 🗄️ EXISTANT
    └── docker-configs-20250108/                 # Sauvegarde avant suppression
```

### Environnements (À Conserver)
```
/data/blockchain/nodes/environments/
├── dev/docker-compose.yml                       # ✅ GARDER
├── staging/docker-compose.yml                   # ✅ GARDER
└── prod/docker-compose.yml                      # ✅ GARDER
```

---

## 🗂️ **Actions de Nettoyage**

### Phase 1: Sauvegarde
- [x] Créer répertoire archive
- [ ] Copier tous les fichiers dans archive
- [ ] Vérifier intégrité sauvegarde

### Phase 2: Suppression des Doublons
- [ ] Supprimer `docker-compose-optimized.yml`
- [ ] Supprimer `docker-compose-base-fix.yml`
- [ ] Supprimer `docker-compose-missing-chains.yml`
- [ ] Supprimer `arbitrum/docker-compose-fixed.yml`

### Phase 3: Réorganisation
- [ ] Créer structure `configs/`
- [ ] Déplacer configurations spécialisées
- [ ] Valider configurations restantes
- [ ] Nettoyer fichiers test/source obsolètes

### Phase 4: Validation
- [ ] Tester docker-compose-production-mev.yml
- [ ] Vérifier aucune régression
- [ ] Documenter structure finale

---

## 📊 **Économies Attendues**

### Réduction Fichiers
- **Avant**: 25+ fichiers docker-compose
- **Après**: ~8 fichiers organisés
- **Économie**: 68% de fichiers en moins

### Clarté Configuration
- **1 fichier principal** pour production
- **Configurations spécialisées** bien organisées
- **Environnements** séparés et clairs

---

## ⚠️ **Précautions**

### Fichiers à ne PAS Toucher
- `docker-compose-production-mev.yml` (optimisé récemment)
- Fichiers dans `environments/` (dev/staging/prod)
- `resource-management/configs/` (configurations système)

### Vérifications Obligatoires
- Sauvegarder avant suppression
- Tester fichier principal après nettoyage
- Valider que les services critiques restent fonctionnels

---

**Status**: 📋 Plan créé - Prêt pour exécution
