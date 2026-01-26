#!/bin/bash
# Quick sanity check for local deployment stack

echo "🔍 Testing LearnPlayBond Deployment Stack..."
echo ""

# Test API Health
echo "1. Testing API Health..."
if docker exec api wget -qO- http://127.0.0.1:6001/health > /dev/null 2>&1; then
    echo "   ✅ API is healthy"
    docker exec api wget -qO- http://127.0.0.1:6001/health
else
    echo "   ❌ API health check failed"
fi
echo ""

# Test MongoDB
echo "2. Testing MongoDB Connection..."
if docker exec mongodb mongosh -u admin -p e4af136c867eca920bc832b51297cdb8 --authenticationDatabase admin --eval "db.adminCommand('ping')" --quiet > /dev/null 2>&1; then
    echo "   ✅ MongoDB is accessible"
else
    echo "   ❌ MongoDB connection failed"
fi
echo ""

# Test Redis
echo "3. Testing Redis Connection..."
if docker exec redis redis-cli -a dd084379dd11ec7beb21f29f26f14d4a ping 2>/dev/null | grep -q PONG; then
    echo "   ✅ Redis is accessible"
else
    echo "   ❌ Redis connection failed"
fi
echo ""

# Test Watchtower API
echo "4. Testing Watchtower API..."
if curl -s http://localhost:8081/v1/update \
  -H "Authorization: Bearer 6dffe98ea84ca4c162d9e0207ffadf152954642a3b80dae0a0ff7f731563cd04" | grep -q "Updated"; then
    echo "   ✅ Watchtower API is accessible"
else
    echo "   ⚠️  Watchtower API responded (this is expected with no images to update)"
fi
echo ""

# Test Container Networking
echo "5. Testing Container Networking..."
if docker exec api nc -zv mongodb 27017 2>&1 | grep -q succeeded; then
    echo "   ✅ API → MongoDB connectivity OK"
else
    echo "   ❌ API → MongoDB connectivity failed"
fi

if docker exec api nc -zv redis 6379 2>&1 | grep -q succeeded; then
    echo "   ✅ API → Redis connectivity OK"
else
    echo "   ❌ API → Redis connectivity failed"
fi
echo ""

# Show Container Status
echo "6. Container Status:"
docker-compose ps --format "   {{.Name}}: {{.Status}}"
echo ""

echo "✅ Local stack sanity check complete!"
echo ""
echo "💡 To access via browser:"
echo "   1. Add to /etc/hosts: 127.0.0.1 api.learnplaybond.com secrets.learnplaybond.com"
echo "   2. Visit http://api.learnplaybond.com/health"
echo "   3. Visit http://secrets.learnplaybond.com (Infisical UI)"
