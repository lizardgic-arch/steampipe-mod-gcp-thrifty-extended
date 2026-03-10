benchmark "pubsub" {
  title         = "Pub/Sub Checks"
  description   = "Thrifty developers keep Pub/Sub subscriptions clean to avoid unnecessary message storage costs."
  documentation = file("./docs/pubsub.md")
  children = [
    control.pubsub_subscription_undelivered_messages,
    control.pubsub_subscription_no_activity,
    control.pubsub_topic_no_subscriptions,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/PubSub"
  })
}

# Large backlogs of undelivered messages indicate broken consumers and wasted storage
control "pubsub_subscription_undelivered_messages" {
  title         = "Pub/Sub subscriptions with large undelivered message backlogs should be reviewed"
  description   = "Subscriptions with a very large backlog of undelivered messages may have a broken consumer. Messages are retained at cost — fix or delete the subscription to stop accruing charges."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/PubSub"
  })

  param "pubsub_subscription_undelivered_messages_threshold" {
    description = "Maximum number of undelivered messages before flagging the subscription."
    default     = var.pubsub_subscription_undelivered_messages_threshold
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when num_undelivered_messages > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' has ' || coalesce(num_undelivered_messages::text, '0') || ' undelivered messages.' as reason,
      project
    from
      gcp_pubsub_subscription;
  EOQ
}

# Subscriptions with no recent activity may be abandoned
control "pubsub_subscription_no_activity" {
  title         = "Pub/Sub subscriptions with no recent activity should be reviewed"
  description   = "Subscriptions that have not delivered a message recently may be abandoned and still hold retained messages at cost. Delete unused subscriptions."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "unused"
    service = "GCP/PubSub"
  })

  param "pubsub_subscription_idle_days" {
    description = "Days without activity before flagging a subscription as idle."
    default     = var.pubsub_subscription_idle_days
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when oldest_unacked_message_age > ($1 * 86400) then 'alarm'
        else 'ok'
      end as status,
      name || ' oldest unacked message is ' || coalesce((oldest_unacked_message_age / 86400)::text, '0')
        || ' days old.' as reason,
      project
    from
      gcp_pubsub_subscription;
  EOQ
}

# Topics with no subscriptions are receiving messages that are immediately discarded
control "pubsub_topic_no_subscriptions" {
  title         = "Pub/Sub topics with no subscriptions should be reviewed"
  description   = "A Pub/Sub topic with no subscriptions discards all published messages. Publishers may be sending messages needlessly, and the topic may be abandoned."
  severity      = "low"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "unused"
    service = "GCP/PubSub"
  })

  sql = <<-EOQ
    select
      t.name as resource,
      case
        when count(s.name) = 0 then 'alarm'
        else 'ok'
      end as status,
      t.name || case
        when count(s.name) = 0 then ' has no subscriptions.'
        else ' has ' || count(s.name) || ' subscription(s).'
      end as reason,
      t.project
    from
      gcp_pubsub_topic t
      left join gcp_pubsub_subscription s on s.topic_name = t.name
    group by
      t.name, t.project;
  EOQ
}

# ---------------------------------------------------------------------------

benchmark "dataflow" {
  title         = "Dataflow Checks"
  description   = "Thrifty developers right-size and clean up Dataflow jobs."
  documentation = file("./docs/dataflow.md")
  children = [
    control.dataflow_job_long_running,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/Dataflow"
  })
}

# Jobs running for longer than expected waste VM time
control "dataflow_job_long_running" {
  title         = "Long-running Dataflow jobs should be reviewed"
  description   = "Dataflow streaming jobs that have been running for an unexpectedly long time or batch jobs that are stalled waste Compute Engine resources. Investigate and terminate if no longer needed."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/Dataflow"
  })

  param "dataflow_job_age_max_days" {
    description = "Maximum number of days a Dataflow job should run before being flagged."
    default     = var.dataflow_job_age_max_days
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when current_state in ('JOB_STATE_RUNNING', 'JOB_STATE_DRAINING')
          and date_part('day', now() - create_time) > $1
          then 'alarm'
        when current_state in ('JOB_STATE_RUNNING', 'JOB_STATE_DRAINING') then 'ok'
        else 'info'
      end as status,
      name || ' has been ' || lower(current_state) || ' for '
        || date_part('day', now() - create_time) || ' days.' as reason,
      location,
      project
    from
      gcp_dataflow_job;
  EOQ
}

# ---------------------------------------------------------------------------

benchmark "composer" {
  title         = "Cloud Composer Checks"
  description   = "Thrifty developers right-size Cloud Composer environments."
  documentation = file("./docs/composer.md")
  children = [
    control.composer_environment_large_node_count,
    control.composer_environment_old_version,
  ]

  tags = merge(local.gcp_thrifty_common_tags, {
    service = "GCP/Composer"
  })
}

# Large node counts in Composer environments are expensive
control "composer_environment_large_node_count" {
  title         = "Cloud Composer environments with large node counts should be reviewed"
  description   = "Cloud Composer environments with a high node count incur significant Compute Engine charges. Consider downsizing the environment or using Composer 2 with autoscaling."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "configuration"
    service = "GCP/Composer"
  })

  param "composer_node_count_threshold" {
    description = "Node count above which a Composer environment is flagged."
    default     = var.composer_node_count_threshold
  }

  sql = <<-EOQ
    select
      name as resource,
      case
        when (config -> 'nodeCount')::int > $1 then 'alarm'
        else 'ok'
      end as status,
      name || ' has ' || coalesce((config -> 'nodeCount')::text, 'unknown') || ' nodes.' as reason,
      location,
      project
    from
      gcp_composer_environment
    where
      state = 'RUNNING';
  EOQ
}

# Old Composer versions are less efficient than v2
control "composer_environment_old_version" {
  title         = "Cloud Composer 1 environments should be migrated to Composer 2"
  description   = "Cloud Composer 2 offers workload autoscaling and is more cost-efficient than Composer 1. Migrate Composer 1 environments to benefit from reduced costs."
  severity      = "medium"

  tags = merge(local.gcp_thrifty_common_tags, {
    class   = "deprecated"
    service = "GCP/Composer"
  })

  sql = <<-EOQ
    select
      name as resource,
      case
        when software_config ->> 'imageVersion' ilike 'composer-1%' then 'alarm'
        else 'ok'
      end as status,
      name || ' runs image version: ' || coalesce(software_config ->> 'imageVersion', 'unknown') || '.' as reason,
      location,
      project
    from
      gcp_composer_environment;
  EOQ
}
