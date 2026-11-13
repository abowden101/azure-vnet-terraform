# Azure VNet — Hub-Spoke Network (Terraform)

A hub-spoke Azure network built with Terraform, written as a portfolio piece
for network engineering: segmented tiers, least-privilege NSGs, and peering —
no paid firewall or gateway required to deploy it.

## Architecture

```mermaid
flowchart TB
    Internet((Internet)) -->|80/443| Web[Spoke: web 10.1.0.0/24]
    Web -->|8080| App[Spoke: app 10.1.1.0/24]
    App -->|1433 / 5432| Data[Spoke: data 10.1.2.0/24]
    Hub[Hub VNet 10.0.0.0/16<br/>GatewaySubnet · AzureFirewallSubnet · SharedServices]
    Web -. peering .-> Hub
    App -. peering .-> Hub
    Data -. peering .-> Hub
```

| VNet | CIDR | Subnets |
| --- | --- | --- |
| `vnet-hub` | 10.0.0.0/16 | GatewaySubnet 10.0.0.0/24, AzureFirewallSubnet 10.0.1.0/24, SharedServices 10.0.2.0/24 |
| `vnet-spoke` | 10.1.0.0/16 | web 10.1.0.0/24, app 10.1.1.0/24, data 10.1.2.0/24 |
| `vnet-spoke-use2` | 10.2.0.0/16 | web 10.2.0.0/24 (East US 2) |
| `vnet-spoke-centralus` | 10.3.0.0/16 | web 10.3.0.0/24 (Central US, hosts the test VM) |

## What it builds

- **Hub and spoke VNets** with bidirectional peering (forwarded traffic
  allowed, gateway transit off — no gateway is deployed).
- **Tiered NSGs:** web accepts 80/443 from the internet; app accepts 8080
  only from the web subnet; data accepts 1433/5432 only from the app subnet.
  Admin SSH/RDP to SharedServices is allowed only from a single source IP
  you set — and no rule is created at all if you leave it empty.
- **Route table** on the spoke subnets, ready for a hub firewall: set
  `firewall_private_ip` and spoke egress gets a `0.0.0.0/0` route via it.
- **Optional NAT Gateway** (`enable_nat_gateway`) for outbound-only
  internet from the spoke subnets.
- **Test VM (`vm-test-web`)** in the Central US spoke: Standard_B2pts_v2
  (2 vCPU / 1 GiB, ARM, burstable), Ubuntu 22.04 LTS ARM64, 64 GB P6
  Premium SSD, no public IP. Managed via serial console or
  `az vm run-command`. See Cost notes for why it is $0.

## Cost notes

With defaults, this deploys only VNets, subnets, NSGs, peering, and a route
table — all free or near-free. The expensive parts are deliberately
optional or absent: Azure Firewall (~$1,000/mo) is not deployed, and the
NAT Gateway (~$32/mo) is off by default. Remember to `terraform destroy`
when you are done with a lab.

**Test VM, $0:** the 12-month free allowance covers 750 hrs/mo of B2pts_v2
compute and 2 x 64 GB P6 disks, and the VM has no public IP (a Standard IP
would bill ~$3.65/mo). Total: $0/mo while the allowance lasts. B2pts_v2
was chosen because the free-trial offer blocks B1s/B1ms/B2s in East US and
East US 2 (`NotAvailableForSubscription` — an offer restriction, not
quota); B2pts_v2 is unrestricted in Central US. After the 12 free months
end, B2pts_v2 bills at list (~$7/mo).

## Usage

```bash
az login
terraform init
terraform plan
terraform apply
```

Copy `terraform.tfvars.example` to `terraform.tfvars` to set your region,
admin source IP, and optional features. Requires Terraform >= 1.5 and the
`azurerm` provider (~> 4.0, pinned in `versions.tf`).

## Files

| File | Purpose |
| --- | --- |
| `main.tf` | Resource group, hub/spoke VNets, peering |
| `network.tf` | Subnets, NSGs, route table, optional NAT Gateway |
| `vm.tf` | East US 2 spoke (network only — the VM moved to Central US) |
| `centralus.tf` | Central US spoke, test VM (B2pts_v2, ARM64, P6 disk, no public IP) |
| `variables.tf` | All inputs, with defaults and descriptions |
| `outputs.tf` | VNet, subnet, and NSG IDs for downstream modules |
| `versions.tf` | Terraform and provider version pins |
| `terraform.tfvars.example` | Example inputs (copy to `terraform.tfvars`) |

## Design decisions

- **Hub-spoke over a single VNet:** keeps shared services (gateway,
  firewall, DNS) in one place and lets each workload live in its own
  spoke — the pattern most enterprise Azure estates use.
- **Subnets as maps with `for_each`:** adding a tier is one line in
  `variables.tf`, not a new resource block.
- **NSGs deny by default:** every allow rule names its source tier, so a
  compromised web VM cannot reach the data tier directly.
- **No firewall by default:** the UDR path is wired up, but the $1k/mo
  appliance is a decision, not a side effect of `terraform apply`.
