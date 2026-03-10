benchmark "bigtable" {
  title         = "Bigtable Checks"
  description   = "Thrifty developers right-size Bigtable instances and remove abandoned tables."
  documentation = file("./docs/bigtable.md")
  children = [
    control.bigtable_instance_low_node_utilization,
    control.bigtable_instance_development_type,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/Bigtable"
  })
}

# Production Bigtable clusters with one node are likely over-provisioned for dev/test use
control "bigtable_instance_low_node_utilization" {
  title         = "Bigtable production instances with single-node clusters should be reviewed"
  description   = "Bigtable production instances with only one node in a cluster may actually be development workloads. Consider switching to DEVELOPMENT type to reduce costs by up to 50%."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "underutilized"
    service = "GCP/Bigtable"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when instance_type = 'PRODUCTION'
          and exists (
            select 1
            from jsonb_array_elements(clusters) as c
            where (c ->> 'serveNodes')::int <= 1
          )
          then 'alarm'
        else 'ok'
      end as status,
      name || ' is a ' || instance_type || ' instance.' as reason,
      project
    from
      gcp_bigtable_instance;
  EOQ
}

# Development instances can be flagged to ensure no production workloads are running on them cheaply but unreliably
control "bigtable_instance_development_type" {
  title         = "Bigtable instances of DEVELOPMENT type should be reviewed"
  description   = "Bigtable DEVELOPMENT instances have no SLA and are not suitable for production workloads. Verify these are being used only for development and testing."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/Bigtable"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when instance_type = 'DEVELOPMENT' then 'info'
        else 'ok'
      end as status,
      name || ' is a ' || instance_type || ' instance.' as reason,
      project
    from
      gcp_bigtable_instance;
  EOQ
}

# ---------------------------------------------------------------------------

benchmark "spanner" {
  title         = "Spanner Checks"
  description   = "Thrifty developers right-size Spanner instances to avoid paying for unused processing units."
  documentation = file("./docs/spanner.md")
  children = [
    control.spanner_instance_low_utilization,
    control.spanner_instance_high_processing_units,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/Spanner"
  })
}

# Spanner is expensive — instances with few databases may be idle
control "spanner_instance_low_utilization" {
  title         = "Spanner instances with no databases should be reviewed"
  description   = "A Spanner instance with no databases still incurs the minimum processing unit charge. Delete empty instances that are no longer needed."
  severity      = "high"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "unused"
    service = "GCP/Spanner"
  })

  sql = <<-EOQ
    select
      i.name as resource,
      case
        when count(d.name) = 0 then 'alarm'
        else 'ok'
      end as status,
      i.name || case
        when count(d.name) = 0 then ' has no databases.'
        else ' has ' || count(d.name) || ' database(s).'
      end as reason,
      i.project
    from
      gcp_spanner_instance i
      left join gcp_spanner_database d on d.instance_name = i.name
    group by
      i.name, i.project;
  EOQ
}

# Very high processing unit counts should be verified
control "spanner_instance_high_processing_units" {
  title         = "Spanner instances with high processing units should be reviewed"
  description   = "Spanner processing units are billed continuously. Instances with a very high processing unit count should be validated to ensure the capacity is actually needed."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/Spanner"
  })

  param "spanner_processing_units_threshold" {
    description = "Processing unit count above which a Spanner instance is flagged."
    default     = var.spanner_processing_units_threshold
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when processing_units > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' has ' || processing_units || ' processing units.' as reason,
      project
    from
      gcp_spanner_instance;
  EOQ
}

# ---------------------------------------------------------------------------

benchmark "memorystore" {
  title         = "Memorystore Checks"
  description   = "Thrifty developers right-size Memorystore Redis and Memcached instances."
  documentation = file("./docs/memorystore.md")
  children = [
    control.redis_instance_high_memory,
    control.redis_instance_old_version,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/Memorystore"
  })
}

# Oversized Redis instances waste memory capacity
control "redis_instance_high_memory" {
  title         = "Memorystore Redis instances with large memory capacity should be reviewed"
  description   = "Redis instances with very large reserved memory capacity may be over-provisioned. Review actual memory usage and right-size to reduce cost."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/Memorystore"
  })

  param "redis_instance_memory_size_gb_threshold" {
    description = "Memory size in GB above which a Redis instance is flagged."
    default     = var.redis_instance_memory_size_gb_threshold
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when memory_size_gb > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' has ' || memory_size_gb || ' GB of memory allocated.' as reason,
      location,
      project
    from
      gcp_redis_instance
    where
      state = 'READY';
  EOQ
}

# Old Redis versions are deprecated and may have security or performance issues
control "redis_instance_old_version" {
  title         = "Memorystore Redis instances on deprecated versions should be reviewed"
  description   = "Redis instances running deprecated versions should be upgraded. Older versions may also be less efficient, and upgrading can reduce memory consumption for the same workload."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "deprecated"
    service = "GCP/Memorystore"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when redis_version in ('REDIS_3_2', 'REDIS_4_0') then 'alarm'
        else 'ok'
      end as status,
      name || ' runs Redis version: ' || coalesce(redis_version, 'unknown') || '.' as reason,
      location,
      project
    from
      gcp_redis_instance;
  EOQ
}
