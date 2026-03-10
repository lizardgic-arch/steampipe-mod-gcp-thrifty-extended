// Benchmarks and controls for specific services should override the "service" tag
locals {
  gcp_thrifty_common_tags = {
    category = "Cost"
    plugin   = "gcp"
    service  = "GCP"
  }
}

variable "common_dimensions" {
  type        = list(string)
  description = "A list of common dimensions to add to each control."
  # Define which common dimensions should be added to each control.
  # - connection_name (_ctx ->> 'connection_name')
  # - location
  # - project
  default     = [ "location", "project" ]
}

variable "tag_dimensions" {
  type        = list(string)
  description = "A list of tags to add as dimensions to each control."
  # A list of tag names to include as dimensions for resources that support
  # tags (e.g. "owner", "environment"). Default to empty since tag names are
  # a personal choice
  default     = []
}

locals {

  common_dimensions_qualifier_sql = <<-EOQ
  %{~ if contains(var.common_dimensions, "connection_name") }, __QUALIFIER___ctx ->> 'connection_name'%{ endif ~}
  %{~ if contains(var.common_dimensions, "location") }, __QUALIFIER__location%{ endif ~}
  %{~ if contains(var.common_dimensions, "project") }, __QUALIFIER__project%{ endif ~}
  EOQ

  tag_dimensions_qualifier_sql = <<-EOQ
  %{~ for dim in var.tag_dimensions },  __QUALIFIER__tags ->> '${dim}' as "${replace(dim, "\"", "\"\"")}"%{ endfor ~}
  EOQ

}

locals {

  common_dimensions_sql = replace(local.common_dimensions_qualifier_sql, "__QUALIFIER__", "")
  tag_dimensions_sql = replace(local.tag_dimensions_qualifier_sql, "__QUALIFIER__", "")
}
variable "cloudrun_min_instances_threshold" {
  type    = number
  default = 3
}
variable "cloudrun_max_instances_threshold" {
  type    = number
  default = 1000
}
variable "cloudfunctions_memory_mb_threshold" {
  type    = number
  default = 1024
}
variable "cloudfunctions_timeout_seconds_threshold" {
  type    = number
  default = 300
}
variable "cloudfunctions_min_instances_threshold" {
  type    = number
  default = 3
}
variable "sql_instance_max_storage_gb" {
  type    = number
  default = 500
}
variable "sql_instance_idle_days" {
  type    = number
  default = 7
}
variable "sql_backup_retention_days" {
  type    = number
  default = 30
}
variable "artifact_registry_repo_stale_days" {
  type    = number
  default = 90
}
variable "artifact_registry_repo_size_gb_threshold" {
  type    = number
  default = 50
}
variable "pubsub_subscription_undelivered_messages_threshold" {
  type    = number
  default = 100000
}
variable "pubsub_subscription_idle_days" {
  type    = number
  default = 30
}
variable "dataflow_job_age_max_days" {
  type    = number
  default = 7
}
variable "composer_node_count_threshold" {
  type    = number
  default = 6
}
variable "spanner_processing_units_threshold" {
  type    = number
  default = 3000
}
variable "redis_instance_memory_size_gb_threshold" {
  type    = number
  default = 16
}
variable "storage_bucket_last_access_days" {
  type    = number
  default = 90
}
variable "logging_bucket_retention_days" {
  type    = number
  default = 90
}
