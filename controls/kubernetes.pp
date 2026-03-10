benchmark "kubernetes" {
  title         = "Kubernetes (GKE) Checks"
  description   = "Thrifty developers eliminate waste in their GKE clusters."
  documentation = file("./docs/kubernetes.md")
  children = [
    control.kubernetes_cluster_no_autoscaling,
    control.kubernetes_cluster_node_pool_large_machine_type,
    control.kubernetes_cluster_old_version,
    control.kubernetes_cluster_single_zone,
    control.kubernetes_node_pool_preemptible_not_used,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/GKE"
  })
}

control "kubernetes_cluster_no_autoscaling" {
  title         = "GKE clusters without autoscaling should be reviewed"
  description   = "GKE clusters that do not use node autoscaling keep nodes running regardless of workload, wasting money during low-utilization periods."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/GKE"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when exists (
          select 1
          from jsonb_array_elements(node_pools::jsonb) as np
          where (np -> 'autoscaling' ->> 'enabled')::bool = true
        ) then 'ok'
        else 'alarm'
      end as status,
      name || case
        when exists (
          select 1
          from jsonb_array_elements(node_pools::jsonb) as np
          where (np -> 'autoscaling' ->> 'enabled')::bool = true
        ) then ' has autoscaling enabled on at least one node pool.'
        else ' has no node pools with autoscaling enabled.'
      end as reason,
      location,
      project
    from
      gcp_kubernetes_cluster
    where
      node_pools is not null;
  EOQ
}

control "kubernetes_cluster_node_pool_large_machine_type" {
  title         = "GKE node pools using large machine types should be reviewed"
  description   = "Node pools using large machine types may be over-provisioned. Consider using smaller nodes with autoscaling instead."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/GKE"
  })

  sql = <<-EOQ
    select
      c.name || '/' || (np ->> 'name') as resource,
      case
        when (np -> 'config' ->> 'machineType') ilike 'n1-standard-16'
          or (np -> 'config' ->> 'machineType') ilike 'n1-standard-32'
          or (np -> 'config' ->> 'machineType') ilike 'n1-standard-64'
          or (np -> 'config' ->> 'machineType') ilike 'n2-standard-32'
          or (np -> 'config' ->> 'machineType') ilike 'n2-standard-48'
          or (np -> 'config' ->> 'machineType') ilike 'n2-standard-64'
          or (np -> 'config' ->> 'machineType') ilike 'n2-standard-80'
          or (np -> 'config' ->> 'machineType') ilike 'n2-standard-96'
          then 'alarm'
        else 'ok'
      end as status,
      c.name || ' node pool ' || (np ->> 'name') || ' uses machine type '
        || coalesce(np -> 'config' ->> 'machineType', 'unknown') || '.' as reason,
      c.location,
      c.project
    from
      gcp_kubernetes_cluster c,
      jsonb_array_elements(c.node_pools::jsonb) as np
    where
      c.node_pools is not null;
  EOQ
}

control "kubernetes_cluster_old_version" {
  title         = "GKE clusters running old Kubernetes versions should be reviewed"
  description   = "Clusters running outdated Kubernetes versions may indicate unused or forgotten clusters."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "deprecated"
    service = "GCP/GKE"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when current_master_version like '1.2%' then 'alarm'
        when current_master_version like '1.2[0-5]%' then 'alarm'
        else 'ok'
      end as status,
      name || ' is running Kubernetes version ' || coalesce(current_master_version, 'unknown') || '.' as reason,
      location,
      project
    from
      gcp_kubernetes_cluster;
  EOQ
}

control "kubernetes_cluster_single_zone" {
  title         = "Production GKE clusters in a single zone should be reviewed"
  description   = "Single-zone GKE clusters may indicate dev/test clusters that were never cleaned up."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/GKE"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when location_type = 'REGIONAL' then 'ok'
        else 'info'
      end as status,
      name || ' is a ' || lower(coalesce(location_type, 'unknown')) || ' cluster in ' || location || '.' as reason,
      location,
      project
    from
      gcp_kubernetes_cluster;
  EOQ
}

control "kubernetes_node_pool_preemptible_not_used" {
  title         = "GKE node pools not using preemptible or Spot VMs should be reviewed"
  description   = "Using preemptible or Spot VMs for GKE node pools can reduce costs by up to 80%."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/GKE"
  })

  sql = <<-EOQ
    select
      c.name || '/' || (np ->> 'name') as resource,
      case
        when (np -> 'config' ->> 'preemptible')::bool = true
          or (np -> 'config' ->> 'spot')::bool = true
          then 'ok'
        else 'alarm'
      end as status,
      c.name || ' node pool ' || (np ->> 'name') || case
        when (np -> 'config' ->> 'preemptible')::bool = true then ' uses preemptible VMs.'
        when (np -> 'config' ->> 'spot')::bool = true then ' uses Spot VMs.'
        else ' does not use preemptible or Spot VMs.'
      end as reason,
      c.location,
      c.project
    from
      gcp_kubernetes_cluster c,
      jsonb_array_elements(c.node_pools::jsonb) as np
    where
      c.node_pools is not null;
  EOQ
}
