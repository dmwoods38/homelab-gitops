#!/bin/bash
# Quick etcd health check script
# Usage: ./scripts/check-etcd-health.sh

set -e

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
NODE="192.168.2.20"

echo "========================================="
echo "etcd Health Check - $TIMESTAMP"
echo "========================================="
echo ""

# Get etcd database size
echo "Checking database size..."
DB_SIZE=$(talosctl -n $NODE read /var/lib/etcd/member/snap/db 2>/dev/null | wc -c)
DB_SIZE_MB=$((DB_SIZE / 1024 / 1024))

echo "Database size: ${DB_SIZE_MB}MB (${DB_SIZE} bytes)"

# Get etcd service health
echo ""
echo "Checking etcd service health..."
talosctl -n $NODE service etcd status | head -5

# Check for performance issues in logs
echo ""
echo "Checking for slow queries..."
SLOW_QUERIES=$(talosctl -n $NODE logs etcd --tail 100 2>/dev/null | grep -c "took too long" || echo 0)
echo "Slow queries (last 100 log lines): $SLOW_QUERIES"

# Get auto-compaction settings
echo ""
echo "Auto-compaction settings:"
talosctl -n $NODE logs etcd 2>/dev/null | grep -E "(auto-compaction|quota-backend)" | head -2

# Health assessment
echo ""
echo "========================================="
echo "Assessment:"
echo "========================================="

if [ $DB_SIZE_MB -gt 200 ]; then
  echo "⚠️  CRITICAL: Database size exceeds 200MB!"
  echo "   Action: Run manual defrag immediately"
  echo "   Command: talosctl -n $NODE etcd defrag"
elif [ $DB_SIZE_MB -gt 100 ]; then
  echo "⚠️  WARNING: Database size exceeds 100MB"
  echo "   Action: Monitor closely, consider manual defrag"
elif [ $DB_SIZE_MB -gt 50 ]; then
  echo "ℹ️  INFO: Database size is growing but normal"
  echo "   Action: Continue monitoring"
else
  echo "✓ Database size is healthy (under 50MB)"
fi

if [ "$SLOW_QUERIES" -gt 10 ] 2>/dev/null; then
  echo "⚠️  WARNING: Many slow queries detected ($SLOW_QUERIES)"
  echo "   Action: Consider manual defrag or reboot"
elif [ "$SLOW_QUERIES" -gt 0 ] 2>/dev/null; then
  echo "ℹ️  INFO: Some slow queries detected ($SLOW_QUERIES)"
else
  echo "✓ No slow queries detected"
fi

echo ""
echo "========================================="
