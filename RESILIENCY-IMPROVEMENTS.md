# VMSS Bicep Resiliency Improvements

This document outlines the improvements made to the Virtual Machine Scale Set (VMSS) Bicep template to align with Azure Proactive Resiliency Library v2 (APRL) recommendations.

## Key Changes

### 1. **Flexible Orchestration Mode** (APRL Recommendation: e7495e1c-0c75-0946-b266-b429b5c7f3bf)
- **Before**: `orchestrationMode: 'Uniform'`
- **After**: `orchestrationMode: 'Flexible'`
- **Impact**: Medium (Scalability)
- **Benefit**: Future-proofs applications for scaling and availability, guarantees high availability up to 1000 VMs by distributing across fault domains

### 2. **Availability Zones Deployment** (APRL Recommendation: 1422c567-782c-7148-ac7c-5fc14cf45adc)
- **Before**: No zone deployment
- **After**: `zones: ['1', '2', '3']`
- **Impact**: High (High Availability)
- **Benefit**: Protects applications and data against datacenter failure by distributing instances across availability zones

### 3. **Automatic Repair Policy** (APRL Recommendation: 820f4743-1f94-e946-ae0b-45efafd87962)
- **Before**: Not configured
- **After**: Enabled with 30-minute grace period
- **Impact**: High (High Availability)
- **Benefit**: Enhances application availability through continuous health check and automatic instance replacement

### 4. **Application Health Monitoring** (APRL Recommendation: 94794d2a-eff0-2345-9b67-6f9349d0a627)
- **Before**: Not configured
- **After**: ApplicationHealthWindows extension added
- **Impact**: Medium (Monitoring and Alerting)
- **Benefit**: Crucial for deployment management, supports rolling upgrades and automatic OS-image upgrades

### 5. **Custom Autoscale Configuration** (APRL Recommendation: ee66ff65-9aa3-2345-93c1-25827cf79f44)
- **Before**: Not configured
- **After**: CPU-based autoscale rules (scale out at 75%, scale in at 25%)
- **Impact**: High (Scalability)
- **Benefit**: Improves performance and cost-effectiveness by adjusting instances based on demand

### 6. **Predictive Autoscale** (APRL Recommendation: 3f85a51c-e286-9f44-b4dc-51d00768696c)
- **Before**: Not configured
- **After**: Enabled in ForecastOnly mode
- **Impact**: Low (Scalability)
- **Benefit**: Uses machine learning to forecast CPU load and scale out before demand spikes

### 7. **Disable Strict Zone Balancing** (APRL Recommendation: b5a63aa0-c58e-244f-b8a6-cbba0560a6db)
- **Before**: Default behavior (strict balancing)
- **After**: `platformFaultDomainCount: 1` (flexible balancing)
- **Impact**: High (High Availability)
- **Benefit**: Prevents scale operation failures, improves scalability and flexibility

### 8. **Updated OS Image**
- **Before**: `2022-Datacenter` (standard edition)
- **After**: `2022-datacenter-azure-edition` (Azure-optimized)
- **Impact**: High (Other Best Practices)
- **Benefit**: Uses Azure-optimized image with latest features and security updates

### 9. **Automatic OS Upgrades and Patching**
- **Before**: Not configured
- **After**: Automatic patching with rolling upgrade policy
- **Impact**: High (Security & Availability)
- **Benefit**: Ensures VMs stay updated with security patches while maintaining availability

### 10. **Updated API Versions**
- **Before**: `2023-04-01` (VNet), `2023-03-01` (VMSS)
- **After**: `2023-11-01` (VNet), `2024-03-01` (VMSS)
- **Impact**: Low (Best Practices)
- **Benefit**: Access to latest features and improvements

## Additional Enhancements

### Resource Configuration
- **Single Placement Group**: Disabled for better scalability beyond 100 instances
- **Platform Fault Domain Count**: Set to 1 for flexible zone balancing
- **Delete Option**: Set to 'Delete' for OS disks to prevent orphaned resources
- **Accelerated Networking**: Available as configuration option
- **Minimum Instance Count**: Set to 3 (aligned with zone deployment)

### Monitoring & Management
- **Health Probe**: TCP probe on port 80 with 30-second intervals
- **Upgrade Policy**: Configurable automatic OS upgrades with rolling policy
- **Rolling Upgrade Settings**:
  - Max batch size: 20% of instances
  - Max unhealthy: 20% threshold
  - Controlled rollout with health checks

### Autoscale Settings
- **Scale Range**: 3-10 instances
- **Scale Out**: When CPU > 75% for 5 minutes
- **Scale In**: When CPU < 25% for 5 minutes
- **Cooldown Period**: 5 minutes between scale operations
- **Predictive Mode**: Forecast-only with 10-minute lookahead

## Usage

### Deployment
```powershell
az deployment group create `
  --resource-group <resource-group-name> `
  --template-file iac-resilient.bicep `
  --parameters vmssName=myapp adminUsername=azureuser adminPassword=<secure-password>
```

### Parameters
- **vmssName**: Prefix for VMSS and related resources (default: 'vmss')
- **location**: Azure region (default: resource group location)
- **vmSize**: VM SKU (default: 'Standard_B2s')
- **instanceCount**: Initial instance count (default: 3, minimum: 3)
- **adminUsername**: Administrator username (required)
- **adminPassword**: Administrator password (required, secure)
- **zones**: Availability zones (default: ['1', '2', '3'])
- **enableAutomaticOSUpgrade**: Enable automatic OS upgrades (default: true)
- **repairGracePeriod**: Grace period for repairs in minutes (default: 30, range: 30-90)

## Compliance Summary

| APRL Recommendation | Status | Priority |
|---------------------|--------|----------|
| Flexible orchestration mode | ✅ Implemented | Medium |
| Application health monitoring | ✅ Implemented | Medium |
| Automatic repair policy | ✅ Implemented | High |
| Custom autoscale configuration | ✅ Implemented | High |
| Predictive autoscale | ✅ Implemented | Low |
| Disable strict zone balancing | ✅ Implemented | High |
| Deploy across availability zones | ✅ Implemented | High |
| Current OS image version | ✅ Implemented | High |

## References
- [Azure Proactive Resiliency Library v2 - VMSS](https://azure.github.io/Azure-Proactive-Resiliency-Library-v2/azure-resources/Compute/virtualMachineScaleSets/)
- [VMSS Flexible Orchestration](https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-orchestration-modes)
- [Availability Zones](https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-use-availability-zones)
- [Automatic Instance Repairs](https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-automatic-instance-repairs)
- [Application Health Extension](https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-health-extension)
- [Autoscale Best Practices](https://learn.microsoft.com/azure/azure-monitor/autoscale/autoscale-get-started)
