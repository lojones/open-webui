# Azure Container Apps Deployment Guide

This guide explains how to set up automated deployment of Open WebUI to Azure Container Apps with GitHub Actions.

## Architecture Overview

The deployment pipeline consists of:
1. **Build Stage**: GitHub Actions builds and pushes Docker images to GitHub Container Registry (GHCR) when code is pushed to `lojoai-customization` branch
2. **Deploy Stage**: GitHub Actions deploys the latest image to Azure Container Apps when code is merged to `main` branch
3. **Authentication**: Uses Azure OIDC (OpenID Connect) for passwordless authentication between GitHub and Azure

## Prerequisites

- Azure subscription with Container Apps enabled
- GitHub repository with Actions enabled
- Azure CLI installed locally
- GitHub CLI installed locally
- Supabase database instance (or other PostgreSQL database)

## Initial Setup

### 1. Run the Setup Script

The setup script will configure all necessary Azure resources and GitHub secrets:

```powershell
# From the scripts directory
.\setup-azure-deployment.ps1
```

When running the script, you'll be prompted to either:
- **Set new secrets**: Enter your Supabase connection details which will be stored as GitHub secrets
- **Use existing secrets**: Skip secret configuration if you've already set them up

This script will:
- Create an Azure service principal with OIDC federation
- Configure GitHub repository secrets
- Set up GitHub environments (production/staging)
- Prompt for and store Supabase credentials securely

### 2. Verify GitHub Secrets

After running the setup script, verify these secrets exist in your repository:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `SUPABASE_HOST`
- `SUPABASE_PORT`
- `SUPABASE_USER`
- `SUPABASE_DATABASE`
- `SUPABASE_PASSWORD`

## Deployment Workflow

### Automatic Deployment

1. **Development**: Work on the `lojoai-customization` branch
2. **Build**: Push changes to trigger the build workflow
3. **Deploy**: Merge to `main` to trigger automatic deployment

### Manual Deployment

You can also trigger deployments manually:

1. Go to the Actions tab in GitHub
2. Select "Deploy to Azure Container Apps"
3. Click "Run workflow"
4. Choose the environment (production/staging)

## Customization

### Environment Variables

Edit `.github/workflows/deploy-to-azure.yml` to modify environment variables:

```yaml
env:
  RESOURCE_GROUP: lojoweb-rg
  LOCATION: eastus
  APP_NAME: openwebui-app3
  ENV_NAME: openwebui-env3
```

### Application Configuration

The deployment includes these configurations:
- **Database**: PostgreSQL connection via Supabase pooler
- **Embedding Engine**: OpenAI
- **STT Engine**: OpenAI
- **Scaling**: 1-2 replicas
- **Resources**: 1 CPU, 2Gi memory

### Adding New Secrets

To add new application secrets:

1. Add to GitHub repository secrets:
   ```bash
   gh secret set MY_NEW_SECRET --body "value" --repo "lojones/open-webui"
   ```

2. Update the deployment workflow to use the secret:
   ```yaml
   --env-vars MY_VAR=secretref:my-secret
   --secrets my-secret="${{ secrets.MY_NEW_SECRET }}"
   ```

## Security Best Practices

1. **OIDC Authentication**: No passwords or keys stored in GitHub
2. **Secret Management**: All sensitive data stored as GitHub secrets
3. **Environment Isolation**: Separate production and staging environments
4. **Least Privilege**: Service principal has access only to specific resource group

## Monitoring and Troubleshooting

### View Deployment Logs

1. **GitHub Actions**: Check the Actions tab for workflow runs
2. **Azure Portal**: Navigate to your Container App for application logs
3. **Azure CLI**: 
   ```bash
   az containerapp logs show -n openwebui-app3 -g lojoweb-rg
   ```

### Common Issues

1. **Authentication Failures**
   - Verify OIDC federation is configured correctly
   - Check GitHub secrets are set properly

2. **Database Connection Issues**
   - Verify Supabase credentials
   - Check if pooler endpoint is accessible

3. **Image Pull Failures**
   - Ensure the Docker image exists in GHCR
   - Verify the image tag is correct

## Cost Optimization

- Container Apps charges based on resource consumption
- Use auto-scaling to handle load efficiently
- Monitor resource usage in Azure Portal
- Consider using consumption plan for development environments

## Maintenance

### Updating the Deployment

1. **Application Updates**: Push to `lojoai-customization`, then merge to `main`
2. **Infrastructure Updates**: Modify the workflow file and commit
3. **Secret Rotation**: Update GitHub secrets and redeploy

### Backup and Recovery

- Database backups are handled by Supabase
- Application state is ephemeral (stateless design)
- Configuration is stored in GitHub (Infrastructure as Code)

## Advanced Scenarios

### Multi-Environment Deployment

To deploy to multiple environments:

1. Create additional Container Apps environments
2. Add environment-specific secrets
3. Modify the workflow to support multiple deployment targets

### Blue-Green Deployments

Azure Container Apps supports revision management:
- Keep multiple revisions active
- Route traffic between revisions
- Instant rollback capability

### Custom Domains

To add a custom domain:
```bash
az containerapp hostname add -n openwebui-app3 -g lojoweb-rg \
  --hostname www.yourdomain.com
```

## Support

For issues related to:
- **Open WebUI**: Check the main repository issues
- **Azure Container Apps**: Refer to Azure documentation
- **GitHub Actions**: Check GitHub Actions documentation
- **This deployment setup**: Create an issue in the repository
