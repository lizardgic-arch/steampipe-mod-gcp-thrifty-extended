benchmark "cloudfunctions" {
  title         = "Cloud Functions Checks"
  description   = "Thrifty developers right-size and clean up unused Cloud Functions."
  documentation = file("./docs/cloudfunctions.md")
  children = [
    control.cloudfunctions_function_high_memory,
    control.cloudfunctions_function_long_timeout,
    control.cloudfunctions_function_high_min_instances,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/CloudFunctions"
  })
}

# Oversized memory allocation is billed even when function completes quickly
control "cloudfunctions_function_high_memory" {
  title         = "Cloud Functions with high memory allocation should be reviewed"
  description   = "Functions allocated more memory than necessary increase cost. Review functions with memory above the threshold and right-size if possible."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/CloudFunctions"
  })

  param "cloudfunctions_memory_mb_threshold" {
    description = "Memory allocation in MB above which a function is flagged."
    default     = var.cloudfunctions_memory_mb_threshold
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when (available_memory_mb)::int > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' is allocated ' || coalesce(available_memory_mb::text, 'unknown') || ' MB.' as reason,
      location,
      project
    from
      gcp_cloudfunctions_function;
  EOQ
}

# Excessively long timeouts mean runaway executions accumulate cost
control "cloudfunctions_function_long_timeout" {
  title         = "Cloud Functions with very long timeouts should be reviewed"
  description   = "A very long function timeout allows runaway executions to accumulate charges. Right-size the timeout to the expected maximum execution duration."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/CloudFunctions"
  })

  param "cloudfunctions_timeout_seconds_threshold" {
    description = "Execution timeout in seconds above which a function is flagged."
    default     = var.cloudfunctions_timeout_seconds_threshold
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when (timeout)::int > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' has a ' || coalesce(timeout::text, 'unknown') || ' second timeout.' as reason,
      location,
      project
    from
      gcp_cloudfunctions_function;
  EOQ
}

# High minimum instance count prevents scale-to-zero
control "cloudfunctions_function_high_min_instances" {
  title         = "Cloud Functions with high minimum instance counts should be reviewed"
  description   = "A high minimum instance count prevents scale-to-zero and causes continuous billing. Only use minimum instances for latency-sensitive functions that cannot tolerate cold starts."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/CloudFunctions"
  })

  param "cloudfunctions_min_instances_threshold" {
    description = "Minimum instance count above which a function is flagged."
    default     = var.cloudfunctions_min_instances_threshold
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when (min_instances)::int > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' has ' || coalesce(min_instances::text, '0') || ' minimum instances.' as reason,
      location,
      project
    from
      gcp_cloudfunctions_function;
  EOQ
}
