benchmark "artifact_registry" {
  title         = "Artifact Registry Checks"
  description   = "Thrifty developers clean up unused container images and artifact repositories."
  documentation = file("./docs/artifact_registry.md")
  children = [
    control.artifact_registry_repository_stale,
    control.artifact_registry_repository_no_cleanup_policy,
    control.artifact_registry_repository_large_size,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/ArtifactRegistry"
  })
}

# Repositories that have not been updated in a long time are likely stale
control "artifact_registry_repository_stale" {
  title         = "Artifact Registry repositories not updated recently should be reviewed"
  description   = "Artifact Registry repositories that have not received a push in a long time may contain abandoned artifacts and can often be deleted to reduce storage costs."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "deprecated"
    service = "GCP/ArtifactRegistry"
  })

  param "artifact_registry_repo_stale_days" {
    description = "Number of days without an update before a repository is considered stale."
    default     = var.artifact_registry_repo_stale_days
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when update_time is null then 'alarm'
        when date_part('day', now() - update_time) > $1 then 'alarm'
        else 'ok'
      end as status,
      name || case
        when update_time is null then ' has never been updated.'
        else ' was last updated ' || date_part('day', now() - update_time) || ' days ago.'
      end as reason,
      location,
      project
    from
      gcp_artifact_registry_repository;
  EOQ
}

# Repositories without cleanup policies accumulate old images indefinitely
control "artifact_registry_repository_no_cleanup_policy" {
  title         = "Artifact Registry repositories without cleanup policies should be reviewed"
  description   = "Repositories without cleanup policies accumulate old container images indefinitely, increasing storage costs. Configure a cleanup policy to remove stale tags and untagged images."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/ArtifactRegistry"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when cleanup_policies is null or cleanup_policies = '{}'::jsonb then 'alarm'
        else 'ok'
      end as status,
      name || case
        when cleanup_policies is null or cleanup_policies = '{}'::jsonb
          then ' has no cleanup policies configured.'
        else ' has cleanup policies configured.'
      end as reason,
      location,
      project
    from
      gcp_artifact_registry_repository;
  EOQ
}

# Very large repositories indicate image sprawl
control "artifact_registry_repository_large_size" {
  title         = "Large Artifact Registry repositories should be reviewed"
  description   = "Artifact Registry repositories consuming very large amounts of storage may contain redundant or obsolete images. Clean up old image versions to reduce costs."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/ArtifactRegistry"
  })

  param "artifact_registry_repo_size_gb_threshold" {
    description = "Repository size in GB above which the repository is flagged for review."
    default     = var.artifact_registry_repo_size_gb_threshold
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when (size_bytes / 1073741824.0) > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' is ' || round((size_bytes / 1073741824.0)::numeric, 2) || ' GB.' as reason,
      location,
      project
    from
      gcp_artifact_registry_repository
    where
      size_bytes is not null;
  EOQ
}
