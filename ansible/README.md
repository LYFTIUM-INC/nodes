# Ansible Roles for Node Management (Phase 2)

Ansible roles for LYFTIUM MEV Lab node management automation. Part of the Phase 2 automation roadmap (see [NODE_MANAGEMENT_AUTOMATION_2026.md](../docs/research/NODE_MANAGEMENT_AUTOMATION_2026.md)).

**Roles:** `erigon`, `lighthouse`, `mev-boost`, `monitoring`

## Quick Start

```bash
# 1. Copy inventory (from repo root)
cp ansible/inventory.example ansible/inventory

# 2. Dry run (check mode)
ansible-playbook -i ansible/inventory ansible/site.yml --tags mev-boost --check
# If mev-boost binary is not installed, add: -e "mev_boost_require_binary=false"

# 3. Run for real
ansible-playbook -i ansible/inventory ansible/site.yml --tags mev-boost
```

Optionally copy `ansible/group_vars/nodes.yml.example` to `ansible/group_vars/nodes.yml` and adjust paths.

---

**Usage:**

```bash
ansible-playbook -i inventory site.yml
```

**Prerequisites:**

- Ansible 2.14+
- SSH access to target hosts
- Python 3 on remote hosts

---

*Owner: Infrastructure / MEV Team*
