# LearnPlayBond Deployment

Production deployment configurations for LearnPlayBond using Docker Compose.

## Prerequisites

- Ubuntu 24.04 LTS server (8GB RAM minimum)
- Docker & Docker Compose installed
- Domain configured in Cloudflare
- Terraform outputs (for MongoDB/Redis passwords)

## Quick Start

### 1. Initial Server Setup

Follow the complete server setup guide in the [Infrastructure Runbook](../docs/infrastructure-runbook.md).

### 2. Clone This Repository

```bash
ssh root@your-server-ip
cd /opt
git clone https://github.com/learnplaybond/deployment.learnplaybond.git app
cd app
```

### 3. Create Environment File

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Fill in all required values. Get MongoDB and Redis passwords from Terraform:

```bash
# On your local machine
cd ../infra/terraform
terraform output -json | jq -r '.mongodb_root_password.value'
terraform output -json | jq -r '.redis_password.value'
```

Generate Infisical keys:

```bash
openssl rand -hex 32  # INFISICAL_ENCRYPTION_KEY
openssl rand -hex 32  # INFISICAL_AUTH_SECRET
```

### 4. Create Docker Network

```bash
docker network create web
```

### 5. Deploy

```bash
docker-compose up -d
```

### 6. Verify Deployment

```bash
# Check all services are running
docker-compose ps

# Check logs
docker-compose logs -f

# Test health endpoint
curl http://localhost:3000/health

# Test via domain (after DNS is configured)
curl https://api.learnplaybond.com/health
```

## Services

| Service | Port | Domain | Description |
|---------|------|--------|-------------|
| Traefik | 80/443 | - | Reverse proxy with SSL |
| API | 3000 (internal) | api.learnplaybond.com | Fastify backend |
| MongoDB | 27017 (internal) | - | Database |
| Redis | 6379 (internal) | - | Cache |
| Infisical | 8080 (internal) | secrets.learnplaybond.com | Secrets management |
| Backup | - | - | Automated MongoDB backups |
| Watchtower | - | - | Automated container updates |

## DNS Configuration

Create these records in Cloudflare:

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| A | api | your-server-ip | ✅ Orange cloud |
| A | secrets | your-server-ip | ✅ Orange cloud |

## Secrets Management with Infisical

The API integrates with Infisical for secure secrets management in production.

### How It Works

1. **Development**: API reads secrets from `.env` file
2. **Production**: API fetches secrets from Infisical at startup using the Infisical SDK

### Setup Infisical

After deploying the infrastructure, configure Infisical:

1. **Access Infisical UI**
   ```bash
   # Open in browser
   https://secrets.learnplaybond.com

   # Or use server IP temporarily
   http://your-server-ip:8080
   ```

2. **Create Admin Account**
   - First user becomes the admin
   - Use a strong password

3. **Create Project**
   - Name: `LearnPlayBond Production`
   - Environment: `production`

4. **Add Application Secrets**

   Add these secrets in Infisical UI (Project Settings → Secrets):

   ```
   FIREBASE_PROJECT_ID=your-firebase-project-id
   FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project-id.iam.gserviceaccount.com
   FIREBASE_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n
   RAZORPAY_KEY_ID=rzp_live_xxxxx
   RAZORPAY_SECRET=your_razorpay_secret
   OPENAI_API_KEY=sk-proj-xxxxx
   EMAIL_USER=your_email@gmail.com
   EMAIL_PASS=your_app_specific_password
   SENTRY_DSN=https://xxxxx@oxxxxx.ingest.sentry.io/xxxxx
   ```

5. **Create Service Token**

   ```bash
   # In Infisical UI: Project Settings → Service Tokens
   # 1. Click "Create Service Token"
   # 2. Name: "API Production"
   # 3. Environment: "production"
   # 4. Permissions: Read
   # 5. Copy the token (starts with "st.prod.xxxxx")
   ```

6. **Update .env File**

   Add the Infisical credentials to `/opt/app/.env`:

   ```bash
   INFISICAL_TOKEN=st.prod.xxxxx
   INFISICAL_PROJECT_ID=xxxxx
   ```

7. **Restart API**

   ```bash
   docker-compose restart api

   # Verify API loaded secrets from Infisical
   docker-compose logs api | grep -i infisical
   # Should see: "Infisical: Secrets loaded successfully"
   ```

### Rotating Secrets

To rotate a secret:

1. Update the secret value in Infisical UI
2. Restart the API container: `docker-compose restart api`
3. The API will fetch the updated secrets on startup

### Troubleshooting Infisical

```bash
# Check Infisical container status
docker-compose ps infisical

# View Infisical logs
docker-compose logs infisical

# Test Infisical connection
docker exec infisical wget -qO- http://localhost:8080/api/status

# Verify API has Infisical token
docker-compose exec api printenv | grep INFISICAL
```

## Automated Deployments

Watchtower automatically updates the API container when new images are pushed to GitHub Container Registry.

### How It Works

1. **CI/CD pushes new image** → GitHub Actions builds and pushes to `ghcr.io/learnplaybond/api.learnplaybond:latest`
2. **Watchtower detects update** → Checks for new images every 5 minutes
3. **Automatic deployment** → Pulls new image, stops old container, starts new one
4. **Slack notification** → Sends update status to your Slack channel
5. **Cleanup** → Removes old unused images

### Configuration

- **Poll Interval**: 5 minutes (300 seconds)
- **Update Strategy**: Rolling restart (zero downtime)
- **Monitored Containers**: Only containers with `com.centurylinklabs.watchtower.enable=true` label
- **Cleanup**: Automatically removes old images after update
- **Notifications**: Slack alerts for updates and failures

### Disable Automated Updates

To update manually instead:

```bash
# Stop Watchtower
docker-compose stop watchtower

# Update manually
docker-compose pull api
docker-compose up -d api
```

## Deployment Commands

> **Note:** Watchtower automatically updates the API container. Manual updates are optional.

```bash
# View logs
docker-compose logs -f
docker-compose logs -f api
docker-compose logs -f watchtower

# Restart a service
docker-compose restart api

# Manual update (if Watchtower is disabled)
docker-compose pull api
docker-compose up -d api

# Stop all services
docker-compose down

# Stop and remove volumes (destructive!)
docker-compose down -v
```

## Updating the Application

### Automatic Updates (Recommended)

Watchtower handles this automatically:
1. Push code to GitHub
2. CI/CD builds and pushes Docker image
3. Watchtower detects new image within 5 minutes
4. Container updates automatically
5. Slack notification confirms deployment

### Manual Updates

If you need to update manually or pull deployment configuration changes:

```bash
cd /opt/app

# Pull latest deployment configuration
git pull

# Pull latest Docker images
docker-compose pull

# Recreate containers with new images
docker-compose up -d

# Check status
docker-compose ps
docker-compose logs -f api
```

## Backup & Recovery

### Manual Backup

```bash
# Trigger manual backup
docker exec mongo-backup /usr/local/bin/backup-now

# List backups
docker exec mongodb ls -la /backup/

# Copy backup locally
docker cp mongodb:/backup/latest.gz ./mongodb-backup-$(date +%Y%m%d).gz
```

### Restore from Backup

```bash
# Stop API to prevent writes
docker-compose stop api

# Restore from backup file
docker cp ./backup.gz mongodb:/tmp/restore.gz
docker exec mongodb mongorestore \
  -u admin -p YOUR_PASSWORD \
  --authenticationDatabase admin \
  --gzip --archive=/tmp/restore.gz

# Restart API
docker-compose up -d api
```

## Troubleshooting

### Check Service Health

```bash
# Check which services are unhealthy
docker-compose ps

# View specific service logs
docker-compose logs api
docker-compose logs mongodb
docker-compose logs traefik
```

### SSL Certificate Issues

```bash
# Check Traefik logs for ACME errors
docker-compose logs traefik | grep -i acme

# Verify DNS is configured correctly
dig api.learnplaybond.com
```

### Database Connection Issues

```bash
# Test MongoDB connection
docker exec mongodb mongosh \
  -u admin -p YOUR_PASSWORD \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"

# Check MongoDB logs
docker-compose logs mongodb
```

### Container Resource Issues

```bash
# Check resource usage
docker stats

# Check disk space
df -h

# Check logs size
du -sh /var/lib/docker/containers/*/*-json.log
```

### Watchtower Not Updating

```bash
# Check Watchtower logs
docker-compose logs watchtower

# Verify API container has the label
docker inspect api | grep watchtower

# Manually trigger update
docker-compose restart watchtower

# Check if new image is available
docker pull ghcr.io/learnplaybond/api.learnplaybond:latest

# Common issues:
# - GitHub Container Registry authentication
# - Container not labeled for updates
# - Slack webhook URL not configured
```

## Security Checklist

- [ ] `.env` file has 600 permissions
- [ ] `.env` is in .gitignore (verified)
- [ ] All secrets are strong (32+ characters)
- [ ] Cloudflare proxy is enabled (orange cloud)
- [ ] Server firewall configured (SSH, HTTP, HTTPS only)
- [ ] fail2ban installed and running
- [ ] Automatic security updates enabled
- [ ] Backups tested and verified
- [ ] Slack webhook configured for Watchtower notifications
- [ ] Test deployment completed successfully

## Monitoring

After deployment, configure Netdata as described in the [Infrastructure Runbook](../docs/infrastructure-runbook.md#monitoring--alerting).

## Related Documentation

- [Infrastructure Runbook](../docs/infrastructure-runbook.md) - Complete infrastructure guide
- [API Repository](https://github.com/learnplaybond/api.learnplaybond) - Backend application
- [Infra Repository](https://github.com/learnplaybond/infra.learnplaybond) - Terraform configuration
