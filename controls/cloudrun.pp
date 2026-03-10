benchmark "cloudrun" {
  title         = "Cloud Run Checks"
  description   = "Thrifty developers eliminate idle and over-provisioned Cloud Run services."
  documentation = file("./docs/cloudrun.md")
  children = [
    control.cloudrun_service_no_traffic,
    control.cloudrun_service_min_instances_high,
    control.cloudrun_service_max_instances_high,
    control.cloudrun_service_cpu_always_allocated,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/CloudRun"
  })
}

# Low / no traffic services waste reserved capacity
control "cloudrun_service_no_traffic" {
  title         = "Cloud Run services with no traffic should be reviewed"
  description   = "A Cloud Run service receiving no traffic may be unused and costing money for container image storage and any always-on CPU allocation."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "unused"
    service = "GCP/CloudRun"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when (traffic) is null or jsonb_array_length(traffic::jsonb) = 0 then 'alarm'
        else 'ok'
      end as status,
      name || case
        when (traffic) is null or jsonb_array_length(traffic::jsonb) = 0
          then ' has no traffic configuration — may be unused.'
        else ' has active traffic routing.'
      end as reason,
      location,
      project
    from
      gcp_cloud_run_service;
  EOQ
}

# High minimum instance count guarantees cost even with zero traffic
control "cloudrun_service_min_instances_high" {
  title         = "Cloud Run services with high minimum instance counts should be reviewed"
  description   = "Setting a high minimum instance count prevents scale-to-zero and incurs continuous cost. Review services with minimum instances above the threshold."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/CloudRun"
  })

  param "cloudrun_min_instances_threshold" {
    description = "The maximum number of minimum instances before flagging as over-provisioned."
    default     = var.cloudrun_min_instances_threshold
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when (scaling ->> 'minInstanceCount')::int > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' has ' || coalesce(scaling ->> 'minInstanceCount', '0') || ' minimum instances.'
        as reason,
      location,
      project
    from
      gcp_cloud_run_service;
  EOQ
}

# Very high max instance counts can lead to surprise cost spikes
control "cloudrun_service_max_instances_high" {
  title         = "Cloud Run services with very high maximum instances should be reviewed"
  description   = "An unbounded or very high maximum instance count can lead to unexpected cost spikes during traffic surges. Set a sensible upper limit."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/CloudRun"
  })

  param "cloudrun_max_instances_threshold" {
    description = "The maximum instance count above which a service is flagged."
    default     = var.cloudrun_max_instances_threshold
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when (scaling ->> 'maxInstanceCount') is null then 'alarm'
        when (scaling ->> 'maxInstanceCount')::int > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' has max instances: ' || coalesce(scaling ->> 'maxInstanceCount', 'unlimited') || '.'
        as reason,
      location,
      project
    from
      gcp_cloud_run_service;
  EOQ
}

# CPU always-allocated keeps billing even when no requests are being processed
control "cloudrun_service_cpu_always_allocated" {
  title         = "Cloud Run services with CPU always allocated should be reviewed"
  description   = "Setting CPU to always-allocated means you pay for CPU even when the service is idle. Only use this setting when background work is required."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/CloudRun"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when launch_stage = 'GA'
          and (template -> 'metadata' -> 'annotations' ->> 'run.googleapis.com/cpu-throttling') = 'false'
          then 'alarm'
        else 'ok'
      end as status,
      name || case
        when (template -> 'metadata' -> 'annotations' ->> 'run.googleapis.com/cpu-throttling') = 'false'
          then ' has CPU always allocated (no throttling).'
        else ' uses default CPU throttling.'
      end as reason,
      location,
      project
    from
      gcp_cloud_run_service;
  EOQ
}
