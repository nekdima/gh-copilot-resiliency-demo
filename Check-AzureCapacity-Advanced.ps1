<#
.SYNOPSIS
    Azure capacity checker - shows available VM SKUs and quota status for a region.

.DESCRIPTION
    Lists top 5 available VM SKUs per family (B, D, E series) and quota status for the specified region.

.PARAMETER Location
    Azure region to check (e.g., 'GermanyWestCentral', 'eastus', 'westus2')

.EXAMPLE
    .\Check-AzureCapacity-Advanced.ps1 -Location "GermanyWestCentral"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Location
)

#Requires -Modules Az.Accounts, Az.Compute

# Ensure logged in
$context = Get-AzContext
if (-not $context) {
    Write-Host "Please login to Azure first: Connect-AzAccount" -ForegroundColor Red
    exit 1
}

$subscriptionId = $context.Subscription.Id
$tenantId = $context.Tenant.Id
Write-Host "Using Subscription: $subscriptionId" -ForegroundColor Cyan

function Invoke-AzureRestRequest {
    param(
        [Parameter(Mandatory = $true)] [string] $Uri,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    try {
        $response = Invoke-AzRestMethod -Uri $Uri -Method Get -ErrorAction Stop
        if ($response.StatusCode -ne 200) {
            throw "API returned status code $($response.StatusCode): $($response.Content)"
        }
        return ($response.Content | ConvertFrom-Json)
    }
    catch {
        Write-Host "✗ Failed to $Description" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        throw
    }
}

# Normalize location for matching
$normalizedLocation = $Location.ToLower() -replace '\s', ''

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Azure Capacity Check: $Location" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Step 1: Fetch all VM SKUs
Write-Host "[1/2] Fetching VM SKUs..." -ForegroundColor Cyan

$skuApiUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Compute/skus?api-version=2021-07-01"

try {
    $skuResponse = Invoke-AzureRestRequest -Uri $skuApiUrl -Description "query Resource SKUs API"
}
catch {
    Write-Host "Cannot continue without SKU data." -ForegroundColor Red
    exit 1
}

# Filter VMs available in the specified location
$allVMs = $skuResponse.value | Where-Object {
    $_.resourceType -eq 'virtualMachines' -and
    $_.locations -and
    ($_.locations | ForEach-Object { $_.ToLower() -replace '\s', '' }) -contains $normalizedLocation
}

if (-not $allVMs) {
    Write-Host "No VM SKUs found for location: $Location" -ForegroundColor Red
    exit 1
}

# Filter unrestricted SKUs per family
$families = @(
    @{ Name = 'B-Series'; Pattern = '^Standard_B' }
    @{ Name = 'D-Series'; Pattern = '^Standard_D' }
    @{ Name = 'E-Series'; Pattern = '^Standard_E' }
)

Write-Host "✓ Found $($allVMs.Count) total VM SKUs in $Location`n" -ForegroundColor Green

foreach ($family in $families) {
    Write-Host "--- $($family.Name) Available SKUs ---" -ForegroundColor Yellow
    
    $familySkus = $allVMs | Where-Object { $_.name -match $family.Pattern } | ForEach-Object {
        $sku = $_
        $restricted = $false
        
        # Check for location restrictions
        if ($sku.restrictions) {
            foreach ($restriction in $sku.restrictions) {
                if ($restriction.type -eq 'Location') {
                    $restrictedLocs = $restriction.restrictionInfo.locations | ForEach-Object { $_.ToLower() -replace '\s', '' }
                    if ($restrictedLocs -contains $normalizedLocation) {
                        $restricted = $true
                        break
                    }
                }
            }
        }
        
        if (-not $restricted) {
            # Extract capabilities
            $vcpus = ($sku.capabilities | Where-Object { $_.name -eq 'vCPUs' }).value
            $memory = ($sku.capabilities | Where-Object { $_.name -eq 'MemoryGB' }).value
            $zones = if ($sku.locationInfo) {
                $locInfo = $sku.locationInfo | Where-Object { ($_.location.ToLower() -replace '\s', '') -eq $normalizedLocation }
                if ($locInfo.zones) { $locInfo.zones -join ',' } else { '-' }
            }
            else { '-' }
            
            [PSCustomObject]@{
                Name     = $sku.name
                vCPUs    = $vcpus
                MemoryGB = $memory
                Zones    = $zones
            }
        }
    } | Sort-Object @{Expression = { [int]$_.vCPUs }; Ascending = $true } | Select-Object -First 5
    
    if ($familySkus) {
        $familySkus | Format-Table -AutoSize
    }
    else {
        Write-Host "  No unrestricted SKUs available in this family.`n" -ForegroundColor Gray
    }
}

# Step 2: Check Quota
Write-Host "[2/2] Checking Quota..." -ForegroundColor Cyan

$usageApiUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Compute/locations/$Location/usages?api-version=2023-03-01"

try {
    $usageResponse = Invoke-AzureRestRequest -Uri $usageApiUrl -Description "query Compute Usage API"
}
catch {
    Write-Host "Cannot continue without quota data." -ForegroundColor Red
    exit 1
}

Write-Host "`n--- Quota Status ---" -ForegroundColor Yellow

$quotaPatterns = @(
    'Total Regional vCPUs'
    'Standard B.*Family vCPUs'
    'Standard D.*Family vCPUs'
    'Standard E.*Family vCPUs'
)

$quotas = @()
foreach ($pattern in $quotaPatterns) {
    $match = $usageResponse.value | Where-Object { $_.name.localizedValue -match $pattern } | Select-Object -First 1
    if ($match) {
        $percentUsed = if ($match.limit -gt 0) {
            [math]::Round(($match.currentValue / $match.limit) * 100, 2)
        }
        else { 0 }
        
        $status = if ($percentUsed -ge 90) { 'CRITICAL' }
        elseif ($percentUsed -ge 75) { 'WARNING' }
        else { 'OK' }
        
        $quotas += [PSCustomObject]@{
            Quota       = $match.name.localizedValue
            Used        = $match.currentValue
            Limit       = $match.limit
            PercentUsed = "$percentUsed%"
            Status      = $status
        }
    }
}

if ($quotas) {
    $quotas | Format-Table -AutoSize
}
else {
    Write-Host "  No quota information found for this region.`n" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Capacity check complete!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

exit 0
