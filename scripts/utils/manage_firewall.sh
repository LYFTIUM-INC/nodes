#!/bin/bash
# Firewall Management Script

case "$1" in
    status)
        echo "=== Firewall Status ==="
        sudo iptables -L -n -v
        echo ""
        echo "=== fail2ban Status ==="
        sudo fail2ban-client status
        ;;
    restart)
        echo "Restarting firewall and fail2ban..."
        sudo systemctl restart fail2ban
        sudo iptables-restore < /etc/iptables/rules.v4
        ;;
    logs)
        echo "=== Recent firewall logs ==="
        sudo tail -n 50 /var/log/kern.log | grep -E "(DROPPED|SSH_CONNECT|MEV_UNAUTHORIZED)"
        echo ""
        echo "=== fail2ban logs ==="
        sudo tail -n 20 /var/log/fail2ban.log
        ;;
    ban-list)
        echo "=== Currently banned IPs ==="
        sudo fail2ban-client status sshd
        sudo fail2ban-client status blockchain-rpc
        sudo fail2ban-client status mev-dashboard
        ;;
    *)
        echo "Usage: $0 {status|restart|logs|ban-list}"
        exit 1
        ;;
esac
