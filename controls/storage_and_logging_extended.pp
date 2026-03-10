benchmark "storage_extended" {
  title         = "Cloud Storage Extended Checks"
  description   = "Additional thrifty checks for Cloud Storage beyond the built-in benchmark."
  documentation = file("./docs/storage_extended.md")
  children = [
    control.storage_bucket_nearline_or_coldline_eligible,
    control.storage_bucket_versioning_large,
    control.storage_bucket_dual_region_unnecessary,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/Storage"
  })
}

control "storage_bucket_nearline_or_coldline_eligible" {
  title         = "Standard storage buckets not accessed recently should consider Nearline/Coldline"
  description   = "Cloud Storage buckets using Standard storage class that are old are good candidates for Nearline or Coldline storage, which can reduce costs by up to 80%."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/Storage"
  })

  param "storage_bucket_last_access_days" {
    description = "Number of days since creation before suggesting a cheaper storage class."
    default     = var.storage_bucket_last_access_days
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when storage_class = 'STANDARD'
          and date_part('day', now() - time_created) > $1
          then 'alarm'
        else 'ok'
      end as status,
      name || ' uses ' || storage_class || ' storage class, created '
        || date_part('day', now() - time_created)::int || ' days ago.' as reason,
      location,
      project
    from
      gcp_storage_bucket;
  EOQ
}

control "storage_bucket_versioning_large" {
  title         = "Versioned storage buckets without a lifecycle rule to expire old versions should be reviewed"
  description   = "Buckets with versioning enabled accumulate noncurrent object versions over time, increasing storage costs. Add a lifecycle rule to delete old versions."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/Storage"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when versioning_enabled = true
          and (
            lifecycle_rules is null
            or not exists (
              select 1
              from jsonb_array_elements(lifecycle_rules) as r
              where r -> 'action' ->> 'type' = 'Delete'
                and (r -> 'condition' ->> 'numNewerVersions') is not null
            )
          )
          then 'alarm'
        else 'ok'
      end as status,
      name || case
        when versioning_enabled = true then ' has versioning enabled'
        else ' does not have versioning enabled'
      end || case
        when lifecycle_rules is null or jsonb_array_length(lifecycle_rules) = 0
          then ' with no lifecycle rules.'
        else ' with lifecycle rules configured.'
      end as reason,
      location,
      project
    from
      gcp_storage_bucket;
  EOQ
}

control "storage_bucket_dual_region_unnecessary" {
  title         = "Dual-region storage buckets should be reviewed"
  description   = "Dual-region storage incurs a replication cost premium over single-region. Verify that geo-redundancy is actually required."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/Storage"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when location_type = 'dual-region' then 'alarm'
        else 'ok'
      end as status,
      name || ' is a ' || coalesce(location_type, 'unknown') || ' bucket in ' || location || '.' as reason,
      location,
      project
    from
      gcp_storage_bucket;
  EOQ
}

# ---------------------------------------------------------------------------

benchmark "logging_extended" {
  title         = "Cloud Logging Extended Checks"
  description   = "Additional thrifty checks to reduce Cloud Logging costs."
  documentation = file("./docs/logging_extended.md")
  children = [
    control.logging_sink_no_destination,
    control.logging_bucket_long_retention,
    control.logging_metric_unused,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/Logging"
  })
}

control "logging_sink_no_destination" {
  title         = "Log sinks with no valid destination should be reviewed"
  description   = "Log export sinks that point to a deleted or non-existent destination still filter and attempt to export logs."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "unused"
    service = "GCP/Logging"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when destination is null or destination = '' then 'alarm'
        else 'ok'
      end as status,
      name || case
        when destination is null or destination = '' then ' has no destination configured.'
        else ' exports to: ' || destination || '.'
      end as reason,
      project
    from
      gcp_logging_sink;
  EOQ
}

control "logging_bucket_long_retention" {
  title         = "Cloud Logging buckets with long retention periods should be reviewed"
  description   = "Log storage beyond the default 30-day retention is billed. Verify that long retention periods are actually required."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/Logging"
  })

  param "logging_bucket_retention_days" {
    description = "Log retention days above which a bucket is flagged."
    default     = var.logging_bucket_retention_days
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when retention_days > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' retains logs for ' || retention_days || ' days.' as reason,
      location,
      project
    from
      gcp_logging_bucket
    where
      not locked;
  EOQ
}

control "logging_metric_unused" {
  title         = "Log-based metrics with no alerting policies should be reviewed"
  description   = "Log-based metrics that have no alerting policies may have been created as tests and never cleaned up."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "unused"
    service = "GCP/Logging"
  })

  sql = <<-EOQ
    select
      name as resource,
      'info' as status,
      name || ' is a log-based metric — verify it is attached to an alerting policy or dashboard.' as reason,
      project
    from
      gcp_logging_metric;
  EOQ
}
