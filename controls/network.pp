benchmark "network" {
  title         = "Network Resource Checks"
  description   = "Thrifty developers eliminate idle network resources that accrue charges without delivering value."
  documentation = file("./docs/network.md")
  children = [
    control.compute_forwarding_rule_unattached,
    control.compute_backend_service_no_backends,
    control.compute_vpn_gateway_no_tunnels,
    control.compute_network_unused,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/Network"
  })
}

control "compute_forwarding_rule_unattached" {
  title         = "Compute forwarding rules with no backend target should be reviewed"
  description   = "Forwarding rules that point to a non-existent or empty target still incur charges. Delete or re-attach unused forwarding rules."
  severity      = "high"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "unused"
    service = "GCP/Network"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when target is null or target = '' then 'alarm'
        else 'ok'
      end as status,
      name || case
        when target is null or target = '' then ' has no backend target.'
        else ' is attached to a target.'
      end as reason,
      location,
      project
    from
      gcp_compute_forwarding_rule;
  EOQ
}

control "compute_backend_service_no_backends" {
  title         = "Backend services with no backends should be reviewed"
  description   = "Backend services with no backend instances or NEGs registered are idle and waste load balancer resources."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "unused"
    service = "GCP/Network"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when backends is null or jsonb_array_length(backends) = 0 then 'alarm'
        else 'ok'
      end as status,
      name || case
        when backends is null or jsonb_array_length(backends) = 0
          then ' has no backends registered.'
        else ' has ' || jsonb_array_length(backends) || ' backend(s).'
      end as reason,
      location,
      project
    from
      gcp_compute_backend_service;
  EOQ
}

control "compute_vpn_gateway_no_tunnels" {
  title         = "VPN gateways with no tunnels should be reviewed"
  description   = "HA VPN gateways with no tunnels configured still incur hourly gateway charges. Remove idle VPN gateways that are no longer needed."
  severity      = "high"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "unused"
    service = "GCP/Network"
  })

  sql = <<-EOQ
    select
      g.name as resource,
      case
        when count(t.name) = 0 then 'alarm'
        else 'ok'
      end as status,
      g.name || case
        when count(t.name) = 0 then ' has no VPN tunnels.'
        else ' has ' || count(t.name) || ' tunnel(s).'
      end as reason,
      g.location,
      g.project
    from
      gcp_compute_ha_vpn_gateway g
      left join gcp_compute_vpn_tunnel t on t.vpn_gateway = g.self_link
    group by
      g.name, g.location, g.project;
  EOQ
}

control "compute_network_unused" {
  title         = "VPC networks with no subnets should be reviewed"
  description   = "VPC networks with no subnets may be abandoned. Remove unused VPCs to keep your environment clean."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "unused"
    service = "GCP/Network"
  })

  sql = <<-EOQ
    select
      n.name as resource,
      case
        when count(s.name) = 0 then 'alarm'
        else 'ok'
      end as status,
      n.name || case
        when count(s.name) = 0 then ' has no subnets.'
        else ' has ' || count(s.name) || ' subnet(s).'
      end as reason,
      n.project
    from
      gcp_compute_network n
      left join gcp_compute_subnetwork s on s.network = n.self_link
    where
      n.auto_create_subnetworks = false
    group by
      n.name, n.project;
  EOQ
}
