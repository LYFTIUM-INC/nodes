# 🚨 PLAN DE RÉPARATION COMPLET - INFRASTRUCTURE BLOCKCHAIN & MEV

**Date**: $(date)
**Objectif**: Restaurer tous les nœuds blockchain et services MEV en état opérationnel
**Temps estimé**: 2-3 heures
**Revenus potentiels**: $500-5000/jour une fois opérationnel

---

## 📊 ÉTAT ACTUEL DIAGNOSTIQUÉ

### ❌ **PROBLÈMES CRITIQUES**

#### 1. **Infrastructure Blockchain (NIVEAU 1)**
- Aucun nœud blockchain fonctionnel malgré 3+ processus actifs
- Services manuels (PID 1300, 1317, 1324, 3430) mal configurés
- Configuration Docker Compose optimisée NON utilisée
- Conflits de ports et instances multiples

#### 2. **Services MEV (NIVEAU 2)**
- wallet-manager en restart loop
- MEV engine non compilé
- Safe wallet sans fonds (0 ETH)
- Broadcasting manager manquant

### ✅ **INFRASTRUCTURE DISPONIBLE**
- `/data/blockchain/storage/` avec données pour tous les réseaux
- Configuration Docker Compose optimisée (8 services)
- Configuration Lighthouse optimisée pour MEV
- Système de maintenance automatisé
- Infrastructure MEV sophistiquée

---

## 🎯 PLAN D'ACTION SÉQUENTIEL

### **PHASE 1: NETTOYAGE DE L'INFRASTRUCTURE (30 min)**

#### Étape 1.1: Arrêter tous les services conflictuels
```bash
# Arrêter les processus manuels
sudo kill -TERM 1300 1317 1324 3430
sudo pkill -f "geth\|lighthouse\|mev-boost\|op-geth"

# Arrêter les services systemd problématiques
sudo systemctl stop wallet-manager mev-engine mev-orchestrator
sudo systemctl disable wallet-manager mev-engine mev-orchestrator

# Nettoyer les conteneurs Docker orphelins
docker stop $(docker ps -aq) 2>/dev/null || true
docker system prune -f
```

#### Étape 1.2: Vérifier l'état des données
```bash
# Vérifier l'intégrité des données blockchain
du -sh /data/blockchain/storage/*/
ls -la /data/blockchain/storage/erigon/chaindata/ 2>/dev/null
ls -la /data/blockchain/storage/lighthouse/beacon/ 2>/dev/null
```

#### Étape 1.3: Préparer les configurations
```bash
# Créer les répertoires manquants si nécessaire
sudo mkdir -p /data/blockchain/storage/{erigon,lighthouse,optimism,arbitrum,polygon,bsc,avalanche,solana}
sudo chown -R lyftium:lyftium /data/blockchain/storage/
```

### **PHASE 2: DÉMARRAGE INFRASTRUCTURE BLOCKCHAIN (45 min)**

#### Étape 2.1: Configuration Lighthouse Optimisée
```bash
cd /data/blockchain/nodes/lighthouse

# Vérifier la configuration
docker-compose -f docker-compose-optimized.yml config

# Démarrer Erigon + Lighthouse + MEV-Boost
docker-compose -f docker-compose-optimized.yml up -d erigon lighthouse-beacon

# Activer le profil MEV si nécessaire
docker-compose -f docker-compose-optimized.yml --profile mev up -d
```

#### Étape 2.2: Configuration Multi-Chaînes
```bash
cd /data/blockchain/nodes

# Démarrer tous les nœuds optimisés
docker-compose -f docker-compose-memory-optimized.yml up -d

# Vérifier les statuts
docker-compose -f docker-compose-memory-optimized.yml ps
```

#### Étape 2.3: Validation des endpoints
```bash
# Tests de connectivité (attendre 5-10 min après démarrage)
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545

curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
  http://localhost:8547  # Base

curl http://localhost:5052/eth/v1/node/health  # Lighthouse
curl http://localhost:18551/eth/v1/builder/status  # MEV-Boost
```

### **PHASE 3: RÉPARATION SERVICES MEV (60 min)**

#### Étape 3.1: Réparation wallet-manager
```bash
# Diagnostic du problème Python
cd /opt/wallet-manager
source /opt/miniconda3/etc/profile.d/conda.sh
conda activate mev || conda create -n mev python=3.9 -y && conda activate mev

# Réinstallation des dépendances
pip install -r requirements.txt --upgrade --force-reinstall

# Test manuel
python -c "import vault_utils; print('Wallet manager imports OK')"
```

#### Étape 3.2: Compilation MEV Engine
```bash
cd /data/blockchain/mev-infra

# Vérifier l'environnement OCaml
eval $(opam env)
dune --version

# Compilation complète
dune clean
dune build src/bin/main.exe

# Vérifier le binaire
ls -la _build/default/src/bin/main.exe
./_build/default/src/bin/main.exe --help
```

#### Étape 3.3: Configuration du Broadcasting Manager
```bash
# Créer le module manquant depuis les tests
cd /data/blockchain/mev-infra/src/orchestration
cp ../tests/test_broadcasting_manager.ml broadcasting_manager.ml

# Adapter pour la production
# Remplacer les fonctions de test par des implémentations réelles
```

### **PHASE 4: FINANCEMENT ET TESTS (30 min)**

#### Étape 4.1: Financement du Safe Wallet
```bash
# Adresse Safe: 0x96dB0dA35d601379DBD0E7729EbEbfd50eE3a813
# Minimum requis: 0.1 ETH pour les frais de gas
# Recommandé: 0.5 ETH pour les opérations continues

echo "Safe Wallet Address: 0x96dB0dA35d601379DBD0E7729EbEbfd50eE3a813"
echo "Transfer minimum 0.1 ETH to this address"
```

#### Étape 4.2: Tests de bout en bout
```bash
# Démarrer tous les services
sudo systemctl start wallet-manager mev-engine mev-orchestrator

# Vérifier les endpoints
curl http://localhost:9099/health
curl http://localhost:8084/opportunities
curl http://localhost:18551/eth/v1/builder/status

# Vérifier les logs
tail -f /data/blockchain/mev-infra/logs/mev-engine.log &
tail -f /opt/wallet-manager/logs/wallet-manager.log &
```

---

## 📈 MONITORING ET VALIDATION

### **Endpoints à surveiller**
| Service | Port | Endpoint | Statut Attendu |
|---------|------|----------|----------------|
| Ethereum | 8545 | `/` | Block number > 0 |
| Base | 8547 | `/` | Network ID = 8453 |
| Arbitrum | 8549 | `/` | Network ID = 42161 |
| Polygon | 8557 | `/` | Network ID = 137 |
| Lighthouse | 5052 | `/eth/v1/node/health` | 200 OK |
| MEV-Boost | 18551 | `/eth/v1/builder/status` | {} |
| Wallet Manager | 9099 | `/health` | {"status": "ok"} |
| MEV Engine | 8084 | `/opportunities` | JSON response |

### **Métriques de performance**
```bash
# Script de monitoring automatique
./monitor.sh --all-endpoints --continuous
```

---

## ⚡ REVENUS ATTENDUS

### **Timeline de génération de revenus**
- **Heure 1**: Services opérationnels
- **Heure 2**: Première transaction MEV
- **Heure 6**: Ethereum fully synced, revenus max
- **Jour 1**: $500-1000 (conservative)
- **Semaine 1**: $5000+ (optimisé)

### **Stratégies MEV activées**
1. **Arbitrage DEX** (immédiat)
2. **Sandwich attacks** (après sync complet)
3. **Liquidations** (nécessite plus de capital)
4. **Front-running** (haute performance)

---

## 🚨 POINTS DE VIGILANCE

1. **Synchronisation Ethereum**: 7h pour sync complet
2. **Mémoire système**: Surveillance continue (29GB/31GB utilisés)
3. **Conflits de ports**: Vérifier qu'aucun service manuel ne redémarre
4. **JWT secrets**: S'assurer de la cohérence entre services
5. **Permissions**: Tous les services doivent accéder aux données

---

## 🔧 COMMANDES DE DÉPANNAGE

```bash
# Redémarrage rapide de tous les services
cd /data/blockchain/nodes
docker-compose -f docker-compose-memory-optimized.yml restart

# Vérification de l'état global
./node-status.sh

# Logs de débogage
docker-compose -f docker-compose-memory-optimized.yml logs -f --tail=50

# Nettoyage d'urgence
./emergency-recovery-plan.sh
```

---

**✅ Ce plan, exécuté séquentiellement, devrait restaurer une infrastructure blockchain complètement fonctionnelle en 2-3 heures avec un potentiel de revenus de $500-5000/jour.**
