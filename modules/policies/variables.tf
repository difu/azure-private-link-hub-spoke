variable "spoke_subscription_ids" {
  description = "Map of spoke subscription IDs where the policy should be applied"
  type        = map(string)
  default     = {}
}

variable "hub_subscription_id" {
  description = "Hub subscription ID"
  type        = string
}

variable "management_group_id" {
  description = "Management group ID for policy assignment scope (optional)"
  type        = string
  default     = null
}

variable "enable_tagging_policy" {
  description = "Whether to enable the tagging policy"
  type        = bool
  default     = false
}