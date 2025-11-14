# Demo Guide

## Show copilot-instructions.md

## Prompt: "Improve the infrastructure resiliency by implementing Azure best practices from APRL and official Microsoft documentation. Generate new file with improved iac. Don't introduce breaking changes like change of OS"

## Prompt "Compare iac.bicep and iac-resilient.bicep. Summarise the differences in resiliency features and present them in a table, ranking each improvement by criticality.Provide in short what are the introduced benefits"

## Run "az deployment group create --resource-group rg-vmss-resiliencyhack1 --template-file .\iac-resilient.bicep"