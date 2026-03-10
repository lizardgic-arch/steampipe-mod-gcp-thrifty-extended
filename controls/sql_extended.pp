benchmark "sql_extended" {
  title         = "Cloud SQL Extended Checks"
  description   = "Additional thrifty checks for Cloud SQL beyond the built-in benchmark."
  documentation = file("./docs/sql_extended.md")
  children = [
    control.sql_instance_high_availability_dev,
    control.sql_instance_large_storage,
    control.sql_instance_idle,
    control.sql_instance_old_generation,
    control.sql_instance_backup_retained_too_long,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/SQL"
  })
}

control "sql_instance_high_availability_dev" {
  title         = "Cloud SQL development instances with high availability should be reviewed"
  description   = "High availability doubles the cost of a Cloud SQL instance. Development and test instances rarely require HA."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/SQL"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when availability_type = 'REGIONAL' then 'alarm'
        else 'ok'
      end as status,
      name || ' has availability type: ' || coalesce(availability_type, 'unknown') || '.' as reason,
      location,
      project
    from
      gcp_sql_database_instance
    where
      (name ilike '%dev%' or name ilike '%test%' or name ilike '%staging%' or name ilike '%qa%')
      and state = 'RUNNABLE';
  EOQ
}

control "sql_instance_large_storage" {
  title         = "Cloud SQL instances with large storage should be reviewed"
  description   = "Cloud SQL instances with very large storage allocations may be over-provisioned."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/SQL"
  })

  param "sql_instance_max_storage_gb" {
    description = "Maximum storage size in GB before flagging."
    default     = var.sql_instance_max_storage_gb
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when disk_size::int > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' has ' || disk_size || ' GB of storage allocated.' as reason,
      location,
      project
    from
      gcp_sql_database_instance
    where
      state = 'RUNNABLE';
  EOQ
}

control "sql_instance_idle" {
  title         = "Cloud SQL instances that appear idle should be reviewed"
  description   = "Cloud SQL instances with no recent connections may be abandoned and can be deleted to eliminate cost."
  severity      = "high"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "unused"
    service = "GCP/SQL"
  })

  param "sql_instance_idle_days" {
    description = "Number of days with no connections before flagging as idle."
    default     = var.sql_instance_idle_days
  }

  sql = <<-EOQ
    select
      i.name as resource,
      case
        when max(m.timestamp) is null then 'alarm'
        when date_part('day', now() - max(m.timestamp)) > $1 then 'alarm'
        else 'ok'
      end as status,
      i.name || case
        when max(m.timestamp) is null then ' has no connection metrics available.'
        else ' last had connections ' || date_part('day', now() - max(m.timestamp))::int || ' days ago.'
      end as reason,
      i.location,
      i.project
    from
      gcp_sql_database_instance i
      left join gcp_sql_database_instance_metric_connections m on i.name = m.instance_id
    where
      i.state = 'RUNNABLE'
    group by
      i.name, i.location, i.project;
  EOQ
}

control "sql_instance_old_generation" {
  title         = "Cloud SQL first-generation instances should be migrated"
  description   = "Cloud SQL first-generation instances use deprecated infrastructure. Migrate to second-generation to save cost and gain better performance."
  severity      = "high"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "deprecated"
    service = "GCP/SQL"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when backend_type = 'FIRST_GEN' then 'alarm'
        else 'ok'
      end as status,
      name || ' uses backend type: ' || coalesce(backend_type, 'unknown') || '.' as reason,
      location,
      project
    from
      gcp_sql_database_instance;
  EOQ
}

control "sql_instance_backup_retained_too_long" {
  title         = "Cloud SQL instances with excessive backup retention should be reviewed"
  description   = "Retaining automated backups for longer than necessary increases Cloud Storage costs."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/SQL"
  })

  param "sql_backup_retention_days" {
    description = "Maximum backup retention count before flagging."
    default     = var.sql_backup_retention_days
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when retained_backups::int > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' retains ' || coalesce(retained_backups::text, 'unknown') || ' backups.' as reason,
      location,
      project
    from
      gcp_sql_database_instance
    where
      backup_enabled = true;
  EOQ
}
